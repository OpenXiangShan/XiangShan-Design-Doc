# WayLookup {#sec:icache-waylookup}

WayLookup is a ring queue structure. It temporarily stores metadata obtained by PrefetchPipe from MetaArray and ITLB for MainPipe. It also monitors MissUnit refill broadcast and updates hit information. The update logic is the same as PrefetchPipe; see [@sec:icache-hit-update] [Hit Information Update section in PrefetchPipe](PrefetchPipe.md#hit-information-update-secicache-hit-update).

## Pointer Update {#sec:icache-waylookup-pointer-update}

When PrefetchPipe writes into WayLookup, `writePtr++`; when MainPipe reads from WayLookup, `readPtr++`. When queue is full (`writePtr.flag =/= readPtr.flag && writePtr.value === readPtr.value`), it no longer accepts new enqueue requests.

WayLookup supports bypass. When queue is empty (`writePtr === readPtr`), data that PrefetchPipe is about to enqueue in the current cycle is immediately dequeued to MainPipe. To simplify pointer update logic, both `writePtr` and `readPtr` update on bypass (`writePtr++` and `readPtr++`), so the queue remains empty after bypass.

## BPU Flush {#sec:icache-waylookup-bpu-flush}

Because of frontend pipeline stage reduction in BPU/FTQ, compared with V2R2, FTQ now sends prefetch requests to ICache one cycle earlier. This means when a fetch block is overridden by BPU s3, that block may already be enqueued in WayLookup, so WayLookup also needs to handle BPU flush requests.

Fortunately, the flushed request is always the just-enqueued tail entry (in the fastest case: BPU s1 = prefetchPipe s0, BPU s2 = prefetchPipe s1 = wayLookup.io.write, BPU s3 = wayLookup `entries[writePtr - 1]`), so only the queue tail needs to be considered.

Specifically, WayLookup records the `ftqIdx` of the tail entry. When a BPU s3 override request arrives, if `ftqIdx` matches and `writePtr > readPtr` (tail entry has not been consumed by MainPipe), flush the tail entry (`writePtr--`).

## Exception Handling {#sec:icache-waylookup-exception}

Signals such as `gpaddr` are useful only when the corresponding exception occurs. Also, after an exception happens, frontend is effectively on the wrong path, and backend guarantees a redirect to frontend (whether because misprediction/interrupt happened before exception handling or because exception itself causes redirect). Therefore, WayLookup only needs to store related signals for the first valid exception after reset/flush, to save storage area.

In implementation, these signals (`itlbException`, `gpaddr`, etc.) are split from normal signals (`waymask`, etc.) into two bundles. Normal signals are instantiated `nWayLookupSize` times, while exception-related signals use only one register. `exceptionPtr` indicates which queue entry corresponds to this exception.

When PrefetchPipe writes into WayLookup and an exception occurs, related signals are written into `exceptionEntry`, and `exceptionPtr` is set to current `writePtr`.

When MainPipe reads from WayLookup:

- If bypass is active, it still directly dequeues data being enqueued by PrefetchPipe.
- Otherwise, if `readPtr === exceptionPtr`, read `exceptionEntry`.
- Otherwise, output all-zero exception fields.

In addition, for the same reason (processor is already on wrong path after exception), while `exceptionEntry` is valid, WayLookup stops accepting new enqueue requests, back-pressuring PrefetchPipe/FTQ/BPU to save power. It resumes after backend redirect brings frontend back to correct path and flushes `exceptionEntry`.
