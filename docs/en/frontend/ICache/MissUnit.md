# MissUnit submodule documentation

The MissUnit handles ICache miss requests, manages them through MSHR, interacts
with the L2 Cache via the Tilelink bus, and is responsible for sending write
requests to the MetaArray and DataArray, as well as sending responses to the
MainPipe.

![MissUnit structure](../figure/ICache/MissUnit/missunit_structure.png)

## MSHR management

The MissUnit manages fetch requests and prefetch requests separately through
MSHRs. To ensure fetch MSHRs can be fully released during a flush, the number of
fetch MSHRs is set to 4, and prefetch MSHRs to 10. A design separating data and
address is used, with all MSHRs sharing a set of data registers, while only
storing address information in the MSHRs.

## Request enqueue

The MissUnit receives fetch requests from the MainPipe and prefetch requests
from the IPrfetchPipe. Fetch requests can only be assigned to fetchMSHRs, and
prefetch requests to prefetchMSHRs, using a lower-index-first allocation
strategy during enqueue. Simultaneously, the MSHR is queried during enqueue. If
the request already exists in the MSHR, it is discarded, with the external
interface still appearing to fire, but the request is not enqueued into the
MSHR. During enqueue, a write request for the waymask is sent to the Replacer.

## acquire

When the bus to L2 is idle, the MSHR entries are selected for processing. The
fetchMSHR has higher priority than the prefetchMSHR, and only when there are no
fetchMSHRs to process will the prefetchMSHRs be handled. For fetchMSHRs, a
lower-index-first priority strategy is used because there are at most two
requests to process simultaneously, and both must be completed before proceeding
further, making the priority among fetchMSHRs less critical. For prefetchMSHRs,
considering the temporal order of prefetch requests, a first-come-first-served
priority strategy is adopted. A FIFO records the enqueue order, and processing
follows this order.

## grant

It interacts with the D channel of Tilelink through a state machine. The
bandwidth to L2 is 32 bytes, requiring two transmissions, and different requests
do not interleave, so only one set of registers is needed to store data. When a
transmission completes, the corresponding MSHR is selected based on the
transmission ID, and information such as address and mask is read from the MSHR.
The relevant information is then written to SRAM, and the MSHR is released.
