# 三级模块 Page Cache

Page Cache 指的是如下模块：
* PtwCache cache

## 设计规格

1. 支持分开缓存三级页表
2. 支持接收来自 L1 TLB 的 PTW 请求
3. 支持接收来自 Miss Queue 的 PTW 请求
4. 支持将命中结果返回给 L1 TLB，返回 PTW 回复
5. 支持将未命中结果返回给 L2 TLB，转发 PTW 请求
6. 支持 Page Cache 的重填
7. 支持 ecc 校验
8. 支持 sfence 刷新
9. 支持异常处理机制
10. 支持 TLB 压缩
11. 支持各级页表分为三种类型
12. 支持接收第二阶段翻译请求（hptw 请求）
13. 支持 hfence 刷新

## 功能

### 分开缓存三级页表 

Page Cache 是"增大版"的 L1 TLB，也是名副其实的 L2 TLB。在 Page Cache 中分开缓存了三级页表，可以一拍完成三级信息的查询（H 拓展每级页表又分为 VS 阶段页表、G 阶段页表和主机页表，在之后的章节介绍）。Page Cache 根据请求的地址判断是否命中，获得最靠近叶子节点的结果。由于访存宽度为 512bits，即 8 项页表，因此 Page Cache 一项含有 8 个页表。（1 个虚拟页号，对应 8 个物理页号、8 个权限位）

在 Page Cache 中根据页表的等级分别缓存，分为 l3，l2，l1，l0，sp 五项。l3、l2、l1、l0 项中只存储有效的页表项，分别存储 Sv48 根页表（512GB）、Sv39 根页表（1GB）、中间级页表（2MB）和叶子页表（4KB）。l3、l2 各包含 16 项，为全相联结构；l1 包含 8 项 2 路组相联，l0 包含 256 项 4 路组相联。sp 为 16 项全相联结构，存储大页（是叶子节点的 2MB、1GB、512GB 页表），以及无效（页表中 V 位为 0，或页表中 W 位为 1、R 位为 0，或页表非对齐）的一级、二级页表。在存储时，l1 、l2 和 l3 项不需要存储权限位，l0 和 sp 项需要存储权限位。

Page Cache 的项配置如 [@tbl:PageCache-config] 。

