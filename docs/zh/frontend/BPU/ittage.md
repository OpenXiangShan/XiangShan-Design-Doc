# Indirect Target Tage (ittage) {#sec:bpu-ittage}

ITTAGE 属于 BPU 的精确目标预测器，负责非返回型间接跳转的目标地址预测。对于 `jalr` 一类间接跳转，指令是否执行、是否跳转可能已经由取指路径确定，但目标来自运行时寄存器，可能有多个取值。ITTAGE 根据 PC 和路径历史，从多张不同历史长度的 tagged table 中选择一个跳转目标，每周期最多进行一条间接跳转指令的预测。

ITTAGE 参考了 TAGE 共享多历史长度、tag 匹配和最长历史 provider 的选择思想。本节不再展开这些共同点，重点说明 ITTAGE 特有的目标表示、预测选择、训练与分配。

## 参数列表 {#sec:bpu-ittage-params}

| 参数 | 默认值 | 描述 | 要求 |
| --- | --- | --- | --- |
| `TableInfos` | 5 张表，见下表 | 每张表只指定总行数和历史长度 | 行数可被 `NumBanks` 整除 |
| `NumBanks` | 2 | 每张 ITTAGE 表的 bank 数 | 2 的幂次 |
| `TagWidth` | 9 | tag 位宽 | 大于 0 |
| `ConfidenceCntWidth` | 2 | 目标置信度计数器位宽 | 至少 2 |
| `UsefulCntWidth` | 1 | useful 计数器位宽 | 大于 0 |
| `UseAltOnNaWidth` | 4 | 备用选择相关参数，当前选择路径未使用 | 大于 0 |
| `TargetWidth` | 20 | 目标低地址偏移位宽，也是区域划分位数 | 大于 0 |
| `TickWidth` | 8 | useful 老化计时器位宽 | 大于 0 |
| `TableSramSize` | 128 | `FoldedSRAMTemplate` 的物理深度切分基准 | 2 的幂次 |
| `TableWriteBufferSize` | 4 | 每个 bank 写缓冲深度 | 大于 0 |
| `RegionNums` | 16 | 共享区域表的 entry 数 | 大于 0 |
| `RegionPorts` | 2 | 训练时区域表的更新端口数 | 大于 0 |
| `RegionReplacer` | `"plru"` | 区域表替换策略 | `plru`、`lru` 或 `random` |

ITTAGE 与 TAGE 类似，采用多种历史长度表进行预测。香山昆明湖架构中的 ITTAGE 提供了5个带 tag 的预测表T1‑T5，基准预测器和带 tag 的预测表的基本信息见下表。

| 预测器 | 是否带tag | 作用 | 表项构成 | 
| --- | ---: | ---: | ---: |
| 基准预测器T0 | 否 | 用于在带tag预测表的tag均不匹配时提供预测结果 | ITTAGE 中并没有实现T0，而是直接使用mbtb的预测结果作为基准预测结果 |
| 预测表T1-T5 | 是 | 存在tag匹配时，选历史长度最长者提供预测结果 | valid：1bit tag：9bits ConfidenceCnt：2bits（最高位表示要不要输出这个预测结果）us：1bit（usefulness计数器）target：20bits |

这里的 SRAM 所存储的 target 是目标地址的低 20 位的偏移，完整的目标地址需要在 `RegionWays` 中读出高位地址，拼接后使用。（见下文 目标地址表示）

在BPU模块中维护了一个397比特的全局路径分支历史PHR，并为 ITTAGE 的5个带 tag 的预测表分别维护了各自的折叠分支历史，折叠算法类似于 TAGE 。折叠历史具体配置见下表：

| 表 | `Size` | `HistoryLength` | 每 bank 的 set 数 |
| --- | ---: | ---: | ---: |
| T0 | 256 | 4 | 128 |
| T1 | 256 | 8 | 128 |
| T2 | 512 | 13 | 256 |
| T3 | 512 | 16 | 256 |
| T4 | 512 | 32 | 256 |

`Size` 表示该表的总 entry 数。ITTAGE 表没有多路的概念，每个 bank 中一个 set 只有一个 entry，因此每 bank 的 set 数就是 `Size / NumBanks`。5 张表总计 2048 个直接映射 entry。

## 表项结构 {#sec:bpu-ittage-entry}

每个 ITTAGE 表项包含：

- `valid`：表项是否有效；
- `tag`：当前 PC 与折叠历史是否匹配；
- `confidenceCnt`：保存的目标结果有多可信；
- `targetOffset.offset`：目标地址的低位偏移；
- `targetOffset.pointer`：共享区域表中的入口编号，默认 4 位；
- `targetOffset.usePcRegion`：目标高位是否直接来自当前 PC 所在区域；
- `usefulCnt`：表项相对备用目标是否提供了额外价值；
- `paddingBit`：用于使 entry 位宽与 SRAM 数据布局对齐。

