# SinkA

## Functional Description
SinkA receives TileLink channel A and prefetcher requests, converts them to TaskBundle, and sends them to RequestBuffer. Matrix Get and PutFullData share this entry with regular channel A requests. Put write data is stored in [PutBuffer](../PutBuffer.md), and TaskBundle carries the corresponding buffer index.

### Feature 1: Request Metadata

SinkA extracts address, opcode, param, source, alias, and other information from channel A, converting it to the tag, set, offset within the block, and task attributes required by the main pipeline.

Matrix requests additionally carry the following information:

Table: Matrix channel A request metadata

| Field                | Internal task field | Purpose                                                       |
| -------------------- | ------------------- | ------------------------------------------------------------- |
| MatrixKey            | matrixTask          | bit 0 of MatrixKey indicates whether this is a matrix request |
| AmeChannelKey        | ameChannel          | Matrix data response channel number                           |
| AmeIndexKey          | ameIndex            | Matrix-side request index                                     |
| MatrixPrefetchTagKey | matrixPrefetchTag   | Training tag for optional matrix-guided prefetching           |

`sourceId` retains the TileLink transaction source, and `ameIndex` retains the matrix-side index. The separate matrix Get data-response interface uses the latter as sourceId; see [GrantBuffer](GrantBuffer.md).

### Feature 2: PutFullData Data Collection

Matrix Put supports only a full 64 B cache line: opcode is PutFullData, size equals the number of cache-line offset bits, all byte-mask bits in each beat are 1, and MatrixKey is `2'b01`. PutPartialData, sub-line PutFullData, and writes with partial masks are unsupported.

Each channel A beat is 32 B, so a full-line Put contains two beats. The first beat writes PutBuffer and locks the buffer entry for the line. The final beat generates a task while writing PutBuffer, placing the entry index in `bufIdx`. RequestBuffer holds the request control information and buffer index; PutBuffer retains the write data.

Acceptance of the first beat is controlled by PutBuffer.ready; acceptance of the final beat is controlled by RequestBuffer.ready. SinkA records an unfinished Put after the first-beat handshake and clears that state after the final-beat handshake.

### Feature 3: Channel A and Prefetch Arbitration

Regular channel A tasks and the final beat of a Put take priority over prefetch requests. The first beat of a Put does not use the TaskBundle output port, so a queued prefetch can be sent in that cycle. No prefetch task is inserted after the first beat has been accepted and before the final beat is accepted.

Prefetch requests are converted to Hint, with param set to PREFETCH_READ or PREFETCH_WRITE according to the required permission. The prefetch task's `matrixTask` is 0. Matrix-guided prefetching is still a read prefetch into the cache and does not write data to CUTE through the matrix data-response interface.

### Feature 4: Blocking

When RequestBuffer cannot accept a task, regular A requests, the final beat of a Put, and prefetch requests are blocked through the valid/ready handshake. When PutBuffer has no free entry, the first beat of a new Put is blocked. Once the main pipeline reads PutBuffer using `bufIdx`, that entry can be used for a new Put.

## Overall Block Diagram

![SinkA](./figure/SinkA.svg)

See the overall block diagram in [Matrix memory access path HBL2](../HBL2.md) for the matrix Put buffering and response paths.
