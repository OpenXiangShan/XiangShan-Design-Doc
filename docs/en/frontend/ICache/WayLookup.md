# WayLookup Submodule Documentation

WayLookup is a FIFO structure that temporarily stores metadata obtained by
IPrefetchPipe from querying MetaArray and ITLB for MainPipe's use. It also
monitors MSHR writes to the SRAM cacheline and updates hit information. The
update logic is the same as in IPrefetchPipe—see the section ["Hit Information
Updates" in the IPrefetchPipe Submodule
Documentation](IPrefetchPipe.md#sec:IPrefetchPipe-hit-update).

![WayLookup Queue
Structure](../figure/ICache/WayLookup/waylookup_structure_rw.png)

![WayLookup Hit Information
Update](../figure/ICache/WayLookup/waylookup_structure_update.png)

Bypass is allowed (i.e., when WayLookup is empty, directly dequeue the enqueue
request). To avoid introducing update logic latency into the DataArray access
path, dequeuing is blocked when MSHR has new writes. MainPipe's S0 stage also
accesses DataArray, so if MSHR has new writes, it cannot proceed further,
meaning this measure has no additional impact.

## GPaddr Area-Saving Mechanism

Since `gpaddr` is only relevant when a guest page fault occurs, and after each
gpf, the frontend operates on the wrong path (with the backend guaranteeing a
redirect (WayLookup flush) to the frontend—whether due to
misprediction/exceptions before the gpf or the gpf itself), WayLookup only needs
to store the gpaddr of the first valid gpf after reset/flush. For dual-line
requests, only the `gpaddr` of the first line with a gpf needs to be stored.

In implementation, the gpf-related signals (currently only `gpaddr`) are
separated from other signals (`paddr`, etc.) into two bundles. Other signals are
instantiated nWayLookupSize times, while gpf-related signals are instantiated as
a single register. A `gpfPtr` pointer is also used. This saves a total of
$(\text{nWayLookupSize}*2-1)* \text{GPAddrBits} -
\log_2{(\text{nWayLookupSize})} - 1$ bits in registers. When prefetch writes to
WayLookup, if a gpf occurs and no existing gpf is present in WayLookup, the
gpf/gpaddr is written to the `gpf_entry` register, and `gpfPtr` is set to the
current `writePtr.` When MainPipe reads from WayLookup, if bypassing, it
directly dequeues the prefetch-enqueued data; otherwise, if `readPtr ===
gpfPtr`, it reads gpf_entry; otherwise, it reads all zeros. Note:

1. For dual-line requests, only one `gpaddr` needs to be stored (if the first
   line triggers a gpf, the second line is already on the wrong path and need
   not be stored). However, the gpf signal itself must still be stored twice, as
   the IFU needs to determine whether it is a cross-line exception.
2. The condition `readPtr===gpfPtr` may cause `readPtr` to loop around and match
   `gpfPtr` again if the flush is slow, erroneously re-reading the gpf. However,
   as mentioned earlier, this occurs on the wrong path, so re-reading the gpf is
   inconsequential.
3. A special case to note: For a fetch block spanning two pages, where the first
   32B lies on the previous page without exceptions and the last 2B on the next
   page triggers a gpf, if the first 32B happens to be 16 RVC compressed
   instructions, the IFU will discard the last 2B and its corresponding
   exception information. This may cause the `gpaddr` of the next fetch block to
   be lost. When WayLookup already has an unclaimed gpf and related information,
   it must block enqueuing (i.e., the IPrefetchPipe s1 stage). See PR#3719.
