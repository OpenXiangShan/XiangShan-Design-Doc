# TAgged GEometric History Length predictor (tage) {#sec:bpu-tage}

tage 使用多张带 tag 的预测表，分别记录不同长度的历史信息与条件分支方向之间的相关性。历史长度大致按几何级数增长：短历史表能够较快地学习常见模式，长历史表用于区分短历史无法区分的执行路径。预测时优先使用命中表中历史最长的一张，并根据置信度决定是否改用较短历史表的结果。

在当前实现中，tage 根据取指块起始地址 `startPc` 和路径历史寄存器 PHR 的折叠历史索引预测表，为 mbtb 提供的各条候选条件分支生成方向预测。基础方向预测（base prediction）由 mbtb 的方向计数器提供，tage 内部没有独立的 baseTable。mbtb 的候选结果也包括 Victim Btb（vbtb）命中的分支，其基础计数器同样通过 mbtb 接口传递。

tage 在 s2 同时输出快速 provider 结果和完成 provider / alternate 选择后的结果：前者用于 Bpu 的 S2 预测，后者在 S3 与 sc 的结果一起参与最终方向选择。分支位置、类型和目标地址仍由 mbtb 等模块提供。

## 参数列表 {#sec:bpu-tage-params}

| 参数 | 默认值 | 描述 | 要求 |
| --- | --- | --- | --- |
| `TableInfos` | 见下表 | 各张预测表的容量、相联度和历史长度 | 按历史长度递增排列，当前 tage 使用非零历史长度；表数不超过 15 |
| `NumBanks` | 4 | 每张表的 bank 数，用于缓解单端口 SRAM 的访问冲突 | 大于 0，通常取 2 的幂次 |
| `TagWidth` | 13 | 各张表共用的 tag 位宽 | 大于 1 |
| `TakenCtrWidth` | 3 | 方向饱和计数器位宽 | 大于等于 2 |
| `UsefulCtrWidth` | 2 | “有用”饱和计数器位宽 | 大于 0 |
| `UsefulCtrInitValue` | 0 | 新分配表项的 useful 初始值 | 能用 `UsefulCtrWidth` bit 表示 |
| `NumUsefulCtrSramFolds` | 8 | useful SRAM 的折叠倍数，将多个逻辑行合并到一个物理行 | 2 的幂次，且能整除 `NumSets` |
| `WriteBufferSize` | 4 | entry 写缓冲每个端口的深度，以及每个 useful 写队列的深度 | 大于等于各张表的 `NumWays` |
| `UsefulResetCtrWidth` | 8 | 累计分配失败、触发 useful 清零的计数器位宽 | 大于 0 |
| `UseAltOnNaWidth` | 5 | provider / alternate 选择计数器位宽 | 大于等于 2 |
| `EnableTageTrace` | false | 是否生成条件分支训练的 ChiselDB trace | |

`TableInfos` 中每项的格式为 `TageTableInfo(Size, NumWays, HistoryLength)`，表下标从 0 开始：

| 表下标 | `Size` | `NumWays` | `HistoryLength` |
| --- | --- | --- | --- |
| 0 | 4096 | 2 | 4 |
| 1 | 4096 | 2 | 9 |
| 2 | 4096 | 2 | 17 |
| 3 | 4096 | 2 | 29 |
| 4 | 4096 | 2 | 56 |
| 5 | 4096 | 2 | 109 |
| 6 | 4096 | 2 | 211 |
| 7 | 4096 | 2 | 397 |

其中 `Size` 是一张表的总表项数，满足：

```text
Size = NumSets * NumBanks * NumWays
```

