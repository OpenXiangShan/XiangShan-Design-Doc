# 访存流水线 LSU

## 子模块列表

| 子模块                                           | Descrption   |
| --------------------------------------------- | ------------ |
| [LoadUnit](LoadUnit.md)                       | Load 指令执行单元  |
| [StoreUnit](StoreUnit.md)                     | Store 地址执行单元 |
| [StdExeUnit](StdExeUnit.md)                   | Store 数据执行单元 |
| [AtomicsUnit](AtomicsUnit.md)                 | 原子指令执行单元     |
| [VLSU](VLSU/index.md)                         | 向量访存         |
| [LSQ](LSQ/index.md)                           | 访存队列         |
| [Uncache](Uncache.md)                         | Uncache 处理单元 |
| [SBuffer](SBuffer.md)                         | Store 提交缓冲   |
| [LoadMisalignBuffer](LoadMisalignBuffer.md)   | Load 非对齐缓冲   |
| [StoreMisalignBuffer](StoreMisalignBuffer.md) | Store 非对齐缓冲  |

## 设计规格

### 指令集规格

- 支持 RVI 指令集中 Load / Store 指令的执行与写回
- 支持 RVA 原子指令扩展
- 支持 RVH 虚拟化扩展
- 支持 RVV 向量扩展
- 支持 Cacheable 地址空间的 Load / Store / Atomic 访问
- 支持 MMIO 与 Uncache 地址空间的 Load / Store 访问（不包括向量访存指令和非对齐访存指令）
- 支持 Zicbom 和 Zicboz 等 cache 操作指令，支持 Zicbop 软件预取指令
- 支持非对齐访存（Zicclsm），且保证 16B 对齐范围内的非对齐访存的原子性（Zama16b）
- 支持 Sv39 与 Sv48 分页机制
- 支持连续页地址翻译（Svnapot）
- 支持基于页的内存属性（Svpbmt）
- 支持 Pointer masking（Supm，Ssnpm，Sspm）
- 支持 Compare-and-Swap 原子指令（Zacas）
- 支持 RVWMO 内存一致性模型
- 支持自定义故障注入指令

### 微结构特性

- 支持乱序调度 Load / Store 指令，包括 Cacheable 和 Uncache（非 MMIO）地址空间的访问
- 支持基于标量流水线的向量访存乱序调度
- 支持单元步长（Unit-stride）向量访存的元素合并访问
- 支持地址与数据分离的 Store 指令发射与执行
- 支持基于 LoadQueue 的 Load 指令重发机制
- 支持原子指令的非推测执行
- 支持 SBuffer 优化 Store 指令性能
- 支持基于 StoreQueue 与 SBuffer 的数据前递机制
- 支持 RAR / RAW 访存违例的检测与恢复
- 支持 MESI 缓存一致性协议
- 支持基于 TileLink 总线的多级 cache 访问
- 支持 DCache SECDED 校验
- 支持软件可配置的 Stream，Stride，SMS 等硬件预取器

### 参数配置

|          参数          |             配置             |
| :------------------: | :------------------------: |
|      VAddr Bits      |    (Sv39) 39, (Sv48) 48    |
|     GPAddr Bits      |  (Sv39x4) 41, (Sv48x4) 50  |
|       LoadUnit       |         3 x 8B/16B         |
|      StoreUnit       |         2 x 8B/16B         |
|     StoreExeUnit     |             2              |
|      LoadQueue       |             72             |
|     LoadQueueRAR     |             72             |
|     LoadQueueRAW     |             32             |
|   LoadQueueReplay    |             72             |
|  LoadUncacheBuffer   |             4              |
|      StoreQueue      |             56             |
|     StoreBuffer      |          16 x 64B          |
|    VLMergeBuffer     |             16             |
|    VSMergeBuffer     |             16             |
|    VSegmentBuffer    |             8              |
|      VFOFBuffer      |             1              |
|       Load TLB       | 48-entry fully associative |
|      Store TLB       | 48-entry fully associative |
|   L1 Prefetch TLB    | 48-entry fully associative |
|   L2 Prefetch TLB    | 48-entry fully associative |
|        DCache        | 64KB 4-way set associative |
|     DCache MSHR      |             16             |
|  DCache Probe Queue  |             8              |
| DCache Way Predictor |            Off             |


## 功能描述

访存流水线负责从发射队列接收访存指令（包括内存、MMIO 与 Uncache 地址空间的 Load / Store
指令，内存地址空间的原子指令），根据访存指令类型完成访存操作，得到指令执行结果，并将结果写回寄存器堆，同时通知前递旁路网络，唤醒后续指令并作数据前递。


