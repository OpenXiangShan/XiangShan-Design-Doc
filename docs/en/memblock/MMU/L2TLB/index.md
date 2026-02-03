
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

L2 TLB 是更大的页表缓存，由 ITLB 和 DTLB 共享，当 L1 TLB 发生 miss 时，会向 L2 TLB 发送 Page Table Walk
请求。L2 TLB 分为 Page Cache（参见 5.3.7 节），Page Table Walker（参见 5.3.8 节），Last Level
Page Table Walker（参见 5.3.9 节）、Hypervisor Page Table Walker（参见 5.3.10）、Miss
Queue（参见 5.3.11 节）和 Prefetcher（参见 5.3.12 节）六部分。

来自 L1 TLB 的请求将首先访问 Page Cache，对于非两阶段地址翻译的请求，若命中叶子节点则直接返回给 L1 TLB，否则根据 Page Cache
命中的页表等级以及 Page Table Walker 和 Last Level Page Table Walker 的空闲情况进入 Page Table
Walker、Last Level Page Table Walker 或 Miss Queue（参见 5.3.7 节）。而对于两阶段地址翻译请求，如果该请求是
onlyStage1 的，则处理方式与非两阶段地址翻译请求一致；如果该请求是 onlyStage2 的，命中叶子页表，则直接返回，没有命中，则发送给 Page
Table Walker 进行翻译；如果该请求是 allStage 的，由于 Page Cache
一次只能查询一次页表，所以首先查询第一阶段页表，分两种情况，如果第一阶段页表命中，则发送给 Page Table
Walker，由其进行接下来的翻译过程，如果第一阶段页表没有命中叶子节点，则根据命中页表等级以及 Page Table Walker 和 Last Level
Page Table Walker 的空闲情况进入 Page Table Walker、Last Level Page Table Walker 或 Miss
Queue。为了加快页表访问，Page Cache 将三级页表都分开做了缓存，可以同时查询三级页表（参见 5.3.7 节）。Page Cache 支持 ecc
校验，如果 ecc 校验出错，则刷新此项，并重新进行 Page Table Walk。

Page Table Walker 接收 Page Cache 的请求，进行 Hardware Page Table
Walk。对于非两阶段地址翻译的请求，Page Table Walker 只访问前两级（1GB 和 2MB）页表，不访问 4KB 页表，对 4KB
页表的访问会由 Last Level Page Table Walker 承担。如果 Page Table Walker 访问到叶子节点（大页），则返回给 L1
TLB，否则需要返回给 Last Level Page Table Walker，由 Last Level Page Table Walker
进行最后一级页表的访问。Page Table Walker 只能同时处理一个请求，无法并行访问前两级页表。对于两阶段地址翻译的请求，第一种情况，如果是
allStage 的请求并且第一阶段翻译的页表 hit，PTW 会发送第二阶段请求进入 Page Cache 查询，如果没有命中，则会发送给
Hypervisor Page Table Walker，第二阶段翻译结果会返回给 PTW；第二种情况，如果是 allStage
请求并且第一阶段翻译的叶子节点没有命中，则 PTW 翻译过程与非虚拟化请求翻译类似，区别在于 PTW
翻译过程中出现的物理地址为客户机物理地址，需要进行一次第二阶段地址翻译后才能访存，具体可见 Page Table Walker 的模块介绍；第三种情况，如果是
onlyStage2 请求，则 PTW 会向外发送第二阶段翻译的请求，接收到 resp 后，返回给 L1TLB；第四种请求是 onlyStage1
的请求，该请求在 PTW 内部的处理过程与非虚拟化请求的处理过程一致。

Miss Queue 接收来自 Page Cache 和 Last Level Page Table Walker 的请求，等待下次访问 Page
Cache。Prefetcher 采用 Next-Line 预取算法，当 miss 或者 hit 但命中项为预取项时，产生下一个预取请求。

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

