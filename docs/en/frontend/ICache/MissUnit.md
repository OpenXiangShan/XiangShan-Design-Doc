# MissUnit Submodule Documentation

MissUnit handles ICache miss requests, manages all in-flight requests through MSHRs, and interacts with L2 cache through bus. After receiving bus responses, it broadcasts refill information to SRAMs, queues, and pipelines.

![MissUnit structure](../figure/ICache/missUnit.png)

## MSHR Management

MissUnit uses separate MSHRs for fetch requests and prefetch requests. To avoid cases where fetch MSHRs cannot be fully released during flush, default configuration sets fetch MSHR count to 4 and prefetch MSHR count to 10. It uses address-data separation: all MSHRs share one set of refill data registers (grant buffer), while each MSHR stores only request address/state information.

## Request Enqueue

MissUnit accepts fetch requests from MainPipe and prefetch requests from PrefetchPipe. Fetch requests can only be allocated to fetchMSHR, and prefetch requests can only be allocated to prefetchMSHR. During enqueue, the free MSHR with smallest index is selected.

### Duplicate Request Filtering

MSHR exposes lookup interface to MissUnit top level, so MissUnit can check whether a new request already exists in any MSHR. If it already exists, MissUnit directly merges this new request. For MainPipe and PrefetchPipe interfaces, handshake still appears as fire, but no actual write into MSHR is performed.

### Victim Selection

When MSHR sends acquire request to bus, a victim way (to be overwritten by refill) is selected from replacer, and victim information is written into MSHR. During refill, MissUnit directly uses victim info recorded in MSHR, without querying replacer again.

## acquire

When bus to L2 is idle, MissUnit selects MSHR entries to process. Overall, fetchMSHR has higher priority than prefetchMSHR. PrefetchMSHR is processed only when there is no fetchMSHR entry to process.

For fetchMSHR, smallest-index-first priority is used. This is because at most two requests are processed simultaneously, and both must complete before proceeding, so relative priority among fetchMSHR entries is not important.

For prefetchMSHR, considering temporal order among prefetch requests, first-come-first-served priority is used. A FIFO records enqueue order, and processing follows this order.

## grant

MissUnit receives bus responses with a state machine. Current L1-to-L2 bus bandwidth is 32B, so one 64B cacheline is transferred in 2 beats. Bus burst mechanism guarantees responses from different requests do not interleave, so only one grant buffer set is needed. When one transfer completes, corresponding MSHR is selected by transfer id. MissUnit reads address/victim and other info from MSHR, broadcasts refill information to SRAMs, queues, and pipelines, then resets MSHR state.

### Exception Handling

Current TileLink bus may report two exception signals: `corrupt` and `denied`. `corrupt` indicates data corruption from L2 cache (or lower memory structures), for example ECC check failure. `denied` indicates request rejection, for example permission failure. According to TileLink spec, asserting `denied` always implies `corrupt` is also asserted. Therefore MissUnit should return `corrupt & !denied` as effective corrupt signal to MainPipe. MainPipe then reports error to BEU and raises related exception.
