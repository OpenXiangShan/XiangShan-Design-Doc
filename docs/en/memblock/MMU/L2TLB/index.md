
# Level-2 Module: L2 TLB

L2 TLBWrapper refers to the following module:

* L2TLBWrapper ptw, where L2TLBWrapper provides an abstraction layer for the L2
  TLB.

L2 TLB refers to:

* L2TLB ptw

## Design specifications

This section describes the overall design specifications of the L2 TLB module.
For the design specifications of submodules within the L2 TLB module, refer to
the tertiary module section of this document.

1. Supports receiving PTW requests from L1 TLB
2. Support for Returning PTW Responses to L1 TLB
3. Supports signal and register duplication
4. Supports exception handling mechanism
5. Supports TLB compression
6. Supports two-stage address translation.

## Function

L2 TLB is a larger page table cache shared by ITLB and DTLB. When an L1 TLB miss
occurs, a Page Table Walk request is sent to L2 TLB. L2 TLB consists of Page
Cache (see Section 5.3.7), Page Table Walker (see Section 5.3.8), Last Level
Page Table Walker (see Section 5.3.9), Hypervisor Page Table Walker (see Section
5.3.10), Miss Queue (see Section 5.3.11), and Prefetcher (see Section 5.3.12).

Requests from L1 TLB first access the Page Cache. For non-two-stage address
translation requests, if a leaf node is hit, it is directly returned to L1 TLB.
Otherwise, based on the page table level hit in Page Cache and the availability
of Page Table Walker and Last Level Page Table Walker, the request enters Page
Table Walker, Last Level Page Table Walker, or Miss Queue (see Section 5.3.7).
For two-stage address translation requests: if the request is onlyStage1, it is
processed the same way as non-two-stage requests; if onlyStage2 and a leaf page
table is hit, it is directly returned; if not hit, it is sent to Page Table
Walker for translation; if the request is allStage, since Page Cache can only
query one page table at a time, it first queries the first-stage page table.
There are two scenarios: if the first-stage page table hits, it is sent to Page
Table Walker for subsequent translation; if the first-stage page table does not
hit a leaf node, it enters Page Table Walker, Last Level Page Table Walker, or
Miss Queue based on the hit page table level and the availability of Page Table
Walker and Last Level Page Table Walker. To accelerate page table access, Page
Cache caches all three levels of page tables separately, allowing simultaneous
queries (see Section 5.3.7). Page Cache supports ECC verification; if an ECC
error is detected, the entry is refreshed, and Page Walk is restarted.

The Page Table Walker handles requests from the Page Cache to perform Hardware
Page Table Walk. For non-two-stage address translation requests, it only
accesses the first two levels (1GB and 2MB) of page tables, leaving 4KB page
table access to the Last Level Page Table Walker. If the Page Table Walker
reaches a leaf node (large page), it returns the result to the L1 TLB;
otherwise, it forwards the request to the Last Level Page Table Walker for the
final level of access. The Page Table Walker can only process one request at a
time and cannot parallelize access to the first two levels. For two-stage
address translation requests: (1) If it is an allStage request and the
first-stage translation hits, PTW sends a second-stage request to the Page
Cache. If it misses, the request is forwarded to the Hypervisor Page Table
Walker, and the second-stage result is returned to PTW. (2) If it is an allStage
request and the first-stage leaf node misses, PTW processing resembles
non-virtualized requests, except that physical addresses encountered are guest
physical addresses and require a second-stage translation before memory access
(see the Page Table Walker module description for details). (3) For onlyStage2
requests, PTW sends a second-stage translation request externally and returns
the response to L1TLB. (4) For onlyStage1 requests, PTW handles them internally
the same way as non-virtualized requests.

The Miss Queue receives requests from the Page Cache and Last Level Page Table
Walker, waiting for the next access to the Page Cache. The Prefetcher employs
the Next-Line prefetching algorithm, generating the next prefetch request upon a
miss or a hit on a prefetched entry.