来自 L1 TLB 的请求将首先访问 Page Cache，对于非两阶段地址翻译的请求，若命中叶子节点则直接返回给 L1 TLB，否则根据 Page Cache
命中的页表等级以及 Page Table Walker 和 Last Level Page Table Walker 的空闲情况进入 Page Table
Walker、Last Level Page Table Walker 或 Miss Queue（参见 5.3.7 节）。而对于两阶段地址翻译请求，如果该请求是
onlyStage1 的，则处理方式与非两阶段地址翻译请求一致；如果该请求是 onlyStage2 的，命中叶子页表，则直接返回，没有命中，则发送给 Page
Table Walker 进行翻译；如果该请求是 allStage 的，由于 Page Cache
一次只能查询一次页表，所以首先查询第一阶段页表，分两种情况，如果第一阶段页表命中，则发送给 Page Table
Walker，由其进行接下来的翻译过程，如果第一阶段页表没有命中叶子节点，则根据命中页表等级以及 Page Table Walker 和 Last Level
Page Table Walker 的空闲情况进入 Page Table Walker、Last Level Page Table Walker 或 Miss
Queue。为了加快页表访问，Page Cache 将三级页表都分开做了缓存，可以同时查询三级页表（参见 5.3.7 节）。Page Cache 支持 ecc
校验，如果 ecc 校验出错，则刷新此项，并重新进行 Page Walk。

Page Table Walker 接收 Page Cache 的请求，进行 Hardware Page Table
Walk。对于非两阶段地址翻译的请求，Page Table Walker 只访问前两级（1GB 和 2MB）页表，不访问 4KB 页表，对 4KB
页表的访问会由 Last Level Page Table Walker 承担。如果 Page Table Walker 访问到叶子节点（大页），则返回给 L1
TLB，否则需要返回给 Last Level Page Table Walker，由 Last Level Page Table Walker
进行最后一级页表的访问。Page Table Walker 只能同时处理一个请求，无法并行访问前两级页表。对于两阶段地址翻译的请求，第一种情况，如果是
allStage 的请求并且第一阶段翻译的页表 hit，PTW 会发送第二阶段请求进入 Page Cache 查询，如果没有命中，则会发送给
Hypervisor Page Table Walker，第二阶段翻译结果会返回给 PTW；第二种情况，如果是 allStage
请求并且第一阶段翻译的叶子节点没有命中，则 PTW 翻译过程与非虚拟化请求翻译类似，区别在于 PTW
翻译过程中出现的物理地址为客户机物理地址，需要进行一次第二阶段地址翻译后才能访存，具体可见 Page Table Walker 的模块介绍；第三种情况，如果是
onlyStage2 请求，则 PTW 会向外发送第二阶段翻译的请求，接收到 resp 后，返回给 L1TLB；第四种请求是 onlyStage1
的请求，该请求在 PTW 内部的处理过程与非虚拟化请求的处理过程一致。

Miss Queue 接收来自 Page Cache 和 Last Level Page Table Walker 的请求，等待下次访问 Page
Cache。Prefetcher 采用 Next-Line 预取算法，当 miss 或者 hit 但命中项为预取项时，产生下一个预取请求。

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
* mem_arb：3 to 1 的仲裁器，输入为 Page Table Walker、Last Level Page Table Walker 和
  Hypervisor Page Table Walker；输出为 L2 Cache（Last Level Page Table Walker 内部也有一个
  mem_arb，把所有 Last Level Page Table Walker 向 L2 Cache 发送的 PTW 项做仲裁，之后传到这个
  mem_arb 里）

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
* 两阶段翻译都有的请求，第一阶段的叶子页表与第二阶段的叶子页表都得到后
* Second-stage translation results in a Page fault or Access fault
* PMP or PMA checks result in a Page fault or Access fault, which also needs to
  be returned to L1 TLB

The Last Level Page Table Walker will always return a response to the L1 TLB,
including the following possibilities:

* Non-two-stage translation requests and single-stage translation requests
  accessing leaf nodes (4KB pages)
* 两阶段翻译都有的请求，第一阶段的叶子页表与第二阶段的叶子页表都得到后
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

