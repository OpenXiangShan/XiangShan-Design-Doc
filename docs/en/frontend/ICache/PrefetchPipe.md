# PrefetchPipe Submodule Documentation

PrefetchPipe is a two-stage prefetch pipeline. It filters prefetch requests.

## S0 Stage

1. Accept hardware/software prefetch requests from FTQ/MemBlock.
2. Select addresses to send to MetaArray and ITLB according to 1-prefetch or 2-prefetch type.
3. Send read requests to MetaArray and ITLB.
4. Accept flush requests caused by BPU s3 override. If `ftqIdx` matches the current stage and this is not a software prefetch, flush the stage.

### 2-prefetch Read Address Selection

As described in [@sec:icache-2fetch], ICache can accept one prefetch request with two fetch blocks in one cycle under specific conditions. PrefetchPipe S0 selects two addresses from four candidate VAddrs of these two fetch blocks:

1. SameLine: two fetch blocks start in the same cacheline. Send only the first block's two addresses (`start` and `nextLine = start + 64`) to MetaArray and ITLB.
2. Overlap1: first block is cross-line, second block is single-line, and second start address falls in the latter half of the first block (`start + 32 < secondStart < start + 64`). Also send only the first block's two addresses (`start` and `nextLine = start + 64`).
3. Overlap2: opposite of Overlap1. Second block is cross-line, first block is single-line, and first start address falls in the first half of the second block (`secondStart + 32 < start < secondStart + 64`). Send only the second block's two addresses (`secondStart` and `secondNextLine = secondStart + 64`).
4. Interleave: both fetch blocks are not cross-line and fall in different interleave banks. Send the two block start addresses (`start` and `secondStart`).
5. Other cases: 2-prefetch is not allowed. FTQ guarantees this. Therefore send the first block's two addresses (`start` and `nextLine = start + 64`).

See also:

- Implementation of `class TwoPrefetchCase` in `TwoFetch.scala`.
- Interleave description in [MetaArray and DataArray doc](Array.md).

## S1 Stage

1. Receive responses from MetaArray/ITLB.
2. If ITLB misses, resend until hit.
3. Select metadata to enqueue into WayLookup according to 1-prefetch or 2-prefetch type.
4. Enqueue metadata into WayLookup.
5. Monitor MissUnit refill broadcast and update hit information.
6. Accept flush requests caused by BPU s3 override. If `ftqIdx` matches the current stage and this is not a software prefetch, flush the stage.

### State Machine

S1 behavior is controlled by a state machine:

- Initial state is `idle`. When a new request enters S1:
  - If ITLB misses, enter `itlbResend`.
  - If ITLB hits but metadata has not been enqueued into WayLookup, enter `enqWay`.
  - If ITLB hits and metadata is enqueued into WayLookup but S2 handling is not finished, enter `enterS2`.
- In `itlbResend`, resend ITLB read requests. During this state, ITLB port is occupied (new prefetch requests entering S0 are blocked) until refill finishes. In the refill cycle, resend a MetaArray read request. If MetaArray is busy (being written by MissUnit), enter `metaResend`; otherwise enter `enqWay`.
- In `metaResend`, resend MetaArray read requests. After request issue succeeds, enter `enqWay`.
- In `enqWay`, try to enqueue metadata into WayLookup. If WayLookup is full, stall until enqueue succeeds. In addition, enqueue is blocked when MissUnit is refilling, mainly to avoid conflicts between stored metadata and hit-status updates. After successful enqueue, return directly to `idle` if S2 is idle; otherwise enter `enterS2`.
  - If current request is software prefetch, it does not try to enqueue into WayLookup, because it does not need to enter MainPipe.
- In `enterS2`, try to move request into the next stage. After transfer, return to `idle`.

![PrefetchPipe S1 state machine](../figure/ICache/prefetchPipe_s1fsm.png)

### Hit Information Update {#sec:icache-hit-update}

After hit information is generated in S1, there are still pipeline stages and queues before it is actually used by MainPipe. During this period, MissUnit may refill MetaArray/DataArray, so refill broadcast must be monitored in two cases:

1. The request was originally a miss in MetaArray. If MissUnit refills the corresponding cacheline, hit status must be updated to hit.
2. The request was originally a hit in MetaArray. If another cacheline write (same set and way, different tag) overwrites that location, hit status must be updated to miss.

To avoid chaining update logic timing paths (set/way/tag comparisons and status updates) onto the normal pipeline path, metadata transfer to the next stage is blocked whenever MissUnit performs refill (regardless of relevance):

- For PrefetchPipe S1: block enqueue into WayLookup.
- For WayLookup: block dequeue to MainPipe.

### 2-prefetch Data Selection

As mentioned above, S0 selects two addresses from four candidates and sends them to MetaArray/ITLB. So S1 needs to reconstruct two metadata responses into the original four-request form for WayLookup enqueue and MainPipe usage:

1. SameLine: two fetch blocks share the same metadata response, `fb0/1.meta = meta`.
2. Overlap1: first fetch block uses full metadata, `fb0.meta = meta`; second fetch block uses only the second response as lower half, upper half invalid, `fb1.meta = (meta(1), null)`.
3. Overlap2: opposite, `fb1.meta = meta`, `fb0.meta = (meta(1), null)`.
4. Interleave: each fetch block uses its own response as lower half, upper half invalid, `fb0.meta = (meta(0), null)`, `fb1.meta = (meta(1), null)`.
5. 1-prefetch: normal case using first fetch block metadata response, `fb0.meta = meta`.

See also:

- Implementation of `class TwoPrefetchCase` in `TwoFetch.scala`.

## S2 Stage

1. Decide whether prefetch is needed according to hit result and exception metadata.
2. If prefetch is needed, use Arbiter to send miss requests for up to two cachelines to MissUnit in order.
