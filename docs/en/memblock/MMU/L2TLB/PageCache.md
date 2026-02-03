# Level-3 Module: Page Cache

Page Cache refers to the following module:
* PtwCache cache

## Design specifications

1. Supports separate caching of three-level page tables.
2. Supports receiving PTW requests from L1 TLB
3. Supports receiving PTW requests from the Miss Queue.
4. Support returning hit results to the L1 TLB and sending PTW replies
5. Supports returning miss results to L2 TLB and forwarding PTW requests
6. 支持 Page Cache 的重填
7. 支持 ecc 校验
8. 支持 sfence 刷新
9. Supports exception handling mechanism
10. 支持 TLB 压缩
11. 支持各级页表分为三种类型
12. 支持接收第二阶段翻译请求（hptw 请求）
13. 支持 hfence 刷新

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

在 Page Cache 中根据页表的等级分别缓存，分为 l3，l2，l1，l0，sp 五项。l3、l2、l1、l0 项中只存储有效的页表项，分别存储 Sv48
根页表（512GB）、Sv39 根页表（1GB）、中间级页表（2MB）和叶子页表（4KB）。l3、l2 各包含 16 项，为全相联结构；l1 包含 8 项 2
路组相联，l0 包含 256 项 4 路组相联。sp 为 16 项全相联结构，存储大页（是叶子节点的 2MB、1GB、512GB 页表），以及无效（页表中 V
位为 0，或页表中 W 位为 1、R 位为 0，或页表非对齐）的一级、二级页表。在存储时，l1 、l2 和 l3 项不需要存储权限位，l0 和 sp
项需要存储权限位。

The configuration items of Page Cache are as shown in [@tbl:PageCache-config].