Table: Page Cache 的项配置 {#tbl:PageCache-config}

| **项** | **项数** | **组织结构** | **实现方式** | **替换算法** | **存储内容** |
|:-----:|:-------:|:----------:|:---------:|:-----------:|:----------------------:|
| l0 | 256（64组×4路） | 4 路组相联 | SRAM | PLRU | 4KB 大小页表，需要存储权限位 |
| l1 | 8（4组×2路） | 2 路组相联 | SRAM | PLRU | 2MB 大小页表，不需要存储权限位 |
| l2 | 16 | 全相联 | 寄存器堆 | PLRU | 1GB 大小页表，不需要存储权限位 |
| l3 | 16 | 全相联 | 寄存器堆 | PLRU | 512GB 大小页表，不需要存储权限位 |
| sp | 16 | 全相联 | 寄存器堆 | PLRU | 大页（是叶子节点的 2MB、1GB、512GB 页表）及无效页表项，需要存储权限位和 level |

Page Cache 项需要存储的信息包括：tag、asid、ppn、perm（可选）、level（可选）、prefetch，H 拓展新增了 vmid 和 h（用来区别三种类型页表）。其中，各项存储信息与地址翻译模式（Sv39 或 Sv48）相关，具体如下：
l3 项仅存在于 Sv48 模式，采用全相联结构，tag 位数为 vpnnlen（9）+ H扩展位（2）= 11 位。
l2 项采用全相联结构，Sv39 模式下，tag 位数为 vpnnlen（9）+ H扩展位（2）= 11 位；Sv48 模式下，tag 位数为 2 * vpnnlen（18）+ H扩展位（2）= 20 位。
l1 项采用 2 路组相联结构（4组×2路），Sv39 模式下，tag 位数为 2 * vpnnlen(18) - log₂(4) - log₂(8) + H扩展位（2） = 18 - 2 - 3 + 2 = 15 位；Sv48 模式下，tag 位数为 3 * vpnnlen(27) - log₂(4) - log₂(8) + H扩展位（2） = 27 - 2 - 3 + 2 = 24 位。
l0 项采用 4 路组相联结构（64组×4路），Sv39 模式下，tag 位数为 3 * vpnnlen(27) - log₂(64) - log₂(8) + H扩展位（2） = 27 - 6 - 3 + 2 = 20 位；Sv48 模式下，tag 位数为 4 * vpnnlen(36) - log₂(64) - log₂(8) + H扩展位（2） = 36 - 6 - 3 + 2 = 29 位。
sp 项采用全相联结构Sv39 模式下，tag 位数为 3 * vpnnlen(27) + H扩展位（2） = 29 位；Sv48 模式下，tag 位数为 4 * vpnnlen(36) + H扩展位（2） = 38 位。
对于 l3 和 sp 项，由于存储叶子节点，因此需要存储 perm 项，而 l1 和 l2 项不需要，perm 项存储 riscv 手册规定的 D、A、G、U、X、W、R 位，无需存储 V 位。对于 sp 项，需要存储 level，表示页表的等级（一级还是二级）。prefetch 表示该页表项是由预取的请求得到的，vmid 只在 VS 阶段页表和 G 阶段页表使用，asid 在 G 阶段页表不使用，h 是个两比特的寄存器，区别这三种页表，编码与 s2xlate 一致。Page Cache 项需要存储的信息如 [@tbl:PageCache-store-info] 所示，页表的属性位如 [@tbl:PageCache-item-attribute] 所示：

Table: Page Cache 项需要存储的信息 {#tbl:PageCache-store-info}

| **项** | **tag（Sv39 / Sv48）** | **asid** | **vmid** | **ppn** | **perm** | **level** | **prefetch** | **h** |
|:-----:|:--------------:|:----:|:-----:|:----:|:-------:|:-------:|:-------:|:------:|
| l0 | 20 位 / 29 位 | Yes | Yes | Yes | YES | NO | Yes | Yes |
| l1 | 15 位 / 24 位 | Yes | Yes | Yes | NO | NO | Yes | Yes |
| l2 | 11 位 / 20 位 | Yes | Yes | Yes | NO | NO | Yes | Yes |
| l3 | 0 位 / 11 位 | Yes | Yes | Yes | NO | NO | Yes | Yes |
| sp | 29 位 / 38 位 | Yes | Yes | Yes | Yes | Yes | Yes | Yes |

<!-- -->

Table: 页表项的属性位 {#tbl:PageCache-item-attribute}

| **位** | **域** | **描述** |
|:-----------:|:-----------:|:---------------------------------------------:|
| 7 | D | Dirty，表示自从上次清除 D 位之后，该虚拟页面被读 |
| 6 | A | Accessed，表示自从上次清除 A 位之后，该虚拟页面被读、写或取指 |
| 5 | G | 表示该页是否为全局映射，该位为 1 表示该页是一个全局映射，也就是存在于所有地址空间中的映射 |
| 4 | U | 表示该页是否可以被 User Mode 访问，该位为 0 表示不可被 User Mode 访问；为 1 表示可以被访问 |
| 3 | X | 表示该页是否可执行，该位为 0 表示不可执行；该位为 1 表示页可执行 |
| 2 | W | 表示该页是否可写，该位为 0 表示不可写；该位为 1 表示页可写 |
| 1 | R | 表示该页是否可读，该位为 0 表示不可读；该位为 1 表示页可读 |
| 0 | V | 表示该页表项是否有效，如果该位为 0，则表示该页表项无效，页表项的其他位可以由软件自由使用 |

<!-- -->

Table: h 编码说明

| **h** |         **描述**         |
|:-----:|:------------------------:|
|  00   |   noS2xlate，主机页表    |
|  01   | onlyStage1，VS 阶段的页表 |
|  10   | onlyStage2，G 阶段的页表  |


手册中允许通过软件和硬件两种方式更新 A/D 位，香山选择软件方式，即当发现如下两种情况时通过报 page fault，通过软件更新页表。

1. 访问某页，但该页页表的 A 位是 0
2. 写入某页，但该页页表的 D 位是 0

页表项中 X、W、R 位可能的组合及含义如 [@tbl:PageCache-item-xwr] 所示：

Table: 页表项中 X、W、R 位可能的组合及含义 {#tbl:PageCache-item-xwr}

| **X** | **W** | **R** |                        **描述**                        |
|:---------:|:---------:|:---------:|:-------------------------------------:|
|   0   |   0   |   0   | 表示该页表项并非叶子节点，需要通过该页表索引下一级页表 |
|   0   |   0   |   1   |                   表示该页是只可读的                   |
|   0   |   1   |   0   |                          保留                          |
|   0   |   1   |   1   |                 表示该页是可读、可写的                 |
|   1   |   0   |   0   |                  表示该页是只可执行的                  |
|   1   |   0   |   1   |                表示该页是可读、可执行的                |
|   1   |   1   |   0   |                          保留                          |
|   1   |   1   |   1   |             表示该页是可读、可写、可执行的             |

### 接收 PTW 请求，并返回结果

Page Cache 接收来自 L2 TLB 的 PTW 请求，L2 TLB 的 PTW 请求通过仲裁器进行仲裁，最终送给 Page Cache。这些 PTW 请求可能来源于 Miss Queue、L1 TLB、hptw_req_arb 或 Prefetcher。由于 Page Cache 每次查询只能处理一个请求，所以对于 allStage 请求首先查询第一阶段，对于 allStage 请求，查询各项 h 时，只查询 onlyStage1 的页表，第二阶段的翻译等该请求发送到 PTW 或者 LLPTW 后由 PTW 或者 LLPTW 进行处理。Page Cache 的查询过程如下所示：

* 第 0 拍：对 l0、l1、l2、l3、sp 五项发出读请求，进行同时查询
* 第 1 拍：得到寄存器堆（l2、l3、sp 项）以及 SRAM（对于 l0、l1 项）读出的结果，但由于时序原因并不在当拍直接使用，等待下一拍再进行后续操作
* 第 2 拍：比对 Page Cache 中各项存储的 tag 和传入请求的 tag，比对各项 h 寄存器与传入的 s2xlate（allStage 转换成查询 onlyStage1），在 l0、l1、l2、l3、sp 项中同时进行是否匹配的查询，另外还需要进行 ecc 检查
* 第 3 拍：将 l0、l1、l2、l3、sp 五项匹配得到的结果，以及 ecc 检查的结果做汇总

经过上述对 Page Cache 的查询过程如果在 Page Cache 中寻找到叶子节点，则返回给 L1 TLB（对于 allStage 的请求，如果第一阶段 hit，则发送给 PTW 处理）；否则根据不同情况向 LLPTW、PTW、HPTW 或 Miss Queue 转发请求。

### 向 L2 TLB 发送 PTW 请求

Page Cache 会 根据不同情况向 LLPTW、PTW、HPTW 或 Miss Queue 转发请求。

1.  对于 noS2xlate、onlyStage1 和 allStage，如果 Page Cache 未命中叶子节点，但二级页表命中（对于 onlyStage1 和 allStage 是第一阶段的二级页表命中），并且该 PTW 请求并不是一个 bypass 请求，此时 Page Cache 将请求转发给 llptw。
2.  对于 noS2xlate、onlyStage1 和 allStage，如果 Page Cache 未命中叶子节点，且二级页表也未命中（对于 onlyStage1 和 allStage 是第一阶段的二级页表未命中），此时需要将请求转发给 Miss queue 或 PTW。如果该请求并不是一个 bypass 请求，同时该请求直接来源于 Miss queue，且 PTW 空闲时将 PTW 请求转发给 PTW。如果是 allStage 请求，第一阶段翻译命中叶子节点，也会发送给 PTW 进行最后一次的第二阶段翻译。如果是 onlyStage2 请求，未命中第二阶段的叶子节点也会发送给 PTW 进行后续翻译
3.  如果该请求是来自于 PTW 或者 LLPTW 发送的第二阶段翻译请求（hptwReq），则该请求命中则会发送给 hptw_resp_arb，未命中则发送给 HPTW 处理，如果 HPTW 此时忙，则阻塞 Page Cache。
4.  如果 Page Cache 未命中叶子节点，且该请求并非来自于预取请求也不是 hptwReq 请求。此时需要满足如下三个条件之一可以进入 miss queue。
    1.  该请求是一个 bypass 请求
    2.  该请求二级页表未命中或者第一阶段翻译命中，同时该请求来自于 L1 TLB 或 PTW 无法接收 Page Cache 的请求
    3.  该请求二级页表命中，但 LLPTW 无法接收请求

这里需要特别说明，1、2、3、4 四点是一个并行化的过程，对于 Page Cache 转发的每一个请求，都一定会满足且唯一满足 1、2、3、4 之一的条件，但 1、2、3、4 是分开进行判断的，四者之间没有先后关系。为了更清晰地描述转发请求的情况，用串行化的流程图对此进一步说明，但事实上硬件语言描述的一定是一个并行化的过程，不存在串行关系。串行化的流程图如 [@fig:PageCache-query-flow] 所示。

![串行化的 Page Cache 查询流程图](../figure/image39.jpeg){#fig:PageCache-query-flow}

### 重填 Cache

当 PTW 或 LLPTW 向 mem 发送的 PTW 请求得到回复时，同时会向 Page Cache 发送 refill 请求。传入 Page Cache 的信息包括：页表项、页表的等级、虚拟页号、页表类型等。在这些信息传入 Cache 后，会根据回填页表的等级以及页表的属性位填入 l0、l1、l2、l3 或 sp 项中。如果页表有效，则根据页表的不同等级分别填入 l0、l1、l2、l3、sp 五项中；如果页表无效，同时页表不是叶子节点页表，则填入 sp 项中。对于替换的 Page Cache 项，可以通过 ReplacementPolicy 选定替换策略，目前香山的 Page Cache 采用 PLRU 替换策略。

### 支持 bypass 访问

当 Page Cache 的请求发生 miss，但同时对于请求的地址有数据正在写入 Cache，此时会对 Page Cache 的请求做 bypass。如果出现这种情况，并不会直接将写入 Cache 的数据直接交给访问 Page Cache 的请求，Page Cache 会向 L2 TLB 发送 miss 信号，同时向 L2 TLB 发送 bypass 信号，表示该请求是一个 bypass 请求，需要再次访问 Page Cache 以获得结果。bypass 的 PTW 请求并不会进入 PTW，而会直接进入 MissQueue，等待下一次访问 Page Cache 得到结果。但需要注意的是，对于 hptw req（来自 PTW 和 LLPTW）的第二阶段翻译请求，也可能出现 bypass，但 hptw req 不进入 miss queue，所以为了避免重复填入 Page Cache，Page Cache 发送给 HPTW 的信号有 bypassed 信号，该信号有效的时候，这个请求进入 HPTW 后进行的访存的结果不会被重填进入 Page Cache。

### 支持 ecc 校验

Page Cache 支持 ecc 校验，当访问 l0 或 l1 项时会同时进行 ecc 检查。如果 ecc 检查报错，并不会报例外，而是会向 L2 TLB 发送该请求 miss 信号。同时 Page Cache 将 ecc 报错的项刷新，重新发送 PTW 请求。其余行为和 Page Cache miss 时相同。ecc 检查采用 secded 策略。

### 支持 sfence 刷新

当 sfence 信号有效时，Page Cache 会根据 sfence 的 rs1 和 rs2 信号以及当前的虚拟化模式对 Cache 项进行刷新。对 Page Cache 的刷新通过将相应 Cache line 的 v 位置 0 进行。由于 l0、l1 项由 SRAM 储存，无法在当拍进行 asid 比较，因此对于 l0、l1 的刷新会忽略 asid（vmid 与 asid 的处理相同），而是使用哈希值进行部分匹配；l2、l3 和 sp 项由寄存器堆储存，可以进行完整的 asid/vmid 比较。关于 sfence 信号的有关信息，参见 riscv 手册。虚拟化情况下，sfence 刷新 VS 阶段（第一阶段翻译）的页表（此时需要考虑 vmid）；非虚拟化情况下，sfence 刷新 G 阶段（第二阶段翻译）的页表（此时不考虑 vmid）。

### 支持异常处理

在 Page Cache 中可能出现 ecc 校验出错的情况，此时 Page Cache 会将当前项无效掉，返回 miss 结果并重新进行 Page Walk。参见本文档的第 6 部分：异常处理机制。

### 支持 TLB 压缩

为支持 TLB 压缩，对于 Page Cache 命中 4KB 页时，需要返回连续的 8 项页表。事实上，Page Cache 每项中由于访存宽度为 512bits 的原因，本就含有 8 个页表，将这 8 个页表直接返回即可。与 L1TLB 不同的是，在 L2TLB 中 H 拓展仍然使用 TLB 压缩。

### 支持各级页表分为三种类型

在 H 拓展中有三种类型的页表，分别属于 vsatp、hgatp、satp 管理的页表，在 Page Cache 中新增了一个 h 寄存器，来区别这三种页表，onlyStage1 代表与 vsatp 有关，onlyStage2 代表与 hgatp 有关（此时 asid 无效），noS2xlate 代表与 satp 有关（此时 vmid 无效）。

### 支持接收第二阶段翻译请求（hptw 请求）

L2TLB 中 PTW 和 LLPTW 会发送第二阶段翻译请求（使用 isHptwReq 信号来表示），该类请求会先进入 Page Cache 中查询，查询过程与 onlyStage2 的请求一样，只查询 onlyStage2 类型的页表，但该类请求根据是否命中发送给 hptw_resp_arb 或者 HPTW，Page Cache 的 hptwReq 的返回信号内有 id 信号，该信号用来判断返回给 PTW 还是 LLPTW。返回信号中有个 bypassed 信号，该信号表示该请求出现了 bypass，该请求如果进入 HPTW 翻译，HPTW 访存得到的页表均不会填入 Page Cache。HptwReq 请求也支持 l1Hit 和 l2Hit 的功能。

### 支持 hfence 刷新

hfence 指令只能在非虚拟化模式下执行，该类型指令有两条，分别负责刷新 VS 阶段页表（第一阶段翻译，h 字段为 onlyStage1）和 G 阶段页表（第二阶段翻译，h 字段为 onlyStage2）。根据 hfence 的 rs1 和 rs2 以及新增的 vmid 和 h 字段来判断刷新的内容，同样由于 asid 和 vmid 在 l0 和 l1 中在 SRAM 中存储，所以刷新 l0 和 l1 不考虑 vmid 和 asid。此外对于刷新 l0 和 l1 的实现，采用了简单的做法，直接刷新 VS 或者 G 阶段页表（未来有必要的时候可以进一步细化刷新 addr 所在的 set）。

## 整体框图

Page Cache 的本质是一个 Cache，在上文已经详细介绍过 Page Cache 的内部实现，关于 Page Cache 的内部框图参考意义不大。关于 Page Cache 与其他 L2 TLB 中模块的连接关系，参见 5.3.3 节。

## 接口列表

Page Cache 的信号列表主要可以归纳成如下 3 类：

1.  req：arb2 会向 Page Cache 发送 PTW 请求。
2.  resp：Page Cache 返回给 L2 TLB 的 PTW 回复，Page Cache 可能向 PTW，LLPTW，Miss Queue，HPTW 发送请求；向 mergeArb 和 hptw_resp_arb 发送回复。
3.  refill：Page Cache 接收 mem 返回的 refill 数据。

具体参见接口列表文档。

## 接口时序

Page Cache 通过 valid-ready 方式与 L2 TLB 中的其他模块进行交互，涉及到的信号较为琐碎，且没有特别需要关注的时序关系，因此不再赘述。