### 访存指令的派遣

Load 与 Store
指令有复杂的控制机制，例如定序、前递、违例等，因此需要有一个队列来保存load与store指令，保证先进先出的顺序，进行相关的控制，这个队列就是
LoadQueue 和 StoreQueue。当指令完成译码和重命名等操作后，Load / Store 指令需要派遣到 ROB 和 LSQ 中，并分配相应的
robIdx、lqIdx 和 sqIdx，然后进入相应的发射队列，等待源操作数全部准备好后发射到 MemBlock 的流水线中。Load / Store 指令在
MemBlock 执行的整个生命周期都会携带 lqIdx 和 sqIdx，用于在访存违例检测、数据前递时进行指令序的定序。

对于标量访存指令，一条指令会分配一项 LoadQueue 或 StoreQueue 项。

对于向量访存指令，一条指令会在译码阶段被拆分成若干个 uop，每个 uop 包含若干个元素，每个元素等同于一次访存操作。在派遣阶段，一个 uop 会分配若干个
LSQ 项，分配项数等于一个 uop 所包含的元素个数。

### 访存指令的执行

访存单元包含 3 条 Load 流水线，2 条 Store 地址流水线，2 条 Store
数据流水线。每一条流水线会独立接收对应的发射队列发射出来的指令并执行。

Load 流水线为 4 级流水线结构：

- **s0**：计算访存地址，完成不同来源（非对齐 Load，Load replay，MMIO，预取，标量 Load，向量 Load 等等）的请求仲裁，访问
  TLB，访问 DCache 目录，发送写回唤醒信号
- **s1**：接收 TLB 地址翻译的响应，接收 DCache 读目录的结果并做路选择，访问 DCache 数据 SRAM；和 StoreUnit s1 的
  store 指令进行 RAW 违例检测；查询 StoreQueue / LoadQueueUncache / SBuffer / DCache MSHR
  进行数据前递
- **s2**：查询 LoadQueueRAR 和 LoadQueueRAW 供后续 Load / Store 指令做违例检查；如果 DCache miss
  需要在 s2 分配 MSHR；和 StoreUnit s1 的 store 指令进行 RAW 违例检
- **s3**：写回；如果没有写回的话需要取消唤醒；如果发生访存违例则刷新流水线；如果需要重发则进入 LoadQueueReplay

Store 地址流水线为 4 级流水线结构：

- **s0**：计算访存地址，完成不同来源（非对齐 Store，标量 Store，向量 Store 等）的请求仲裁，访问 TLB
- **s1**：接收 TLB 地址翻译的响应；和 LoadUnit s1 和 s2 的 load 指令进行 RAW 违例检测；查询 LoadQueueRAW
  进行违例检查
- **s2**：在 StoreQueue 中标记为地址已准备好
- **s3**：写回

Store 数据流水线从发射队列接收到数据后将数据写回到 StoreQueue 并标记为数据已准备好。

### 向量访存指令的执行

对于除 Segment 以外的向量访存指令，VLSplit 和 VSSplit 接收从向量访存发射队列发射的 uop，将 uop 拆分成若干元素，VLSplit
和 VSSplit 会将这些元素发射到 LoadUnit / StoreUnit 上执行，执行流程和标量访存相同。元素执行完成后会写回到 VLMerge /
VSMerge，Merge 模块负责收集元素、组合成 uop 并写回向量寄存器堆。

Segment 指令由独立的 VSegmentUnit 模块处理。

### Load 指令重发

Load 指令不支持在发射队列中重发，因此当 Load 指令发生如下特殊情况时需要进入 LoadQueueReplay 等待重新执行：

- **C_MA**：访存违例预测算法（MDP）认为 Load 与某条更老的 Store 有地址依赖，且该 Store 地址还没有准备好
- **C_TM**：TLB 缺失
- **C_FF**：Load 与某条更老的 Store 存在地址依赖，但是这条 Store 数据还没有准备好
- **C_DR**：DCache 缺失且 MSHR 满，或者存在同地址 MSHR 暂无法接收新的 Load
- **C_DM**：DCache 缺失，当前 Load 成功被 MSHR 接收
- **C_WF**：路预测器预测失败（路预测器默认关）
- **C_BC**：访问 DCache 发生 bank 冲突
- **C_RAR**：LoadQueueRAR 满
- **C_RAW**：LoadQueueRAW 满
- **C_NK**：与 StoreUnit 的 Store 指令发生了访存违例
- **C_MF**：LoadMisalignBuffer 满