Table: Page Cache Entry Configuration {#tbl:PageCache-config}

| **entry** | **item count** |       **组织结构**        | **Implementation method** | **Replacement Algorithm** |                **stored content**                |
| :-------: | :------------: | :-------------------: | :-----------------------: | :-----------------------: | :----------------------------------------------: |
|    l0     |  256（64组×4路）   | 4-way set-associative |           SRAM            |           PLRU            |                 4KB 大小页表，需要存储权限位                 |
|    l1     |    8（4组×2路）    | 2-way set-associative |           SRAM            |           PLRU            |                2MB 大小页表，不需要存储权限位                 |
|    l2     |       16       |          全相联          |           寄存器堆            |           PLRU            |                1GB 大小页表，不需要存储权限位                 |
|    l3     |       16       |          全相联          |           寄存器堆            |           PLRU            |               512GB 大小页表，不需要存储权限位                |
|    sp     |       16       |          全相联          |           寄存器堆            |           PLRU            | 大页（是叶子节点的 2MB、1GB、512GB 页表）及无效页表项，需要存储权限位和 level |

Page Cache 项需要存储的信息包括：tag、asid、ppn、perm（可选）、level（可选）、prefetch，H 拓展新增了 vmid 和
h（用来区别三种类型页表）。其中，各项存储信息与地址翻译模式（Sv39 或 Sv48）相关，具体如下： l3 项仅存在于 Sv48 模式，采用全相联结构，tag
位数为 vpnnlen（9）+ H扩展位（2）= 11 位。 l2 项采用全相联结构，Sv39 模式下，tag 位数为 vpnnlen（9）+ H扩展位（2）=
11 位；Sv48 模式下，tag 位数为 2 * vpnnlen（18）+ H扩展位（2）= 20 位。 l1 项采用 2
路组相联结构（4组×2路），Sv39 模式下，tag 位数为 2 * vpnnlen(18) - log₂(4) - log₂(8) + H扩展位（2） =
18 - 2 - 3 + 2 = 15 位；Sv48 模式下，tag 位数为 3 * vpnnlen(27) - log₂(4) - log₂(8) +
H扩展位（2） = 27 - 2 - 3 + 2 = 24 位。 l0 项采用 4 路组相联结构（64组×4路），Sv39 模式下，tag 位数为 3 *
vpnnlen(27) - log₂(64) - log₂(8) + H扩展位（2） = 27 - 6 - 3 + 2 = 20 位；Sv48 模式下，tag
位数为 4 * vpnnlen(36) - log₂(64) - log₂(8) + H扩展位（2） = 36 - 6 - 3 + 2 = 29 位。 sp
项采用全相联结构Sv39 模式下，tag 位数为 3 * vpnnlen(27) + H扩展位（2） = 29 位；Sv48 模式下，tag 位数为 4 *
vpnnlen(36) + H扩展位（2） = 38 位。 对于 l3 和 sp 项，由于存储叶子节点，因此需要存储 perm 项，而 l1 和 l2
项不需要，perm 项存储 riscv 手册规定的 D、A、G、U、X、W、R 位，无需存储 V 位。对于 sp 项，需要存储
level，表示页表的等级（一级还是二级）。prefetch 表示该页表项是由预取的请求得到的，vmid 只在 VS 阶段页表和 G 阶段页表使用，asid 在
G 阶段页表不使用，h 是个两比特的寄存器，区别这三种页表，编码与 s2xlate 一致。Page Cache 项需要存储的信息如
[@tbl:PageCache-store-info] 所示，页表的属性位如 [@tbl:PageCache-item-attribute] 所示：

Table: Information to be stored in Page Cache entries
{#tbl:PageCache-store-info}

| **entry** | **tag（Sv39 / Sv48）** | **asid** | **vmid** | **ppn** | **perm** | **level** | **prefetch** | **h** |
| :-------: | :------------------: | :------: | :------: | :-----: | :------: | :-------: | :----------: | :---: |
|    l0     |     20 位 / 29 位      |   Yes    |   Yes    |   Yes   |   YES    |    NO     |     Yes      |  Yes  |
|    l1     |     15 位 / 24 位      |   Yes    |   Yes    |   Yes   |    NO    |    NO     |     Yes      |  Yes  |
|    l2     |     11 位 / 20 位      |   Yes    |   Yes    |   Yes   |    NO    |    NO     |     Yes      |  Yes  |
|    l3     |      0 位 / 11 位      |   Yes    |   Yes    |   Yes   |    NO    |    NO     |     Yes      |  Yes  |
|    sp     |     29 位 / 38 位      |   Yes    |   Yes    |   Yes   |   Yes    |    Yes    |     Yes      |  Yes  |

<!-- -->

Table: Attribute Bits of Page Table Entries {#tbl:PageCache-item-attribute}

| ** bit ** | **field** |                                                                         **描述**                                                                         |
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

| **h** |              **描述**              |
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

| **X** | **W** | **R** |                                                           **描述**                                                           |
| :---: | :---: | :---: | :------------------------------------------------------------------------------------------------------------------------: |
|   0   |   0   |   0   | Indicates that the page table entry is not a leaf node and requires indexing the next-level page table through this entry. |
|   0   |   0   |   1   |                                              Indicates the page is read-only                                               |
|   0   |   1   |   0   |                                                             保留                                                             |
|   0   |   1   |   1   |                                     Indicates that the page is readable and writable.                                      |
|   1   |   0   |   0   |                                                         表示该页是只可执行的                                                         |
|   1   |   0   |   1   |                                                        表示该页是可读、可执行的                                                        |
|   1   |   1   |   0   |                                                             保留                                                             |
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

* 第 0 拍：对 l0、l1、l2、l3、sp 五项发出读请求，进行同时查询
* 第 1 拍：得到寄存器堆（l2、l3、sp 项）以及 SRAM（对于 l0、l1 项）读出的结果，但由于时序原因并不在当拍直接使用，等待下一拍再进行后续操作
* 第 2 拍：比对 Page Cache 中各项存储的 tag 和传入请求的 tag，比对各项 h 寄存器与传入的 s2xlate（allStage
  转换成查询 onlyStage1），在 l0、l1、l2、l3、sp 项中同时进行是否匹配的查询，另外还需要进行 ecc 检查
* 第 3 拍：将 l0、l1、l2、l3、sp 五项匹配得到的结果，以及 ecc 检查的结果做汇总

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

当 PTW 或 LLPTW 向 mem 发送的 PTW 请求得到回复时，同时会向 Page Cache 发送 refill 请求。传入 Page Cache
的信息包括：页表项、页表的等级、虚拟页号、页表类型等。在这些信息传入 Cache 后，会根据回填页表的等级以及页表的属性位填入 l0、l1、l2、l3 或 sp
项中。如果页表有效，则根据页表的不同等级分别填入 l0、l1、l2、l3、sp 五项中；如果页表无效，同时页表不是叶子节点页表，则填入 sp 项中。对于替换的
Page Cache 项，可以通过 ReplacementPolicy 选定替换策略，目前香山的 Page Cache 采用 PLRU 替换策略。

### Supports bypass access

当 Page Cache 的请求发生 miss，但同时对于请求的地址有数据正在写入 Cache，此时会对 Page Cache 的请求做
bypass。如果出现这种情况，并不会直接将写入 Cache 的数据直接交给访问 Page Cache 的请求，Page Cache 会向 L2 TLB 发送
miss 信号，同时向 L2 TLB 发送 bypass 信号，表示该请求是一个 bypass 请求，需要再次访问 Page Cache
以获得结果。bypass 的 PTW 请求并不会进入 PTW，而会直接进入 MissQueue，等待下一次访问 Page Cache
得到结果。但需要注意的是，对于 hptw req（来自 PTW 和 LLPTW）的第二阶段翻译请求，也可能出现 bypass，但 hptw req 不进入
miss queue，所以为了避免重复填入 Page Cache，Page Cache 发送给 HPTW 的信号有 bypassed
信号，该信号有效的时候，这个请求进入 HPTW 后进行的访存的结果不会被重填进入 Page Cache。

### 支持 ecc 校验

Page Cache 支持 ecc 校验，当访问 l0 或 l1 项时会同时进行 ecc 检查。如果 ecc 检查报错，并不会报例外，而是会向 L2 TLB
发送该请求 miss 信号。同时 Page Cache 将 ecc 报错的项刷新，重新发送 PTW 请求。其余行为和 Page Cache miss
时相同。ecc 检查采用 secded 策略。

### 支持 sfence 刷新

当 sfence 信号有效时，Page Cache 会根据 sfence 的 rs1 和 rs2 信号以及当前的虚拟化模式对 Cache 项进行刷新。对
Page Cache 的刷新通过将相应 Cache line 的 v 位置 0 进行。由于 l0、l1 项由 SRAM 储存，无法在当拍进行 asid
比较，因此对于 l0、l1 的刷新会忽略 asid（vmid 与 asid 的处理相同），而是使用哈希值进行部分匹配；l2、l3 和 sp
项由寄存器堆储存，可以进行完整的 asid/vmid 比较。关于 sfence 信号的有关信息，参见 riscv 手册。虚拟化情况下，sfence 刷新 VS
阶段（第一阶段翻译）的页表（此时需要考虑 vmid）；非虚拟化情况下，sfence 刷新 G 阶段（第二阶段翻译）的页表（此时不考虑 vmid）。

### Support for exception handling

ECC verification errors may occur in the Page Cache, in which case the Page
Cache invalidates the current entry, returns a miss result, and reinitiates the
Page Walk. Refer to Section 6 of this document: Exception Handling Mechanism.

### 支持 TLB 压缩

To support TLB compression, when the Page Cache hits a 4KB page, it must return
8 consecutive page table entries. In fact, due to the 512-bit memory access
width, each Page Cache entry inherently contains 8 page tables, which can be
directly returned. Unlike the L1TLB, the L2TLB still uses TLB compression under
the H extension.

### 支持各级页表分为三种类型

In the H extension, there are three types of page tables, managed by vsatp,
hgatp, and satp, respectively. The Page Cache adds an h register to distinguish
these page tables: onlyStage1 represents those related to vsatp, onlyStage2
represents those related to hgatp (where asid is invalid), and noS2xlate
represents those related to satp (where vmid is invalid).

### 支持接收第二阶段翻译请求（hptw 请求）

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

### 支持 hfence 刷新

hfence 指令只能在非虚拟化模式下执行，该类型指令有两条，分别负责刷新 VS 阶段页表（第一阶段翻译，h 字段为 onlyStage1）和 G
阶段页表（第二阶段翻译，h 字段为 onlyStage2）。根据 hfence 的 rs1 和 rs2 以及新增的 vmid 和 h
字段来判断刷新的内容，同样由于 asid 和 vmid 在 l0 和 l1 中在 SRAM 中存储，所以刷新 l0 和 l1 不考虑 vmid 和
asid。此外对于刷新 l0 和 l1 的实现，采用了简单的做法，直接刷新 VS 或者 G 阶段页表（未来有必要的时候可以进一步细化刷新 addr 所在的
set）。

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


