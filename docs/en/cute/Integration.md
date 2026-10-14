# Memory Interface and System Integration

## Interface List

CUTE's control input and matrix data accesses connect to the control core and HBL2, respectively. The control core decides when to deliver matrix commands to CUTE; TaskController inside CUTE decides when each command's data operation starts and completes. The connected cache system handles memory coherence; LocalMMU only organizes access streams within CUTE.

Table: CUTE top-level and adapter interfaces {#tbl:cute-integration-io}

| Interface                | Direction and handshake                | Function                                                                                   |
| ------------------------ | -------------------------------------- | ------------------------------------------------------------------------------------------ |
| `ctrl2top.amuCtrl`       | Control core→CUTE, Decoupled           | Asynchronous matrix commands and operands                                                  |
| `ctrl2top.mrelease`      | CUTE→control core, Valid               | Release completion pulse for a specified synchronization register                          |
| `mmu2llc.Request`        | CUTE→Cute2TL, eight Decoupled channels | Address, read/write type, write data, mask, 64-bit SourceID, and matrix attributes         |
| `mmu2llc.Response`       | Cute2TL→CUTE, eight Decoupled channels | 64-bit SourceID, returned data, and coherence attributes                                   |
| `Cute2TL.node`           | Eight independent TileLink clients     | 64 B Get/PutFullData requests and ordinary acknowledgements                                |
| `Cute2TL.matrix_data_in` | HBL2→Cute2TL, eight Decoupled channels | 512-bit matrix read data and 64-bit source per channel                                     |
| `perf`                   | CUTE→control core                      | 9 backend events and 12 memory events, delayed by one cycle at the top level               |
| `matrixPrefetch`         | Optional, CUTE→cache prefetch control  | Generates descriptors and control information when statically enabled; disabled by default |

Ordinary legacy AML/BML/CML requests use internal channel 0. The A/B transpose engine and parameterized loaders assign requests according to their channel configurations and may use multiple physical channels. Each task's request width depends on its selected loader implementation.

## LocalMMU Request Arbitration

LocalMMU accepts six access streams: A, B, and C load, C store, A scale, and B scale. Each physical channel arbitrates independently with the following fixed priority:

```text
A read > A scale read > B read > B scale read > C load > C store
```

Only the selected stream receives downstream ready. A blocked downstream keeps its request waiting; continuous high-priority requests keep lower-priority streams waiting. Scale task valid is false by default, but the arbiter reserves these priority positions for statically enabled Scale accesses.

The control-core MLSU writes the translated physical base address into the command's `baseAddr`. The loader adds row stride and beat offsets to that address, and LocalMMU forwards the generated request address directly downstream. The upstream configuration field named `BaseVaddr` also holds the address supplied by the command; CUTE has no internal TLB or PTW, and subsequent row and beat accesses must lie within the valid physical address ranges provided by the system.

## Transaction IDs

### Source Tags

LocalMMU distinguishes access streams with the low three bits of SourceID, retaining the stream's original transaction ID in the upper bits:

```text
encodedSourceId = (origId << 3) | sourceTag
```

Table: LocalMMU source tags {#tbl:cute-source-tags}

| Access stream | sourceTag |
| ------------- | --------- |
| A read        | 0         |
| B read        | 1         |
| C load        | 2         |
| C store       | 3         |
| A scale read  | 4         |
| B scale read  | 5         |

On return, the source tag is decoded first, then the ID with the tag removed is delivered to the corresponding loader. Tags identify physical access streams: for example, transpose B issues through AML's A read path and uses tag 0; the architectural instruction class remains in the task record.

### Allocated and Self-Encoded IDs

Legacy A/B loaders use SourceIDs allocated by LocalMMU. LocalMMU maintains a busy table with 64 entries by default, allocating only free entries; the loader stores bank, entry, and tail lookup information under that index. The original ID sent to the cache also carries an allocation marker, which releases the busy entry on return and recovers the loader's index.

Parameterized loaders and the transpose engine encode bank, entry, and tail, or slot and source row, directly into their original IDs. `UseAllocatedSourceID` selects allocated or self-encoded IDs; both append the low-three-bit source tag and pass downstream through `AmeIndex`.

## Cute2TL Request Conversion

Cute2TL creates one `TLClientNode` for each of the eight default channels. Every client's TileLink `source` range is `IdRange(0,1)`, and request source is fixed at 0. The true 64-bit ID needed to distinguish multiple in-flight CUTE requests is carried by the TileLink user field `AmeIndex`.

Each read request becomes one 64 B Get, and each write request becomes one 64 B PutFullData. Write masks must be all ones, which the adapter checks with an assertion. Partial-byte MatrixReg updates occur inside loaders; the external write interface covers the entire 64 B transfer.

Table: TileLink matrix extension fields {#tbl:cute-tl-fields}

| Field               | Generation rule and use                                                                                        |
| ------------------- | -------------------------------------------------------------------------------------------------------------- |
| `AmeIndex`          | Holds the complete `RequestSourceID` and returns through the response path to recover the original transaction |
| `MatrixKey`         | Binary `11` for C reads; `01` for other matrix requests, including C stores                                    |
| `ReqSource`         | Marks `MatrixRead` or `MatrixWrite` for cache request-source statistics                                        |
| `MatrixPrefetchTag` | Generated when matrix prefetching is statically enabled; absent from the default configuration                 |

`MatrixIsAcc && !RequestType_isWrite` selects the `11` encoding for C reads; C stores use `01`. `MatrixPrefetchTag` travels into the cache with the request, while `MatrixTraceTag` remains in Cute2TL's debug records for task correlation.

## Read Data Return and Acknowledgement Merging

HBL2 returns matrix read data through the separate `matrix_data_in`, carrying 512-bit data and a 64-bit source. TileLink channel D provides ordinary acknowledgements and `AmeIndex`. Cute2TL merges these two paths into an internal `MMUResponseIO` on each channel.

If matrix data is present in the current cycle, its source and data take priority, and TL-D ready is deasserted. Otherwise, TL-D `AmeIndex` supplies the response ID. Internal response ready backpressures the selected path. C store ACKs require only an ID and do not consume matrix read data.

Cute2TL's `ReseponseData` connects directly to `matrix_data_in.data`, while TL-D supplies acknowledgement IDs, so HBL2 must return read data according to the matrix extension protocol. See the XSAI integration section of [L2 Cache](../cache/l2cache/CoupledL2.md) for cache-side requests, return Hint pairing, and data organization.

For example, an A load request saves its target entry at the request handshake and places the encoded SourceID in `AmeIndex`. After completing the access, HBL2 returns data/source through the matrix data channel; Cute2TL merges the response, LocalMMU removes the source tag, and AML looks up the bank and entry and splits 64 B into two internal writes. AML reports load completion after the final internal write finishes.

## Address, Coherence, and Exception Boundaries

All Cute2TL requests enter the same group of TileLink clients; `RequestConherent` does not select the bus. Returned coherence attributes are fixed true, and noncoherent SourceID interface valid is fixed false; HBL2 handles cache coherence behavior.

The control core handles exceptions during address translation. Cute2TL/LocalMMU internal response Bundles provide data, SourceID, and coherence attributes but do not convert TileLink `denied` or `corrupt` into precise matrix instruction exceptions. CML store releases in-flight state according to write ACK IDs, and its completion interface reports receipt of all acknowledgements.

Default loaders read with complete 64 B requests, and stores write complete 64 B transfers. Software and the system must satisfy validity and layout requirements across the full access range, particularly those for [transpose-load alignment and store tails](MemoryLoader.md).

## Synchronization and Busy State

The control core delivers commands to `amuCtrl` after ROB commit. CUTE completes tasks after their data operations finish and retires them in window order. After all older Store ACKs arrive, Release sends a completion vector to the control core, and Fence updates synchronization counters; unrelated Load/Compute tasks may still be running. `macquire` waits for the counter to reach its target, while `mfence` requests scalar SBuffer draining and waits for `sbIsEmpty`; they handle matrix task completion and scalar store ordering, respectively. See [Matrix Synchronization](../backend/FunctionUnit/IntFunctionUnit.md#sec:matrix-sync).

Cute2TL's `idle` is fixed true, independently of task and in-flight access state. TaskController resource-activity events reflect the execution modules' state; software synchronizes through Release and the control-core synchronization register protocol. See [Release](TaskController.md#sec:cute-release) for its semantics.

## Implementation References

This section corresponds to [LocalMMU](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/LocalMMU.scala), [Cute2TL](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTE2YGJK.scala), [request/response Bundles](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTEParameters.scala), and [CUTE top-level interfaces](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTETOP.scala).
