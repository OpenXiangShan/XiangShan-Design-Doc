# Matrix Load/Store Queue: MLSQ

## Functional Description

The matrix load/store queue `MlsQueue` manages matrix memory instructions in the control core, records the address-preparation state of allocated instructions, and retains requests that need to execute again after a TLB miss. It consists of VirtualMlsQueue and MlsQueueReplay. Queue entries hold instructions, addresses, and control state.

VirtualMlsQueue sets the completion flag when MLSU returns an address-preparation result requiring no replay and reclaims entries according to that flag. After instruction commit, CUTE independently tracks data transfers and reports task completion. MLSQ reclamation does not depend on a CUTE data-return event.

## Submodule List

Table: Matrix load/store queue submodules {#tbl:MLSQ-submodules}

| Submodule       | Function                                                                                                                                            | Default entries |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| VirtualMlsQueue | Allocate matrix memory instructions in program order, record address-preparation state, and reclaim consecutive completed entries at the queue head | 8               |
| MlsQueueReplay  | Retain TLB-miss requests and send them back to MLSU after wakeup                                                                                    | 8               |

The two queues manage state and capacity separately. After backend writeback, AmuCtrlBuffer stores matrix descriptors by ROB index; after instruction commit, they enter CUTE's task issue window.

## Overall Design

The connection between the matrix load/store queue and MLSU is shown in [@fig:MLSQ-overall].

![Matrix load/store queue allocation, preparation completion, and replay paths](./figure/xsai-mlsq.svg){#fig:MLSQ-overall}

At dispatch, matrix memory instructions use the separate bit2 in the LSQ allocation mask and receive `mlsqIdx`. Scalar and vector Load / Store instructions use the LoadQueue and StoreQueue allocation bits, respectively. Each matrix memory instruction allocates one MLSQ entry, whose address-preparation state applies to the entire matrix.

The LSQ allocation controller maintains the matrix queue's free-entry count and allocation pointer. Dispatch acceptance considers free space in LoadQueue, StoreQueue, and MLSQ together. After a redirect, the allocation pointer and count are restored according to the cancellation count returned by the queue.

## VirtualMlsQueue

### Queue Entries and Allocation

Each VirtualMlsQueue entry stores `allocated`, the ROB index, and the preparation-completion flag `committed`. Allocation sets `allocated`, records the instruction's ROB index, and clears the preparation-completion flag.

MLSU's address-preparation result sets `committed`, which controls VirtualMlsQueue reclamation. Backend commit logic controls ROB retirement, while CUTE tracks completion of external matrix accesses.

### Preparation Completion and Reclamation

MLSU s3 returns the instruction's `mlsqIdx`, address-preparation state, and replay cause to the queue. When the request requires no replay and `updateAddrValid` is active, the corresponding entry is marked as preparation complete.

The queue searches for consecutive preparation-complete entries from its head, reclaims at most `CommitWidth` entries per cycle, and stops advancing at the first incomplete entry. The reclamation count and head pointer are returned to the LSQ allocation controller and MlsQueueReplay.

### Redirect Recovery

A redirect determines which entries to cancel using each entry's saved ROB index and clears `allocated` for affected entries. The registered cancellation count rolls back the allocation pointer. Recovery also accounts for newly allocated entries affected by the redirect and determines the allocation pointer's lower bound from the head pointer after reclamation.

## MlsQueueReplay

### Replay Causes and Saved Information

`MlsReplayCauses` currently defines only `C_TM`, indicating a TLB miss. The replay queue allocates free entries through FreeList and saves the following information:

- The original instruction and its ROB and MLSQ indices.
- The starting virtual address, row stride, and two matrix dimensions.
- The TLB hint identifier and miss cause.
- The `allocated`, `scheduled`, and `blocking` states.

The first TLB miss allocates a replay entry. If the replay misses again, it updates the original entry without allocating another.

### TLB Wakeup

Normally, a TLB-miss entry becomes blocked while waiting for a response with the matching hint identifier. A TLB `replay_all` also clears the corresponding blocking state.

If the TLB hint path reports that it is full, the request does not remain blocked waiting for that hint, allowing translation to be retried later. A matching hint arriving in the enqueue cycle also avoids further waiting, preventing a lost wakeup.

### Selection and Replay Pipeline

An entry eligible for replay must be allocated, unscheduled, and unblocked. Selection prioritizes ready entries close to the VirtualMlsQueue head; otherwise, it selects by enqueue age.

Replay has three stages: select a queue entry, read its saved virtual address and instruction information, and send the request back to MLSU. The selected entry sets `scheduled` and remains scheduled until the execution result returns. After MLSU arbitration and a valid/ready handshake, the output request enters s0. During backpressure, it remains in the last replay pipeline stage.

Consecutive replays are controlled by a cooldown counter whose conditions limit replay-pipeline advancement. Replay waiting time depends on TLB hint return, queue selection, the cooldown counter, and the MLSU handshake.

### Release and Cancellation

The replay entry is released when the result needs no further replay or produces an exception other than a TLB miss. If another replay is required, `scheduled` is cleared and the blocking and hint information is updated. A redirect also releases affected entries according to their ROB indices.

MLSQ manages address preparation and TLB-miss replay; RAW / RAR violation checks for matrix memory accesses are not implemented. CUTE and L2 handle cache transactions for matrix data, and matrix synchronization mechanisms notify the control core of task completion.

## Implementation

- [MlsQueue.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/mem/lsqueue/MlsQueue.scala)
- [VirtualMlsQueue.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/mem/lsqueue/VirtualMlsQueue.scala)
- [MlsQueueReplay.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/mem/lsqueue/MlsQueueReplay.scala)
- [LsqWrapper.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/mem/lsqueue/LsqWrapper.scala)
