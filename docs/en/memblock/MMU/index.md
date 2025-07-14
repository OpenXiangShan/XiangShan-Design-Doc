# Overview of Memory Management Unit

## Glossary of Terms

Table: Memory Management Unit Terminology Explanation {#tbl:MMU-Term}

| Abbreviation | Full name                                              | Descrption                                                                |
| ------------ | ------------------------------------------------------ | ------------------------------------------------------------------------- |
| MMU          | Memory Management Unit                                 | Memory Management Unit                                                    |
| TLB          | Translation Lookaside Buffer                           | Page table cache                                                          |
| ITLB         | Instruction TLB                                        | Instruction Page Table Cache                                              |
| DTLB         | Data TLB                                               | Data Page Table Cache                                                     |
| L1 TLB       | Level 1 TLB                                            | Level 1 TLB                                                               |
| L2 TLB       | Level 2 TLB                                            | Second-level TLB                                                          |
| SV39         | Page-Based 39-bit Virtual-Memory System                | A paging mechanism defined in the RISC-V manual                           |
| PGD          | Page Global Directory                                  | Page Global Directory                                                     |
| PMD          | Page Mid-level Directory                               | Page middle directory                                                     |
| PTE          | Page Table Entry                                       | Page Table Entry                                                          |
| PTW          | Page Table Walk                                        | Page table lookup process.                                                |
| PMP          | Physical Memory Protection                             | Physical Memory Protection                                                |
| PMA          | Physical Memory Attributes                             | Physical Address Attributes                                               |
| ASID         | Address Space IDentifier                               | Address Space Identifier                                                  |
| CSR          | Control and Status Register                            | Control and status registers                                              |
| VPN          | Virtual Page Number                                    | Virtual Page Number                                                       |
| PPN          | Physical Page Number                                   | Physical Page Number                                                      |
| PLRU         | Pseudo-Least Recently Used                             | an approximate least recently used algorithm                              |
| VMID         | Virtual Machine Identifier                             | Virtual Machine ID                                                        |
| GVPN         | Guest Virtual Page Number                              | Virtual page number for second-stage translation (guest physical address) |
| VS-Stage     | Virtual Superior Stage                                 | First-stage Translation                                                   |
| G-Stage      | Guest Stage                                            | Second-stage translation                                                  |
| SV39x4       | A Variation on Page-Based 39-bit Virtual-Memory System | SV39 with two-bit address extension, root page table now 16KB             |
| HPTW         | Hypervisor Page Table Walker                           | Handles page table lookup for the second-stage translation                |
| GPA          | Guest Physical Address                                 | Guest Physical Address                                                    |

## Design specifications

The overall design specifications of the MMU module are as follows:

1. Supports converting virtual addresses to physical addresses
2. Supports Sv39 paging mechanism
3. Support accessing page tables in memory
4. supports dynamic and static PMP checks
5. Supports dynamic and static PMA checks
6. Supports ASID
7. Support Sfence.vma
8. Support software updates for A/D bits
9. Supports two-stage address translation with the H extension.
10. Supports the Sv39x4 paging mechanism
11. Supports VMID
12. Supports hfence.vvma and hfence.gvma

## Functional Description

The MMU module of Xiangshan consists of L1 TLB, Repeater, L2 TLB, PMP, and PMA
modules, with the L2TLB module further divided into Page Cache, Page Table
Walker, Last Level Page Table Walker, Miss Queue, and Prefetcher. Before memory
read/write operations within the core, including frontend instruction fetch and
backend memory access, address translation is performed by the MMU module.
Frontend instruction fetch and backend memory access perform address translation
via ITLB and DTLB, respectively, both using non-blocking access. The TLB must
return whether a request misses to the request source, which then schedules a
resend of the TLB query until a hit occurs. For missed Load requests, the
Kunming Lake architecture supports TLB Hint, meaning that when the L2 TLB
refills the page table into the L1 TLB, it can precisely wake up Load
instructions blocked due to TLB misses for that virtual address. When L1 TLB
(ITLB or DTLB) misses, it accesses the L2 TLB. If the L2 TLB also misses, the
Page Table Walker accesses the page table in memory.

The Repeater serves as a request buffer between the L1 TLB and L2 TLB, adding
pipeline stages due to the significant physical distance between them. Since
both the ITLB and DTLB support multiple outstanding requests, the Repeater also
functions similarly to an MSHR, filtering duplicate requests. The MMU module
performs permission checks on physical address accesses, divided into PMP and
PMA components. PMP and PMA checks are conducted in parallel, and violating
either permission constitutes an illegal operation. All physical address
accesses within the core must undergo these checks, including after ITLB and
DTLB checks and before Page Table Walker memory accesses.

With the addition of the H extension, the L2TLB now includes a Hypervisor Page
Table Walker module primarily responsible for second-stage translation, along
with partial architectural modifications to the L2TLB.

### Supports Sv39 paging mechanism, translating virtual addresses to physical addresses {#sec:MMU-Support-Sv39}

To achieve process isolation, each process has its own address space and uses
virtual addresses. The MMU translates virtual addresses into physical addresses,
which are then used for memory access. The Xiangshan processor's Kunminghu
architecture supports the Sv39 paging mechanism (see the RISC-V Privileged
Specification), with a 39-bit virtual address. The lower 12 bits are the page
offset, and the upper 27 bits are divided into three segments (9 bits each),
forming a three-level page table. The Kunminghu architecture uses a 36-bit
physical address. The structures of virtual and physical addresses are shown in
[@fig:MMU-Sv39Vaddr; @fig:MMU-Sv39Paddr]. Traversing the page table requires
three memory accesses, necessitating the use of a TLB to cache page tables.

![Virtual Address Structure of Xiangshan
Processor](figure/image1.png){#fig:MMU-Sv39Vaddr}

![Physical Address Structure of Xiangshan
Processor](figure/image2.png){#fig:MMU-Sv39Paddr}

During address translation, frontend instruction fetch performs address
translation via ITLB, while backend memory access uses DTLB. If ITLB or DTLB
miss, requests are sent to the L2 TLB via the Repeater. In the current design,
both frontend instruction fetch and backend memory access employ non-blocking
TLB access—when a request misses, the miss information is returned, and the
request source schedules a resend of the TLB query until a hit occurs.

Additionally, the memory access features 2 Load pipelines, 2 Store pipelines,
along with an SMS prefetcher and an L1 Load stream & stride prefetcher. To
handle numerous requests, the two Load pipelines and the L1 Load stream & stride
prefetcher utilize the Load DTLB, the two Store pipelines use the Store DTLB,
and prefetch requests employ the Prefetch DTLB, totaling 3 DTLBs.

To avoid duplicate entries in the TLB, the ITLB repeater and DTLB repeater
receive requests from the ITLB and DTLB respectively, filtering out duplicate
requests before forwarding them to the L2 TLB. If an L2 TLB miss occurs, the
Hardware Page Table Walker is used to access the page table contents in memory.
The retrieved page table contents are then returned to the Repeater and
ultimately back to the ITLB and DTLB. (Refer to [@sec:MMU-overall] [Overall
Design](#sec:MMU-overall))

### Supports two-stage address translation for virtualization.

After the H extension is added, in non-virtualization mode and without executing
virtualization memory access instructions, the address translation process
remains largely the same as without the H extension. In virtualization mode or
when executing virtualization memory access instructions, the two-stage
translation (VS-stage and G-stage) is determined by vsatp and hgatp. The
VS-stage converts guest virtual addresses to guest physical addresses, while the
G-stage converts guest physical addresses to host physical addresses. The
first-stage translation is similar to non-virtualized translation, and the
second-stage translation is performed in the PTW and LLPTW modules. The lookup
logic is as follows: first, search the Page Cache; if found, return to PTW or
LLPTW; if not found, proceed to HPTW for translation, which then returns and
populates the Page Cache.

In G-stage, the paging mechanism is called Sv39x4, where virtual addresses in
this mode are 41 bits wide, and the root page table expands to 16KB.

![Virtual address structure (guest physical address) of the Xiangshan
processor's Sv39x4](figure/image3.png)

In two-stage address translation, the addresses obtained from the first stage of
translation (including the page table addresses calculated during the
translation process) are all guest physical addresses. These must undergo a
second stage of translation to obtain the actual physical addresses before
memory access can proceed to read the page tables. The logical translation
process is illustrated as follows
[@fig:MMU-two-stage-sv39;@fig:MMU-two-stage-sv48].

![Sv39 - Sv39x4 Two-Stage Address Translation
Process](figure/two-stage-translation-sv39-sv39x4.svg){#fig:MMU-two-stage-sv39}

![Sv48 - Sv48x4 Two-Stage Address Translation
Process](figure/two-stage-translation-sv48-sv48x4.svg){#fig:MMU-two-stage-sv48}

### Supports accessing page table contents in memory

When the L1 TLB sends a request to the L2 TLB, it first accesses the Page Cache.
For non-two-stage translation requests, if a leaf node is hit, the result is
directly returned to the L1 TLB. Otherwise, based on the page table level hit in
the Page Cache and the availability of the Page Table Walker, Last Level Page
Table Walker, or Miss Queue, the request is forwarded accordingly (see Section
5.3). For two-stage address translation requests, since the Page Cache can only
handle one query at a time, the request first queries the first-stage page table
in the Page Cache. If the first stage hits, the request is sent to the Page
Table Walker for second-stage translation. If the first stage misses, the
request is forwarded to either the Page Table Walker or Last Level Page Table
Walker based on the hit page table level, where second-stage translation is
performed. Second-stage translation requests from the Page Table Walker and Last
Level Page Table Walker are first sent to the Page Cache for querying. If a hit
occurs, the Page Cache directly returns the result to the corresponding module.
If a miss occurs, the request is sent to the Hypervisor Page Table Walker for
translation, with the result returned directly to the Page Table Walker or Last
Level Page Table Walker. The Page Table Walker can only handle one request at a
time, performing Hardware Page Table Walk. It accesses the first two levels of
page tables in memory but not 4KB page tables. If the Page Table Walker hits a
2MB or 1GB leaf node or encounters a Page fault or Access fault, it returns the
result to the L1 TLB; otherwise, the request is forwarded to the Last Level Page
Table Walker to access the final level (4KB) page table in memory. The
Hypervisor Page Table Walker can only process one request at a time, so
second-stage translation requests in the Last Level Page Table Walker are sent
serially. The Hypervisor Page Table Walker may trigger a Page fault or Access
fault, which is returned to the PTW or LLPTW, which in turn returns it to the
L1TLB.

The Page Table Walker, Last Level Page Table Walker, and the newly added
Hypervisor Page Table Walker can all send requests to memory to access page
table contents. Before accessing page table contents in memory via physical
addresses, the physical address must be checked by the PMP and PMA modules (see
Sections 3.2.3 and 5.4). If an access fault occurs, no request is sent to
memory. Requests from the Page Table Walker, Last Level Page Table Walker, and
Hypervisor Page Table Walker are arbitrated and then sent to the L2 Cache via
the TileLink bus. The L2 Cache has a memory access width of 512 bits, so it
returns 8 page table entries per request.

The MMU of Kunming Lake implements a page table compression mechanism that
compresses consecutive page table entries. Specifically, for page table entries
with the same high-order bits of the virtual page number, when the high-order
bits of their physical page numbers and page table attributes are also
identical, these entries can be compressed into a single entry, thereby
increasing the effective capacity of the TLB. Consequently, when the L2 TLB hits
a 4KB page, it can return up to 8 consecutive page table entries (refer to
Section 5.2 for details on the L2 TLB). In the H extension, the page table
compression mechanism related to virtualization extensions in the L1TLB is
invalidated and treated as a single page table entry, while the L2TLB still
employs the page table compression mechanism for virtualization-related entries.

### Supports permission checks for physical address access.

Xiangshan supports PMP and PMA checks, which are performed in parallel.
Violating either permission constitutes an illegal operation. PMP and PMA
implementations are divided across four components: CSR Unit, Frontend,
Memblock, and L2 TLB. In the Kunminghu architecture, both PMP and PMA have 16
entries. For details on PMP/PMA register address spaces and configuration
registers, refer to Section 5.4.

The CSR Unit is responsible for responding to CSR instructions like CSRRW for
reading and writing these PMP and PMA registers. Backups of these PMP and PMA
registers are stored in the Frontend, Memblock, and L2 TLB for address checking.
By pulling the CSR write signals, the consistency of these registers is ensured.
Due to the small size of L1 TLB, the backups of PMP and PMA registers are stored
in the Frontend or Memblock, providing checks for ITLB and DTLB respectively.
The larger size of L2 TLB allows the backups of PMP and PMA registers to be
stored directly within it.

After querying results in the ITLB and DTLB, and before accessing memory with
physical addresses in the L2 TLB, PMP and PMA checks must be performed.
According to the manual, PMP and PMA checks should be dynamic, meaning they must
be performed after TLB translation using the translated physical address for
physical address permission checks. For timing considerations, the PMP & PMA
check results for the DTLB can be queried in advance and stored in the TLB entry
during backfill, which constitutes static checking. Specifically, when the L2
TLB page table entry is backfilled into the DTLB, the backfilled page table
entry is simultaneously sent to PMP and PMA for permission checks. The resulting
attribute bits (including R, W, X, C, Atomic; see Section 5.4 for specific
meanings of these bits) are stored in the DTLB, allowing these check results to
be directly returned to MemBlock without rechecking. To implement static
checking, the granularity of PMP and PMA must be increased to 4KB.

It is important to note that currently, PMP & PMA checks are not the timing
bottleneck for Kunming Lake, hence static checks are not employed; all checks
are performed dynamically, i.e., after obtaining the physical address through
TLB lookup. The Kunming Lake V1 code does not include static checks, only
dynamic checks—please take note again. However, for compatibility, the
granularity of PMP and PMA remains at 4KB.

### supports memory management fence instructions

{{processor_name}} supports memory management fence instructions such as
SFENCE.VMA, HFENCE.VVMA, and HFENCE.GVMA.

When the Sfence.vma instruction is executed, it first writes all contents of the
Store Buffer back to the DCache, then issues a flush signal to various parts of
the MMU. The flush signal is unidirectional, lasting only one cycle with no
return signal. The Sfence.vma instruction ultimately flushes the entire
pipeline, restarting execution from fetch. It cancels all inflight requests,
including those in the Repeater and Filter, as well as inflight requests in the
L1TLB and L2 TLB, and flushes cached page tables in the L1 TLB and L2 TLB based
on the address and ASID. The parameters of the Sfence.vma instruction are shown
in [@fig:MMU-sfence_vma_inst].

![Instruction format of Sfence.vma](figure/image5.png){#fig:MMU-sfence_vma_inst}

Additionally, the Xiangshan Kunminghu architecture supports the Svinval
extension. The format of the Svinval.vma instruction is shown in
[@fig:MMU-svinval_vma_inst], where the meanings of rs1 and rs2 are the same as
those in the Sfence.vma instruction. In the Kunminghu architecture, the internal
implementation of the TLB treats the Svinval.vma and Sfence.vma instructions
identically, with the TLB only accepting the incoming sfence_valid signal and
the corresponding rs1 and rs2 parameters.

![Instruction format of
Svinval.vma](figure/image6.png){#fig:MMU-svinval_vma_inst}

Hfence instructions include Hfence.vvma and Hfence.gvma. The execution effect of
these instructions is similar to Sfence.vma, first writing all contents of the
Store Buffer back to DCache, then issuing refresh signals to various parts of
the MMU. The refresh signal is unidirectional, lasting only one clock cycle with
no return signal. The instruction finally flushes the entire pipeline,
restarting execution from the fetch stage. It cancels all inflight requests,
including those in Repeater and Filter, as well as inflight requests in L1TLB
and L2 TLB. Hfence.vvma refreshes page tables related to VSATP in L1TLB and
L2TLB based on address, ASID, and VMID, while Hfence.gvma refreshes page tables
related to HGATP in L1TLB and L2TLB based on address and VMID.

![Instruction format of Hfence](figure/image7.png)

Additionally, since the Kunminghu architecture supports the Svinval extension,
it includes the hinval.vvma and hinval.gvma instructions, which correspond to
the two hfence instructions respectively.

![Instruction format of Hinval](figure/image8.png)

### Supports ASID and VMID

The Xiangshan Kunminghu architecture supports ASIDs (Address Space Identifiers)
with a length of 16, stored in the SATP register. The format of the SATP
register is shown in [@tbl:MMU-CSR_SATP].

Table: SATP Register Format {#tbl:MMU-CSR_SATP}

| ** bit ** | **field** | **Description**                                                                                                                                                                                                                                                                       |
| :-------: | :-------: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|  [63:60]  |   MODE    | indicates the address translation mode. When this field is 0, it is Bare mode, with no address translation or protection enabled. When this field is 8, it represents the Sv39 address translation mode. If this field has any other value, an illegal instruction fault is reported. |
|  [59:44]  |   ASID    | Address Space Identifier. The length of ASID is configurable as a parameter. For the Sv39 address translation mode adopted by the Xiangshan Kunminghu architecture, the maximum length of ASID is 16.                                                                                 |
|  [43:0]   |    PPN    | Represents the physical page number of the root page table, obtained by right-shifting the physical address by 12 bits.                                                                                                                                                               |

Note that in virtualization mode, SATP is replaced by the VSATP register, and
its PPN field represents the guest physical page number of the guest root page
table, not the actual physical address. Second-stage translation is required to
obtain the real physical address.

The Xiangshan Kunming Lake architecture supports a 14-bit VMID (Virtual Machine
Identifier), stored in the HGATP register. The format of the HGATP register is
shown in [@tbl:MMU-CSR_HGATP].

Table: HGATP Register Format {#tbl:MMU-CSR_HGATP}

| ** bit ** | **field** |                                                                                                                   **Description**                                                                                                                    |
| :-------: | :-------: | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------: |
|  [63:60]  |   MODE    | Indicates the address translation mode. When this field is 0, it is Bare mode with no address translation or protection enabled. A value of 8 represents Sv39x4 address translation mode. Any other value will trigger an illegal instruction fault. |
|  [57:44]  |   VMID    |                                                 Virtual machine identifier. For the Sv39x4 address translation mode adopted by the Xiangshan Kunminghu architecture, the maximum VMID length is 14.                                                  |
|  [43:0]   |    PPN    |                                               Represents the physical page number of the root page table for the second-stage translation, obtained by right-shifting the physical address by 12 bits.                                               |

### Support software updates for A/D bits

Xiangshan supports software management of A/D bits in page tables. The A bit
indicates that the page has been read, written, or fetched since the last time
the A bit was cleared. The D bit indicates that the page has been written since
the last time the D bit was cleared. The manual allows updating A/D bits through
either software or hardware methods. Xiangshan opts for the software approach,
triggering a page fault under the following two conditions to update the page
table via software.

* accessing a page where the A bit of its page table is 0
* Writing to a page where the D bit of its page table entry is 0.

Note that the current Xiangshan Kunminghu architecture does not support hardware
updates to the A/D bits.

### Supports exception handling mechanism

When PMP or PMA checks report an access fault, or in cases of page fault or
guest page fault, the TLB module will return exceptions to the Frontend via ITLB
or to the Memblock via DTLB, depending on the source of the PTW request. The
types of exceptions the TLB module may return to the Frontend and Memblock are
listed in Table 3.3, with Memblock further divided into LoadUnit, AtomicsUnit,
and StoreUnit. The TLB module is only responsible for returning access faults,
page faults, or guest page faults to the Frontend or Memblock, with subsequent
handling performed by the Frontend or Memblock. For a summary and explanation of
exception handling, refer to [@sec:MMU-exception] [Exception Handling
Mechanism](#sec:MMU-exception).

Table: Types of Exceptions Returned by TLB

| **type**  |     **destination**      |                     **Description**                     |
| :-------: | :----------------------: | :-----------------------------------------------------: |
| pf_instr  |         Frontend         |    Indicates an instruction page fault has occurred.    |
| af_instr  |         Frontend         |     Indicates an instruction access fault occurred      |
| gpf_instr |         Frontend         | Indicates an instruction guest page fault has occurred. |
|   pf_ld   | LoadUnit or AtomicsUnit  |          Indicates a load page fault occurred           |
|   af_ld   | LoadUnit or AtomicsUnit  |         indicates a load access fault occurred          |
|  gpf_ld   | LoadUnit or AtomicsUnit  |     Indicates a load guest page fault has occurred.     |
|   pf_st   | StoreUnit or AtomicsUnit |          Indicates a store page fault occurred          |
|   af_st   | StoreUnit or AtomicsUnit |         Indicates a store access fault occurred         |
|  gpf_st   | StoreUnit or AtomicsUnit |    Indicates a store guest page fault has occurred.     |

## Exception Handling Mechanism {#sec:MMU-exception}

The MMU module may generate exceptions including: guest page fault, page fault,
access fault, and ECC check errors in the L2 TLB Page Cache. The ITLB, DTLB, and
L2 TLB can all generate guest page fault, page fault, and access fault. For
exceptions generated by ITLB and DTLB, they are handled by the module that sent
the physical address query based on the request source. ITLB exceptions are
delivered to Icache or IFU; DTLB exceptions are delivered to LoadUnits,
StoreUnits, or AtomicsUnit for processing.

If the L2 TLB encounters a guest page fault, page fault, or access fault, it
does not directly handle the exception. Instead, it returns the information to
the L1 TLB. Upon detecting such faults during a query, the L1 TLB generates
different types of exceptions based on the request's cmd and delivers them to
the respective modules for processing according to the request source.

The Page Cache in L2 TLB supports ECC checking. If an ECC error is detected, it
does not raise an exception but sends a miss signal to the L2 TLB for that
request. Meanwhile, the Page Cache refreshes the entry with the ECC error and
reissues a PTW request for Page Walk.

In other words, the MMU module only handles ECC check errors for the Page Cache
in the L2 TLB. Any page faults or access faults generated are handed over to the
front-end or back-end pipeline for processing.

Possible exceptions and the MMU module's handling process are shown in
[@tbl:MMU-exceptions]:

Table: Possible MMU exceptions and handling procedures {#tbl:MMU-exceptions}

| **module** |     **Possible Exceptions**     |                                 ** processing flow **                                  |
| :--------: | :-----------------------------: | :------------------------------------------------------------------------------------: |
|    ITLB    |                                 |                                                                                        |
|            |    Generate inst page fault     |            Deliver to Icache or IFU for processing based on request source             |
|            | Generate inst guest page fault  |            Deliver to Icache or IFU for processing based on request source             |
|            |   Generate inst access fault    |            Deliver to Icache or IFU for processing based on request source             |
|    DTLB    |                                 |                                                                                        |
|            |   Generates a load page fault   |                         Hand over to LoadUnits for processing.                         |
|            | Generate load guest page fault  |                         Hand over to LoadUnits for processing.                         |
|            |    Generate store page fault    | Based on the request source, it is processed by StoreUnits or AtomicsUnit respectively |
|            | Generate store guest page fault | Based on the request source, it is processed by StoreUnits or AtomicsUnit respectively |
|            |  Generate a load access fault   |                         Hand over to LoadUnits for processing.                         |
|            |   Generate store access fault   | Based on the request source, it is processed by StoreUnits or AtomicsUnit respectively |
|   L2 TLB   |                                 |                                                                                        |
|            |    Generate guest page fault    |          Delivered to L1 TLB, which processes the request based on its origin          |
|            |       Generate page fault       |          Delivered to L1 TLB, which processes the request based on its origin          |
|            |      Generate access fault      |          Delivered to L1 TLB, which processes the request based on its origin          |
|            |         ECC check error         |       Invalidate the current entry, return a miss result, and restart Page Walk.       |


## Overall Design {#sec:MMU-overall}

The overall architecture of the MMU is shown in [@fig:MMU-arch-overall].

![MMU Module Overall Block Diagram](figure/image9.jpeg){#fig:MMU-arch-overall}

The ITLB receives PTW requests from the Frontend, while the DTLB receives PTW
requests from the Memblock. PTW requests from the Frontend include 3 requests
from the ICache and 1 request from the IFU. PTW requests from the Memblock
include 2 requests from the LoadUnit (with the AtomicsUnit occupying one of the
LoadUnit's request channels), 1 request from the L1 Load stream & stride
prefetcher, 2 requests from the StoreUnit, and 1 request from the SMSPrefetcher.
The ITLB and DTLB connect to the L2 TLB via Repeaters, both supporting
non-blocking access. These Repeaters, in addition to their pipelining function,
incorporate a duplicate request filtering mechanism to eliminate redundant
requests sent from the L1 TLB to the L2 TLB, preventing duplicates in the L1
TLB.

Requests from the ITLB and DTLB are first arbitrated (via a 2-to-1 Arbiter) and
then access the Page Cache. For non-two-stage address translation requests, if a
leaf node is hit, the result is directly returned to the L1 TLB. If not, the
request is forwarded to the Page Table Walker, Last Level Page Table Walker, or
Miss Queue (see Section 5.3) based on the page table level hit in the Page Cache
and the availability of the Page Table Walker and Last Level Page Table Walker.
Requests from the Miss Queue or Prefetcher are arbitrated (via a 3-to-1 Arbiter)
alongside requests from the L1 TLB before re-accessing the Page Cache. For
two-stage address translation requests: if both stages are enabled and the
first-stage page table is hit, the request is sent to the PTW for second-stage
translation; otherwise, it is forwarded to the PTW, LLPTW, or Miss Queue based
on the first-stage hit level and their availability. If only the first stage is
enabled, processing resembles non-two-stage requests. If only the second stage
is enabled and the query succeeds, the result is returned to the L1 TLB;
otherwise, it is sent to the PTW for second-stage translation. Additionally, the
Page Cache handles isHptwReq-flagged requests (indicating second-stage
translation). If such a request hits in the Page Cache, it is sent to
hptw_resp_arb; if not, it is forwarded to the HPTW for querying, with results
sent to hptw_resp_arb.

Both the Page Table Walker and Last Level Page Table Walker can perform the
second stage of address translation. In PTW and LLPTW, if it is a two-stage
address translation request, the addresses obtained from PTEs are guest physical
addresses, which must undergo a second-stage translation to obtain the actual
physical address before memory access. Refer to the PTW and LLPTW module
descriptions for details.

Both the Page Table Walker and the Last Level Page Table Walker can send
requests to memory to access page table contents. Before accessing page table
contents in memory via physical addresses, the physical addresses must be
checked by the PMP and PMA modules. If an access fault occurs, no request will
be sent to memory. Requests from the Page Table Walker and the Last Level Page
Table Walker are arbitrated (Memory Arbiter 2to1) and then sent to the L2 Cache
via the TileLink bus. In addition to sending physical addresses to the L2 Cache,
the L2 TLB also needs to indicate the request source via an ID. The memory
access width of the L2 Cache is 512 bits, so each access returns 8 page table
entries. The returned page tables from each memory access are refilled into the
Page Cache.

After obtaining results from ITLB and DTLB queries, and before L2 TLB performs
Page Table Walker, PMP and PMA checks are required. Due to the small size of L1
TLB, backups of PMP and PMA registers are not stored within L1 TLB but in
Frontend or Memblock, providing checks for ITLB and DTLB respectively. L2 TLB
has a larger area, with PMP and PMA register backups stored directly within it.

## Interface list

The interface list between the MMU module and upper-level modules is shown in
[@tbl:MMU-IO-list].

Table: MMU IO Interface List {#tbl:MMU-IO-list}

| **upper module** | **Module Name** |     **Instance name**      |                             **Description**                             |
| :--------------: | :-------------: | :------------------------: | :---------------------------------------------------------------------: |
|     Frontend     |                 |                            |                                                                         |
|                  |       TLB       |            itlb            |                     ITLB, introduced in Section 5.1                     |
|                  |       PMP       |            pmp             |          Distributed PMP registers, introduced in Section 5.4.          |
|                  |   PMPChecker    |         PMPChecker         |                 PMP checker, introduced in Section 5.4                  |
|                  |   PMPChecker    |        PMPChecker_1        |                 PMP checker, introduced in Section 5.4                  |
|                  |   PMPChecker    |        PMPChecker_2        |                 PMP checker, introduced in Section 5.4                  |
|                  |   PMPChecker    |        PMPChecker_3        |                 PMP checker, introduced in Section 5.4                  |
|                  |    PTWFilter    |       itlbRepeater1        |   Repeater1 connecting the ITLB and L2 TLB, described in Section 5.2    |
|                  |  PTWRepeaterNB  |       itlbRepeater2        |     Repeater2 connecting ITLB and L2 TLB, introduced in Section 5.2     |
|     MemBlock     |                 |                            |                                                                         |
|                  |   TLBNonBlock   |       dtlb_ld_tlb_ld       |                  Load DTLB, introduced in Section 5.1                   |
|                  |  TLBNonBlock_1  |       dtlb_ld_tlb_st       |                  Store DTLB, introduced in Section 5.1                  |
|                  |  TLBNonBlock_2  | dtlb_prefetch_tlb_prefetch |                Prefetch DTLB, introduced in Section 5.1                 |
|                  |  PTWNewFilter   |        dtlbRepeater        |     Repeater1 connecting DTLB and L2 TLB, introduced in Section 5.2     |
|                  |  PTWRepeaterNB  |       itlbRepeater3        |     Repeater3 connecting ITLB and L2 TLB, introduced in Section 5.2     |
|                  |      PMP_2      |            pmp             |          Distributed PMP registers, introduced in Section 5.4.          |
|                  |  PMPChecker_8   |         PMPChecker         |                 PMP checker, introduced in Section 5.4                  |
|                  |  PMPChecker_8   |        PMPChecker_1        |                 PMP checker, introduced in Section 5.4                  |
|                  |  PMPChecker_8   |        PMPChecker_2        |                 PMP checker, introduced in Section 5.4                  |
|                  |  PMPChecker_8   |        PMPChecker_3        |                 PMP checker, introduced in Section 5.4                  |
|                  |  PMPChecker_8   |        PMPChecker_4        |                 PMP checker, introduced in Section 5.4                  |
|                  |  PMPChecker_8   |        PMPChecker_5        |                 PMP checker, introduced in Section 5.4                  |
|                  |  L2TLBWrapper   |            ptw             |                    L2 TLB, introduced in Section 5.3                    |
|                  |   TLBuffer_20   |      ptw_to_l2_buffer      | The buffer between the L2 TLB and L2 Cache is described in Section 5.3. |

List of interfaces between L2 TLB module components and L2 TLB

Table: L2 TLB IO Interface List

| **upper module** | **Module Name** | **Instance name** |                          **Description**                           |
| :--------------: | :-------------: | :---------------: | :----------------------------------------------------------------: |
|   L2TLBWrapper   |                 |                   |                                                                    |
|                  |      L2TLB      |        ptw        |                 L2 TLB, introduced in Section 5.3                  |
|      L2TLB       |                 |                   |                                                                    |
|                  |       PMP       |        pmp        |       Distributed PMP registers, introduced in Section 5.4.        |
|                  |   PMPChecker    |    PMPChecker     |               PMP checker, introduced in Section 5.4               |
|                  |   PMPChecker    |   PMPChecker_1    |               PMP checker, introduced in Section 5.4               |
|                  | L2TlbMissQueue  |     missQueue     |           L2 TLB Miss Queue, described in Section 5.3.11           |
|                  |    PtwCache     |       cache       |       L2 TLB Page Table Cache, introduced in Section 5.3.7.        |
|                  |       PTW       |        ptw        |       L2 TLB Page Table Walker, introduced in Section 5.3.8        |
|                  |      LLPTW      |       llptw       |  L2 TLB Last Level Page Table Walker, introduced in Section 5.3.9  |
|                  |      HPTW       |       hptw        | L2 TLB Hypervisor Page Table Walker, introduced in Section 5.3.10. |
|                  |  L2TlbPrefetch  |     prefetch      |       The L2 TLB Prefetcher is introduced in Section 5.3.12.       |

Refer to the interface list documentation for details. Additionally, certain
arbiters are involved but omitted from the interface list.

## Interface timing

The overall MMU interfaces with the external environment involve the L1 TLB
interfaces with Frontend and Memblock, as well as the L2 TLB interfaces with
memory (L2 Cache).

The interface timing between L1 TLB and Frontend, Memblock can be found in
[@sec:ITLB-time-frontend] [ITLB and Frontend Interface
Timing](./L1TLB.md#sec:ITLB-time-frontend), [@sec:DTLB-time-memblock] [DTLB and
Memblock Interface Timing](./L1TLB.md#sec:DTLB-time-memblock).

The timing interface between the L2 TLB and L2 Cache adheres to the TileLink bus
protocol.