默认每个 bank 有 512 组，每组 2 路，8 张表共 32768 个表项。`HistoryLength` 表示参与折叠的 PHR 历史位数，不能直接理解为条件分支条数；历史的维护由 PHR 模块完成，另请参考 [@sec:bpu-phr] [路径历史寄存器](history.md#sec:bpu-phr)。

## 表索引 {#sec:bpu-tage-index}

### 地址与历史的混合 {#sec:bpu-tage-index-hash}

对每张表，使用该表对应历史长度的三份折叠历史：

- 索引历史：折叠到 `min(HistoryLength, log2Ceil(Size / NumWays))` bit，高位补 0 后拆分为 bank 和 set 两部分。
- 第一份 tag 历史：折叠到 `min(HistoryLength, TagWidth)` bit。
- 第二份 tag 历史：折叠到 `min(HistoryLength, TagWidth - 1)` bit，左移一位后参与 tag 计算。

默认参数下，索引历史的目标位宽为 11 bit，其中低 2 bit 用于 bank，高 9 bit 用于 set；两份 tag 历史的目标位宽分别为 13 bit 和 12 bit。短历史不足相应位宽时，高位补 0。

默认参数支持压缩指令，`instOffsetBits = 1`。`startPc` 中参与计算的地址域为：

```text
| 49........25 | 24........12 | 11.........3 | 2.........1 | 0          |
| unused       | tag          | setIdx       | bankIdx     | instOffset |
```

设 `indexHist` 为补齐到 11 bit 的索引历史，`tagHist0/1` 为两份折叠后的 tag 历史，则有：

```text
bankIdx = startPc[2:1]   ^ indexHist[1:0]
setIdx  = startPc[11:3]  ^ indexHist[10:2]
tag     = startPc[24:12] ^ tagHist0 ^ (tagHist1 << 1) ^ cfiPosition
```

其中 `^` 表示按位异或，各操作数按目标位宽补齐。bank 和 set 都混入了历史，因此即使 `startPc` 相同，不同路径历史也可能访问不同的 bank 和组。

### 一个取指块中的多条分支 {#sec:bpu-tage-index-position}

同一取指块中的候选分支共用 `startPc` 和 PHR，因此每张表只需读取一个 bank 的一组表项。各条分支使用各自的 `cfiPosition` 计算不同的 tag，再分别与这组表项比较，从而复用同一次 SRAM 读取。

`cfiPosition` 是分支相对于取指块起始地址按 half-align 对齐后的偏移，以 2B 为单位，默认宽度为 5 bit。另请参考 [@sec:bpu-mbtb-half-align] [mbtb 的 Half-align](mbtb.md#sec:bpu-mbtb-half-align) 小节。

候选分支数由 `NumBtbResultEntries` 决定。当前默认每个 align bank 有 4 路 mbtb 结果和 1 路 vbtb 结果，两个 align bank 共提供 10 路候选结果。它们共享 tage 的读数据，分别进行 tag 匹配和方向选择；实际是否采用某一路方向，还需要 Bpu 检查该 mbtb 结果是否有效、是否为条件分支。

## 表项结构 {#sec:bpu-tage-entry}

每个逻辑表项包含以下状态：

| 字段 | 默认位宽 | 描述 |
| --- | --- | --- |
| `valid` | 1 | 表项是否有效 |
| `tag` | 13 | 地址、历史和分支位置混合得到的 tag |
| `takenCtr` | 3 | 方向饱和计数器，最高位为 1 表示跳转，为 0 表示不跳转 |
| `usefulCtr` | 2 | 表项相对于 alternate / base 的预测价值，用于决定能否被替换 |

物理上，`valid`、`tag` 和 `takenCtr` 组成 `TageEntry`，保存在 entry SRAM 中；`usefulCtr` 单独保存在 useful SRAM 中，两者具有独立的写使能。这样组织的好处是 `usefulCtr` 的 reset 比较方便，而且只更新 useful 时不需要重写 entry，只训练方向时也不需要重写 useful。

`takenCtr` 是无符号饱和计数器。默认取值 0～7，其中 0～3 预测不跳转，4～7 预测跳转，3 和 4 是临界（weak）状态。weak 表示再向相反方向更新一次就会改变预测方向；它也被用作“新分配或尚未充分训练”的近似标志，表项中没有单独的年龄字段。计数器接口另请参考 [@sec:bpu-saturate-counter] [饱和计数器](saturateCounter.md)。

## 层级结构与流水线 {#sec:bpu-tage-hierarchy}

### 顶层 Tage {#sec:bpu-tage-hierarchy-top}

顶层实例化 `NumTables` 个 `TageTable`，负责索引生成、命中比较、provider / alternate 选择、训练和分配，以及全局 useful 清零控制。

在预测流水级上：

- s0：接收 `startPc` 和 PHR 提供的 `foldedPathHist`，为每张表计算 bank、set 索引，并通过 `readReq(0)` 发出预测读请求。
- s1：接收各张表的读响应，根据 mbtb 提前提供的 `s1_positions` 计算各条候选分支的 tag，并与每张表的各路表项比较。读响应使用 `DataHoldBypass` 保持，以适应预测流水线停顿。
- s2：接收 mbtb 的有效候选结果，选择命中路、provider 和 alternate；输出 `fastTakenVec`、`takenVec`、送往 sc 的 provider 计数器，以及训练元数据。

两路方向输出的用途见 [@sec:bpu-tage-prediction] [预测结果选择](#sec:bpu-tage-prediction) 小节。tage 自身在 s2 完成这些计算，Bpu 再寄存完整结果供 S3 使用。

在训练流水级上：

- t0：接收训练块，筛出有效条件分支，按分支位置匹配 mbtb 元数据，取得基础计数器和对应的 tage 元数据；决定本次训练是否需要重读预测表，必要时通过 `readReq(1)` 发出请求。
- t1：接收训练读响应，计算各张表不含 `cfiPosition` 的 `rawTag`，寄存训练所需的信息。
- t2：从元数据恢复或从读响应重新匹配 provider / alternate，计算计数器更新、选择器训练和分配需求。
- t3：合并各条分支的写请求，更新选择器，选择至多一个新表项进行分配，并将写请求发往各张表。

训练路径的选择和更新条件见 [@sec:bpu-tage-train] [训练](#sec:bpu-tage-train) 小节。训练请求一旦在 t0 被接收，后续 t1～t3 逐拍推进。

### 底层 TageTable {#sec:bpu-tage-hierarchy-table}

每个 `TageTable` 包含 `NumBanks` 个 bank，每个 bank 的各路分别实例化 entry SRAM 和 useful SRAM，均为单端口。useful 数据较窄，通过 `FoldedSRAMTemplate` 合并多个逻辑行，以改善存储面积效率。

每张表提供两个逻辑读请求接口：`readReq(0)` 用于预测，`readReq(1)` 用于训练重读。它们只有访问不同 bank 时才能并行；同一 bank 的读冲突在顶层通过 `trainReady` 避免。一次读操作会读取选中 bank 内对应 set 的全部路，下一周期返回响应。

写请求进入 `TageTable` 后先寄存一拍，再进入 entry 写缓冲或 useful 写队列，在相应 SRAM 没有读请求时回写。写缓冲与读写仲裁的细节见 [@sec:bpu-tage-storage] [存储访问与写缓冲](#sec:bpu-tage-storage) 小节。

## 预测结果选择 {#sec:bpu-tage-prediction}

### Provider、alternate 与 base {#sec:bpu-tage-prediction-provider}

对每条候选分支，按以下顺序选择命中结果：

1. 每张表中，仅当 `valid` 为真且 tag 相等时命中。如果同一张表有多路命中（multi-hit），使用 `PriorityEncoderOH` 选择下标最小的一路。
2. 在命中的表中，选择历史最长（表下标最大）的表项作为 provider。
3. 去掉 provider 所在的整张表，再选择历史最长的命中表项作为 alternate，代码中简称 alt。因此同一张表的另一命中路不会成为 alternate。
4. 没有 alternate 时，使用 mbtb 提供的基础方向预测作为后备结果。

multi-hit 的直接原因是同一张表的同一个 bank、set 内，多路同时保存了有效且相同 tag 的表项。预测、训练和 SRAM 写回之间存在时间差：训练依据较早的读响应或预测元数据生成写请求时，其他训练可能已经替换或重新分配了相关表项，使相同 tag 有机会被安装到不同路。当前实现的读端不旁路写缓冲中的待写数据，元数据训练也不重新检查原路的 tag，因此不能保证写入时的表项状态仍与训练依据一致。写缓冲虽然会合并其记录范围内相同 `setIdx + tag` 的写请求，但不会对整组 SRAM 做跨路去重，也不会在写入一路时失效其他路的同 tag 表项，因而重复项可能保留，并在后续预测时同时命中。存储访问细节见 [@sec:bpu-tage-storage] [存储访问与写缓冲](#sec:bpu-tage-storage) 小节。

provider 通常能利用更多历史信息，但新分配表项的计数器尚未充分训练，因此 weak provider 不一定优于 alternate / base。为此，tage 使用 `useAltOnNa` 选择器决定是否暂时采用后备结果。

### UseAltOnNa 选择器 {#sec:bpu-tage-use-alt-on-na}

`useAltOnNaVec` 是寄存器实现的饱和计数器数组，包含 `2 * NumTables` 个计数器，默认共 16 个。每张 provider 表对应两个计数器，分别处理后备结果置信度低和高的情况：

```text
altConf = hasAlt ? !alt.takenCtr.isWeak : baseCtr.isSaturate
useAltOnNaIdx = Cat(providerTableIdx, altConf)
useAltOnNa = useAltOnNaVec[useAltOnNaIdx].isPositive
useProvider = hasProvider && !(useAltOnNa && provider.takenCtr.isWeak)
```

这里 `Cat` 表示拼接，`altConf` 是索引最低位。alternate 非 weak 时认为置信度高；没有 alternate 时，则要求基础计数器已经饱和。预测阶段的基础置信度由 mbtb 的 `baseConf` 接口提供。

默认选择计数器为 5 bit 无符号计数器，初始值为 `WeakPositive = 16`。值在 16～31 时，weak provider 让位于 alternate / base；值在 0～15 时，仍使用 provider。非 weak provider 始终优先。

### 两路方向输出与 sc {#sec:bpu-tage-prediction-output}

| 输出 | 内容 | 使用位置 |
| --- | --- | --- |
| `fastTakenVec` | 原始 provider 的方向；有任意命中时有效 | Bpu S2 的快速方向选择 |
| `takenVec` | 完成 `useAltOnNa` 选择后的 provider 或 alternate 方向 | 寄存后参与 Bpu S3 的方向选择 |
| `providerTakenCtrVec` | 原始 provider 的完整方向计数器，附带有效位 | sc 的输入 |

为了减少 Bpu 的 override bubble，在时序允许的情况下，只使用 provider 结果作为 Bpu S2 级的方向预测，可以实现相当于 tage 的预测延迟减一拍的效果。快速路径按“表下标从大到小、表内路下标从小到大”的顺序直接选择第一个命中项的方向，避免等待 alternate 和选择器计算。没有 provider 时，Bpu S2 使用 mbtb 的基础方向。

完整路径作为Bpu S3 级的方向预测，按以下规则输出：

```text
if useProvider:
    takenVec = Valid(provider.takenCtr.isPositive)
else if hasAlt:
    takenVec = Valid(alt.takenCtr.isPositive)
else:
    takenVec.valid = false   // 由 Bpu 使用基础方向
```

例如，provider 为 weak taken、alternate 预测不跳转且选择器倾向后备结果时，S2 的快速路径预测跳转，完整路径预测不跳转。Bpu 在 S3 使用完整的结果重新选择最早跳转分支，必要时覆盖前级预测。

S3 对有效条件分支的方向选择优先级为：sc 修正结果、tage 的 `takenVec`、mbtb 基础方向。由于时序原因，送给 sc 的始终是原始 provider 计数器，完整路径由于包含 alt 的选择，sc 无法在一拍内用完整结果去计算并给出预测。

### 训练元数据 {#sec:bpu-tage-meta}

tage 为每路 mbtb 候选结果生成一个 `TageMetaEntry`，经 Bpu 送入 FTQ，训练时再按分支位置取回。主要字段如下：

- `hasProvider`、`hasAlt`：预测时是否存在 provider / alternate。
- `useProvider`：完整预测路径是否选择了 provider。
- `providerTableIdx`、`providerWayIdx`：provider 所在的表和路。
- `providerTakenCtr`、`providerUsefulCtr`：预测时的 provider 方向和 useful 计数器。
- `altTableIdx`、`altWayIdx`、`altTakenCtr`：alternate 所在的表、路和方向计数器。

基础计数器保存在 mbtb 元数据中，包含 vbtb 命中时的基础计数器。训练时使用训练块的 `startPc`、PHR 提供的训练历史和分支位置重算 bank、set 和 tag，因此 tage 元数据不需要保存这些索引。

## 训练 {#sec:bpu-tage-train}

### 元数据路径与重读路径 {#sec:bpu-tage-train-read}

由于 tage 使用的是单端口 SRAM，如果每次训练都重新读 SRAM，预测读和训练读会发生很严重的冲突。如果优先训练读，会严重阻塞预测带宽；如果优先预测读，则会影响训练，导致更多地误预测。因此，香山 tage 选择将预测时的元数据保存起来，训练时如果预测正确就使用保存的元数据去训练，不必重读 SRAM，但是在误预测时依然重读SRAM。这样，预测读和训练读的冲突大大减少，同时几乎不会影响预测的准确率，代价是增加了一部分用于存储元数据的面积。

tage 使用来自 FTQ 的训练请求，只对有效、类型为条件分支且能够匹配预测时 mbtb 元数据的分支进行训练。匹配依据为 mbtb 元数据的 `rawHit` 和 `cfiPosition`；若有多个匹配，取下标最小的一项，并取出与之对应的 tage 元数据。

tage 只会训练已经存在于 mbtb 中的分支。当一条分支第一次出现时，因为它没有被 mbtb 记录而产生了一次误预测，这次误预测只会让 mbtb 分配新表项，而发生这次误预测时，tage 使用的是旧的 mbtb meta，因此当这条分支第二次误预测时才会为它分配表项。这样设计的考虑是：有些分支的模式比较简单，用 mbtb 的 2-bit 饱和计数器就可以预测得很好，这种情况下不应该占用宝贵的 tage 表项。

在 t0，先用预测时保存的 `useProvider`、provider / alternate 计数器和基础计数器，还原完整路径的 TAGE 方向。若任一可训练条件分支满足下列条件，就为整个训练请求重读所有 tage 表：

- 还原的 TAGE 方向与实际方向不同；或
- 分支的 `mispredict` 标记为真。

否则，整个请求使用元数据路径，跳过 SRAM 读取。因此，最终预测正确也不一定能跳过重读，例如 sc 修正了错误的 TAGE 方向时，仍需重读。

元数据路径保留预测时的 provider / alternate 身份和 `useProvider` 决策，使用保存的计数器计算更新。重读路径使用读出的表项重新比较 tag、选择 provider / alternate，并结合训练时的 `useAltOnNaVec` 重新计算方向和分配需求。元数据路径不需要 alternate 的 useful 值，因为 alternate 训练只更新方向计数器。

预测和训练都访问各张表的一个 bank。只有需要重读且预测同时发起读取时，才检查二者的 bank 是否冲突：若任意一张表的预测 bank 与训练 bank 相同，`trainReady` 拉低，整个训练请求等待；各张表都不冲突时，预测和训练可以并行读取。元数据路径没有训练读请求，不产生这类冲突。

### 方向与 useful 更新 {#sec:bpu-tage-train-counter}

对每条可训练分支，设 `actualTaken` 为实际方向，`providerPred` 为 provider 方向，`altOrBasePred` 为 alternate 存在时的方向、否则为基础方向：

| 状态 | 更新条件 | 更新动作 |
| --- | --- | --- |
| provider 的 `takenCtr` | 存在 provider，且向实际方向更新会改变计数器 | 实际跳转则加 1，否则减 1；不要求本次采用 provider |
| alternate 的 `takenCtr` | 完整路径实际采用 alternate，且更新会改变计数器 | 按实际方向加减 1 |
| provider 的 `usefulCtr` | provider 预测正确，且与 alternate / base 方向不同，计数器未到最大值 | 加 1；不要求本次采用 provider |

普通训练不会因为 provider 预测错误而减少其 useful，也不会更新 alternate 的 useful。useful 通过新表项分配时初始化，以及 [@sec:bpu-tage-useful-reset] [全局清零](#sec:bpu-tage-useful-reset) 来释放。已经沿本次更新方向饱和的计数器不生成对应字段的写请求，以减少写入。

每条分支的更新最终在 t3 按表和路合并。entry 与 useful 使用独立写使能；同一训练块可以更新多张表、多路表项。实现中检查同一物理路不会同时接收多条 provider 更新、多条 alternate 更新，或 provider / alternate 两类更新。

### 选择器更新 {#sec:bpu-tage-train-selector}

仅当存在 provider、provider 为 weak，且 provider 与 alternate / base 的预测方向不同时，训练 `useAltOnNaVec`：

- alternate / base 正确：对应计数器加 1，增加采用后备结果的倾向。
- provider 正确：对应计数器减 1，增加采用 provider 的倾向。

两者方向相同时不更新，因为选择器无法改变该次预测的方向。这一训练条件不要求实际已经采用 alternate / base。

同一训练块内可能有多条分支更新同一个选择计数器。t3 分别统计增加和减少的次数，取二者之差作为净步长，再进行一次饱和更新，避免更新结果依赖分支处理顺序。

## 表项分配与替换 {#sec:bpu-tage-allocation}

### 分配条件 {#sec:bpu-tage-allocation-condition}

新表项分配同时要求分支带有 `mispredict` 标记，且本次训练计算出的 TAGE 方向仍然错误。仅有最终误预测标记不足以触发分配；如果重读后 TAGE 方向已经正确，就只进行必要的训练。

以下情况也不分配：

- provider 已位于历史最长的表，没有更长历史可用。
- provider 为 weak、其方向正确，但完整路径采用了 alternate / base。此时错误来自选择决策，优先通过训练 provider 和选择器纠正。

一次训练请求至多为一条分支分配一个新表项，t3 对需要分配的分支数量进行断言检查。

### 候选表与候选路 {#sec:bpu-tage-allocation-victim}

存在 provider 时，只考虑历史比 provider 更长的表；没有 provider 时，所有表均可参与分配。

对每张候选表本次访问的 set，依次确定可替换路集合：

1. 如果有无效路，只保留无效路。
2. 否则，如果有 `takenCtr` 为 weak 且 `usefulCtr == 0` 的路，只保留这些路。
3. 否则，保留所有 `usefulCtr == 0` 的路。

集合为空的表不能分配。这里的优先级先在各张表内部确定，再选择具体的表；并非先在所有表中统一寻找无效路。

对可分配表，使用 15 bit 最大周期 LFSR 的低 `NumTables` bit 作为随机掩码，过滤一部分候选，再选择剩余候选中历史最短的一张。如果随机掩码过滤掉全部候选，就回退到原始候选集合。这样既偏向尽量短的历史，又避免总是集中分配到同一张表。LFSR 的周期为 $2^{15}-1$，因此当前实现要求 `NumTables <= 15`。

选定表后，在其可替换路集合中选择下标最小的一路，不使用 LRU / PLRU 作为 tage 表项替换策略。

### 新表项初始化 {#sec:bpu-tage-allocation-init}

- `valid`：置为真。
- `tag`：本次训练对应的 `rawTag ^ cfiPosition`。
- `takenCtr`：实际跳转时初始化为 `WeakPositive`，默认值为 4；实际不跳转时初始化为 `WeakNegative`，默认值为 3。
- `usefulCtr`：初始化为 `UsefulCtrInitValue`，默认为 0。

分配会同时写 entry 和 useful。如果某一路同时产生普通更新与分配写入，则分配结果优先。

### Useful 全局清零 {#sec:bpu-tage-useful-reset}

由于普通训练只增加 useful，需要释放已经积累 useful、但对后续执行路径不再有价值的表项。顶层使用 `usefulResetCtr` 累计“需要分配，但所有候选表均无可替换路”的次数。

默认计数器为 8 bit，从 0 开始，分配失败时加 1，成功时保持，不会减 1。计数器饱和后，在后续一次 t3 有效训练时启动所有表的 useful 清零，并将失败计数器归零。清零进行中不重复累计分配失败，也不再次启动清零。

各张表的各个 bank 独立遍历 set，将所有路的 useful 写为 0，直到最后一组写入完成。期间：

- entry SRAM 保留原有内容，方向预测仍可继续读取。
- 正在清零的 bank 不读取 useful SRAM，其读响应中的 useful 统一视为 0。
- useful 写队列在清零开始时 flush，清零期间不接受该 bank 的普通 useful 更新。
- useful 清零写入优先于普通 useful 写回；各 bank 依据实际写握手推进清零地址。

清零不会使表项失效，而是使它们重新具备被替换的条件；仍然有效的方向信息可以继续用于预测。

## 存储访问与写缓冲 {#sec:bpu-tage-storage}

entry 和 useful 使用不同的缓冲结构：

- entry：每个 bank 一个通用 `WriteBuffer`，具有 `NumWays` 个写入和回写端口，分别连接各路 entry SRAM。内部每个端口有 `WriteBufferSize` 个槽位，默认每个 bank 共 `2 * 4 = 8` 个槽位。
- useful：每个 bank 的每一路一个深度为 `WriteBufferSize` 的队列，开启 `pipe`、`flow` 和 `flush`。

entry 写缓冲按 `setIdx + tag` 在各端口的槽位中查找已有项。命中时，利用缓冲内的方向计数器和当前分支的实际方向继续训练，避免连续训练总是基于较早读出的计数器值。回写 SRAM 后，槽位会清除 dirty 标记，但保留 shadow 内容和有效标记，后续相同表项的训练仍可命中该状态。未命中时，则把顶层计算的新表项放入对应端口的槽位，并标记为待回写。

读请求优先于普通写回：预测或训练正在读取某个 bank 时，该 bank 的 entry 普通写回等待；useful SRAM 同理，但 useful 全局清零具有单独的优先控制。不同 bank 可以分别进行读写，各路也可独立回写。

当前 `TableReadResp` 直接取自 SRAM，预测读和训练重读均不旁路 entry 写缓冲或 useful 写队列中的待写数据。因此，写缓冲内的连续训练合并与读端取得待写状态是两件不同的事，读出的表项可能尚未包含排队中的更新。

写缓冲不会通过 `trainReady` 对训练请求施加反压。entry 写缓冲在未命中且对应端口全为 dirty 时会覆盖一个待写槽位，并统计 `overwrite`；useful 队列无法入队时也不会使顶层训练停顿。因此，这些缓冲用于吸收预测表训练流量，不保证无限保留尚未写入 SRAM 的更新。

上电复位时，entry SRAM 和 useful SRAM 均执行复位；所有表的两类 SRAM 都完成后，顶层才拉高 `sramResetDone`。这与运行中只清零 useful 的维护操作不同。

## 实现对应关系 {#sec:bpu-tage-implementation}

以下路径均相对于 `src/main/scala/xiangshan/frontend/bpu/`：

| 文件 | 内容 |
| --- | --- |
| `tage/Parameters.scala` | 默认参数和派生参数 |
| `Types.scala` 中的 `TageTableInfo` | 表配置和折叠历史规格 |
| `tage/Helpers.scala` | bank、set、tag 计算和最长历史选择 |
| `tage/Bundles.scala` | 表项、预测、训练元数据与表访问接口 |
| `tage/Tage.scala` | 预测与训练流水线、选择器、分配和 useful 清零控制 |
| `tage/TageTable.scala` | SRAM、写缓冲和 useful 清零实现 |
| `WriteBuffer.scala` | entry 写缓冲的匹配、计数器合并和回写状态维护 |
| `Bpu.scala` | mbtb、tage、sc 的连接，以及 S2 / S3 预测选择 |
