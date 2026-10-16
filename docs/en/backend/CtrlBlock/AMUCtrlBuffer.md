# AmuCtrlBuffer

- Version: V2R2A
- Status: OK
- Date: 2026/10/13
- commit: [XSAI ee268923](https://github.com/OpenXiangShan/XSAI/tree/ee268923b7175d79a9d0183a0181a684ccec9487)

## Glossary of Terms

Table: Terminology Explanation

| Name    | Description                                                                         |
| ------- | ----------------------------------------------------------------------------------- |
| AMU     | Matrix accelerator control interface                                                |
| amuCtrl | Control request for matrix computation, memory access, zeroing, or release          |
| needAMU | Whether this entry needs to send a control request to CUTE                          |
| canDeq  | The entry has completed the processing required by this buffer and can be reclaimed |

## Design specifications

- Runs in parallel with the ROB, has a capacity of RobSize, and uses the same allocation indices.
- Receives ROB allocation, writeback, commit, and redirect information in sync.
- Only matrix control requests that have written back and committed can be sent to CUTE.
- Retains requests when CUTE cannot accept them and backpressures ROB allocation.
- Outputs CommitWidth candidate channels, merged into one channel by the fixed-priority arbiter in XSCore.

## Function

Matrix functional units in the control core check parameters, generate control information, and write amuCtrl back to AmuCtrlBuffer. The buffer retains each request until the corresponding instruction commits normally from the ROB, then sends it to CUTE through a ready/valid handshake. Parameter checks can execute out of order in the control core. CUTE performs matrix operations according to the requests sent after commit.

ROB commit sets the request's committed state. The request remains in the buffer during CUTE backpressure. After the handshake, CUTE accepts the request and executes the corresponding task. Software uses mrelease / macquire to wait for older Stores and their dependency chains to complete. Unrelated Loads / Computes can remain in flight; see [Release synchronization semantics](../../cute/TaskController.md#sec:cute-release).

## Overall Block Diagram

![AmuCtrlBuffer](./figure/xsai-amu-buffer.svg){width=85%}

## Entries

Table: AmuCtrlEntry signal list

| Signal      | Description                                                 |
| ----------- | ----------------------------------------------------------- |
| valid       | This entry has been allocated                               |
| needAMU     | An AMU control request needs to be sent                     |
| writebacked | Control information has written back                        |
| committed   | The corresponding ROB entry has committed                   |
| amuCtrl     | Control information waiting to be sent                      |
| canDeq      | Processing is complete; the entry can be reclaimed in order |

Every valid ROB allocation occupies a buffer entry, including ordinary non-matrix instructions. Non-matrix instructions set canDeq directly on commit. Matrix instructions set canDeq after the control-request handshake.

## Allocation and writeback

Allocation uses the ROB's allocatePtr. The corresponding buffer entry is cleared and allocated only when the ROB accepts the instruction and no redirect occurs. Writeback matches an entry by robIdx.value, stores amuCtrl, and sets writebacked. When DiffTest is enabled, the instruction's PC and coreid are added in the buffer.

The buffer determines available capacity from the valid-entry count and the current request count. ROB enqueue reserves RenameWidth entries, while the condition sent ahead to Dispatch reserves 2×RenameWidth entries. Both acceptance conditions are registered before output.

## Commit and transmission

Normal ROB commit sets committed. A request can be sent when:

```text
valid && needAMU && writebacked && committed && !canDeq
```

CommitWidth candidate entries are selected starting at the buffer dequeue pointer. The fixed-priority arbiter in XSCore selects older valid requests first, sending at most one request per cycle to CUTE. Request fire sets canDeq, and the entry is released on the next in-order reclamation.

The dequeue pointer advances by the number of consecutive canDeq entries, reclaiming up to CommitWidth entries per cycle. Both committed ordinary-instruction entries and matrix entries that have completed the handshake participate in in-order reclamation.

## Redirects and exceptions

On a redirect, the buffer clears affected entries directly according to the circular interval specified by the ROB. Older committed requests still waiting for CUTE are retained. Tasks already accepted by CUTE continue executing.

Illegal matrix parameters and memory exceptions enter the ROB through the exception path. A redirect clears the control information of the faulting instruction. A software protocol handles matrix-register save/restore and completion synchronization for committed tasks.

The implementation is in [AMUCtrlBuffer.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/backend/rob/AMUCtrlBuffer.scala).
