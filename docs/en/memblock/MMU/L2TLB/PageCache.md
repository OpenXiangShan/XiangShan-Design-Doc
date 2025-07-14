# Level-3 Module: Page Cache

Page Cache refers to the following module:
* PtwCache cache

## Design specifications

1. Supports separate caching of three-level page tables.
2. Supports receiving PTW requests from L1 TLB
3. Supports receiving PTW requests from the Miss Queue.
4. Support returning hit results to the L1 TLB and sending PTW replies
5. Supports returning miss results to L2 TLB and forwarding PTW requests
6. Supports Page Cache refill
7. Supports ECC verification
8. Support sfence refresh
9. Supports exception handling mechanism
10. Supports TLB compression
11. Supports dividing each level of page tables into three types
12. Supports receiving second-stage translation requests (hptw requests)
13. Supports hfence refresh

## Function

### Separately cache the level-3 page tables

The Page Cache is an "enlarged" version of the L1 TLB and effectively serves as
the L2 TLB. It separately caches three-level page tables, enabling single-cycle
queries of three-level information (the H extension further divides each level
into VS-stage page tables, G-stage page tables, and host page tables, which will
be discussed in later chapters). The Page Cache determines hits based on the
requested address, obtaining results closest to the leaf nodes. Since the memory
access width is 512 bits (i.e., 8 page table entries), each Page Cache entry
contains 8 page tables (1 virtual page number corresponding to 8 physical page
numbers and 8 permission bits).

In the Page Cache, entries are cached separately based on the level of the page
table, divided into l1, l2, l3, and sp items. The l1, l2, and l3 items only
store valid page table entries, corresponding to first-level, second-level, and
third-level page tables, respectively. The l1 cache contains 16 entries with a
fully associative structure; the l2 cache contains 64 entries with a 2-way
set-associative structure; the l3 cache contains 512 entries with a 4-way
set-associative structure. The sp cache is a 16-entry fully associative
structure, storing large pages (first-level or second-level page tables that are
leaf nodes) and invalid entries (page tables with the V bit set to 0, or page
tables with the W bit set to 1 and the R bit set to 0, or misaligned page
tables). When storing, the l1 and l2 items do not need to store permission bits,
while the l3 and sp items do.

The configuration items of Page Cache are as shown in [@tbl:PageCache-config].

