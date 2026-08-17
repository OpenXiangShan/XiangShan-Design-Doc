# Micro Btb (ubtb) {#sec:bpu-ubtb}

ubtb 属于 S1 快速预测器组，可以将其看作是一个小型的、全相联的、寄存器实现的 mbtb 缓存（或者说 L0-mbtb），负责记录分支指令的位置、目标地址、分支类型等元数据。

与 mbtb / abtb 不同，ubtb 采用 Instruction-BTB 设计，而非 Region-BTB 设计。对一个 startPc，其只能给出至多一条分支的预测。因此，我们希望这条分支尽可能是跳转的（不跳转的分支可以由 fallThrough 提供基本的预测，由 ubtb 记录额外的分支类型等信息价值不大）。进而，我们要求所有训练进 ubtb 的分支都是跳转的，在预测时假定它们仍是跳转的，因此不需要额外的饱和计数器对方向进行预测。另请参考 [@sec:bpu-ubtb-replacement] [替换策略](#sec:bpu-ubtb-replacement) 中关于 useful 的说明。

## 参数列表 {#sec:bpu-ubtb-params}

| 参数 | 默认值 | 描述 | 要求 |
| ------ | --- | --------- | ------ |
| `NumEntries` | 32 | 表项总数 | |
| `TagWidth` | 22 | tag 位宽 | |
| `TargetWidth` | 22 | 跳转目标地址地位位宽 | |
| `UsefulCntWidth` | 2 | “有用”计数器位宽 | |
| `Replacer` | "plru" | 替换器 | rocket-chip 的 ReplacementPolicy 支持的算法，目前包括 "random", "lru", "plru" |
| `UseFastTrain` | true | 是否启用快速训练，请参考 [@sec:bpu-s1-fast-train] [S1 预测器组的快速训练](#sec:bpu-s1-fast-train) 一节 | |
| `EnableTargetFix` | false | 是否记录 target 进位/借位信息并进行修正，请参考 [@sec:bpu-target-fix] [目标地址修正](#sec:bpu-target-fix) 一节 | |

## 表项结构 {#sec:bpu-ubtb-entry}

- `tag`：tag
- `usefulCnt`：“有用”计数器，请参考 [@sec:bpu-ubtb-replacement] [替换策略](#sec:bpu-ubtb-replacement) 中的说明
- `slot1/2.position`：cfi 指令在当前 region 中的位置（虽然 ubtb 本身不是 region-btb，但为了避免额外的计算逻辑，仍然使用和 mbtb / abtb 语义相同的 position 字段）
- `slot1/2.attribute`：分支属性，见 [@sec:bpu-constants-branchattribute] [BranchAttribute](index.md#sec:bpu-constants-branchattribute) 小节
- `slot1/2.target`：跳转目标低位[^target-fix]
- `slot1/2.targetCarry`：跳转目标低位进位/借位标记，仅当 `EnableTargetFix` 为 true 时存在[^target-fix]
- `slot1.isStaticTarget`：跳转目标稳定（是固定目标的分支/直接跳转指令，或者自从训练以来没有见过不同目标的简介跳转指令），用于判断能否进行 2-taken 训练
- `slot2.valid`：2-taken 的第二条分支是否有效
- `slot2.taken`：2-taken 的第二条分支是否跳转

[^target-fix]: 请参考 [@sec:bpu-target-fix] [目标地址修正](#sec:bpu-target-fix) 一节中关于目标地址计算的说明。

## 替换策略 {#sec:bpu-ubtb-replacement}

ubtb 采用 useful 计数器和替换算法结合的替换策略。每个表项有一个 useful 计数器，表示该表项的“有用”程度，计数器值越大表示越有用。替换时，首先选择 useful 计数器值为 0 的表项，如果没有，则按替换算法（默认 plru）选择一个表项进行替换。

在训练时，useful 计数器的更新策略如下：

- 未命中（分配新项）时，初始化为最大值
- 预测错误（分支属性错、位置错、目标错、实际不跳转）时
  - 若已经减至 0，视为未命中，分配新项并初始化为最大值
  - 否则，减 1
- 预测正确且跳转时，增 1

在此策略下，useful 计数器实际上同时承担了 valid 标志位和 taken 计数器的功能。当 useful 为 0 时，表项无效，预测时不命中（预测为跳转），训练时优先被替换；当 useful 大于 0 时，表项有效，预测时做 always-taken 预测。可以理解为 `valid = taken = (useful > 0)`。

## 2-taken {#sec:bpu-ubtb-2-taken}

TODO：当前版本 RTL 暂未实现，正在方案讨论中