LoadQueueReplay 会根据重发的原因按如上的优先级从高到低进行重发。

### Store 指令重发

Store 指令由发射队列负责重发。Store 指令从发射队列中发射后，发射队列不会立即清空这条 Store 指令，而是等待 StoreUnit
的反馈，StoreUnit 会根据 TLB 是否命中给发射队列发送相应的反馈。如果 TLB 缺失，发射队列会负责指令重发。

### RAR 访存违例的检测与恢复

**RAR 访存违例**：根据 RVWMO 模型，当 (1) 两个相同地址（包括存在地址重叠的情况）的读操作中间插入同地址的写操作，且 (2)
这两次读操作返回的结果来自于不同的写操作时，这两次读操作需要保持和程序序统一。在单核场景下，访存单元虽然会乱序执行 Load
指令，但是会通过数据前递机制保证两条同地址的 Load 的执行结果一定会保证程序序；但在多核场景下，两条被打乱顺序的同地址 Load
中间插入另一个核的写操作（注意是写操作不是写指令）时，更老的 Load 会读到写操作后的更新的值，更年轻的 Load 会读到写操作前的旧值，即 RAR
访存违例。

**RAR 访存违例的检测**：LoadQueue 中的 LoadQueueRAR 模块会用 FreeList
的结构记录所有**有可能存在相同地址但还没有执行的更老的 Load** 的 Load 指令。Load 指令在 LoadUnit 执行到 s2
级（此时已完成地址翻译和 PMA / PMP 检查）时，会分配 LoadQueueRAR 项。当 LoadQueueRAR 中的 Load
指令**在程序序上更老的 Load 都已全部写回**时，这条 Load 指令即可从 LoadQueueRAR 中释放。当 Load 指令在访问
LoadQueueRAR 时发现有更年轻的、相同地址的 Load，且更年轻的 Load 可能被另一个核访问过（该地址发生过替换，或者被 Probe 过），则发生
RAR 访存违例，需要进行回滚。

**RAR 访存违例的恢复**：当检测到 RAR 违例发生时，LoadUnit 会发起回滚，从发生违例的更老的 Load 的下一条指令开始刷新流水线。

### RAW 访存违例的检测与恢复

**RAW 访存违例**：处理器核执行 Load
指令的结果应该来自于**当前处理器核所见的全局内存序的最近一次写操作**，特别地，如果最近一次写操作来自当前核的 Store 指令，那么 Load 应该拿到这条
Store 所写的数据。超标量乱序处理器为了优化 Load 指令的性能会推测执行 Load，因此一条 Load 指令可能会越过一条更老的、相同地址的 Store
先执行，拿到 Store 之前的旧值，即 RAW 访存违例。

**RAW 访存违例的检测**：LoadQueue 中的 LoadQueueRAW 模块会用 FreeList
的结构记录所有**有可能存在相同地址但还没有执行的更老的 Store** 的 Load 指令。Load 指令在 LoadUnit 执行到 s2
级（此时已完成地址翻译和 PMA / PMP 检查）时，会分配 LoadQueueRAW 项。当 StoreQueue 中所有 Store
地址都已就绪，LoadQueueRAW 中所有的 Load 都可以被释放；或者当 LoadQueueRAW 中的指令**在程序序上更老的 Store
全部地址准备就绪**时，这条 Load 即可从 LoadQueueRAW 中释放。当 Store 指令在查询 LoadQueueRAW
时发现有更年轻的、相同地址的 Load，则发生 RAW 访存违例，需要进行回滚。

**RAW 访存违例的恢复**：当检测到 RAW 违例发生时，LoadQueueRAW 会发起回滚，从发生违例的 Store 的下一条指令开始刷新流水线。

### SBuffer 优化 Store 指令性能

根据 RVWMO 模型，在多核场景下，（没有 FENCE 或其他带有屏障语义的指令前提下）一个核的 Store 指令可以晚于更年轻的不同地址 Load
指令对其他核可见。该内存模型规则主要是为了优化 Store 指令的性能，包括 RVWMO 在内的弱一致性模型允许在处理器核中加入
SBuffer，用于暂存已提交的 Store 指令的写操作，对这些写操作做合并后再写入 DCache，减少 Store 指令对 DCache SRAM
端口的争用，从而提高 Load 指令的执行带宽。

