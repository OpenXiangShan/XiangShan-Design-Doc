# PrefetchPipe Submodule Documentation

PrefetchPipe is a two-stage prefetch pipeline. It filters prefetch requests.

## S0 Stage

1. Accept hardware/software prefetch requests from FTQ/MemBlock.
2. Send read requests to MetaArray and ITLB.
3. Accept flush requests caused by BPU s3 override. If `ftqIdx` matches the current stage and this is not a software prefetch, flush the stage.

## S1 Stage

1. Receive responses from MetaArray/ITLB.
2. If ITLB misses, resend until hit.
3. Enqueue metadata into WayLookup.
4. Monitor MissUnit refill broadcast and update hit information.
5. Accept flush requests caused by BPU s3 override. If `ftqIdx` matches the current stage and this is not a software prefetch, flush the stage.

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

## S2 Stage

1. Decide whether prefetch is needed according to hit result and exception metadata.
2. If prefetch is needed, use Arbiter to send miss requests for up to two cachelines to MissUnit in order.
