# Matrix-Guided Prefetching

Matrix-guided prefetching is enabled jointly by MatrixPrefetchParameters in L2 and EnableMatrixPrefetch in CUTE.

Table: Matrix prefetch configurations

| Configuration                   | Matrix-guided prefetching | Other prefetch sources                             |
| ------------------------------- | ------------------------- | -------------------------------------------------- |
| DefaultMatrixConfig             | Disabled                  | Retains the base configuration's BOP / L1 receiver |
| DefaultMatrixPrefetchConfig     | Enabled                   | Retains the base configuration's prefetch sources  |
| DefaultMatrixOnlyPrefetchConfig | Enabled                   | Removes other prefetch sources                     |

CUTE provides allocate, activate, retire, cStoreStart, and cStoreEnd events through MatrixPrefetchControl. allocate carries a matrix descriptor containing the task number, stream type, base address, row stride, row count, range within each row, group width, and transpose attribute. The matrixPrefetchTag carried by a demand Get consists of a 1-bit valid flag, a 3-bit stream type, and a 16-bit task number, associating main-pipeline training with a matrix task.

## Address Generation and Scheduling

The address generator traverses the covered address range by group, row, and cache line according to the descriptor. For an unaligned start address, traversal begins with the cache line containing the first byte. When the row stride is not cache-line aligned, the end of each row is checked separately to skip out-of-range candidates.

The current prefetch scheduler prioritizes the C store window to generate lookahead for the next group of A data. B-on-A and C-on-B are two other optional policies whose independent control switches both initialize to 0. Matrix prefetch requests are sent as read-only Hints to the corresponding Slice; prefetched data is not written directly into CUTE.

## Queues and Demand Requests

The matrix source uses a separate lossless queue per bank, with ready backpressure to the address generator. Conventional speculative prefetching retains the overwrite behavior of OverwriteQueue. The two sources are arbitrated and sent to SinkA in each Slice. Regular demand requests and the final beat of a Put take priority over prefetches.

Matrix prefetching uses Hint transactions; Get / Put demand requests perform their respective coherence operations according to the directory state.
