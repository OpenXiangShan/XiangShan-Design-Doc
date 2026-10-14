# Matrix Loads and Stores: MemoryLoader

## Design Specifications

MemoryLoader transfers external row-based data into MatrixReg or writes C register results back to external memory. The default external data width is 64 B, while a MatrixReg bank entry is 32 B; one external response typically requires two internal writes.

In the default `ALBLCLLCSL` configuration, ordinary A/B loaders and C load/store use legacy implementations. A and B transpose loads both use the `TransposeLoadEngine` in the AML wrapper, while BML handles ordinary B loads. Parameterized channel implementations provide an alternative static configuration; see [Parameterized Loaders](#sec:cute-parameterized-loader).

## Overall Design

![Data buffering for ordinary loads, transpose loads, and C stores](./figure/cute-loaders.svg){#fig:cute-loaders}

In [@fig:cute-loaders], ordinary A/B responses recover the target bank and entry from the transaction ID, then write MatrixReg through response buffers. The transpose path first collects data by source row, then distributes fragments to multiple banks. C store first reads 8×8 result blocks, assembles 64 B write requests through a FIFO and two-slot rearrangement buffer, and finally waits for external write acknowledgements.

## Task Configuration and Completion

TaskController starts a loader through `MicroTaskValid` and `MicroTaskReady`, and reclaims execution resources through `MicroTaskEndValid` and `MicroTaskEndReady`. CML load and store have separate task ready, valid, and completion signals, and each stores its own target C register number.

After starting, the loader latches the address, stride, matrix dimensions, register number, and relevant modes. Request counters advance on external request `fire`, response counters on return handshakes, and internal write counters during filling. A load completes once all data has been filled into MatrixReg; a store completes once all data has been sent and all write acknowledgements have arrived.

## Ordinary A/B Loads

### Address Generation

The outer coordinate of an ordinary A load is M, and that of an ordinary B load is N; both have an inner reduction dimension arranged as contiguous bytes. For outer row `r` and external beat `b` within that row:

```text
memoryAddress = baseAddr + r * stride + b * 64
targetBank    = r % 8
targetEntry   = floor(r / 8) * 2 + b * 2
```

One 64 B response is split into two 32 B entries at `targetEntry` and `targetEntry+1`. The factor of 2 in the internal physical row spacing comes from the full AB register row capacity; short-K tasks use the same fixed spacing.

MLSU generates A descriptors as `row=M, column=K` and B descriptors as `row=K, column=N`. These fields hold architectural shapes, which TaskController interprets by operation class: ordinary B uses N outer rows with K contiguous elements per row; transpose B loads from K source rows with N contiguous elements per row. Transpose A likewise changes the source row count to K and the elements per row to M. See [MLSU Source Memory Layout](../memblock/LSU/MLSU.md#tbl:MLSU-source-layout) for the four source layouts and their relation to whole-register B.

Ordinary legacy loaders use external request channel 0. Requests are interleaved across a group of up to eight outer rows before advancing to the next external beat and row group; each request still transfers only one 64 B beat from one row. The controller may issue further requests before earlier requests return, subject to the transaction ID pool and return-buffer capacity.

### Response Placement and Filling

When a request issues, the loader records its target bank, starting entry, and tail-beat flag indexed by the allocated SourceID. On response return, a SourceID table lookup recovers the write location. Response data enters the fill table, and the target bank's queue stores the corresponding fill-entry index.

Each bank takes pending fill entries from its own queue, writes the low 32 B first, and then writes the high 32 B. Different banks may advance internal fills simultaneously; a full fill queue in one bank backpressures responses for that bank. Even the final memory response must pass through the fill queue and two internal writes before the loader can complete the task.

The tail beat records the valid byte count, which the loader expands into a prefix mask and splits into two 32 B write masks. MatrixReg bytes outside the valid range retain their previous values. The external read still covers the entire beat, so source memory must provide readable space for a complete beat.

### AB Zeroing

`ZeroTr` uses AML's zero-load mode to write all zeros with a full-byte mask to every bank, entry by entry. Each bank has 32 entries by default, so the entire selected AB register is zeroed without external requests. Zero-load mode shares AML's task resource with ordinary and transpose loads.

## A/B Transpose Loads

### Tasks and Resources

Both transpose A and transpose B route to AML's `TransposeLoadEngine`. Ordinary B loads use BML and may overlap an AML transpose task on a different AB register; ordinary A, A/B transpose, and ZeroTr execute serially through AML.

The transpose engine defines the transfer region by source rows and columns and converts source-matrix columns into outer rows of the AB register. The default external beat is 64 B, with e8, e16, or e32 element formats; e4 triggers a format assertion. The input base address must be 64 B aligned, as must stride when there are multiple source rows. Source row count times element bytes must not exceed `Tensor_K`, and source column count must not exceed `Tensor_MN`. Zero-sized tasks complete immediately.

### Two-Slot Collection and Tags

The engine has two collection slots, each holding eight 512-bit source-row responses, totaling 512 B. It reserves a slot before issuing its requests and tracks expected, issued, and received masks separately. Response SourceID carries the slot number and source row number, so tags recover data placement; out-of-order returns do not change matrix coordinates.

Physical response lanes receive data according to the source-row and channel assignment rules. A slot enters transpose writeback after all responses covered by its expected mask have arrived. The two slots collect and drain adjacent blocks independently; full slots or blocked writeback stop subsequent requests.

### Transpose Writeback

After a slot fills, fixed wiring selects elements from its eight source rows to assemble fragments for the target banks. Writeback has two register stages: the first selects transpose fragments; the second places them in the target entry at fixed 8 B increments and outputs per-bank addresses, data, and byte masks.

The writeback pipeline accepts backpressure and releases the current fragment only on a writeback handshake. After the final memory response arrives, remaining fragments continue through the transpose and writeback pipeline; task completion is generated after the final fragment is written. The AML adapter converts writeback into per-bank AB byte writes, with uncovered bytes retaining their previous values.

## Default C Loads

### Ordinary Loads

Ordinary CML loads access memory at `baseAddr + m*stride + beat*64`. In the default e32 format, each response contains 16 elements from the same source row and splits into two 32 B entries. The target bank is `m%8`, and entries use the fixed C row-group spacing:

```text
entry = floor(m / 8) * 16 + beat * 2 + fillPhase
fillPhase = 0 or 1
```

Internal write masks limit tail bytes; unwritten C lanes retain their previous values. CML load and store have independent state machines and target registers and may overlap on different C registers. They share a configuration payload; TaskController selects and sends one task configuration per cycle.

### Transpose Loads

Default legacy CML supports e32 transpose loads. The 16 elements in a source row become separate rows of the transposed matrix; the source row coordinate determines the target lane, while the source column coordinate determines the target bank and entry row group.

One 64 B response is processed in two phases, each handling eight elements and writing one 32-bit lane to each of the eight banks. Only that lane's four-byte mask is enabled. The target entry is formed from the source column's 8-row group and the source row's 8-column group, retaining the same fixed physical row-group spacing as ordinary C layout. Tail validity is limited per element; uncovered lanes are not zeroed.

### C Zeroing

`ZeroAcc` uses the CML load path to write zeros with full masks to all 256 entries in every bank of the selected C register, without accessing external memory. Zeroing covers the whole register regardless of the current smaller matrix shape.

TaskController selects ordinary load or zero-load mode for CML, with `RepeatRowLoad` held false; the corresponding repeated-row fill logic in CML is disabled.

## Default C Stores

### Reads and Two-Slot Rearrangement

CML store reads the same entry from all eight banks to obtain an 8×8×32-bit block, totaling 256 B. Returned data enters a block FIFO of depth 4. SRAM reads have one-cycle latency, so the read-request full threshold reserves one queue position for an in-flight return.

The rearrangement buffer has two slots. Each slot holds eight rows and collects two 32 B fragments per row to form eight 64 B requests, totaling 512 B. Ordinary stores concatenate the same row from adjacent N blocks; transpose stores first exchange rows and columns within an 8×8 block, then concatenate along the original M direction. Block-read traversal therefore differs between the modes: N blocks vary fastest for ordinary stores, and M blocks vary fastest for transpose stores.

The two slots track filling and draining separately, allowing one slot to send requests while the other collects MatrixReg returns. When external ready is low, the current output is retained, and its slot cannot be reused early.

### Addresses and Acknowledgements

For ordinary stores, M is the outer dimension and N the contiguous dimension; for transpose stores, N is the outer dimension and M the contiguous dimension. Each request address is the outer-row start plus the byte offset along the contiguous dimension; stride is in bytes. Physical C entry reads always use the fixed row-group spacing `Tensor_MN/Matrix_MN = 16`.

CML holds 64 entries of pending-write state. A successfully issued request marks its SourceID as in flight; a write ACK clears it. Unacknowledged writes may remain after all data has been sent; store completes and allows a dependent Release to issue only after every acknowledgement arrives.

### Store Boundaries {#sec:cute-store-boundary}

Default C store handles e32 INT32/FP32 elements; data layout and rearrangement are based on `ResultWidthByte=4`. The MLS descriptor's `widths` affects addresses and request counts, but store buffering, concatenation, and tail zero filling always use 32-bit elements. e8, e16, and e4 descriptors change the counts without changing the data format, so store tasks must use e32.

Default C store issues complete 64 B `PutFullData` requests with an all-ones mask. Elements beyond the logical extent in the final contiguous-dimension request are filled with zeros and written to external memory together with valid elements; every byte covered by that request is updated.

For example, an e32 row with only eight elements to store occupies 32 B, but its final request still covers 64 B; the second half is zeroed by the tail rule. Software must reserve space for the complete write beat, particularly for the final group of a transpose store with fewer than 16 elements along M.

Store dispatch always uses CML and selects a C register using the low two bits of `ms`, so C is the valid store class. A/B store descriptors generated by MLSU also enter this dispatch branch and actually read the C register with the same low-two-bit number. AB registers have only load-write and compute-read ports; current A/B stores do not perform the architecturally defined AB writeback.

## Parameterized Loaders {#sec:cute-parameterized-loader}

`LoaderBridgeChannelConfig` selects implementations separately for A load, B load, C load, and C store: `L` selects legacy, while `1`, `2`, `4`, and `8` select parameterized modules with the corresponding response width. C load and C store share a module and must both use either legacy or parameterized implementations; the parameterized module may select different response widths for load and store internally.

Table: Differences between parameterized data paths and default paths {#tbl:cute-parameterized-loaders}

| Module                     | Mechanism                                                                                                           | Current functional boundaries                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `MultiChannelsABMemLoader` | Independent row/beat counters, request FIFO, and return fill queue per bank; SourceID encodes tail, bank, and entry | Ordinary loads; transposition still uses the separate engine in the AML wrapper             |
| `ResponseChannelBridge`    | Routes by the SourceID bank field through an Omega network to bank-group queues                                     | Routing contention and full queues cause backpressure                                       |
| Parameterized C load       | Independent counters and fill queue per bank                                                                        | Uses ordinary-load layout; the transpose flag is not latched or used for address generation |
| Parameterized C store      | A depth-4 read-return queue per bank, with a collector combining two 32 B returns into 64 B                         | Ordinary path; transpose address state and in-block transposition remain incomplete         |
| Parameterized C store ACK  | Counts ACKs per lane directly by default; may also count per bank                                                   | Completes when all expected ACKs arrive                                                     |

Parameterized AB return queues have a default depth of 2, C load fill queues a default depth of 2, and response-bridge queues a default depth of 8 per bank. The Omega network consists of multiple layers of 2×2 combinational switches and perfect shuffles; responses enter bank-group queues at the network outputs. Path contention or full queues propagate backpressure to the inputs.

Parameterized C store holds `transpose_scp_addr` at zero, and the collector concatenates two 32 B returns in the original bank order. Transpose mode currently lacks block-by-block address advancement and in-block row/column exchange, so transpose loads or stores require legacy CML. Parameterized store also issues full-mask 64 B writes; its collector concatenates original data, and its counter and data-selection logic determine tail behavior.

## Implementation References

This section corresponds to [TaskController shape interpretation](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/TaskController.scala), [AMemoryLoader](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/AMemoryLoader.scala), [BMemoryLoader](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/BMemoryLoader.scala), [TransposeLoadEngine](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/TransposeLoadEngine.scala), [CMemoryLoader](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CMemoryLoader.scala), and [MultiChannelsCML](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/MultiChannelsCML.scala).
