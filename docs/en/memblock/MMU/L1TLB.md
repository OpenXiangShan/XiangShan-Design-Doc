# Secondary Module L1 TLB

## Design specifications

1. Supports receiving address translation requests from the Frontend and
   MemBlock.
2. Supports the PLRU replacement algorithm.
3. Supports returning physical addresses to the Frontend and MemBlock.
4. Both the ITLB and DTLB employ non-blocking access.
5. Both ITLB and DTLB entries are implemented using register files
6. Both ITLB and DTLB entries are fully associative structures
7. ITLB and DTLB adopt the current privilege level of the processor and the
   effective privilege level for memory access execution
8. Supports determining whether virtual memory is enabled and whether two-stage
   translation is enabled within the L1 TLB.
9. Support sending PTW requests to L2 TLB
10. The DTLB supports copying the returned physical address.
11. Support for exception handling
12. Supports TLB compression
13. Support TLB Hint mechanism
14. Stores four types of TLB entries.
15. TLB refill merges the two stages of page tables.
16. The hit logic for TLB entries.
17. Supports reissuing PTW to obtain gpaddr after a guest page fault.

## Function

### Receives address translation requests from the Frontend and MemBlock.

Before performing memory read/write operations within the core, including
frontend instruction fetching and backend memory access, address translation
must be performed by the L1 TLB. Due to physical distance and to avoid mutual
contamination, it is divided into the ITLB (Instruction TLB) for frontend
instruction fetching and the DTLB (Data TLB) for backend memory access. The ITLB
operates in a fully associative mode, with 48 fully associative entries storing
all page sizes. The ITLB receives address translation requests from the
Frontend, where itlb_requestors(0) to itlb_requestors(2) come from the icache,
with itlb_requestors(2) being the prefetch request from the icache;
itlb_requestors(3) comes from the ifu, representing the address translation
request for MMIO instructions.

The configuration of ITLB entries and request sources are detailed in
[@tbl:ITLB-config;@tbl:ITLB-request-source].

