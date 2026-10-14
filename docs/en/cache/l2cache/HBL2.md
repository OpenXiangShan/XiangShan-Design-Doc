# Matrix Memory Access Path: HBL2

HBL2 (High Bandwidth L2 Cache) is the XSAI extension to CoupledL2 for matrix memory accesses. CUTE sends matrix read and write requests through TileLink channel A. In addition to the regular TileLink channel D response path, each Slice provides a 512-bit read-data interface that transfers a 64 B cache line to the matrix unit in one handshake.

Matrix requests share CoupledL2's directory, main pipeline, MSHRs, and CHI coherence mechanism. When a request misses, needs the latest data from an upper-level cache, or needs to invalidate upper-level copies, an MSHR performs the required permission and data exchanges.

## Terminology

Table: HBL2 terminology

| Name          | Description                                                                                           |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| Slice / Bank  | An L2 cache slice selected by the low-order bits of the cache-line address                            |
| MatrixDataOut | A separate matrix read-data response interface for each Slice                                         |
| ameIndex      | Matrix-side request index used to match returned data or write responses                              |
| ameChannel    | Matrix-side data channel number                                                                       |
| PutBuffer     | Collects the two input beats of a matrix PutFullData request                                          |
| RefillBuffer  | Full-line buffer addressed by MSHR index, holding downstream refill data or Put data awaiting a write |
| ReleaseBuffer | Holds an old cache line awaiting release or data returned by an upper-level Probe                     |

## Design Specifications

Table: HBL2 parameters in DefaultMatrixConfig

| Parameter                 | Configuration                                                 |
| ------------------------- | ------------------------------------------------------------- |
| Number of Slices          | 8                                                             |
| Sets and ways per Slice   | 512 sets, 8 ways                                              |
| Capacity per Slice        | 256 KiB                                                       |
| Total capacity            | 2 MiB                                                         |
| Cache-line size           | 64 B                                                          |
| Channel A / D data beat   | 32 B                                                          |
| Matrix read-data response | 512 bits per Slice, one line per handshake                    |
| PutBuffer                 | 4 entries per Slice, one line per entry                       |
| MSHRs                     | 16 entries per Slice, at most 15 occupied by channel A        |
| DataStorage MCP2          | Disabled                                                      |
| Matrix-guided prefetching | Disabled by default; enabled through a separate configuration |

Total capacity is the product of the set count, way count, line size, and Slice count; see [CoupledL2 design specifications](CoupledL2.md) for the parameter combination. The aggregate matrix read-response width across the eight Slices is 512 B/cycle. Matrix writes enter at 32 B/beat per Slice, for an aggregate input width of 256 B/cycle. These values are interface limits under continuous handshakes without conflicts. Actual throughput depends on bank distribution, DataStorage accesses, queue occupancy, and coherence transactions.

## Overall Design

### Overall Block Diagram

