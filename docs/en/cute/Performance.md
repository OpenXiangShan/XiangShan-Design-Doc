# Performance Events and Debugging

## Overall Design

CUTE combines TaskController task state and LocalMMU request state into `CutePerfToCoreIO` and sends it to the control-core HPM. The interface contains 9 backend events and 12 memory events, each 6 bits wide; the top level delays the entire event group by one cycle. The indices below identify positions in CUTE's local interface; the control core maps these inputs to HPM counters through event-selection logic.

Task events record task occupancy, completion, and retirement; request events record external requests that handshake downstream of LocalMMU. One task may generate multiple requests, and multiple modules may be active in the same cycle. The control core commits a matrix instruction before delivering its command; CUTE completion and retirement events occur during subsequent asynchronous execution.

## Backend Events

Table: CUTE backendEvents {#tbl:cute-backend-events}

| Local index | Source         | Counting semantics                                                                     |
| ----------- | -------------- | -------------------------------------------------------------------------------------- |
| 0           | `ownedWork`    | Cycles with a valid decoded FIFO head or nonempty issue window                         |
| 1           | `retire`       | Counts 1 when a window-head task retires                                               |
| 2           | `compDone`     | Counts 1 when CDC finishes writeback and Compute completes overall                     |
| 3           | `releaseDone`  | Counts 1 when Release issues and generates a synchronization register completion pulse |
| 4           | `mteActive`    | Cycles when the Compute FU tracker is busy                                             |
| 5           | `mmaNonfpDone` | Counts 1 when a non-floating-point Compute completes                                   |
| 6           | `mmaFp16Done`  | Counts 1 when an FP16×FP16→FP32 Compute completes                                      |
| 7           | `mmaBf16Done`  | Counts 1 when a BF16×BF16→FP32 Compute completes                                       |
| 8           | `mmaTf32Done`  | Counts 1 when a TF32×TF32→FP32 Compute completes                                       |

`mteActive` counts cycles with the Compute FU tracker busy, covering data-supply waits, active computation, and pipeline draining. `ownedWork` counts cycles with a valid decoded FIFO head or nonempty issue window, covering task waiting, execution, and waiting for retirement.

FP16 and TF32 are disabled in the default configuration, so their type events are zero. FP8 counts in `compDone` like other computation, but the type-specific events cover only non-floating-point, FP16, BF16, and TF32. FP8 completion counts therefore require compute-type trace records.

## Memory Events

Table: CUTE memEvents {#tbl:cute-mem-events}

| Local index | Source           | Counting semantics                                                                         |
| ----------- | ---------------- | ------------------------------------------------------------------------------------------ |
| 0           | `loadADone`      | Counts 1 when a physical AML task completes                                                |
| 1           | `loadBDone`      | Counts 1 when a physical BML task completes                                                |
| 2           | `loadCDone`      | Counts 1 when a physical CML load task completes                                           |
| 3           | `storeDone`      | Counts 1 when CML store completes after receiving all required write ACKs                  |
| 4           | `amlActive`      | Cycles when the AML FU tracker is busy                                                     |
| 5           | `bmlActive`      | Cycles when the BML FU tracker is busy                                                     |
| 6           | `cmlLoadActive`  | Cycles when the CML load FU tracker is busy                                                |
| 7           | `cmlStoreActive` | Cycles when the CML store FU tracker is busy                                               |
| 8           | `rdReq`          | Counts 1 if at least one LocalMMU downstream read request handshakes in the current cycle  |
| 9           | `wrReq`          | Counts 1 if at least one LocalMMU downstream write request handshakes in the current cycle |
| 10          | `rd32BReq`       | Sum of `popcount(RequestMask)>>5` over all read requests that handshake                    |
| 11          | `wr32BReq`       | Sum of `popcount(RequestMask)>>5` over all write requests that handshake                   |

AML completion covers ordinary A loads, transpose A, transpose B, and ZeroTr; CML load completion covers C loads and ZeroAcc. Completion events count physical execution resources; architectural instruction classes can be distinguished through task traces. Zeroing executes inside MatrixReg and generates the corresponding loader activity and completion events while leaving external request counts unchanged.

`rdReq` and `wrReq` OR the channel handshake signals to count cycles with request handshakes; multiple channels handshaking in the same cycle still count as 1. The 32 B events sum masked byte counts across channels: each default full-mask 64 B request contributes 2, and multiple requests in the same cycle accumulate per request.

## Request Counts and Bandwidth Statistics

Over an observation interval, `32 × sum(rd32BReq)` and `32 × sum(wr32BReq)` give cumulative bytes according to request masks. Dividing by observed cycles yields average request bytes per cycle at this CUTE request interface; multiplying by the actual operating frequency gives the corresponding interface rate.

The counting point is LocalMMU's downstream request interface, accumulating request bytes sent from CUTE to the cache. Response bytes, HBL2 hit or miss traffic, and DDR traffic require event counts from their corresponding interfaces. Default reads cover complete 64 B requests, including bytes in the final beat that are not written into MatrixReg; C store tail zero filling also counts as a complete write request.

Compute, loaders, and external requests may be active in the same cycle, and their activity counts cover their respective execution stages. Tasks may stall after window entry on dependencies or resources, on FU data supply, array backpressure, blocked return buffers, or write acknowledgements. Issue, read-completion, and completion timestamps in task traces can separate these stages.

## ChiselDB Task Events

TaskController defines four basic task tables to associate issue and completion events with the same task.

Table: CUTE ChiselDB task tables {#tbl:cute-chiseldb-tables}

| Table              | Main fields and use                                                                                                                                         |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CUTELoadEvent`    | `eventType`, register, row/column counts, transpose, A/B/C mask, `fifoIdx`, `slotId`, `seqId`; correlates allocation, issue, and physical loader completion |
| `CUTEComputeEvent` | A/B/C numbers, M/N/K, type, `slotId`, `seqId`; distinguishes compute issue, A read completion, B read completion, and C write completion                    |
| `CUTEStoreEvent`   | C number, row/column counts, transpose, `slotId`, `seqId`; correlates store issue with receipt of all ACKs                                                  |
| `CUTEReleaseEvent` | Synchronization register number, `slotId`, `seqId`; correlates Release scheduling and completion                                                            |

`slotId` is the window slot number, reused after retirement; `seqId` is a 16-bit sequence number that advances on task allocation and wraps on overflow. Task correlation uses time, sequence number, and task attributes together. `fifoIdx` advances separately for each task class and records order within that class; window age is determined by window-entry order.

These tables are output through ChiselDB, with generation and recording controlled by simulation/debug configuration. Control-core HPM counters are driven by `CutePerfToCoreIO` events; the two provide task details and cumulative statistics, respectively.

## Matrix Prefetch Observations

By default, `EnableMatrixPrefetch=false`, so matrix prefetch descriptors, control outputs, and request prefetch tags are not generated. When statically enabled, `CUTEMatrixPrefetchDesc`, separate `CUTECStoreDesc`, and Cute2TL `CUTEMemoryTrace` records can be generated.

Load descriptors contain task ID, stream class, base address, outer stride, outer count, inner beat count, valid row bytes, group width, and transpose attributes; they correlate task access sequences and supply prefetch control information. The separate C store descriptor supports trace reconstruction; L2 matrix prefetcher training inputs come from the load path. TileLink requests carry prefetch tags, while debug trace tags remain in Cute2TL trace tables.

Matrix prefetching is enabled jointly by static CUTE and HBL2 configurations and generates subsequent requests using access shapes supported by descriptors.

## Implementation References

This section corresponds to [performance interface Bundles](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/Bundles.scala), [TaskController events](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/TaskController.scala), [LocalMMU request counters](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/LocalMMU.scala), [top-level event mapping](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTETOP.scala), and [Cute2TL tracing](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTE2YGJK.scala).