Table: ITLB Entry Configuration {#tbl:ITLB-config}

| **Item name** | **item count** | **Organization structure ** | **Replacement Algorithm** | **stored content** |
| :-----------: | :------------: | :-------------------------: | :-----------------------: | :----------------: |
|     Page      |       48       |      Fully associative      |           PLRU            |   All size pages   |


Table: ITLB Request Sources {#tbl:ITLB-request-source}

| **Serial number** |      **Source**       |
| :---------------: | :-------------------: |
|   requestors(0)   |   Icache, mainPipe    |
|   requestors(1)   |   Icache, mainPipe    |
|   requestors(2)   | Icache, fdipPrefetch. |
|   requestors(3)   |          IFU          |

Xiangshan's memory access channels consist of 2 Load pipelines, 2 Store
pipelines, an SMS prefetcher, and an L1 Load stream & stride prefetcher. To
handle the numerous requests, the two Load pipelines and the L1 Load stream &
stride prefetcher use the Load DTLB, the two Store pipelines use the Store DTLB,
and prefetch requests use the Prefetch DTLB—totaling 3 DTLBs, all employing the
PLRU replacement algorithm (see Section 5.1.1.2).

The DTLB operates in a fully associative mode, with 48 fully associative entries
storing all page sizes. The DTLB receives address translation requests from
MemBlock, where dtlb_ld handles requests from loadUnits and the L1 Load stream &
stride prefetcher, responsible for address translation of Load instructions;
dtlb_st processes requests from StoreUnits, handling address translation for
Store instructions. Notably, for AMO instructions, the dtlb_ld_requestor of
loadUnit(0) is used to send requests to dtlb_ld. The SMSPrefetcher sends
prefetch requests to a separate DTLB.

The configuration and request sources of DTLB entries are as shown in
[@tbl:DTLB-config;@tbl:DTLB-request-source].

Table: DTLB Entry Configuration {#tbl:DTLB-config}

| **Item name** | **item count** | **Organization structure ** | **Replacement Algorithm** | **stored content** |
| :-----------: | :------------: | :-------------------------: | :-----------------------: | :----------------: |
|     Page      |       48       |      Fully associative      |           PLRU            |   All size pages   |


Table: DTLB Request Sources {#tbl:DTLB-request-source}

| **module** | **Serial number** |            **Source**             |
| :--------: | :---------------: | :-------------------------------: |
|  DTLB_LD   |                   |                                   |
|            | ld_requestors(0)  |     loadUnit(0), AtomicsUnit      |
|            | ld_requestors(1)  |            loadUnit(1)            |
|            | ld_requestors(2)  |            loadUnit(2)            |
|            | ld_requestors(3)  | L1 Load stream & stride Prefetch. |
|  DTLB_ST   |                   |                                   |
|            | st_requestors(0)  |           StoreUnit(0)            |
|            | st_requestors(1)  |           StoreUnit(1)            |
|  DTLB_PF   |                   |                                   |
|            | pf_requestors(0)  |            SMSPrefetch            |
|            | pf_requestors(1)  |            L2 Prefetch            |

### Uses the PLRU replacement algorithm

L1 TLB employs a configurable replacement policy, defaulting to the PLRU
algorithm. In the Nanhu architecture, both ITLB and DTLB include NormalPage and
SuperPage, complicating the refill strategy. ITLB's NormalPage handles 4KB page
translations, while SuperPage handles 2MB and 1GB page translations, requiring
entries to be filled into NormalPage or SuperPage based on the refilled page
size (4KB, 2MB, or 1GB). DTLB's NormalPage handles 4KB page translations, while
SuperPage handles all page sizes. NormalPage uses direct mapping with many
entries but low utilization. SuperPage is fully associative with high
utilization but fewer entries due to timing constraints, resulting in a high
miss rate.

Note that the Kunminghu architecture optimizes the above issues by unifying the
ITLB and DTLB as 48-entry fully associative structures under timing constraints,
allowing any page size to be refilled. Both ITLB and DTLB use the PLRU
replacement strategy.

The refill policies for ITLB and DTLB are shown in [@tbl:L1TLB-refill-policy].

Table: ITLB and DTLB refill policy {#tbl:L1TLB-refill-policy}

| **module** | **Item name** |                              **Policy**                              |
| :--------: | :-----------: | :------------------------------------------------------------------: |
|    ITLB    |               |                                                                      |
|            |     Page      | 48-entry fully associative, capable of backfilling pages of any size |
|    DTLB    |               |                                                                      |
|            |     Page      | 48-entry fully associative, capable of backfilling pages of any size |

### Returns the physical address to the Frontend and MemBlock.

After obtaining the physical address from the virtual address in the L1 TLB, the
corresponding physical address of the request, along with information such as
whether a miss occurred, guest page fault, page fault, or access fault, is
returned to the Frontend and MemBlock. For each request in the Frontend or
MemBlock, a response is sent by the ITLB or DTLB, indicated by
tlb_requestor(i)\_resp_valid to signify the response is valid.

In the Nanhu architecture, although SuperPage and NormalPage are physically
implemented using register files, SuperPage is a 16-entry fully associative
structure, while NormalPage is a direct-mapped structure. After reading data
from the direct-mapped NormalPage, a tag comparison is required. Despite the
SuperPage having 16 fully associative entries, only one entry can be hit at a
time, which is marked by hitVec to select the data read from the SuperPage. The
time taken to read data + tag comparison in NormalPage is significantly longer
than reading data + selecting data in SuperPage. Therefore, from a timing
perspective, the dtlb returns a fast_miss signal to the MemBlock, indicating a
SuperPage miss, and a miss signal indicating both SuperPage and NormalPage
misses.

Meanwhile, in the Nanhu architecture, due to tight timing constraints for PMP &
PMA checks in the DTLB, the PMP is divided into dynamic and static checks (see
Section 5.4). When the L2 TLB's page table entry is refilled into the DTLB, the
refilled entry is simultaneously sent to the PMP and PMA for permission checks,
with the results stored in the DTLB. The DTLB must additionally return a signal
indicating the validity of the static check and the check results to the
MemBlock.

It is important to note that the Kunminghu architecture optimizes TLB query
configurations and corresponding timing. Currently, fast_miss has been removed,
and no additional static PMP & PMA checks are required. However, these may be
reinstated in the future due to timing or other reasons. For documentation
completeness and compatibility, the previous two sections are retained. The
Kunminghu architecture has eliminated fast_miss and static PMP & PMA
checks—please take note again.

### Blocking and non-blocking accesses

In the Nanhu architecture, the frontend's instruction fetch requires blocking
access to the ITLB, while the backend's memory access requires non-blocking
access to the DTLB. In reality, the TLB itself is non-blocking and does not
store request information. The reason for blocking or non-blocking access lies
in the requirements of the request source. When the frontend encounters a TLB
miss during instruction fetch, it must wait for the TLB to retrieve the result
before sending the instruction to the processor backend for processing,
resulting in a blocking effect. In contrast, memory operations can be scheduled
out-of-order. If one request misses, another load/store instruction can be
scheduled for execution, thus exhibiting a non-blocking effect.

The above functionality in the Nanhu architecture is implemented via TLB, where
control logic ensures that after an ITLB miss, it continuously waits for the PTW
to retrieve the page table entry. In Kunminghu, this functionality is guaranteed
by ICache, where after an ITLB miss is reported to ICache, ICache continuously
resends the same request until a hit, ensuring non-blocking access.

However, it should be noted that in the Kunminghu architecture, both the ITLB
and DTLB are non-blocking. Whether the external effect is blocking or
non-blocking is controlled by the fetch unit or memory access unit.

### Storage structure of L1 TLB entries.

Xiangshan's TLB allows configuration of organizational structures, including
associative modes, entry counts, and replacement policies. The default
configuration is: both ITLB and DTLB are 48-entry fully associative structures,
implemented by register files (see Section 5.1.2.3). If simultaneous read and
write operations to the same address occur in the same cycle, results can be
obtained directly via bypass.

Referenced ITLB or DTLB configuration: Both employ a fully associative structure
with 8/16/32/48 entries. Currently, parameterized modification of TLB structures
(fully associative/set-associative/direct-mapped) is not supported and requires
manual code changes.

### Supports determining whether virtual memory is enabled and whether two-stage translation is enabled within the L1 TLB.

Xiangshan supports the Sv39 page table specified in the RISC-V manual, with a
virtual address length of 39 bits. Xiangshan's physical address is 36 bits,
which can be modified parametrically.

Determining whether virtual memory is enabled depends on the privilege level and
the MODE field of the SATP register, among other factors. This decision is made
internally by the TLB and is transparent to external modules. For details on
privilege levels, refer to Section 5.1.2.7. Regarding the SATP MODE field, the
Kunminghu architecture of Xiangshan only supports MODE=8, corresponding to the
Sv39 paging mechanism; otherwise, an illegal instruction fault is raised. From
the perspective of external modules (Frontend, LoadUnit, StoreUnit, AtomicsUnit,
etc.), all addresses have undergone TLB translation.

When the H extension is added, enabling address translation also requires
determining whether two-stage address translation is active. Two-stage address
translation is triggered under two conditions: first, when executing a
virtualization memory access instruction, and second, when virtualization mode
is enabled and the MODE field of VSATP or HGATP is non-zero. The translation
modes in this scenario are as follows. The translation mode is used to search
for the corresponding type of page table in the TLB and to send PTW requests to
the L2TLB.

Table: Two-Stage Translation Mode

| **VSATP Mode** | **HGATP Mode** |                 **Translation Mode**                  |
| :------------: | :------------: | :---------------------------------------------------: |
|    Non-zero    |    Non-zero    |       allStage, both translation stages present       |
|    Non-zero    |       0        |       onlyStage1, only first-stage translation        |
|       0        |    Non-zero    | onlyStage2, indicating only second-stage translation. |

### Privilege level of L1 TLB.

According to the RISC-V manual requirements, the privilege level for frontend
instruction fetch (ITLB) is the current processor privilege level, while the
privilege level for backend memory access (DTLB) is the effective memory access
execution privilege level. Both the current processor privilege level and the
effective memory access execution privilege level are determined in the CSR
module and passed to the ITLB and DTLB. The current processor privilege level is
stored in the CSR module; the effective memory access execution privilege level
is determined by the MPRV, MPV, and MPP bits of the mstatus register, along with
the SPVP bit of the hstatus register. If executing a virtualized memory access
instruction, the effective memory access execution privilege level is the
privilege level stored in the SPVP bit of hstatus. If the executed instruction
is not a virtualized memory access instruction and the MPRV bit is 0, the
effective memory access execution privilege level is the same as the current
processor privilege level, and the effective virtualization mode for memory
access also matches the current virtualization mode. If the MPRV bit is 1, the
effective memory access execution privilege level is the privilege level stored
in the MPP field of the mstatus register, and the effective virtualization mode
is the virtualization mode stored in the MPV bit of the hstatus register. The
privilege levels for ITLB and DTLB are as shown in the table.

Table: Privilege Levels of ITLB and DTLB

| **module** |                                                                                                                             **Privilege Level**                                                                                                                             |
| :--------: | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------: |
|    ITLB    |                                                                                                                      Current processor privilege level                                                                                                                      |
|    DTLB    | When executing non-virtualized memory access instructions, if mstatus.MPRV=0, the current processor privilege level and virtualization mode are used; if mstatus.MPRV=1, the privilege level saved in mtatus.MPP and the virtualization mode saved in hstatus.MPV are used. |

### Send PTW request

When an L1 TLB miss occurs, a Page Table Walk request must be sent to the L2
TLB. Due to the significant physical distance between L1 TLB and L2 TLB,
intermediate pipeline stages, known as Repeaters, are required. Additionally,
the repeater must filter out duplicate requests to prevent redundant entries in
the L1 TLB (see Section 5.2). Hence, the first-level Repeater for ITLB or DTLB
is also referred to as a Filter. The L1 TLB sends PTW requests and receives PTW
responses via the Repeater to/from the L2 TLB (see Section 5.3).

### DTLB copies the queried physical address.

In physical implementation, the dcache of Memblock is located far from the lsu.
Generating hitVec in the load_s1 stage of LoadUnit and then sending it
separately to dcache and lsu would cause severe timing issues. Therefore, it is
necessary to generate two hitVec in parallel near dcache and lsu, sending them
to dcache and lsu respectively. To address the timing issues of Memblock, the
DTLB needs to duplicate the queried physical address into two copies, sending
them to dcache and lsu separately, with both physical addresses being identical.

### Exception Handling Mechanism

Exceptions that ITLB may generate include inst guest page fault, inst page
fault, and inst access fault, all of which are delivered to the requesting
ICache or IFU for handling. DTLB may generate exceptions such as load guest page
fault, load page fault, load access fault, store guest page fault, store page
fault, and store access fault, all delivered to the requesting LoadUnits,
StoreUnits, or AtomicsUnit for handling. L1TLB does not store gpaddr, so when a
guest page fault occurs, PTW must be reinitiated. Refer to Section 6 of this
document: Exception Handling Mechanism.

Additional clarification is needed regarding exceptions related to
virtual-to-physical address translation. Here, we categorize exceptions as
follows:

1. Page table-related exceptions
   1. In non-virtualized scenarios or during VS-Stage virtualization, if the
      page table has reserved bits not equal to 0, is misaligned, lacks write
      permission (w), etc. (see the manual for details), a page fault must be
      reported.
   2. During the virtualization stage (G-Stage), if reserved bits in the page
      table are non-zero, misaligned, or write operations lack 'w' permission
      (refer to the manual for details), a guest page fault must be reported.
2. Exceptions related to virtual or physical addresses
    1. Exceptions related to virtual or physical addresses during address
       translation. These checks are performed during the PTW process of the L2
       TLB.
       1. In non-virtualized scenarios or during all-Stage virtualization, the
          G-stage gvpn needs to be checked. If hgatp's mode is 8 (representing
          Sv39x4), all bits above (41 - 12 = 29) of gvpn must be 0; if hgatp's
          mode is 9 (representing Sv48x4), all bits above (50 - 12 = 38) of gvpn
          must be 0. Otherwise, a guest page fault will be reported.
       2. When translating an address to obtain a page table, the upper bits
          (above 36, since 48-12=36) of the PPN portion of the page table must
          all be 0. Otherwise, an access fault will be raised.
    2. Exceptions related to virtual or physical addresses in the original
       address are summarized as follows. In theory, these should all be checked
       in the L1 TLB. However, since the ITLB's redirect results come entirely
       from the Backend, the corresponding exceptions in the ITLB will be
       recorded when the Backend sends a redirect to the Frontend and will not
       be rechecked in the ITLB. Please refer to the Backend's explanation for
       details.
       1. Sv39 Mode: Includes cases where virtual memory is enabled without
          virtualization (sATP's mode is 8) or virtual memory is enabled with
          virtualization (vsatp's mode is 8). In this mode, bits [63:39] of the
          vaddr must match the sign of bit 38; otherwise, instruction page
          fault, load page fault, or store page fault will be reported based on
          the fetch/load/store request.
       2. Sv48 mode: Includes scenarios where virtual memory is enabled without
          virtualization (satp mode is 9) or where virtual memory is enabled
          with virtualization (vsatp mode is 9). In these cases, bits [63:48] of
          the vaddr must match the sign of bit 47 of the vaddr. Otherwise,
          depending on whether it's an instruction fetch, load, or store
          request, an instruction page fault, load page fault, or store page
          fault will be raised, respectively.
       3. Sv39x4 Mode: Virtual memory is enabled, virtualization is enabled,
          vsatp's mode is 0, and hgatp's mode is 8. (Note: When vsatp's mode is
          8/9 and hgatp's mode is 8, the second-stage address translation is
          also in Sv39x4 mode, which may generate corresponding exceptions.
          However, these exceptions fall under "exceptions related to virtual or
          physical addresses during address translation" and are handled during
          the page table walk in the L2 TLB, not within the scope of the L1 TLB.
          The L1 TLB only handles "exceptions related to the original virtual or
          physical addresses.") In this mode, bits [63:41] of the vaddr must all
          be 0; otherwise, instruction guest page fault, load guest page fault,
          or store guest page fault will be reported based on the
          fetch/load/store request.
       4. Sv48x4 mode: Virtual memory is enabled, virtualization is enabled,
          vsatp's mode is 0, and hgatp's mode is 9. (Note: When vsatp's mode is
          8/9 and hgatp's mode is 9, the second-stage address translation is
          also in Sv48x4 mode, which may generate corresponding exceptions.
          However, these belong to "exceptions related to virtual or physical
          addresses during address translation" and are handled during the page
          table walk of L2 TLB, not within the scope of L1 TLB. L1 TLB only
          additionally handles "exceptions related to virtual or physical
          addresses in the original address.") In this case, bits [63:50] of
          vaddr must all be 0; otherwise, instruction guest page fault, load
          guest page fault, or store guest page fault must be reported based on
          the fetch/load/store request.
       5. Bare mode: Virtual memory is disabled, so paddr = vaddr. Since the
          physical address of the Xiangshan processor is currently limited to 48
          bits, vaddr must have bits [63:48] all set to 0; otherwise,
          instruction access fault, load access fault, or store access fault
          will be reported based on fetch/load/store requests.

To support the exception handling for the aforementioned "original address," the
L1 TLB needs to add input signals fullva (64 bits) and checkfullva (1 bit).
Additionally, vaNeedExt must be added to the output. Specifically:

1. checkfullva is not a control signal for fullva. In other words, the content
   of fullva is not only valid when checkfullva is asserted.
2. When is checkfullva valid (needs to be asserted)
    1. For ITLB, checkfullva is always false, so when Chisel generates Verilog,
       checkfullva may be optimized out and not reflected in the input.
    2. For the DTLB, all load/store/amo/vector instructions must undergo a
       checkfullva check when first sent from the Backend to the MemBlock. It is
       further clarified that the "exception related to virtual or physical
       addresses in the original address" is a check solely for vaddr (for
       load/store instructions, the vaddr is typically calculated as the value
       of a register plus an immediate value to form a 64-bit value). Therefore,
       it does not require waiting for a TLB hit, and when such an exception
       occurs, the TLB will not return a miss, indicating the exception is
       valid. Thus, "when first sent from the Backend to the MemBlock," this
       exception can always be detected and reported. For misaligned memory
       accesses, they will not enter the misalign buffer; for load instructions,
       they will not enter the load replay queue; for store instructions, they
       will not be resent by the reservation station. Therefore, if the
       exception is not detected "when first sent from the Backend to the
       MemBlock," it will not appear during a load replay, and no checkfullva
       check is needed. For prefetch instructions, checkfullva is not raised.
3. When fullva is valid (when it is used)
    1. Except for one specific case, fullva is only valid when checkfullva is
       high, representing the full vaddr to be checked. It should be noted that
       for a load/store instruction, the original vaddr calculated is 64 bits
       (the value read from the register is 64 bits), but querying the TLB only
       uses the lower 48/50 bits (Sv48/Sv48x4), while querying exceptions
       requires the full 64 bits.
    2. Special case: A misaligned instruction triggers a gpf, requiring
       retrieval of the gpaddr. The current logic for handling misaligned
       exceptions on the memory access side is as follows:
       1. For example, the original vaddr is 0x81000ffb, and an 8-byte data load
          is required.
       2. The misalign buffer splits this instruction into two loads with vaddr
          0x81000ff8 (load 1) and 0x81001000 (load 2), which do not belong to
          the same virtual page.
       3. For load 1, the vaddr passed to the TLB is 0x81000ff8, with fullva
          always being the original vaddr 0x81000ffb; for load 2, the vaddr
          passed to the TLB is 0x81001000, with fullva always being the original
          vaddr 0x81000ffb.
       4. For load 1, if an exception occurs, the offset written to the *tval
          register is defined as the offset of the original addr (i.e., 0xffb).
          For load 2, if an exception occurs, the offset written to the *tval
          register is defined as the starting value of the next page (0x000). In
          virtualization scenarios with onlyStage2, gpaddr equals the vaddr
          where the exception occurred. Thus, for misaligned requests spanning
          pages where the exception occurs on the subsequent page, gpaddr is
          generated using only vaddr (with an offset of 0x000), not fullva. For
          misaligned requests within a single page or spanning pages where the
          exception occurs on the original address, gpaddr is generated using
          the offset from fullva (0xffb). Here, fullva is always valid,
          regardless of whether checkfullva is asserted.
4. When vaNeedExt is valid (under what circumstances it is used)
   1. In the memory access queue (load queue/store queue), to save area, the
      original 64-bit address is truncated to 50 bits for storage. However, when
      writing to the *tval register, a 64-bit value must be written. As
      mentioned earlier, for exceptions related to "virtual or physical
      addresses in the original address," the full 64-bit address must be
      preserved. For other page table-related exceptions, the high bits of the
      address itself meet the requirements. For example:
        * fullva = 0xffff,ffff,8000,0000; vaddr = 0xffff,8000,0000. Mode is
          non-virtualized Sv39. Here, the original address does not trigger an
          exception. Assuming this is a load request, the first TLB access
          results in a miss, so the load enters the load replay queue for
          retransmission, and the address is truncated to 50 bits. Upon
          retransmission, it is discovered that the V bit of the page table is
          0, causing a page fault. The vaddr must be written to the *tval
          register. Since the address was truncated in the load queue replay,
          sign extension is required (e.g., for Sv39, extending bits above 39 to
          the value of bit 38), and vaNeedExt is asserted.
        * fullva = 0x0000,ffff,8000,0000; vaddr = 0xffff,8000,0000. Mode is
          non-virtualized Sv39. Here, it can be observed that the original
          address already triggers an exception, and we will directly write this
          address into the corresponding exception buffer (the exception buffer
          stores the complete 64-bit value). At this point, the original value
          of 0x0000,ffff,8000,0000 must be written directly into *tval without
          sign extension, and vaNeedExt is low.

### Supports the pointer masking extension

Currently, the Xiangshan processor supports the pointer masking extension.

The essence of the pointer masking extension is to transform the fullva of
memory access from the original value of "register file value + imm immediate"
to the "effective vaddr," where higher bits may be ignored. When pmm is 2, the
upper 7 bits are ignored; when pmm is 3, the upper 16 bits are ignored. A pmm of
0 means no higher bits are ignored, and pmm of 1 is reserved.

The value of pmm may come from the PMM bits ([33:32]) of
mseccfg/menvcfg/henvcfg/senvcfg or from the HUPMM bits ([49:48]) of the hstatus
register. The specific selection is as follows:

1. For frontend instruction fetch requests or an hlvx instruction specified in
   the manual, pointer masking (pmm = 0) will not be used.
2. When the current effective memory access privilege level (dmode) is M-mode,
   select the PMM bits ([33:32]) of mseccfg
3. In a non-virtualized scenario, where the current effective memory access
   privilege level is S-mode (HS), select the PMM bits ([33:32]) of menvcfg.
4. In a virtualized scenario, when the current effective memory access privilege
   level is S-mode (VS), select the PMM bits ([33:32]) of henvcfg.
5. For virtualization instructions where the current processor privilege level
   (imode) is U-mode, the HUPMM bits ([49:48]) of hstatus are selected.
6. For other U-mode scenarios, select the PMM bits ([33:32]) of senvcfg.

Since pointer masking only applies to memory accesses and not to frontend
instruction fetching, the ITLB does not have the concept of "effective vaddr"
and does not incorporate these signals from CSR in its ports.

Since these high-order addresses are only checked and used in the aforementioned
"original address, virtual address, or physical address-related exceptions," for
cases where high-order bits are masked, we simply ensure they do not trigger
exceptions. Specifically:

1. For non-virtualized scenarios with virtual memory enabled, or virtualized
   scenarios that are not onlyStage2 (vsatp mode is not 0); depending on whether
   pmm is 2 or 3, sign-extend the upper 7 or 16 bits of the address,
   respectively.
2. For the onlyStage2 case in virtualized scenarios or when virtual memory is
   not enabled, zero-extend the upper 7 or 16 bits of the address based on
   whether the pmm value is 2 or 3, respectively.

### Supports TLB compression

![TLB Compression Diagram](figure/image18.png)

The Kunminghu architecture supports TLB compression, where each compressed TLB
entry stores eight consecutive page table entries, as shown in the figure. The
theoretical basis for TLB compression is that operating systems, due to
mechanisms like buddy allocation, tend to allocate contiguous physical pages to
contiguous virtual pages. Although page allocation becomes less ordered over
time, this page correlation is common. Thus, multiple contiguous page table
entries can be merged into a single TLB entry, effectively increasing TLB
capacity.

In other words, for page table entries with the same upper bits of the virtual
page number, if the upper bits of the physical page number and the page table
attributes are also the same, these entries can be compressed into a single
entry for storage, thereby increasing the effective capacity of the TLB. The
compressed TLB entry shares the upper bits of the physical page number and the
page table attribute bits, while each page table individually retains the lower
bits of the physical page number. The valid field indicates whether the page
table is valid within the compressed TLB entry, as shown in Table 5.1.8.

Table 5.1.8 shows the comparison before and after compression. The tag before
compression is the vpn, while the compressed tag is the upper 24 bits of the
vpn, with the lower 3 bits not needing to be stored. In fact, for the i-th entry
of 8 consecutive page table entries, i corresponds to the lower 3 bits of the
tag. The upper 21 bits of ppn are the same, and ppn_low stores the lower 3 bits
of ppn for each of the 8 entries. Valididx indicates the validity of these 8
entries, where only valididx(i) being 1 means the entry is valid. pteidx(i)
represents the i-th entry corresponding to the original request, i.e., the value
of the lower 3 bits of the original request's vpn.

Here is an illustrative example. For instance, if a vpn is 0x0000154 with the
lower three bits being 100 (i.e., 4), after being filled back into the L1 TLB,
the 8 page table entries from vpn 0x0000150 to 0x0000157 will all be filled back
and compressed into a single entry. For example, if the upper 21 bits of the ppn
for vpn 0x0000154 are PPN0 and the page table attribute bits are PERM0, and if
the upper 21 bits of the ppn and the page table attributes for the i-th entry
among these 8 page tables are also PPN0 and PERM0, then valididx(i) is 1, with
the lower 3 bits of the i-th page table saved via ppn_low(i). Additionally,
pteidx(i) represents the i-th entry corresponding to the original request. Here,
the lower three bits of the original request's vpn are 4, so pteidx(4) is 1,
while all other pteidx(i) are 0.

Additionally, the TLB does not compress query results for large pages (1GB,
2MB). For large pages, every bit of valididx(i) is set to 1 upon return.
According to page table query rules, large pages do not actually use ppn_low, so
the value of ppn_low can be arbitrary.

Table: Contents stored per TLB entry before and after compression

| **compressed or not** | **tag** | **asid** | **level** | **ppn** |       **perm**        | **valididx** | **pteidx** | **ppn_low** |
| :-------------------: | :-----: | :------: | :-------: | :-----: | :-------------------: | :----------: | :--------: | :---------: |
|          No           | 27 bits | 16-bit.  |  2 bits   | 24-bit  | Page table attributes |  Not saved   | Not saved  |  Not saved  |
|          Yes          | 24-bit  | 16-bit.  |  2 bits   | 21 bits | Page table attributes |    8 bits    |   8 bits   |  8×3 bits.  |


After implementing TLB compression, the hit condition of L1 TLB changes from TAG
hit to TAG hit (high bits of vpn match), while also requiring the valididx(i)
indexed by the lower 3 bits of vpn to be valid. PPN is obtained by concatenating
ppn (upper 21 bits) with ppn_low(i).

Note that after adding the H extension, L1TLB entries are divided into four
types. The TLB compression mechanism is not enabled for virtualized TLB entries
(though TLB compression is still used in the L2TLB). These four types will be
described in detail later.

### Stores four types of TLB entries.

The L1 TLB entries have been modified with the addition of the H extension, as
shown in [@fig:L1TLB-item].

![TLB Entry Diagram](figure/image19.png){#fig:L1TLB-item}

Compared to the original design, g_perm, vmid, and s2xlate have been added.
Here, g_perm stores the permission bits of the second-stage page table, vmid
stores the VMID of the second-stage page table, and s2xlate distinguishes the
types of TLB entries. The content stored in TLB entries varies depending on
s2xlate.

Table: Types of TLB entries

|  **type**   | **s2xlate** |                      **tag**                       |                       **ppn**                       |                       **perm**                       |          **g_perm**          |                   **level**                    |
| :---------: | :---------: | :------------------------------------------------: | :-------------------------------------------------: | :--------------------------------------------------: | :--------------------------: | :--------------------------------------------: |
|  noS2xlate  |     b00     |    Virtual page number in non-virtualized mode     |    Physical page number in non-virtualized mode     | Page table entry permissions in non-virtualized mode |           Not used           | Page table entry level in non-virtualized mode |
|  allStage   |     b11     | Virtual page number of the first-stage page table  | Physical page number of the second-stage page table |          First-stage page table permissions          | Second-stage page table perm |   The highest level in two-stage translation   |
| onlyStage1  |     b01     | Virtual page number of the first-stage page table  | Physical page number of the first-stage page table  |          First-stage page table permissions          |           Not used           |      Level of the first-stage page table       |
| onlyStage2. |     b10     | Virtual page number of the second-stage page table | Physical page number of the second-stage page table |                       Not used                       | Second-stage page table perm |      Level of the second-stage page table      |


TLB compression technology is enabled in noS2xlate and onlyStage1 but not in
other cases. In allStage and onlyS2xlate scenarios, the L1TLB hit mechanism uses
pteidx to calculate the tag and ppn of valid ptes, and these two cases also
differ during refill. Furthermore, asid is valid in noS2xlate, allStage, and
onlyStage1, while vmid is valid in allStage and onlyS2xlate.

### TLB refill merges the two stages of page tables.

With the H extension added to the MMU, the PTW response structure is divided
into three parts. The first part, s1, is the original PtwSectorResp, storing the
first-stage translation page table. The second part, s2, is HptwResp, storing
the second-stage translation page table. The third part is s2xlate, indicating
the type of this resp, which can be noS2xlate, allStage, onlyStage1, or
onlyStage2, as shown in [@fig:L1TLB-PTW-resp-struct]. Here, PtwSectorEntry is a
PtwEntry with TLB compression, with the main difference being the length of the
tag and ppn fields.

![Schematic diagram of PTW resp
structure](figure/image20.png){#fig:L1TLB-PTW-resp-struct}

For noS2xlate and onlyStage1 cases, only the s1 result needs to be filled into
the TLB entry, with a method similar to the original design, filling the
corresponding fields of the returned s1 into the entry's corresponding fields.
Note that for noS2xlate, the vmid field is invalid.

For the onlyS2xlate case, we populate the TLB entry with the s2 result. Due to
the TLB compression structure, special handling is required. First, the asid and
perm fields of this entry are unused, so we do not care about the values filled
here. The vmid is populated with the s1 vmid (since the PTW module always fills
this field regardless of the scenario, it can be directly used for writing). The
s2 tag is written into the TLB entry's tag, and the pteidx is determined based
on the lower sectortlbwidth bits of the s2 tag. If s2 is a large page, all
valididx fields in the TLB entry are marked valid; otherwise, only the valididx
corresponding to the pteidx is valid. The ppn field is filled by reusing the
allStage logic, which will be explained in the allStage case.

For allStage, the two-stage page tables must be merged. First, populate the tag,
asid, and vmid based on s1. Since there is only one level, the level field
should be filled with the maximum value between s1 and s2. This accounts for
scenarios where the first stage uses large pages and the second stage uses small
pages, which might cause a query to hit a large page while exceeding the range
of the second-stage page table. The tag for such requests must also be
merged—for example, combining the first-level page number from the first tag
with the second-level page number from the second tag (the third-level page
number can be padded with zeros) to form the new page table tag. Additionally,
populate the perm fields from both s1 and s2, along with s2xlate. For ppn, since
guest physical addresses are not stored, if the first stage uses small pages and
the second stage uses large pages, directly storing s2's ppn would result in
incorrect physical address calculations during queries. Thus, s2's tag and ppn
must first be concatenated based on s2's level, with s2ppn as the high-order ppn
and s2ppn_tmp constructed for the low-order calculation. The high-order bits are
stored in the TLB entry's ppn field, and the low-order bits in the ppn_low
field.

### The hit logic for TLB entries.

There are three types of hits used in the L1TLB: TLB query hits, TLB fill hits,
and PTW request response hits.

For TLB hit queries, new parameters such as vmid, hasS2xlate, onlyS2, and onlyS1
have been added. The Asid hit is always true during the second-stage
translation. The H extension adds pteidx hit, which is enabled for small pages
in allStage and onlyS2 scenarios to mask the TLB compression mechanism.

For TLB fill hits (wbhit), the input is PtwRespS2. The current VPN for
comparison must be determined. If only the second-stage translation is involved,
the upper bits of the s2 tag are used; otherwise, the tag of s1vpn is used, with
zeros padded in the lower sectortlbwidth bits. The VPN is then compared with the
tag of the TLB entry. The H extension modifies the wb_valid judgment and adds
pteidx_hit and s2xlate_hit. For PTW responses involving only second-stage
translation, wb_valididx is determined by the s2 tag; otherwise, it is directly
connected to s1's valididx. The s2xlate hit compares the s2xlate field of the
TLB entry with that of the PTW response to filter TLB entry types. The
pteidx_hit is used to invalidate TLB compression: for second-stage-only
translations, the lower bits of the s2 tag are compared with the pteidx of the
TLB entry; for other two-stage translation cases, the pteidx of the TLB entry is
compared with s1's pteidx.

For PTW request resp hits, they are primarily used to determine whether the PTW
req sent by the TLB corresponds to the resp or whether the PTW resp matches the
TLB's request during a query. This method is defined in PtwRespS2 and internally
divides hits into three types: for noS2_hit (noS2xlate), only s1 hit needs to be
checked; for onlyS2_hit (onlyStage2), only s2 hit needs to be checked; for
all_onlyS1_hit (allStage or onlyStage1), the vpnhit logic must be redesigned—it
cannot simply check s1hit. The level for vpn_hit should use the maximum of s1
and s2, then determine the hit based on the level, and include checks for vasid
(from vsatp) hit and vmid hit.

### Supports reissuing PTW to obtain gpaddr after a guest page fault.

Since the L1TLB does not store the gpaddr from translation results, when a guest
page fault occurs after querying a TLB entry, a new PTW is required to obtain
the gpaddr. In this case, the TLB response remains a miss. Additional registers
have been added for this purpose.

Table: New Registers for Obtaining gpaddr

|    **Name**     | **type** |                                ** function **                                |
| :-------------: | :------: | :--------------------------------------------------------------------------: |
|    need_gpa.    |   Bool   |         Indicates that there is currently a request acquiring gpaddr         |
| need_gpa_robidx |  RobPtr  |                    robidx of the request to obtain gpaddr                    |
|  need_gpa_vpn   |  vpnLen  |                   The vpn of the request to obtain gpaddr                    |
|  need_gpa_gvpn  |  vpnLen  |                    Stores the gvpn of the obtained gpaddr                    |
| need_gpa_refill |   Bool   | Indicates that the gpaddr of this request has been filled into need_gpa_gvpn |


When a TLB query results in a guest page fault, a PTW is required again. At this
point, need_gpa is set to valid, the requested vpn is filled into need_gpa_vpn,
the requested robidx is filled into need_gpa_robidx, and resp_gpa_refill is
initialized to false. When the PTW response is received and it is determined
through need_gpa_vpn that it is a previously sent request to obtain gpaddr, the
s2 tag from the PTW response is filled into need_gpa_gvpn, and need_gpa_refill
is set to valid, indicating that the gvpn of gpaddr has been obtained. When the
previous request re-enters the TLB, this need_gpa_gvpn can be used to calculate
gpaddr and return it. Once a request completes this process, need_gpa is
invalidated. Here, resp_gpa_refill remains valid, so the refilled gvpn may be
used by other TLB requests (as long as they match need_gpa_vpn).

Additionally, a redirect may occur, changing the entire instruction flow and
preventing previously issued gpaddr requests from entering the TLB. If a
redirect happens, the need_gpa_robidx register is used to determine whether to
invalidate TLB registers related to gpaddr fetching.

Additionally, to ensure that PTW requests for obtaining gpaddr do not refill the
TLB upon return, a new output signal, getGpa, is added when sending PTW
requests. This signal follows a path similar to memidx and can be referenced
accordingly. The signal is passed into the Repeater, and when the PTW resp
returns to the TLB, this signal is also sent back. If the signal is valid, it
indicates that this PTW request is solely for obtaining gpaddr, and thus the TLB
will not be refilled.

Regarding the handling process of obtaining gpaddr after a guest page fault
occurs, key points are reiterated here:

1. The mechanism for obtaining GPA can be viewed as a buffer with only one
   entry. When a guest page fault occurs for a request, the corresponding
   information of need_gpa is written into this buffer. The GPA information
   remains until the conditions need_gpa_vpn_hit && resp_gpa_refill are met, or
   a flush (itlb)/redirect (dtlb) signal is received to refresh the GPA
   information.

  * need_gpa_vpn_hit refers to: after a guest page fault occurs for a request,
    the vpn information is written into need_gpa_vpn. If the same vpn queries
    the TLB again, the need_gpa_vpn_hit signal is raised, indicating that the
    obtained gpaddr corresponds to the original get_gpa request. If
    resp_gpa_refill is also high at this time, it means the vpn has already
    obtained the corresponding gpaddr, which can be returned to the frontend for
    instruction fetch or backend for memory access to handle the exception.
  * Therefore, for any frontend or memory access request that triggers a GPA,
    one of the following two conditions must subsequently be satisfied:

    1. The request triggering gpa can always be resent (the TLB will return a
       miss for the request until the gpaddr result is obtained).
    2. It is necessary to flush or redirect the gpa request by sending a flush
       or redirect signal to the TLB. Specifically, for all possible requests:

        1. ITLB fetch request: If a gpf fetch request occurs on the speculative
           path and incorrect speculation is detected, it will be flushed via
           the flushPipe signal (including backend redirect or updates from the
           frontend multi-level branch predictor where later-stage predictor
           results update earlier-stage predictor results, etc.). For other
           cases, since the ITLB will return a miss for the request, the
           frontend ensures the same vpn request is resent.
        2. DTLB load request: If a gpf load request is on a speculative path and
           incorrect speculation is detected, it will be flushed via the
           redirect signal (the relationship between the robidx of the gpf and
           the robidx of the incoming redirect must be determined). For other
           cases, since the DTLB will return a miss for the request and
           simultaneously assert the tlbreplay signal, ensuring the load queue
           can replay the request.
        3. DTLB store request: If a gpf store request is on a speculative path
           and incorrect speculation is detected, it will be flushed via the
           redirect signal (requires comparing the robidx of the gpf with the
           robidx of the incoming redirect). For other cases, since the DTLB
           will return a miss for this request, the backend will reschedule the
           store instruction to resend the request.
        4. DTLB prefetch request: The returned GPF signal will be asserted,
           indicating a GPF occurred for the prefetch request address. However,
           it will not write to the GPA* series of registers, will not trigger
           the GPADDR lookup mechanism, and thus requires no further
           consideration.
2. Under the current handling mechanism, it is necessary to ensure that a TLB
   entry waiting for a gpa during a gpf is not evicted. Here, we simply block
   TLB refills when waiting for a gpa to prevent replacement. Since a gpf
   triggers exception handling and subsequent instructions are flushed, blocking
   refills during gpa waiting does not cause performance issues.

## Overall Block Diagram

The overall block diagram of the L1 TLB is described in [@fig:L1TLB-overall],
including the ITLB and DTLB within the green box. The ITLB receives PTW requests
from the Frontend, while the DTLB receives PTW requests from the Memblock. PTW
requests from the Frontend include 3 requests from the ICache and 1 request from
the IFU. PTW requests from the Memblock include 2 requests from the LoadUnit
(with the AtomicsUnit occupying one of the LoadUnit's request channels), 1
request from the L1 Load Stream & Stride prefetch, 2 requests from the
StoreUnit, and 1 request from the SMSPrefetcher.

After obtaining results from ITLB and DTLB queries, PMP and PMA checks are
required. Due to the small size of L1 TLB, the backup of PMP and PMA registers
is not stored within L1 TLB but in the Frontend or Memblock, providing checks
for ITLB and DTLB respectively. Upon a miss in ITLB or DTLB, a query request
must be sent to L2 TLB via the repeater.

![L1 TLB Module Overall Diagram](figure/image21.png){#fig:L1TLB-overall}

## Interface timing

### ITLB and Frontend interface timing {#sec:ITLB-time-frontend}

#### PTW Request from Frontend to ITLB Hits in ITLB

The timing diagram for PTW requests sent by the Frontend to the ITLB when the
ITLB hits is shown in [@fig:ITLB-time-hit].

![Timing diagram of a PTW request from the Frontend hitting the
ITLB](figure/image11.svg){#fig:ITLB-time-hit}

When a PTW request sent by the Frontend to the ITLB hits in the ITLB, the
resp_miss signal remains 0. On the next clock rising edge after req_valid
becomes 1, the ITLB sets the resp_valid signal to 1 and returns the physical
address translated from the virtual address to the Frontend, along with
information on whether a guest page fault, page fault, or access fault occurred.
The timing is described as follows:

* Cycle 0: The Frontend sends a PTW request to the ITLB, with req_valid set to
  1.
* Cycle 1: ITLB returns the physical address to Frontend, with resp_valid set to
  1.

#### PTW requests sent by the Frontend to the ITLB miss the ITLB.

When a PTW request sent by Frontend to ITLB misses in ITLB, the timing diagram
is as shown in [@fig:ITLB-time-miss].

![Timing Diagram of PTW Request from Frontend to ITLB Missing
ITLB](figure/image13.svg){#fig:ITLB-time-miss}

When a PTW request from the Frontend misses in the ITLB, the ITLB returns a
resp_miss signal in the next cycle, indicating an ITLB miss. At this point, the
requestor channel of the ITLB no longer accepts new PTW requests, and the
Frontend repeats the same request until the page table is found in the L2 TLB or
memory and a response is returned. (Note: "The requestor channel of the ITLB no
longer accepts new PTW requests" is controlled by the Frontend. This means that
whether the Frontend chooses not to resend the missed request or to resend
another request, the Frontend's behavior is transparent to the TLB. If the
Frontend sends a new request, the ITLB will directly discard the old request.)

When a PTW request from the Frontend misses in the ITLB, the ITLB returns a
resp_miss signal in the next cycle, indicating an ITLB miss. At this point, the
requestor channel of the ITLB no longer accepts new PTW requests, and the
Frontend repeats the same request until the page table is found in the L2 TLB or
memory and a response is returned. (Note: "The requestor channel of the ITLB no
longer accepts new PTW requests" is controlled by the Frontend. This means that
whether the Frontend chooses not to resend the missed request or to resend
another request, the Frontend's behavior is transparent to the TLB. If the
Frontend sends a new request, the ITLB will directly discard the old request.)

When an ITLB miss occurs, a PTW request is sent to the L2 TLB until a result is
obtained. The timing interaction between the ITLB and L2 TLB, as well as the
return of physical addresses and other information to the Frontend, can be seen
in the timing diagram of Figure 4.4 and the following timing description:

* Cycle 0: The Frontend sends a PTW request to the ITLB, with req_valid set to
  1.
* Cycle 1: The ITLB query results in a miss, returning resp_miss as 1 and
  resp_valid as 1 to the Frontend. Simultaneously, the ITLB sends a PTW request
  to the L2 TLB (specifically to itlbrepeater1) in the same cycle, with
  ptw_req_valid set to 1.
* Cycle X: The L2 TLB returns a PTW response to the ITLB, including the
  requested virtual page number, obtained physical page number, page table
  information, etc., with ptw_resp_valid set to 1. In this cycle, the ITLB has
  already received the PTW response from the L2 TLB, and ptw_req_valid is set to
  0.
* Cycle X+1: ITLB hits at this point, with resp_valid being 1 and resp_miss
  being 0. ITLB returns the physical address to Frontend along with information
  on whether an access fault or page fault occurred.
* Cycle X+2: The resp_valid signal returned by the ITLB to the Frontend is set
  to 0.

### DTLB and Memblock interface timing {#sec:DTLB-time-memblock}

#### PTW request sent by Memblock to DTLB hits in DTLB

When a PTW request sent by MemBlock to the DTLB hits, the timing diagram is
shown in [@fig:DTLB-time-hit].

![Timing diagram of PTW request from Memblock to DTLB hitting
DTLB](figure/image11.svg){#fig:DTLB-time-hit}

When the PTW request sent by Memblock to the DTLB hits in the DTLB, the
resp_miss signal remains 0. On the next clock rising edge after req_valid is set
to 1, the DTLB will set the resp_valid signal to 1, simultaneously returning the
physical address translated from the virtual address to Memblock, along with
information such as whether a page fault or access fault occurred. The timing
description is as follows:

* Cycle 0: Memblock sends a PTW request to the DTLB with req_valid set to 1.
* Cycle 1: The DTLB returns the physical address to MemBlock, with resp_valid
  set to 1.

#### PTW Request from Memblock to DTLB Misses in DTLB

DTLB and ITLB operate similarly, both supporting non-blocking access (i.e., the
TLB internally does not include blocking logic. If the request source remains
unchanged, meaning it continuously resends the same request after a miss, it
exhibits behavior similar to blocking access. If the request source schedules
other different requests to query the TLB after receiving a miss feedback, it
exhibits behavior similar to non-blocking access). Unlike frontend instruction
fetching, when a PTW request sent by Memblock to DTLB misses in DTLB, it does
not block the pipeline. DTLB will return a miss signal and resp_valid to
Memblock in the next cycle after req_valid. Upon receiving the miss signal,
Memblock can proceed with scheduling and continue querying other requests.

After a DTLB miss occurs during a Memblock access, the DTLB sends a PTW request
to the L2 TLB to query the page table from either the L2 TLB or memory. The DTLB
forwards the request to the L2 TLB via a Filter, which can merge duplicate
requests from the DTLB to the L2 TLB, ensuring no duplicates in the DTLB and
improving L2 TLB utilization. The timing diagram for a PTW request from Memblock
to the DTLB that misses in the DTLB is shown in [@fig:DTLB-time-miss], which
only depicts the process from the miss to the DTLB sending the PTW request to
the L2 TLB.

![Timing Diagram of PTW Request from Memblock to DTLB Missing in
DTLB](figure/image15.svg){#fig:DTLB-time-miss}

After the DTLB receives the PTW response from the L2 TLB, it stores the page
table entry in the DTLB. When Memblock accesses the DTLB again, a hit occurs,
similar to the scenario in [@fig:DTLB-time-hit]. The timing interaction between
DTLB and L2 TLB is the same as the ptw_req and ptw_resp parts in
[@fig:ITLB-time-miss].

### TLB and tlbRepeater interface timing {#sec:L1TLB-tlbRepeater-time}

#### TLB sends a PTW request to tlbRepeater

The timing diagram of the PTW request interface from the TLB to the tlbRepeater
is shown in [@fig:L1TLB-time-ptw-req].

![Timing diagram of TLB sending PTW request to
Repeater](figure/image23.svg){#fig:L1TLB-time-ptw-req}

In the Kunminghu architecture, both ITLB and DTLB employ non-blocking access. On
a TLB miss, a PTW request is sent to the L2 TLB, but the pipeline and the PTW
channel between the TLB and Repeater are not blocked while waiting for the PTW
response. The TLB can continuously send PTW requests to the tlbRepeater, which
merges duplicate requests based on their virtual page numbers to avoid resource
wastage in the L2 TLB and duplicate entries in the L1 TLB.

As shown in the timing relationship of [@fig:L1TLB-time-ptw-req], in the next
cycle after the TLB sends a PTW request to the Repeater, the Repeater continues
to forward the PTW request downstream. Since the Repeater has already sent a PTW
request for virtual page number vpn1 to the L2 TLB, when it receives another PTW
request with the same virtual page number, it will not forward it to the L2 TLB
again.

#### itlbRepeater returns the PTW response to the ITLB.

The interface timing diagram for the itlbRepeater returning PTW responses to the
ITLB is shown in [@fig:ITLB-time-ptw-resp].

![Timing diagram of itlbRepeater returning PTW response to
ITLB](figure/image25.svg){#fig:ITLB-time-ptw-resp}

The timing description is as follows:

* Cycle X: The itlbRepeater receives the PTW response from the lower-level
  itlbRepeater via the L2 TLB, with itlbrepeater_ptw_resp_valid asserted high.
* Cycle X+1: The ITLB receives a PTW response from itlbRepeater.

#### dtlbRepeater Returns PTW Response to DTLB

The timing diagram for the interface where dtlbRepeater returns PTW responses to
the DTLB is shown in [@fig:DTLB-time-ptw-resp].

![Timing Diagram of DTLBRepeater Returning PTW Response to
DTLB](figure/image27.svg){#fig:DTLB-time-ptw-resp}

The timing description is as follows:

* Cycle X: dtlbRepeater receives the PTW response from the L2 TLB passed through
  the lower-level dtlbRepeater, with dtlbrepeater_ptw_resp_valid high.
* Cycle X+1: dtlbRepeater passes the PTW response to memblock.
* Cycle X+2: The DTLB receives the PTW response.