![XSAI HBL2 matrix request and data paths](./figure/xsai-hbl2.svg){#fig:xsai-hbl2}

Matrix requests pass through SinkA, RequestBuffer, and RequestArb into MainPipe. Control tasks and data are stored separately: incoming Put data first enters PutBuffer, then moves to RefillBuffer, addressed by MSHR index, when coherence operations must complete before the write. The task carries only the buffer index and request metadata.

After processing, MainPipe passes the upstream response to GrantBuffer. Matrix read responses return through MatrixDataOut, while matrix write responses use regular channel D. The two response paths share a response queue and use CustomL1Hint to preserve pairing with early-wakeup information.

### Request and Response Identifiers

Table: Identifier propagation for matrix requests

| Channel A field      | Internal field    | Final use                                                                   |
| -------------------- | ----------------- | --------------------------------------------------------------------------- |
| source               | sourceId          | source of a regular channel D response                                      |
| MatrixKey            | matrixTask        | bit 0 identifies a matrix request and selects the matrix read-response path |
| AmeIndexKey          | ameIndex          | MatrixDataOut.sourceId or AmeIndex in a write response                      |
| AmeChannelKey        | ameChannel        | MatrixDataOut.channel                                                       |
| MatrixPrefetchTagKey | matrixPrefetchTag | Training for optional matrix-guided prefetching                             |

The TileLink source and matrix-side index are separate identifiers. MatrixDataOut.sourceId is 64 bits wide and contains ameIndex; data is one DSBlock; channel takes the low three bits of the 4-bit ameChannel. The interface uses a valid/ready handshake. When the receiver is not ready, the full-line data and identifiers remain at the head of the response queue.

## Functional Description

### Matrix Get

1. SinkA receives Get and records the matrix identifiers. RequestBuffer checks for conflicts with the pipeline and MSHRs.
2. The request enters the main pipeline and queries the directory. On a hit that requires no Probe, it reads DataStorage. A Get hit does not require a directory update.
3. On a TRUNK hit with an upper-level copy, an MSHR is allocated and obtains the latest copy through Probe toB. On a miss, an MSHR sends ReadNotSharedDirty downstream, waits for data and permission responses, and refills through the normal replacement flow.
4. The response task retains matrixTask, ameIndex, and ameChannel, with response type AccessAckData. GrantBuffer sends the full line through MatrixDataOut in one transfer.

Matrix Get selects its data source and Probe operations according to the directory state and upper-level copies. See [MSHR](MSHR.md) for the detailed states and data sources.

### Matrix PutFullData

Matrix Put supports full-cache-line PutFullData with all byte-mask bits set. MatrixKey must be `2'b01`. The request contains two 32 B beats. The first beat allocates and locks a PutBuffer entry; the final beat completes collection of the full line and produces an internal task carrying bufIdx.

MainPipe reads PutBuffer in s2 and selects processing in s3 according to the directory result:

- Hit in a writable state with no upper-level client: write directly to DataStorage, set dirty and TIP with clients equal to 0, and schedule AccessAck.
- BRANCH hit: allocate an MSHR and send MakeUnique downstream to obtain write permission.
- Hit with an upper-level client: allocate an MSHR and use Probe toN to invalidate upper-level copies; also schedule MakeUnique if permission must be upgraded.
- Miss: allocate an MSHR, query the replacement way after the Comp response to MakeUnique, and release the old line as needed before writing the new data.

When an MSHR is required, the new Put data moves from PutBuffer to RefillBuffer and waits for the required coherence responses. The refill task sets `useProbeData` to false to select the new data in RefillBuffer. MakeUnique returns write permission; Probe and replacement tasks invalidate upper-level copies and release the old line.

The Put response is AccessAck on regular channel D. source corresponds to the TileLink source, and AmeIndex corresponds to the matrix-side index. PutBuffer is released when data is handed to the main pipeline; the MSHR is released after all Schedule / Wait entries complete. See [PutBuffer](PutBuffer.md) and [Request arbiter and main pipeline](ReqArb_MainPipe.md) for the detailed data flow.

### Response Ordering and Backpressure

Regular channel D responses containing data are sent in two beats. If the second beat is still buffered in GrantBuffer, it takes priority over a new matrix response. Matrix read data must also wait until its response reaches the head of the response queue.

CustomL1Hint records an isMatrixData entry for matrix AccessAckData. Slice allows MatrixDataOut to send only when that entry is at the head of the Hint queue, and the matrix-data handshake releases the matching Hint entry. Matrix entries send no regular Hint to L1 and do not use the two data beats on regular channel D. Receiver backpressure retains the matrix response and eventually blocks later main-pipeline requests through response-queue capacity checks. See [GrantBuffer](upstream/GrantBuffer.md) for the detailed rules.

## Optional Matrix-Guided Prefetching

### Configuration and Control Interface

Matrix-guided prefetching is enabled jointly by MatrixPrefetchParameters in L2 and EnableMatrixPrefetch in CUTE.

Table: Matrix prefetch configurations

| Configuration                   | Matrix-guided prefetching | Other prefetch sources                             |
| ------------------------------- | ------------------------- | -------------------------------------------------- |
| DefaultMatrixConfig             | Disabled                  | Retains the base configuration's BOP / L1 receiver |
| DefaultMatrixPrefetchConfig     | Enabled                   | Retains the base configuration's prefetch sources  |
| DefaultMatrixOnlyPrefetchConfig | Enabled                   | Removes other prefetch sources                     |

CUTE provides allocate, activate, retire, cStoreStart, and cStoreEnd events through MatrixPrefetchControl. allocate carries a matrix descriptor containing the task number, stream type, base address, row stride, row count, range within each row, group width, and transpose attribute. The matrixPrefetchTag carried by a demand Get consists of a 1-bit valid flag, a 3-bit stream type, and a 16-bit task number, associating main-pipeline training with a matrix task.

### Address Generation and Scheduling

The address generator traverses the covered address range by group, row, and cache line according to the descriptor. For an unaligned start address, traversal begins with the cache line containing the first byte. When the row stride is not cache-line aligned, the end of each row is checked separately to skip out-of-range candidates.

The current prefetch scheduler prioritizes the C store window to generate lookahead for the next group of A data. B-on-A and C-on-B are two other optional policies whose independent control switches both initialize to 0. Matrix prefetch requests are sent as read-only Hints to the corresponding Slice; prefetched data is not written directly into CUTE.

### Queues and Demand Requests

The matrix source uses a separate lossless queue per bank, with ready backpressure to the address generator. Conventional speculative prefetching retains the overwrite behavior of OverwriteQueue. The two sources are arbitrated and sent to SinkA in each Slice. Regular demand requests and the final beat of a Put take priority over prefetches.

A matrix Get matching an outstanding prefetch at the same address updates late-prefetch statistics. The demand request types eligible for `mergeA` are limited to AcquireBlock / AcquirePerm. Matrix prefetching uses Hint transactions; Get / Put demand requests perform their respective coherence operations according to the directory state.
