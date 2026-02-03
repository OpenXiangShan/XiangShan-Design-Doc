# Secondary Module L1 TLB

## Design specifications

1. Supports receiving address translation requests from the Frontend and
   MemBlock.
2. Supports the PLRU replacement algorithm.
3. Supports returning physical addresses to the Frontend and MemBlock.
4. ITLB 和 DTLB 均采用非阻塞式访问，特别地，对于 MMIO 地址翻译请求，ITLB 采用阻塞式访问
5. Both ITLB and DTLB entries are implemented using register files
6. Both ITLB and DTLB entries are fully associative structures
7. ITLB and DTLB adopt the current privilege level of the processor and the
   effective privilege level for memory access execution
8. 支持在 L1 TLB 内部判断虚存是否开启以及两个阶段翻译是否开启
9. Support sending PTW requests to L2 TLB
10. The DTLB supports copying the returned physical address.
11. Support for exception handling
12. 支持 TLB 压缩
13. Support TLB Hint mechanism
14. 存储四种类型的 TLB 项
15. TLB refill 将两个阶段的页表进行融合
16. TLB 项的 hit 的判断逻辑
17. 支持客户机缺页后重新发送 PTW 获取 gpaddr

## Function

### Receives address translation requests from the Frontend and MemBlock.

在核内进行内存读写，包括前端取指和后端访存前，都需要由 L1 TLB 进行地址翻译。因物理距离较远，并且为了避免相互污染，分为前端取指的
ITLB（Instruction TLB）和后端访存的 DTLB（Data TLB）。ITLB 采用全相联模式，48 项全相联保存全部大小页。ITLB 接收来自
Frontend 的地址翻译请求，itlb_requestors(0) 至 itlb_requestors(1) 来自 icache 中的
IPrefetch；itlb_requestors(2) 来自 ifu，为 MMIO 指令的地址翻译请求，特别地，对 MMIO 使用阻塞式 ITLB
进行地址翻译。

The configuration of ITLB entries and request sources are detailed in
[@tbl:ITLB-config;@tbl:ITLB-request-source].