默认参数下，逻辑目标偏移为 20 位。由于 RISC-V 指令地址最低位为 0，`PrunedAddr` 在物理存储中省去该位。`confidenceCnt` 使用 2 位无符号饱和计数器：

| 数值 | 含义 |
| ---: | --- |
| 0 | 最低置信度；有 alternate 时改用 alternate 的目标 |
| 1 | 低置信度，但仍采用 provider |
| 2 | 新分配 entry 的初始值 |
| 3 | 最高置信度 |

## 层级结构 {#sec:bpu-ittage-design-hierarchy}

ITTAGE 由三类模块组成：

```plaintext
Bpu
 ├─ Ittage
 │   ├─ IttageTable T0
 │   ├─ IttageTable T1
 │   ├─ IttageTable T2
 │   ├─ IttageTable T3
 │   └─ IttageTable T4
 └─ RegionWays
```

`Ittage` 负责跨表选择，并组织预测、训练和性能事件；每个 `IttageTable` 负责本表的索引、SRAM 和更新；`RegionWays` 由 5 张表共享，用来保存目标高位区域。

### 顶层 Ittage {#sec:bpu-ittage-hierarchy-top}

在预测流水级上：

- s1：接收 Bpu 提供的 `startPc` 和折叠 PHR，向全部 ITTAGE 表发送读请求；
- s2：接收各表 tag 匹配结果，选择 provider 和 alternate，查询 `RegionWays`，重建 provider 和 alternate 的目标；
- s3：输出最终的 ITTAGE 目标和训练元数据，由 Bpu 顶层决定是否采用。

在训练流水级上：

- t0：接收 Bpu 的训练 bundle，并把预测时保存的 `IttageMeta` 送入训练逻辑；
- t1：选择实际执行的非返回型间接分支，更新 provider、alternate、目标、置信度和 useful，并在误预测时尝试分配。

`Ittage.scala` 中的 s1/s2/s3 是 Bpu 全局流水级。`IttageTable.scala` 内部也把请求分成自己的 s0/s1，用来表示“计算索引并读 SRAM”和“接收 SRAM 响应”，两者不要混为同一层级的流水级。

当前实现把 `s1_isIndirect` 常量设为 `true.B`。只要 ITTAGE 使能，就会为经过 s1 的请求发起所有表的读操作；顶层是否真正使用 ITTAGE 目标，仍由分支属性和命中的结果决定。源码注释保留了用快速 BTB 信息关闭无用查询的低功耗优化方向，但该优化当前尚未启用。

### IttageTable {#sec:bpu-ittage-hierarchy-table}

每张 ITTAGE 表包含 `NumBanks` 个 bank，每个 bank 是一个单端口 `FoldedSRAMTemplate`。预测请求只读 PC 选中的 bank，写回请求也由同一套索引计算定位 bank 和 set。

对读请求：

- 第 0 周期：计算 bank、set 和 tag，向对应 bank 发出 SRAM 读请求；
- 第 1 周期：接收 entry，比较 `valid` 和 tag，向顶层输出置信度、useful 和目标摘要。

对写请求：

- 顶层把更新写到每张表的对应 bank；
- bank 的写缓冲暂存 entry；
- 当该 bank 当前没有读请求时，写缓冲把 entry 回写到 SRAM，避免更新长期阻塞预测。

ITTAGE 使用按字段 bitmask 的写入。普通训练通常更新置信度、目标或 useful 的一部分；useful 老化则使用只包含 useful 字段的 mask。这样无需为每次小更新重建并覆盖完整 entry。

### RegionWays {#sec:bpu-ittage-hierarchy-region}

`RegionWays` 保存目标地址的高位区域，共有 `RegionNums` 个 entry。预测时，5 张 ITTAGE 表各自提供一个区域指针；训练时使用 2 个端口查询 provider 和 alternate 目标的区域。若目标区域已存在，则复用原入口；否则使用空闲项或替换器选择一个 victim。

`RegionWays` 是共享的高带宽结构，因此不同 ITTAGE entry 的目标低位可以彼此独立，而目标高位只保存一次。默认采用 PLRU，也可以通过参数切换为 LRU 或随机替换。

## 目标地址表示 {#sec:bpu-ittage-target}

目标地址被拆成：

```plaintext
target = target region || TargetWidth 位低位偏移
```

默认 `TargetWidth=20`，所以 entry 内主要保存 20 位低位偏移和 4 位区域指针，而不是每项都保存完整虚拟地址。

按 `GuardedPc` 的完整布局，可以写成：

```plaintext
| guard(1) | target region(VAddrBits - 20) | targetOffset(20 logical bits) |
                                  offset 的最低位在 PrunedAddr 存储中被省去
```

预测时需要区分两种情况：

1. `usePcRegion=1`：目标与当前 fetch block 位于同一高位区域，直接使用 `s2_startPc` 的高位区域；
2. `usePcRegion=0`：使用区域指针读取 `RegionWays`，再把区域值与偏移拼接。

