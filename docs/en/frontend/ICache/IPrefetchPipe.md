# IPrefetchPipe submodule documentation

The IPrefetchPipe is a prefetch pipeline designed as a two-stage pipeline,
responsible for filtering prefetch requests.

![IPrefetchPipe
structure](../figure/ICache/IPrefetchPipe/iprefetchpipe_structure.png)

## S0 pipeline stage

In the S0 pipeline stage, it receives prefetch requests from the FTQ/backend and
sends read requests to the MetaArray and ITLB.

## S1 pipeline stage

First, it receives the response from the ITLB to obtain the paddr, then compares
it with the tag returned by the MetaArray to determine the hit information. The
metadata (hit information `waymask`, ITLB information `paddr`/`af`/`pf`) is
written into WayLookup. Simultaneously, a PMP check is performed, and the result
is registered for the next pipeline stage.

Controlled by the state machine:

- The initial state is `idle`. When a new request enters the S1 pipeline stage,
  it first checks whether the ITLB is missing. If it is missing, it enters
  `itlbResend`; if the ITLB hits but the hit information has not been enqueued
  into WayLookup, it enters `enqWay`; if the ITLB hits and WayLookup is enqueued
  but the S2 request has not been fully processed, it enters `enterS2`.
- In the `itlbResend` state, resend a read request to the ITLB, occupying the
  ITLB port (thus blocking new prefetch requests entering the S0 pipeline stage)
  until the request is refilled. On the cycle when refill completes, send
  another read request to the MetaArray. During refill, new writes may occur. If
  the MetaArray is busy (being written by MSHR), transition to `metaResend`;
  otherwise, proceed to `enqWay`.
- In the `metaResend` state, it resends a read request to the MetaArray. Upon
  successful sending, it enters `enqWay`.
- In the `enqWay` state, it attempts to enqueue the metadata into WayLookup. If
  the WayLookup queue is full, it blocks until enqueuing succeeds. Additionally,
  enqueuing is prohibited when a new write occurs in the MSHR, primarily to
  prevent conflicts between the written information and the hit information,
  requiring an update to the hit information. When successfully enqueued into
  WayLookup, if S2 is idle, it directly returns to `idle`; otherwise, it enters
  `enterS2`.
  - If the current request is a software prefetch, it will not attempt to
    enqueue into WayLookup because this request does not need to enter the
    MainPipe/IFU or be executed.
- In the `enterS2` state, it attempts to flow the request to the next pipeline
  stage. After flowing, it returns to `idle`.

![IPrefetchPipe S1 state
machine](../figure/ICache/IPrefetchPipe/iprefetchpipe_s1_fsm.png)

## S2 pipeline stage

It synthesizes the hit result of the request, ITLB exceptions, and PMP
exceptions to determine whether prefetching is needed. Prefetching is only
performed when no exceptions exist. Since the same prediction block may
correspond to two cachelines, the requests are sequentially sent to the MissUnit
via the Arbiter.

## Hit information update {#sec:IPrefetchPipe-hit-update}

After obtaining the hit information in the S1 pipeline stage, it takes two
stages before the hit information is actually used in the MainPipe: the stage
waiting to be enqueued into WayLookup in the IPrefetchPipe and the stage waiting
to be dequeued in WayLookup. During this waiting period, updates to the
Meta/DataArray by the MSHR may occur, so the MSHR responses need to be
monitored, divided into two scenarios:

1. Miss in MetaArray, monitored that MSHR wrote the corresponding cacheline into
   SRAM, need to update the hit status to hit.
2. The request has already hit in the MetaArray, but it detects that another
   cacheline write has occurred at the same location, overwriting the original
   data. The hit information needs to be updated to a miss state.

To prevent the delay of update logic from being introduced into the access path
of the DataArray, enqueuing into WayLookup is prohibited when a new write occurs
in the MSHR, and it is enqueued in the next cycle.