### Receives requests from L1 TLB and returns responses

As a whole, L2 TLB receives PTW requests from L1 TLB. PTW requests sent by L1
TLB are transmitted to L2 TLB through two levels of Repeaters. Depending on
whether the request comes from itlbRepeater or dtlbRepeater, L2 TLB returns
responses to itlbRepeater or dtlbRepeater, respectively. L2 TLB receives the
virtual page number sent by L1 TLB and returns information including first-stage
page tables, second-stage page tables, etc. The behavior of L2 TLB is
transparent to L1 TLB, and only partial signal interfaces are required for
interaction between L1 TLB and L2 TLB.

### Sending PTW Requests to L2 Cache

The L2 TLB sends PTW requests to the L2 Cache via the TileLink bus, connected
through the ptw_to_l2_buffer, which provides and receives relevant signals for
TileLink A and D channels.

### Signal and register duplication

Due to the large size of the L2 TLB module, signals such as sfence and csr
registers need to drive multiple components, thus requiring the sfence signals
and csr registers to be duplicated. Duplicating registers facilitates timing
optimization and physical implementation without affecting functional
implementation, as the duplicated content remains identical. The duplicated
signals and registers can be used to drive components at different locations.

The replication scenarios and their respective driven parts are shown in
[@tbl:L2TLB-signal-replication-drive]:

Table: Signal replication status and drive components
{#tbl:L2TLB-signal-replication-drive}

| **Copy Signal** | **Serial number** |     **drive component**      |
| :-------------: | :---------------: | :--------------------------: |
|     sfence      |                   |                              |
|                 |   sfence_dup(0)   |           Prefetch           |
|                 |   sfence_dup(1)   | Last Level Page Table Walker |
|                 |   sfence_dup(2)   |           cache(0)           |
|                 |   sfence_dup(3)   |           cache(1)           |
|                 |   sfence_dup(4)   |           cache(2)           |
|                 |   sfence_dup(5)   |           cache(3)           |
|                 |   sfence_dup(6)   |          Miss Queue          |
|                 |   sfence_dup(7)   |      Page Table Walker       |
|                 |   sfence_dup(8)   | Hypervisor Page Table Walker |
|       csr       |                   |                              |
|                 |    csr_dup(0)     |           Prefetch           |
|                 |    csr_dup(1)     | Last Level Page Table Walker |
|                 |    csr_dup(2)     |           cache(0)           |
|                 |    csr_dup(3)     |           cache(1)           |
|                 |    csr_dup(4)     |           cache(2)           |
|                 |    csr_dup(5)     |          Miss Queue          |
|                 |    csr_dup(6)     |      Page Table Walker       |
|                 |    csr_dup(7)     | Hypervisor Page Table Walker |

### Exception Handling Mechanism

Exceptions that may arise from the L2 TLB include: guest page fault, page fault,
access fault, and ECC check errors. For guest page fault, page fault, and access
fault, they are delivered to the L1 TLB, which handles them based on the request
source. For ECC check errors, they are processed internally within the L2 TLB by
invalidating the current entry, returning a miss result, and reinitiating Page
Walk. Refer to Section 6 of this document: Exception Handling Mechanism.

### TLB compression

After adding virtualization extensions, stage1 in L2TLB reuses the logic design
of TLB compression, and the structure returned to L1TLB is also TLB-compressed.
However, TLB compression is not enabled in L1TLB, while stage2 does not adopt
the TLB compression structure and only returns a single page table during resp.

The L2 TLB accesses memory in 512-bit widths, returning 8 page table entries per
access. The l3 entries of the Page Cache are composed of SRAM and can store 8
consecutive page table entries during refill, while the sp entries use register
files and store only a single entry. Thus, when the Page Cache hits and returns
to the L1 TLB (excluding two-stage address translation, where a first-stage hit
would be forwarded to PTW for further processing), if the hit is for a 4KB page
table, the 8 consecutive entries can be compressed. For large pages, no
compression is performed, and the entry is directly refilled into the L1 TLB.
(In practice, misses for 1GB or 2MB large pages are rare, so compression is only
considered for 4KB pages. For 4KB pages, the ppn is 24 bits, and compression
requires the upper 21 bits of the ppn to match across 8 consecutive entries. For
1GB or 2MB large pages, the lower 9 bits of the ppn are unused for physical
address generation and are thus irrelevant in the current design.)

When a Page Cache miss occurs and the Page Table Walker or Last Level Page Table
Walker accesses the page table in memory, the page table from memory is returned
to the L1 TLB and refilled into the Page Cache. If a second-stage address
translation is required, the page table accessed by the Hypervisor Page Table
Walker is also refilled into the Page Cache. The HPTW returns the final
translation result to the PTW or LLPTW, which then returns both stages of the
page table to the L1 TLB. For non-two-stage translation requests, the L1 TLB can
also compress up to 8 consecutive page table entries upon return. Since the Page
Table Walker only returns directly to the L1 TLB when accessing a leaf node, the
page tables returned by the Page Table Walker to the L1 TLB are all large pages.
Given the minimal performance impact of large pages and the simplicity of the
optimization implementation, as well as the reuse of the data path for sp
entries in the Page Cache, the large pages returned by the Page Table Walker are
not compressed.

The L2 TLB only compresses 4KB page tables. According to the Sv39 paging
mechanism in the RISC-V Privileged Specification, the lower 3 bits of the
physical address for a 4KB page table correspond to the lower 3 bits of the
virtual page number. Thus, the 8 consecutive page table entries returned by the
Page Cache or Last Level Page Table Walker can be indexed using the lower 3 bits
of the virtual page number. The valid bit indicates whether the compressed page
table entry is valid. Based on the lower 3 bits of the virtual page number in
the page table lookup request from the L1 TLB, the corresponding page table
entry is indexed, and its valid bit must be 1. For the remaining 7 consecutive
entries, their validity is determined by comparing their upper physical page
numbers and page table attribute bits with those of the indexed entry. If they
match, the valid bit is set to 1; otherwise, it is 0. Additionally, the L2 TLB
returns pteidx, indicating which of the 8 consecutive page table entries
corresponds to the vpn sent by the L1 TLB. The L2 TLB compression is illustrated
in [@fig:L2TLB-compress-1;@fig:L2TLB-compress-2].

![L2 TLB Compression Diagram 1](../figure/image34.png){#fig:L2TLB-compress-1}

![L2 TLB Compression Schematic 2](../figure/image35.png){#fig:L2TLB-compress-2}

With TLB compression implemented, each entry in the L1 TLB is a compressed TLB
entry, indexed by the upper bits of the virtual page number. A TLB hit requires
not only matching the upper vpn bits but also the valid bit for the
corresponding lower vpn bits to be 1, indicating the entry is valid in the
compressed TLB. Details on TLB compression and its relation to L1 TLB are
covered in the L1TLB module description.

## Overall Block Diagram

![L2 TLB Overall Block Diagram](../figure/image9.jpeg){#fig:L2TLB-overall}

As shown in [@fig:L2TLB-overall], the L2 TLB is divided into six parts: Page
Cache, Page Table Walker, Last Level Page Table Walker, Hypervisor Page Table
Walker, Miss Queue, and Prefetcher.

Requests from L1 TLB first access the Page Cache. For non-two-stage address
translation requests, if a leaf node is hit, it is directly returned to L1 TLB.
Otherwise, based on the page table level hit in Page Cache and the availability
of Page Table Walker and Last Level Page Table Walker, the request enters Page
Table Walker, Last Level Page Table Walker, or Miss Queue (see Section 5.3.7).
For two-stage address translation requests: if the request is onlyStage1, it is
processed the same way as non-two-stage requests; if onlyStage2 and a leaf page
table is hit, it is directly returned; if not hit, it is sent to Page Table
Walker for translation; if the request is allStage, since Page Cache can only
query one page table at a time, it first queries the first-stage page table.
There are two scenarios: if the first-stage page table hits, it is sent to Page
Table Walker for subsequent translation; if the first-stage page table does not
hit a leaf node, it enters Page Table Walker, Last Level Page Table Walker, or
Miss Queue based on the hit page table level and the availability of Page Table
Walker and Last Level Page Table Walker. To accelerate page table access, Page
Cache caches all three levels of page tables separately, allowing simultaneous
queries (see Section 5.3.7). Page Cache supports ECC verification; if an ECC
error is detected, the entry is refreshed, and Page Walk is restarted.

The Page Table Walker handles requests from the Page Cache to perform Hardware
Page Table Walk. For non-two-stage address translation requests, it only
accesses the first two levels (1GB and 2MB) of page tables, leaving 4KB page
table access to the Last Level Page Table Walker. If the Page Table Walker
reaches a leaf node (large page), it returns the result to the L1 TLB;
otherwise, it forwards the request to the Last Level Page Table Walker for the
final level of access. The Page Table Walker can only process one request at a
time and cannot parallelize access to the first two levels. For two-stage
address translation requests: (1) If it is an allStage request and the
first-stage translation hits, PTW sends a second-stage request to the Page
Cache. If it misses, the request is forwarded to the Hypervisor Page Table
Walker, and the second-stage result is returned to PTW. (2) If it is an allStage
request and the first-stage leaf node misses, PTW processing resembles
non-virtualized requests, except that physical addresses encountered are guest
physical addresses and require a second-stage translation before memory access
(see the Page Table Walker module description for details). (3) For onlyStage2
requests, PTW sends a second-stage translation request externally and returns
the response to L1TLB. (4) For onlyStage1 requests, PTW handles them internally
the same way as non-virtualized requests.

The Miss Queue receives requests from the Page Cache and Last Level Page Table
Walker, waiting for the next access to the Page Cache. The Prefetcher employs
the Next-Line prefetching algorithm, generating the next prefetch request upon a
miss or a hit on a prefetched entry.

The diagram involves the following arbiters, named as in the chisel code:

* arb1: A 2-to-1 arbiter, shown as Arbiter 2 to 1 in the diagram, with inputs
  from ITLB (itlbRepeater2) and DTLB (dtlbRepeater2), and output to Arbiter 5 to
  1.
* arb2: A 5-to-1 arbiter (Arbiter 5 to 1 in the diagram) with inputs from Miss
  Queue, Page Table Walker, arb1, hptw_req_arb, and Prefetcher; output to Page
  Cache
* hptw_req_arb: A 2-to-1 arbiter with inputs from Page Table Walker and Last
  Level Page Table Walker, output to Page Cache
* hptw_resp_arb: A 2-to-1 arbiter with inputs from Page Cache and Hypervisor
  Page Table Walker, outputting to PTW or LLPTW.
* outArb: A 1-to-1 arbiter with input from mergeArb and output to L1TLB's resp
* mergeArb: A 3-to-1 arbiter with inputs from Page Cache, Page Table Walker, and
  Last Level Page Table Walker, outputting to outArb.
* mq_arb: A 2-to-1 arbiter with inputs from Page Cache and Last Level Page Table
  Walker; output goes to the Miss Queue.
* mem_arb: A 3-to-1 arbiter with inputs from Page Table Walker, Last Level Page
  Table Walker, and Last Level Page Table Walker; output to L2 Cache (Last Level
  Page Table Walker also has an internal mem_arb that arbitrates all PTW items
  sent by Last Level Page Table Walker to L2 Cache before passing them to this
  mem_arb)

![L2 TLB module hit path](../figure/image36.jpeg){#fig:L2TLB-hit-passthrough}

The hit path of the L2 TLB module is illustrated in
[@fig:L2TLB-hit-passthrough]. Requests from ITLB and DTLB first go through
arbitration before being sent to the Page Cache for lookup. For requests
involving non-two-stage address translation, only the second stage, or only the
first stage, if the Page Cache hits, the page table entry and physical address
information are directly returned to the L1 TLB. For allStage requests, the Page
Cache first queries the first-stage page table. If the first stage hits, it
sends the request to PTW, which then issues an hptw request. The hptw request
enters the Page Cache for lookup; if it hits, it is sent to PTW; if not, it is
sent to HPTW. After HPTW completes the query, the result is sent to PTW, and the
page table obtained from HPTW memory access is backfilled into the Page Cache.
All PTW requests from ITLB and DTLB, as well as hptw requests from PTW or LLPTW,
are first queried in the Page Cache.

For miss scenarios, all modules may participate. Requests from ITLB and DTLB are
first arbitrated and then sent to Page Cache for query. If Page Cache misses,
the request may enter MissQueue under certain conditions (requests from PTW or
LLPTW sent to Page Cache as hptw requests or prefetch requests do not enter
MissQueue). Missed requests enter MissQueue in cases such as bypass requests,
L1TLB sending isFirst requests to PageCache that need to enter PTW, MissQueue
sending requests to PTW when PTW is busy, or sending requests to LLPTW when
LLPTW is busy. Page Cache determines whether to enter Page Table Walker or Last
Level Page Table Walker for query based on the page table level hit (hptw
requests are sent to HPTW). Page Table Walker can only handle one request at a
time and can access the first two levels of page tables in memory; Last Level
Page Table Walker is responsible for accessing the last-level 4KB page table.
Hypervisor Page Table Walker can only handle one request at a time.

The Page Table Walker, Last Level Page Table Walker, and Hypervisor Page Table
Walker can all send requests to memory to access page table contents. Before
accessing memory, the physical address is checked by the PMP and PMA modules. If
the check fails, no memory request is sent. Requests from these walkers are
arbitrated and then sent to the L2 Cache via the TileLink bus.

Both Page Table Walker and Last Level Page Table Walker may return PTW responses
to L1 TLB. Page Table Walker may generate responses in the following scenarios:

* For non-two-stage translation requests and only first-stage translation
  requests, accessing a leaf node (1GB or 2MB large page) directly returns to L1
  TLB
* For requests involving only the second-stage translation, after receiving the
  second-stage translation result
* For requests involving two-stage translation, both the first-stage leaf page
  table and the second-stage leaf page table are obtained.
* Second-stage translation results in a Page fault or Access fault
* PMP or PMA checks result in a Page fault or Access fault, which also needs to
  be returned to L1 TLB

The Last Level Page Table Walker will always return a response to the L1 TLB,
including the following possibilities:

* Non-two-stage translation requests and single-stage translation requests
  accessing leaf nodes (4KB pages)
* For requests involving two-stage translation, both the first-stage leaf page
  table and the second-stage leaf page table are obtained.
* PMP or PMA checks result in an Access fault

## Interface timing

### Interface Timing Between L2 TLB and Repeater

The timing interface between the L2 TLB and the Repeater is shown in
[@fig:L2TLB-repeater-time]. The L2 TLB and Repeater handshake via valid-ready
signals, with the Repeater sending PTW requests and the corresponding virtual
addresses from the L1 TLB to the L2 TLB. The L2 TLB returns the physical address
and corresponding page table to the Repeater after querying the result.

![L2TLB and Repeater Interface
Timing](../figure/image38.svg){#fig:L2TLB-repeater-time}

### Interface timing between L2 TLB and L2 Cache

The timing interface between the L2 TLB and L2 Cache adheres to the TileLink bus
protocol.