以示意值说明：

```plaintext
entry.offset      = 20'h45678
entry.pointer     = 3
entry.usePcRegion = 0
RegionWays[3]     = R

target = R || 20'h45678
```

若 `RegionWays` 中对应区域已经不可用，或者 entry 明确使用当前 PC 区域，则目标高位取 `s2_startPc` 的区域。最终目标还带有 `GuardedPc` 的溢出保护位，用于跨合法虚拟地址边界时的校验。

训练时，如果真实目标与 `startPc` 不在同一区域，并且本次写入至少更新了一张 ITTAGE 表，则训练逻辑把真实目标区域写入 `RegionWays`，并把得到的指针放入新 entry 或更新后的 entry。若目标仍在当前区域，则只需设置 `usePcRegion=1`。

## 预测选择 {#sec:bpu-ittage-design-select}

每张表在 `valid && storedTag == calculatedTag` 时命中。跨表选择规则与 TAGE 相同：

- 历史最长的命中表是 provider；
- 历史第二长的命中表是 alternate；
- 没有任何表命中时，ITTAGE 输出 miss。

ITTAGE 当前的目标选择为：

```plaintext
if provider.valid:
    if provider.confidenceCnt == 0 && alternate.valid:
        target = alternate.target
    else:
        target = provider.target
else:
    miss
```

只有置信度恰好为 0 时才尝试 alternate。由于新 entry 从 2 初始化，分配后的第一个 provider 会直接使用自己的目标。若没有 alternate，即使 provider 的置信度为 0，也仍然使用 provider 的目标。

`Parameters.scala` 中保留了 `UseAltOnNaWidth`，`Ittage.scala` 中也声明了 `useAltOnNa` 寄存器，但当前选择逻辑没有读取或更新该寄存器。实际切换条件就是 provider 的置信度计数器。

`prediction.hit` 表示的是“ITTAGE 至少有一个合法 provider”，而不是“最终必定采用 ITTAGE 目标”。Bpu 顶层还要结合分支属性和 RAS 的选择结果决定是否使用它。

## 训练与分配 {#sec:bpu-ittage-design-train}

ITTAGE 训练只接受实际执行、且满足以下条件的间接分支：

```plaintext
needIttage = isIndirect && !hasPop
```

因此返回地址类跳转由 RAS 处理，ITTAGE 主要训练其他间接跳转。

### provider 更新 {#sec:bpu-ittage-train-provider}

provider 的目标与实际目标相等时，置信度加 1；不相等时，置信度减 1。两者都按 2 位饱和计数器更新，因此不会越过 3 或 0。

目标内容采用带迟滞的更新方式。置信度不为 0 时，即使本次目标错误，也主要降低置信度；只有以下情况才写入新的目标偏移：

- 该 entry 是新分配的；
- 该 entry 更新前的置信度已经为 0。

这让一个偶发目标变化不会立刻覆盖已稳定的映射，连续证明原目标不可靠后，entry 才切换到新目标。

如果 provider 因置信度为 0 而采用了 alternate，且最终预测错误，训练逻辑还会更新该 alternate 的置信度和目标状态。目标相同时不更新有用性；目标不同时，provider 的 `usefulCnt` 取决于 provider 目标是否正确。

### 预测错误后的分配 {#sec:bpu-ittage-train-alloc}

分配候选需要同时满足：

1. 查询时没有命中该表；
2. 该 set 当前 entry 的 `usefulCnt=0`；
3. 表的历史长度比 provider 更长；没有 provider 时，所有表都可作为候选。

候选表中使用 15 位 LFSR 掩码随机选择，降低总是分配到同一张表的偏差。若随机掩码没有选中任何候选，则回退到编号最小的候选。新 entry 保存真实目标，置信度初始化为 2，useful 初始化为 0。

如果 provider 保存的目标本身正确，只是因为置信度为 0 而采用了错误的 alternate，当前实现会抑制这次分配。这种错误属于 provider/alternate 选择问题，不需要把同一目标复制到更长历史的表。

### 替换与老化 {#sec:bpu-ittage-design-replacer}

ITTAGE 表本身是直接映射结构，每个 set 没有多路替换器。跨历史长度表的选择由 provider 和分配规则完成，单个 set 内部则依靠 tag、useful 和误预测分配处理冲突。

`usefulCnt` 用于防止新目标经常覆盖仍有价值的 entry。如果 useful 一直为 1，候选集合可能耗尽。训练逻辑在相关误预测且没有可分配 entry 时递增 8 位 tick counter；计数器饱和后，每张表分批扫描 set，并把 useful 字段清零。这一老化过程不会同时改变置信度和目标。

`RegionWays` 的替换独立于 ITTAGE 表。它使用 `RegionReplacer` 配置的 PLRU、LRU 或随机策略，并通过已存在的区域值去重，因此多个 entry 可以指向同一个区域入口。