Table: ITLB Entry Configuration {#tbl:ITLB-config}

| **Item name** | **item count** | **Organization structure ** | **Replacement Algorithm** | **stored content** |
| :-----------: | :------------: | :-------------------------: | :-----------------------: | :----------------: |
|     Page      |       48       |      Fully associative      |           PLRU            |   All size pages   |


Table: ITLB Request Sources {#tbl:ITLB-request-source}

| **Serial number** | **Source** |
| :---------------: | :--------: |
|   requestors(0)   |   Icache   |
|   requestors(1)   |   Icache   |
|   requestors(2)   |    IFU     |

香山的访存通道访存拥有 3 个 Load 流水线，2 个 Store 流水线，以及 SMS 预取器、L1 Load stream & stride
预取器。为应对众多请求，三条 Load 流水线及 L1 Load stream & stride 预取器使用 Load DTLB，两条 Store 流水线使用
Store DTLB，预取请求使用 Prefetch DTLB，共 3 个 DTLB，均采用 PLRU 替换算法（参见 5.1.1.2 节）。

DTLB 采用全相联模式，48 项全相联保存全部大小页。DTLB 接收来自 MemBlock 的地址翻译请求，dtlb_ld 接收来自 loadUnits,
VSegmentUnit 和 L1 Load stream & stride 预取器的请求，负责 Load 指令的地址翻译；dtlb_st 接收
StoreUnits 的请求，负责 Store 指令的地址翻译。特别地，对于 AMO 指令，会使用 loadUnit(0) 的
dtlb_ld_requestor，向 dtlb_ld 发送请求。SMSPrefetcher 与来自 L2 的预取会向单独的 DTLB 发送预取请求。

The configuration and request sources of DTLB entries are as shown in
[@tbl:DTLB-config;@tbl:DTLB-request-source].

Table: DTLB Entry Configuration {#tbl:DTLB-config}

| **Item name** | **item count** | **Organization structure ** | **Replacement Algorithm** | **stored content** |
| :-----------: | :------------: | :-------------------------: | :-----------------------: | :----------------: |
|     Page      |       48       |      Fully associative      |           PLRU            |   All size pages   |


Table: DTLB Request Sources {#tbl:DTLB-request-source}

| **模块**  | **Serial number** |               **Source**               |
| :-----: | :---------------: | :------------------------------------: |
| DTLB_LD |                   |                                        |
|         | ld_requestors(0)  | loadUnit(0), AtomicsUnit, VSegmentUnit |
|         | ld_requestors(1)  |              loadUnit(1)               |
|         | ld_requestors(2)  |              loadUnit(2)               |
|         | ld_requestors(3)  |   L1 Load stream & stride Prefetch.    |
| DTLB_ST |                   |                                        |
|         | st_requestors(0)  |              StoreUnit(0)              |
|         | st_requestors(1)  |              StoreUnit(1)              |
| DTLB_PF |                   |                                        |
|         | pf_requestors(0)  |              SMSPrefetch               |
|         | pf_requestors(1)  |              L2 Prefetch               |

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

| **模块** | **Item name** |     **Policy**     |
| :----: | :-----------: | :----------------: |
|  ITLB  |               |                    |
|        |     Page      | 48 项全相联，可以回填任意大小的页 |
|  DTLB  |               |                    |
|        |     Page      | 48 项全相联，可以回填任意大小的页 |

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

但需要注意，昆明湖架构的 DTLB 是非阻塞的，ITLB的前两个通道是非阻塞的，但是对于MMIO的地址翻译请求，ITLB是阻塞式的。

### Storage structure of L1 TLB entries.

Xiangshan's TLB allows configuration of organizational structures, including
associative modes, entry counts, and replacement policies. The default
configuration is: both ITLB and DTLB are 48-entry fully associative structures,
implemented by register files (see Section 5.1.2.3). If simultaneous read and
write operations to the same address occur in the same cycle, results can be
obtained directly via bypass.

参考的 ITLB 或 DTLB 配置：均采用全相联结构，项数 8 / 16 / 32 / 48。目前并不支持参数化修改全相联 / 组相联 / 直接映射的 TLB
结构，需要手动修改代码。

### 支持在 L1 TLB 内部判断虚存是否开启以及两个阶段翻译是否开启

香山支持 RISC-V 手册中的 Sv39/Sv48 页表，虚拟地址长度为 39/48 位。香山的物理地址为 48 位，可参数化修改。

虚存是否开启需要根据特权级和 SATP 寄存器的 MODE 域等共同决定，这一判断在 TLB 内部完成，对 TLB 外透明。关于特权级的描述，参见
5.1.2.7 节；关于 SATP 的 MODE 域，香山的昆明湖架构支持 MODE 域为 8/9，也就是 Sv39/Sv48 分页机制，否则会上报
illegal instruction fault。在 TLB
外的模块（Frontend、LoadUnit、StoreUnit、AtomicsUnit、VSegmentUnit 等）看来，所有地址都经过了 TLB
的地址转换。

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
|      非 0       |      非 0       |       allStage, both translation stages present       |
|      非 0       |       0        |       onlyStage1, only first-stage translation        |
|       0        |      非 0       | onlyStage2, indicating only second-stage translation. |

### Privilege level of L1 TLB.

根据 RISC-V
手册要求，前端取指（ITLB）的特权级为当前处理器特权级，后端访存（DTLB）的特权级为访存执行有效特权级。当前处理器特权级和访存执行有效特权级均在 CSR
模块中判断，传递到 ITLB 和 DTLB 中。当前处理器特权级保存在 CSR 模块中；访存执行有效特权级由 mstatus 寄存器的 MPRV、MPV 和
MPP 位以及 hstatus 的 SPVP 共同决定。如果执行虚拟化访存指令，则访存执行有效特权级为 hstatus 的 SPVP
位保存的特权级，如果执行的指令不是虚拟化访存指令，MPRV 位为
0，则访存执行有效特权级和当前处理器特权级相同，访存执行有效虚拟化模式也与当前虚拟化模式一致；如果 MPRV 位为 1，则访存执行有效特权级为 mstatus
寄存器的 MPP 中保存的特权级，访存执行有效虚拟化模式位 hstatus 寄存器的 MPV 保存的虚拟化模式。ITLB 和 DTLB 的特权级如表所示。

Table: Privilege Levels of ITLB and DTLB

| **模块** |                                            **Privilege Level**                                            |
| :----: | :-------------------------------------------------------------------------------------------------------: |
|  ITLB  |                                     Current processor privilege level                                     |
|  DTLB  | 执行非虚拟化访存指令，如果 mstatus.MPRV=0，为当前处理器特权级和虚拟化模式；如果 mstatus.MPRV=1，为 mstatus.MPP 保存的特权级和 hstatus.MPV 保存的虚拟化模式 |

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
       5. TLB 通过比较 fullva 与 vaddr 来判断是否跨页。具体逻辑为：`crossPageVaddr = Mux(fullva[12]
          ≠ vaddr[12], vaddr, fullva)`。即如果 fullva 和 vaddr 的第 12
          位不同（说明跨到了不同的页），则使用 vaddr；否则使用 fullva。对于 onlyStage2 模式，gpaddr 直接等于
          crossPageVaddr；对于其他模式，gpaddr 由 gvpn 与 crossPageVaddr 的 offset 拼接而成。
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

### 支持 Svnapot 拓展

目前香山还支持 Svnapot 拓展。

Svnapot 拓展的目的是将一段连续的页（2的幂次个）用一个页表项表示，减少 TLB 的压力，在 PTE 中，第 63 位为 1 时表示这个页表项为
NAPOT 页表项，一个 NAPOT 页表项的 PPN 低 4 位设置 NAPOT 表示的连续地址空间。例如 ppn 低 4 位为 1000 时，表示这个是一个
64KB 大小的页表项。在香山中，目前只支持表示 64KB 大小的 NAPOT 页表项。

在 TLB 中，同样设置一个 N 位表示 NAPOT 属性，在命中匹配时，对于普通 4KB 的页，通过对比 tag 低 6 位与 vpn 的 [8:3]
位进行命中匹配；如果 TLB 项的 N 位为 1，通过对比 tag 的 [6:1] 位与 vpn 的 [8:4] 位进行匹配。因为 NAPOT 页覆盖了 16
个连续的 4KB 页。在生成物理地址时，NAPOT 页会用 vpn 的低 4 位替换生成 ppn 的低 4 位。

### 支持 Svpbmt 扩展

目前香山还支持 Svpbmt 扩展。

Svpbmt 扩展允许在页表项中指定内存类型属性。在 PTE 中，第 62-61 位（即 pbmt 字段）用于指定内存类型，具体编码如下：

Table: Svpbmt 类型编码

| **pbmt 值** | **类型** | **描述**                                                                 |
| :--------: | :----: | ---------------------------------------------------------------------- |
|     00     |  PMA   | 无特殊属性，使用 PMA配置                                                         |
|     01     |   NC   | Non-cacheable, idempotent, weakly-ordered (RVWMO), 主存类型                |
|     10     |   IO   | Non-cacheable, non-idempotent, strongly-ordered (I/O ordering), I/O 类型 |
|     11     |   保留   | 保留供未来标准使用                                                              |

在 L1 TLB 项中，新增了 pbmt 和 g_pbmt 两个字段，分别存储第一阶段和第二阶段页表的内存类型属性，其中 pbmt 存储第一阶段页表的 pbmt
属性，在 noS2xlate、allStage、onlyStage1 模式下有效，g_pbmt 存储第二阶段页表的 pbmt 属性，在
allStage、onlyStage2 模式下有效，对于 allStage 模式，当两个阶段都有 pbmt 属性时，第一阶段的 pbmt 优先级更高。

### 支持 TLB 压缩

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

表 5.1.8 展示了压缩前后的对比，压缩前的 tag 即为 vpn，压缩后的 tag 为 vpn 的高 vpnLen - 3 位，低 3
位无需保存，事实上连续 8 项页表的第 i 项，i 即为 tag 的低 3 位。ppn 高 ppnLen - 3 位相同，ppn_low 分别保存 8 项页表的
ppn 低 3 位。Valididx 表示这 8 项页表的有效性，只有 valididx(i) 为 1 时才有效。pteidx(i) 代表原始请求对应的第 i
项，即原始请求 vpn 的低 3 位的值。

这里举例进行说明。例如，某 vpn 为 0x0000154，低三位为 100，即 4。当回填入 L1 TLB 后，会将 vpn 为 0x0000150 到
0x0000157 的 8 项页表均回填，且压缩为 1 项。例如，vpn 为 0x0000154 的 ppn 高位为 PPN0，页表属性位为 PERM0，如果这
8 项页表的第 i 项 ppn 高位和页表属性也为 PPN0 和 PERM0，则 valididx(i) 为 1，通过 ppn_low(i) 保存第 i
项页表的低 3 位。另外，pteidx(i) 代表原始请求对应的第 i 项，这里原始请求的 vpn 低三位为 4，因此 pteidx(4) 为 1，其余
pteidx(i) 均为 0。

另外，TLB 不会对查询结果为大页（1GB、2MB）情况或者 NAPOT 页进行压缩。对于大页，返回时会将 valididx(i) 的每一位都设置为
1，根据页表查询规则，大页事实上不会使用 ppn_low，因此 ppn_low 的值可以为任意值。

Table: Contents stored per TLB entry before and after compression

| **compressed or not** | **tag** | **asid** | **level** | **ppn** | **n** | **perm** | **valididx** | **pteidx** | **ppn_low** |
| :-------------------: | :-----: | :------: | :-------: | :-----: | :---: | :------: | :----------: | :--------: | :---------: |
|          No           | 27/36 位 |   16 位   |    2 位    | 24/44 位 |  1位   |   页表属性   |     不保存      |    不保存     |     不保存     |
|          Yes          | 24/33 位 |   16 位   |    2 位    | 21/41 位 |  1位   |   页表属性   |     8 位      |    8 位     |  8×3 bits.  |


在实现 TLB 压缩后，L1 TLB 的命中条件由 TAG 命中，变为 TAG 命中（vpn 高位匹配），同时还需满足用 vpn 低 3 位索引的
valididx(i) 有效。PPN 由 ppn（高位）与 ppn_low(i) 拼接得到。

Note that after adding the H extension, L1TLB entries are divided into four
types. The TLB compression mechanism is not enabled for virtualized TLB entries
(though TLB compression is still used in the L2TLB). These four types will be
described in detail later.

### 存储四种类型的 TLB 项

The L1 TLB entries have been modified with the addition of the H extension, as
shown in [@fig:L1TLB-item].

![TLB Entry Diagram](figure/image19.png){#fig:L1TLB-item}

与原先的设计相比，新增了 g_perm、vmid、s2xlate、pbmt、g_pbmt，其中 g_perm 用来存储第二阶段页表的 perm，vmid
用来存储第二阶段页表的 vmid，s2xlate 用来区分 TLB 项的类型，pbmt 和 g_pbmt 分别存储第一阶段和第二阶段页表的内存类型属性。根据
s2xlate 的不同，TLB 项目存储的内容也有所不同。

Table: Types of TLB entries

|   **类型**    | **s2xlate** |                      **tag**                       |                      **ppn**                       |  **n**  |                       **perm**                       |  **g_perm**  |  **pbmt**   | **g_pbmt** |                   **level**                    |
| :---------: | :---------: | :------------------------------------------------: | :------------------------------------------------: | :-----: | :--------------------------------------------------: | :----------: | :---------: | :--------: | :--------------------------------------------: |
|  noS2xlate  |     b00     |    Virtual page number in non-virtualized mode     |    Physical page number in non-virtualized mode    | NAPOT属性 | Page table entry permissions in non-virtualized mode |     不使用      | 非虚拟化下的 pbmt |    不使用     | Page table entry level in non-virtualized mode |
|  allStage   |     b11     |                    第一阶段页表的虚拟页号                     |                    第二阶段页表的物理页号                     | NAPOT属性 |                     第一阶段页表的 perm                     | 第二阶段页表的 perm | 第一阶段的 pbmt  | 第二阶段的 pbmt |                两阶段翻译中最小的 level                 |
| onlyStage1  |     b01     |                    第一阶段页表的虚拟页号                     | Physical page number of the first-stage page table | NAPOT属性 |                     第一阶段页表的 perm                     |     不使用      | 第一阶段的 pbmt  |    不使用     |      Level of the first-stage page table       |
| onlyStage2. |     b10     | Virtual page number of the second-stage page table |                    第二阶段页表的物理页号                     | NAPOT属性 |                         不使用                          | 第二阶段页表的 perm |     不使用     | 第二阶段的 pbmt |      Level of the second-stage page table      |


其中 TLB 压缩技术在 noS2xlate 和 onlyStage1 中启用，在其他情况下不启用，allStage 和 onlyS2xlate
情况下，L1TLB 的 hit 机制会使用 pteidx 来计算有效 pte 的 tag 与 ppn，这两种情况在重填的时候也会有所区别。此外，asid 在
noS2xlate、allStage、onlyStage1 中有效，vmid 在 allStage、onlyStage2 中有效，pbmt 在
noS2xlate、allStage、onlyStage1 中有效，g_pbmt 在 allStage、onlyStage2 中有效。

### TLB refill 将两个阶段的页表进行融合

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

对于 onlyS2xlate 的情况，我们将 s2 的结果给填入 TLB 项，这里由于要符合 TLB 压缩的结构，所以需要进行一些特殊处理。首先该项的
asid、perm 不使用，所以我们不关心此时填入的什么值，vmid、n 填入 s2 的 vmid、n。将 s2 的 tag 填入 TLB 项的
tag，pteidx 根据 s2 的 tag 的低 sectortlbwidth 位来确定，如果 s2 是大页，那么 TLB 项的 valididx
均为有效，否则 TLB 项的 pteidx 对应 valididx 有效。关于 ppn 的填写，复用了 allStage 的逻辑，将在 allStage
的情况下介绍。

对于 allStage，需要将两阶段的页表进行融合，首先根据 s1 填入 tag、asid、vmid 等，由于只有一个 level，level 填入 s1 和
s2 最小的值，这是考虑到如果存在第一阶段是大页和第二阶段是小页的情况，可能会导致某个地址进行查询的时候 hit
大页，但实际已经超出了第二阶段页表的范围，对于这种请求的 tag 也要进行融合，比如第一个 tag 是一级页表，第二个 tag 是二级页表，我们需要取第一个
tag 的第一级页号与第二个 tag 的第二级页号拼合（第三级页号可以直接补零）得到新页表的 tag。此外，还需要填入 s1 和 s2 的 perm 以及
s2xlate，对于 ppn，由于我们不保存客户机物理地址，所以对于第一阶段小页和第二阶段大页的情况，如果直接存储 s2 的 ppn
会导致查询到该页表时计算得到的物理地址出错，所以首先要根据 s2 的 level 将 s2 的 tag 与 ppn 拼接一下，s2ppn 为高位
ppn，s2ppn_tmp 则是为了计算低位构造出来的，然后高位填入 TLB 项的 ppn 字段，低位填入 TLB 项的 ppn_low 字段。对于填入的
n，以下几种情况认为 n 位为 1：

1. 当 stage1 的 n 位为 1 且 stage2 不是叶节点时。
2. 当 stage2 的 n 位位 1 且 stage1 不是叶节点时。
3. 当 stage1 与 stage2 的 n 位都为 1 时。

特别的，对于存在异常的 allStage，若 stage1 出现异常，填入的 level 应写回为 s1_level，若 stage2 出现异常：

1. 若 stage1 是 fakePTE，level 应写回为 stage1 和 stage2 中的最大值（表明 vsatp 配置错误）。
2. 若 stage1 是非叶节点，level 应写回为 s1_level。
3. 若 stage1 是叶节点，level 应写回为 stage1 和 stage2 中的最小值。

### TLB 项的 hit 的判断逻辑

There are three types of hits used in the L1TLB: TLB query hits, TLB fill hits,
and PTW request response hits.

对于查询 TLB 的 hit，新增了 vmid，hasS2xlate，onlyS2，onlyS1 等参数。Asid 的 hit 在第二阶段翻译的时候一直为
true。H 拓展中增加了 pteidx hit，在小页、n 位为 0 并且在 allStage 和 onlyS2 的情况下启用，用来屏蔽掉 TLB 压缩机制。

对于填写 TLB 的 hit（wbhit），输入是 PtwRespS2，需要判断当前的进行对比的 vpn，如果是只有第二阶段的翻译，则使用 s2 的 tag
的高位，其他情况使用 s1vpn 的 tag，然后在低 sectortlbwidth 位补上 0，然后使用 vpn 与 TLB 项的 tag 进行对比。H
拓展对 wb_valid 的判断进行了修改，并且新增了 pteidx_hit 和 s2xlate_hit。如果是只有第二阶段翻译的 PTW resp，则
wb_valididx 根据 s2 的 tag 来确定，否则直接连接 s1 的 valididx。s2xlate hit 则是对比 TLB 项的 s2xlate
与 PTW resp 的 s2xlate，用来筛选 TLB 项的类型。pteidx_hit 则是为了无效 TLB 压缩，如果是只有第二阶段翻译，则对比 s2 的
tag 的低位与 TLB 项的 pteidx，其他的两阶段翻译情况则对比 TLB 项的 pteidx 和 s1 的 pteidx。

对于 PTW 请求的 resp hit，主要用于 PTW resp 的时候判断此时 TLB 发送的 PTW req 是否正好与该 resp 对应或者判断在查询
TLB 的时候 PTW resp 是否是 TLB 这个请求需要的 PTW 结果。该方法在 PtwRespS2 中定义，在该方法内部分为三种 hit，对于
noS2_hit（noS2xlate），只需要判断 s1 是否 hit 即可，对于 onlyS2_hit（onlyStage2），则判断 s2 是否 hit
即可，对于 all_onlyS1_hit（allStage 或者 onlyStage1），需要重新设计 vpnhit 的判断逻辑，不能简单判断 s1hit，判断
vpn_hit 的 level 应该取用 s1 和 s2 的最小值，然后根据 level 来判断 hit，并且增加 vasid（来自 vsatp）的 hit 和
vmid 的 hit。

### 支持客户机缺页后重新发送 PTW 获取 gpaddr

由于 L1 TLB 不保存翻译结果中的 gpaddr，当 TLB 命中但发现查询出的 TLB 项存在 guest page fault 时，需要通过
need_gpa 的特殊机制重新获取 gpaddr 用于异常处理。下面是 need_gpa 机制使用到的寄存器。

Table: New Registers for Obtaining gpaddr

|      **Name**       |     **类型**      |                                ** function **                                |
| :-----------------: | :-------------: | :--------------------------------------------------------------------------: |
|      need_gpa.      |      Bool       |         Indicates that there is currently a request acquiring gpaddr         |
|   need_gpa_robidx   |     RobPtr      |                    robidx of the request to obtain gpaddr                    |
|    need_gpa_vpn     |     vpnLen      |                   The vpn of the request to obtain gpaddr                    |
|    need_gpa_gvpn    |     vpnLen      |                    Stores the gvpn of the obtained gpaddr                    |
|   resp_gpa_refill   |      Bool       | Indicates that the gpaddr of this request has been filled into need_gpa_gvpn |
|    resp_s1_level    | log2Up(Level+1) |                         存储 s1 页表的 level，用于计算 gpaddr                          |
|   resp_s1_isLeaf    |      Bool       |                                存储 s1 是否为叶子节点                                 |
|  resp_s1_isFakePte  |      Bool       |                                存储 s1 是否为假 PTE                                |
| need_clear_need_gpa |      Bool       |                          用于 PTW 快速命中时快速清除 need_gpa                           |

#### need_gpa 机制 ####

1. TLB 查询命中某 TLB 项，但该项存在 guest page fault。此时设置 need_gpa 为有效，将请求的 vpn 填入
   need_gpa_vpn，将请求的 robidx 填入 need_gpa_robidx，初始化 resp_gpa_refill 为 false。同时发送
   PTW 请求，在 PTW 请求中，将 getGpa 信号设置为 true，表示这个请求只是用来获取 gpaddr。若 PTW bypass
   命中时（p_hit_fast），可以直接获取 gpaddr 相关信息。此时设置 need_clear_need_gpa，在下一周期清除 need_gpa
   状态，无需等待请求重发。
2. PTW resp 后，通过 need_gpa_vpn 判断是之前发送的获取 gpaddr 的请求，将
   gvpn、s1_level、s1_isLeaf、s1_isFakePte 等信息保存到寄存器中，若 resp 为处于 OnlyStage2，则将 PTW
   resp 的 s2 tag 填入 need_gpa_gvpn，否则通过 need_gpa_vpn 计算出 resp_gpa_gvpn，并且将
   resp_gpa_refill 有效，表示已经获取到 gpaddr 的 gvpn，当之前的请求重新进入 TLB 的时候，就可以使用这个
   need_gpa_gvpn 来计算出 gpaddr 并且返回，当一个请求完成以上过程后，将 need_gpa 无效掉。这里的
   resp_gpa_refill 依旧有效，所以重填的 gvpn 可能被其他的 TLB 请求使用（只要跟 need_gpa_vpn 相等）。由于
   getGpa 有效，该 PTW 响应不会回填 TLB。
3. 原请求重发进入 TLB 时，由于 resp_gpa_refill && need_gpa_vpn_hit 条件满足，miss 信号不再拉高，TLB
   使用缓存的 gpaddr 信息正常返回异常结果。

在处理过程中可能出现 redirect 的情况，导致整个指令流变化，之前获取 gpaddr 的请求不会再进入 TLB，所以如果出现 redirect
就根据我们保存的 need_gpa_robidx 来判断是否需要无效掉 TLB 内与获取 gpaddr 有关的寄存器。

为了保证获取 gpaddr 的 PTW 请求返回的时候不会 refill TLB，由于 need_gpa 是寄存器，在设置的同一周期无法阻止
refill。因此新增 `maybe_need_gpa_not_allow_refill` 组合逻辑信号，用于在触发 need_gpa 的同周期立即阻止 TLB
refill。

Regarding the handling process of obtaining gpaddr after a guest page fault
occurs, key points are reiterated here:

1. 可以将获取 gpa 的机制看作一个只有 1 项的 buffer，当某个请求发生 guest page fault 时，即向该 buffer 写入
   need_gpa 的相应信息；直至 `need_gpa_vpn_hit && resp_gpa_refill` 条件有效，或传入 flush（itlb）/
   redirect（dtlb）信号刷新 gpa 信息。

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

L1 TLB 的整体框图如 [@fig:L1TLB-overall] 所述，包括绿框中的 ITLB 和 DTLB。ITLB 接收来自 Frontend 的
PTW 请求，DTLB 接收来自 Memblock 的 PTW 请求。来自 Frontend 的 PTW 请求包括 ICache 的 2 个请求和 IFU 的
1 个请求，来自 Memblock 的 PTW 请求包括 LoadUnit 的 3 个请求（AtomicsUnit 与 VSegmentUnit 占用
LoadUnit 的 1 个请求通道）、L1 Load Stream & Stride prefetch 的 1 个请求，StoreUnit 的 2
个请求，以及 SMSPrefetcher 的 1 个请求。

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

* 第 0 拍：Frontend 向 ITLB 发送 PTW 请求，req_valid 置 1。
* Cycle 1: ITLB returns the physical address to Frontend, with resp_valid set to
  1.

#### PTW requests sent by the Frontend to the ITLB miss the ITLB.

When a PTW request sent by Frontend to ITLB misses in ITLB, the timing diagram
is as shown in [@fig:ITLB-time-miss].

![Timing Diagram of PTW Request from Frontend to ITLB Missing
ITLB](figure/image13.svg){#fig:ITLB-time-miss}

当 Frontend 向 ITLB 发送的 PTW 请求在 ITLB 中未命中时，下一拍会向 ITLB 返回 resp_miss 信号，表示 ITLB
未命中。此时 ITLB 的该条 requestor 通道不再接收新的 PTW 请求，由 Frontend 重复发送该请求，直至查询得到 L2 TLB
或内存中的页表并返回。（请注意，"ITLB 的该条 requestor 通道不再接收新的 PTW 请求"由 Frontend 控制，也就是说，无论
Frontend 选择不重发 miss 的请求，或重发其他请求，Frontend 的行为对 TLB 来说是透明的。如果 Frontend
选择发送新请求，ITLB 会将旧请求直接丢失掉。）

当 Frontend 向 ITLB 发送的 PTW 请求在 ITLB 中未命中时，下一拍会向 ITLB 返回 resp_miss 信号，表示 ITLB
未命中。此时 ITLB 的该条 requestor 通道不再接收新的 PTW 请求，由 Frontend 重复发送该请求，直至查询得到 L2 TLB
或内存中的页表并返回。（请注意，"ITLB 的该条 requestor 通道不再接收新的 PTW 请求"由 Frontend 控制，也就是说，无论
Frontend 选择不重发 miss 的请求，或重发其他请求，Frontend 的行为对 TLB 来说是透明的。如果 Frontend
选择发送新请求，ITLB 会将旧请求直接丢失掉。）

When an ITLB miss occurs, a PTW request is sent to the L2 TLB until a result is
obtained. The timing interaction between the ITLB and L2 TLB, as well as the
return of physical addresses and other information to the Frontend, can be seen
in the timing diagram of Figure 4.4 and the following timing description:

* 第 0 拍：Frontend 向 ITLB 发送 PTW 请求，req_valid 置 1。
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

时序描述如下：

* Cycle X: The itlbRepeater receives the PTW response from the lower-level
  itlbRepeater via the L2 TLB, with itlbrepeater_ptw_resp_valid asserted high.
* Cycle X+1: The ITLB receives a PTW response from itlbRepeater.

#### dtlbRepeater Returns PTW Response to DTLB

The timing diagram for the interface where dtlbRepeater returns PTW responses to
the DTLB is shown in [@fig:DTLB-time-ptw-resp].

![Timing Diagram of DTLBRepeater Returning PTW Response to
DTLB](figure/image27.svg){#fig:DTLB-time-ptw-resp}

时序描述如下：

* Cycle X: dtlbRepeater receives the PTW response from the L2 TLB passed through
  the lower-level dtlbRepeater, with dtlbrepeater_ptw_resp_valid high.
* Cycle X+1: dtlbRepeater passes the PTW response to memblock.
* Cycle X+2: The DTLB receives the PTW response.