Table: Page Cache Entry Configuration {#tbl:PageCache-config}

| **entry** | **item count** |       **组织结构**        | **Implementation method** | **Replacement Algorithm** |                                  **stored content**                                   |
| :-------: | :------------: | :-------------------: | :-----------------------: | :-----------------------: | :-----------------------------------------------------------------------------------: |
|    l1     |       16       |   Fully associative   |       Register File       |           PLRU            |      Valid first-level (1GB size) page table, no need to store permission bits.       |
|    l2     |       64       | 2-way set-associative |           SRAM            |           PLRU            | A valid second-level (2MB-sized) page table does not require storage permission bits. |
|    l3     |      512       | 4-way set-associative |           SRAM            |           PLRU            |      Valid three-level (4KB size) page tables require storage of permission bits      |
|    sp     |       16       |   Fully associative   |       Register File       |           PLRU            |                         大页（是叶子节点的一级、二级页表）、无效的一级、二级页表，需要存储权限位                          |

Information stored in a Page Cache entry includes: tag, asid, ppn, perm
(optional), level (optional), prefetch. The H extension adds vmid and h (used to
distinguish the three types of page tables). For l1 and sp entries, which use a
fully associative structure, the tag bits are vpnnlen (9) and 2 \* vpnnlen (18)
respectively. Since the second-stage translation address has two more bits than
the first stage, the tag requires two additional bits. l2 and l3 use a
set-associative structure, requiring consideration of the number of sets and the
fact that each virtual page number can index 8 page table entries. l2 is 2-way
set-associative, so the tag bits are 2 \* vpnnlen(18) - log2(64) - log2(8) +
log2(2) = 10 bits; l3 is 4-way set-associative, so the tag bits are 3 *
vpnnlen(27) - log2(512) - log2(8) + log2(4) = 17 bits. For l3 and sp entries,
which store leaf nodes, the perm field is required, whereas l1 and l2 entries do
not need it. The perm field stores the D, A, G, U, X, W, R bits as specified in
the RISC-V manual, omitting the V bit. The sp entry requires the level field to
indicate the page table level (first or second). The prefetch field indicates
the page table entry was obtained via a prefetch request. vmid is only used for
VS-stage and G-stage page tables, asid is unused for G-stage page tables, and h
is a 2-bit register distinguishing these three page table types, with encoding
consistent with s2xlate. The information stored in a Page Cache entry is shown
in [@tbl:PageCache-store-info], and the page table attribute bits are shown in
[@tbl:PageCache-item-attribute]:

Table: Information to be stored in Page Cache entries
{#tbl:PageCache-store-info}

| **entry** |        **tag**         | **asid** | **vmid** | **ppn** | **perm** | **level** | **prefetch** | **h** |
| :-------: | :--------------------: | :------: | :------: | :-----: | :------: | :-------: | :----------: | :---: |
|    l1     |   Yes, 9-bit + 2-bit   |   Yes    |   Yes    |   Yes   |    NO    |    NO     |     Yes      |  Yes  |
|    l2     |     Yes，10 位 + 2 位     |   Yes    |   Yes    |   Yes   |    NO    |    NO     |     Yes      |  Yes  |
|    l3     | Yes, 17 bits + 2 bits  |   Yes    |   Yes    |   Yes   |   Yes    |    NO     |     Yes      |  Yes  |
|    sp     | Yes, 18 bits + 2 bits. |   Yes    |   Yes    |   Yes   |   Yes    |    Yes    |     Yes      |  Yes  |

<!-- -->

Table: Attribute Bits of Page Table Entries {#tbl:PageCache-item-attribute}

| ** bit ** | **field** |                                                                    **Description**                                                                     |
| :-------: | :-------: | :----------------------------------------------------------------------------------------------------------------------------------------------------: |
|     7     |     D     |                            Dirty, indicates that since the last time the D bit was cleared, the virtual page has been read.                            |
|     6     |     A     |                      Accessed, indicating that since the last A bit clear, this virtual page has been read, written, or fetched.                       |
|     5     |     G     |                                                     表示该页是否为全局映射，该位为 1 表示该页是一个全局映射，也就是存在于所有地址空间中的映射                                                     |
|     4     |     U     | Indicates whether the page can be accessed by User Mode. A value of 0 means it cannot be accessed by User Mode; a value of 1 means it can be accessed. |
|     3     |     X     |              Indicates whether the page is executable; a value of 0 means not executable, and a value of 1 means the page is executable.               |
|     2     |     W     |                 Indicates whether the page is writable; a value of 0 means not writable, and a value of 1 means the page is writable.                  |
|     1     |     R     |                 Indicates whether the page is readable; a value of 0 means not readable, and a value of 1 means the page is readable.                  |
|     0     |     V     |  Indicates whether the page table entry is valid. If this bit is 0, the entry is invalid, and other bits of the entry can be freely used by software   |

<!-- -->

Table: h Encoding Description

| **h** |         **Description**          |
| :---: | :------------------------------: |
|  00   |    noS2xlate, host page table    |
|  01   | onlyStage1, VS-stage page tables |
|  10   |  onlyStage2, G-stage page table  |


The manual permits updating the A/D bits via either software or hardware.
Xiangshan opts for the software approach, where a page fault is triggered under
the following two conditions, and the page table is updated by software.

1. accessing a page where the A bit of its page table is 0
2. Writing to a page where the D bit of its page table entry is 0.

页表项中 X、W、R 位可能的组合及含义如 [@tbl:PageCache-item-xwr] 所示：

Table: Possible combinations and meanings of X, W, R bits in page table entries
{#tbl:PageCache-item-xwr}

| **X** | **W** | **R** |                                                      **Description**                                                       |
| :---: | :---: | :---: | :------------------------------------------------------------------------------------------------------------------------: |
|   0   |   0   |   0   | Indicates that the page table entry is not a leaf node and requires indexing the next-level page table through this entry. |
|   0   |   0   |   1   |                                              Indicates the page is read-only                                               |
|   0   |   1   |   0   |                                                          Reserved                                                          |
|   0   |   1   |   1   |                                     Indicates that the page is readable and writable.                                      |
|   1   |   0   |   0   |                                                         表示该页是只可执行的                                                         |
|   1   |   0   |   1   |                                                        表示该页是可读、可执行的                                                        |
|   1   |   1   |   0   |                                                          Reserved                                                          |
|   1   |   1   |   1   |                                  Indicates the page is readable, writable, and executable                                  |

### Receives PTW requests and returns results

The Page Cache receives PTW requests from the L2 TLB, which are arbitrated by an
arbiter before being sent to the Page Cache. These PTW requests may originate
from the Miss Queue, L1 TLB, hptw_req_arb, or Prefetcher. Since the Page Cache
can only process one request per query, for allStage requests, it first queries
the first stage. For allStage requests, when querying each h, only the
onlyStage1 page tables are queried. The second-stage translation is handled by
PTW or LLPTW after the request is forwarded to them. The Page Cache query
process is as follows:

* 第 0 拍：对 l1、l2、l3、sp 四项发出读请求，进行同时查询
* Cycle 1: The results read from the register file (l1, sp entries) and SRAM
  (for l2, l3 entries) are obtained, but due to timing constraints, they are not
  used immediately in the same cycle. Instead, they are processed in the next
  cycle.
* Cycle 2: Compare the tags stored in each item of the Page Cache with the tags
  from the incoming request, and compare the h registers with the incoming
  s2xlate (allStage is converted to query onlyStage1). Simultaneously, perform
  matching queries in the l1, l2, l3, and sp items, and also conduct ECC checks.
* Cycle 3: Summarize the matching results from the l1, l2, l3, and sp items,
  along with the ECC check results.

After the aforementioned Page Cache lookup process, if a leaf node is found in
the Page Cache, it is returned to the L1 TLB (for allStage requests, if the
first stage hits, it is sent to PTW for processing); otherwise, the request is
forwarded to LLPTW, PTW, HPTW, or the Miss Queue based on different scenarios.

### Send a PTW request to the L2 TLB

The Page Cache forwards requests to LLPTW, PTW, HPTW, or the Miss Queue
depending on the situation.

1.  For noS2xlate, onlyStage1, and allStage, if the Page Cache misses the leaf
    node but hits the second-level page table (for onlyStage1 and allStage, it's
    a first-stage second-level page table hit), and this PTW request is not a
    bypass request, the Page Cache forwards the request to llptw.
2.  For noS2xlate, onlyStage1, and allStage, if the Page Cache misses the leaf
    node and the second-level page table also misses (for onlyStage1 and
    allStage, this refers to the first-stage second-level page table miss), the
    request must be forwarded to the Miss Queue or PTW. If the request is not a
    bypass request, originates directly from the Miss Queue, and the PTW is
    idle, the PTW request is forwarded to the PTW. For allStage requests, if the
    first-stage translation hits a leaf node, it is also sent to the PTW for the
    final second-stage translation. For onlyStage2 requests, missing the
    second-stage leaf node also triggers sending to the PTW for further
    translation.
3.  If the request is a second-stage translation request (hptwReq) from PTW or
    LLPTW, a hit will send it to hptw_resp_arb, while a miss will forward it to
    HPTW for processing. If HPTW is busy at this time, the Page Cache will be
    blocked.
4.  If the Page Cache misses the leaf node and the request is neither from a
    prefetch request nor an hptwReq request, it must meet one of the following
    three conditions to enter the miss queue.
    1.  This request is a bypass request
    2.  This request misses in the L2 page table or hits in the first-stage
        translation, and the request originates from the L1 TLB or PTW cannot
        accept Page Cache requests.
    3.  该请求二级页表命中，但 LLPTW 无法接收请求

It is important to note that points 1, 2, 3, and 4 are parallel processes. For
every request forwarded by the Page Cache, it will always satisfy exactly one of
the conditions in 1, 2, 3, or 4. However, these four conditions are evaluated
independently, with no sequential relationship between them. To clarify the
request forwarding scenario, a serialized flowchart is provided for
illustration, but in reality, the hardware description is inherently parallel,
with no sequential dependencies. The serialized flowchart is shown in
[@fig:PageCache-query-flow].

![串行化的 Page Cache 查询流程图](../figure/image39.jpeg){#fig:PageCache-query-flow}

### Refill Cache

When a PTW or LLPTW request sent to memory receives a response, a refill request
is simultaneously sent to the Page Cache. The information passed to the Page
Cache includes: page table entry, page table level, virtual page number, page
table type, etc. After this information is fed into the Cache, it is filled into
the l1, l2, l3, or sp entries based on the refill page table level and page
table attribute bits. If the page table is valid, it is filled into the l1, l2,
l3, or sp entries according to its level; if the page table is invalid and is a
level-1 or level-2 page table, it is filled into the sp entry. For replaced Page
Cache entries, the replacement policy can be selected via ReplacementPolicy.
Currently, Xiangshan's Page Cache employs the PLRU replacement strategy.

### Supports bypass access

When a Page Cache request misses but data for the requested address is currently
being written into the Cache, the request is bypassed. In this case, the data
being written into the Cache is not directly forwarded to the Page Cache
request. Instead, the Page Cache sends a miss signal to L2 TLB along with a
bypass signal, indicating that the request is a bypass request and needs to
access the Page Cache again to obtain the result. Bypassed PTW requests do not
proceed to PTW but go directly to the MissQueue, waiting for the next Page Cache
access to retrieve the result. However, it should be noted that hptw req
(second-stage translation requests from PTW and LLPTW) may also encounter bypass
scenarios. Since hptw req does not enter the miss queue, to avoid duplicate
refills into the Page Cache, the signal sent by the Page Cache to HPTW includes
a bypassed signal. When this signal is active, the results of memory accesses
performed by HPTW for this request will not be refilled into the Page Cache.

### Supports ECC verification

Page Cache 支持 ecc 校验，当访问 l2 或 l3 项时会同时进行 ecc 检查。如果 ecc 检查报错，并不会报例外，而是会向 L2 TLB
发送该请求 miss 信号。同时 Page Cache 将 ecc 报错的项刷新，重新发送 PTW 请求。其余行为和 Page Cache miss
时相同。ecc 检查采用 secded 策略。

### Support sfence refresh

When the sfence signal is active, the Page Cache refreshes its entries based on
the rs1 and rs2 signals of sfence and the current virtualization mode.
Refreshing the Page Cache is done by clearing the v bit of the corresponding
cache line. Since l2 and l3 entries are stored in SRAM and cannot perform asid
comparison in the same cycle, refreshing l2 and l3 entries ignores asid (vmid is
handled similarly to asid). For details about the sfence signal, refer to the
RISC-V manual. In virtualization mode, sfence refreshes the page tables of the
VS stage (first-stage translation, where vmid must be considered); in
non-virtualization mode, sfence refreshes the page tables of the G stage
(second-stage translation, where vmid is not considered).

### Support for exception handling

ECC verification errors may occur in the Page Cache, in which case the Page
Cache invalidates the current entry, returns a miss result, and reinitiates the
Page Walk. Refer to Section 6 of this document: Exception Handling Mechanism.

### Supports TLB compression

To support TLB compression, when the Page Cache hits a 4KB page, it must return
8 consecutive page table entries. In fact, due to the 512-bit memory access
width, each Page Cache entry inherently contains 8 page tables, which can be
directly returned. Unlike the L1TLB, the L2TLB still uses TLB compression under
the H extension.

### Supports dividing each level of page tables into three types

In the H extension, there are three types of page tables, managed by vsatp,
hgatp, and satp, respectively. The Page Cache adds an h register to distinguish
these page tables: onlyStage1 represents those related to vsatp, onlyStage2
represents those related to hgatp (where asid is invalid), and noS2xlate
represents those related to satp (where vmid is invalid).

### Supports receiving second-stage translation requests (hptw requests)

In L2TLB, PTW and LLPTW send second-stage translation requests (indicated by the
isHptwReq signal). These requests first query the Page Cache, following the same
process as onlyStage2 requests—only querying page tables of the onlyStage2 type.
However, depending on whether they hit, these requests are forwarded to either
hptw_resp_arb or HPTW. The hptwReq return signal from the Page Cache includes an
id signal to determine whether the response should go to PTW or LLPTW. The
return signal also contains a bypassed signal, indicating that the request was
bypassed. If such a request proceeds to HPTW for translation, none of the page
tables obtained by HPTW's memory accesses will be refilled into the Page Cache.
HptwReq requests also support l1Hit and l2Hit functionality.

### Supports hfence refresh

The hfence instruction can only be executed in non-virtualization mode. There
are two types of such instructions, responsible for refreshing the VS-stage page
tables (first-stage translation, h field is onlyStage1) and the G-stage page
tables (second-stage translation, h field is onlyStage2), respectively. The
refresh content is determined by the rs1 and rs2 of hfence, along with the
additional vmid and h fields. Similarly, since asid and vmid are stored in SRAM
for l3 and l2, refreshing l3 and l2 does not consider vmid and asid.
Additionally, for refreshing l3, a simple approach is adopted by directly
refreshing the VS or G-stage page tables (further refinement can be made to
refresh the set containing the addr if necessary in the future).

## Overall Block Diagram

The essence of the Page Cache is a cache. The internal implementation of the
Page Cache has been detailed above, and the internal block diagram of the Page
Cache is of limited reference value. For the connection relationships between
the Page Cache and other modules in the L2 TLB, see Section 5.3.3.

## Interface list

The signal list of Page Cache can be mainly categorized into the following 3
types:

1.  req: arb2 sends PTW requests to the Page Cache.
2.  resp: The response from Page Cache to L2 TLB's PTW, where Page Cache may
    send requests to PTW, LLPTW, Miss Queue, and HPTW; and send responses to
    mergeArb and hptw_resp_arb.
3.  refill: The Page Cache receives refill data returned from memory.

具体参见接口列表文档。

## Interface timing

The Page Cache interacts with other modules in the L2 TLB using a valid-ready
handshake mechanism. The signals involved are relatively trivial, and there are
no particularly noteworthy timing relationships, so they will not be elaborated
further.