SBuffer 为 16 × 512B 的全相联结构。当多个 Store 地址落在同一 cache 块时，SBuffer 会对这些 Store 进行合并。

SBuffer 每周期最多写入 2 条 Store 指令，每条 Store 指令的写数据宽度为 16B（特殊地，cbo.zero 指令一次操作一个 cache
块）。

**SBuffer 的换出**：

- 当 SBuffer 的容量超过一定阈值时会执行换出操作，根据 PLRU 替换算法选出替换块写入 DCache
- SBuffer 支持被动刷新机制，FENCE / 原子 / 向量 Segment 等指令执行时会清空 SBuffer
- SBuffer 支持超时刷新机制，数据块超过 $2^{20}$ 拍没有被替换会被换出

### Store-to-Load 数据前递

SBuffer 的存在以及 Load 指令的推测执行，导致 Load 指令除了要访问 DCache 还需要访问 SBuffer 和
StoreQueue，因此要求 SBuffer 和 StoreQueue 提供 Store-to-Load 数据前递功能。当多个来源同时命中时，LoadUnit
需要对多个来源的数据做合并，合并的优先级 StoreQueue > SBuffer > DCache。

### MMIO 指令的执行

香山核只允许标量访存指令访问 MMIO 地址空间。MMIO 访问和其他任何访存操作都是强定序的（Strongly-ordered），因此 MMIO
指令需要等待其成为 RoB 队头才能执行，即这条指令之前的指令已经全部完成。对于 MMIO Load 指令，要求完成虚实地址转换且 PMA / PMP
物理地址检查通过；对于 MMIO Store 指令，要求完成虚实地址转换且物理地址检查通过，且写数据就绪。然后 LSQ 负责将访存请求发往 Uncache
模块，Uncache 模块通过总线访问外设，得到结果后又 LSQ 写回 RoB。

原子指令、向量指令不支持 MMIO 访问，如果有访问 MMIO 地址空间的这类指令会报相应的 AccessFault 异常。

### Uncache 指令的执行

香山核除了支持访问非幂等的、强定序的 MMIO 地址空间，还支持访问幂等的、弱一致性（RVWMO）的 Non-cacheable 地址空间，后者简称
NC，软件通过将页表的 PBMT 位域配置成 NC 来覆盖原有的 PMA 属性。不同于 MMIO 访问，NC 访问允许乱序访存，NC Load
的执行不会有副作用，因此可以推测执行。

在 LoadUnit / StoreUnit 流水线上被认为是 NC 地址（PBMT = NC）的访存指令会在 LSQ 中进行标记。LSQ 负责将 NC
访存发往 Uncache 模块。Uncache 支持同时处理多个 NC 请求，支持请求合并，并负责前递 Store 给 LoadUnit 中正在执行的 NC
Load。

原子指令、向量指令不支持 NC 访问，如果有访问 NC 地址空间的这类指令会报相应的 AccessFault 异常。

### 非对齐访存

香山核支持标量和向量访存指令对 Memory 空间的非对齐访问。

- 不跨 16B 边界的标量非对齐访存，直接正常访问即可，不需要额外处理
- 跨 16B 边界的标量非对齐访存，会在 MisalignBuffer 拆分成 2 次对齐的访存操作，完成后 MisalignBuffer 负责拼接和写回
- 向量非 Segment 的 Unit-stride 指令会访问连续的一段地址空间，在元素合并后一次访问连续 16B，因此不需要额外处理
- 向量非 Segment 的除 Unit-stride 外的其他指令，在 VSplit 模块中完成元素拆分和地址计算，发往流水线，如果是非对齐的元素会被发往
  MisalignBuffer，剩下的流程和非对齐标量相同，区别在于最终 MisalignBuffer 会写回 VMerge 而不是直接写回后端
- 向量 Segment 指令的非对齐处理由 VSegmentUnit 独立完成，不复用标量访存通路，而是通过独立状态机完成

原子指令不支持非对齐访问，MMIO 和 NC 地址空间均不支持非对齐方位，这些情况会报 AccessFault 异常。

### 原子指令的执行

香山核支持 RVA 和 Zacas 指令集。香山目前的设计会将原子指令所访问的 cache 块缓存到 DCache 后再执行原子操作。

访存单元会侦听 Store 发射队列发射的地址和数据，如果是原子指令则进入 AtomicsUnit。AtomicsUnit 会完成 TLB 地址翻译、清空
SBuffer、访问 DCache 等一系列操作。

## 总体设计

### 整体框图和流水级

![MemBlock 架构图](./figure/memblock.svg)
