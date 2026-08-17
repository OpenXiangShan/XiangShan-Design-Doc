# XiangShan Bpu 设计文档 {#sec:bpu-index}

- 版本：V3
- 状态：draft
- 日期：2026/04/22
- commit：TODO

## 术语说明 {#sec:bpu-glossary}

| 缩写 | 全称 | 描述 |
| --- | --------- | ------------ |
| cfi | Control Flow Instruction | 控制流指令，即分支（e.g. `bne`）和跳转指令（e.g. `j`） |
| BTB | Branch Target Buffer | 分支目标缓冲器，存储分支指令的目标地址和一些元数据的缓存结构 |

## 子模块列表 {#sec:bpu-submodules}

| 子模块 | 描述 |
| --- | --------- |
| [FallThrough](fallThrough.md) | S1，总是预测不跳转，当所有其他预测器都未命中或预测不跳转时提供预测结果。 |
| [Ubtb](ubtb.md) | Micro Btb，S1，寄存器实现的小 BTB，提供分支信息。 |
| [Abtb](abtb.md) | Ahead Btb，S1，使用 ahead-pipeline 技术实现的中等大小的 BTB，提供分支信息。 |
| [Utage](utage.md) | Micro Tage，S1，小 Tage，提供方向预测。 |
| [Mbtb](mbtb.md) | Main Btb，S3，主 BTB，提供更准确的分支信息。 |
| [Tage](tage.md) | TAgged GEometic History Length predictor，S3，提供更准确的方向预测 |
| [Sc](sc.md) | Statistical Corrector，S3，使用统计模式修正 Tage 的预测。 |
| [Ittage](ittage.md) | Indirect Target Tage，S3，间接跳转指令预测器，提供间接跳转目标预测。 |
| [Ras](ras.md) | Return Address Stack，S3，返回地址预测器，提供返回地址预测。 |
| [历史信息寄存器](history.md) | 存储分支历史信息的寄存器，供 Tage 等预测器索引存储结构使用。 |
| [饱和计数器](saturateCounter.md) | 饱和计数器工具类，供各预测器使用。 |

## 设计规格 {#sec:bpu-design-spec}

## 参数列表 {#sec:bpu-params}

## 功能概述 {#sec:bpu-functional-overview}

## 功能详述 {#sec:bpu-functional-details}

### S1 预测器组的快速训练 {#sec:bpu-s1-fast-train}

在 overriding 架构下，S3 预测器组会检查并纠正 S1 预测器组的结果。这同时意味着 S1 预测器组既可以像 S3 预测器组一样由后端执行单元进行训练，也可以由 S3 预测器组进行快速训练（类似于将它们作为 S3 精确预测器的缓存）。前者更加准确，后者更加及时，反应到总体 IPC 上可能会有不同的表现。

具体到每个预测器上：

- ubtb：使用参数 `EnableFastTrain` 控制是否使用快速训练，前期评估表明快速训练有一定的性能提升，故其默认值为 true。
- abtb：由于 ahead pipeline 的设计，abtb 需要更多流水线上的信息才能进行训练，因此无法使用后端训练，仅能快速训练。
- utage：TODO

### 目标地址修正 {#sec:bpu-target-fix}

为了节约存储面积，各 btb 结构不会保存完整的 50bit（Sv48x4）目标虚地址，而是仅保存低位（请参考各 btb 参数列表）。根据指令集手册，有：

- branch：跳转目标为 pc + offset，其中 offset 为 12 bit 立即数，因此仅需保存目标地址的低 14 bit（offset 需在立即数低位补一个 0，还需保存高位的进位/借位）
- jal：跳转目标为 pc + offset，其中 offset 为 20 bit 立即数，因此仅需保存目标地址的低 22 bit（同上）
- jalr：跳转目标为寄存器值，仅存低位可能误预测，但为了平衡硬件开销和性能收益，我们接受这种误预测

在预测时，我们直接将“取指块的起始地址的高位”与“保存的目标地址的低位”拼接即可在多数情况下得到正确的目标地址，但区域边界上存在进位/借位导致的例外。例如，仅存低 12 bit，若取指块起始地址 `startPc = 0x12345ffe`，`offset = +0x20`，则目标地址为 `0x1234601e`，但我们保存的 12bit 低位为 `0x01e`，简单拼接得到的目标地址为 `0x1234501e`。

为了解决这个问题，我们引入 2bit 的 `targetCarry` 标志，来记录是否存在进位/借位，并在预测时对拼接结果进行修正。这一功能可以通过 btb 的 `EnableTargetFix` 参数进行开关。如上对各指令类型的跳转范围分析，需要进行修正的情况理论上很少，并且原则上可以通过编译器的指令排布优化来进一步规避，因此这一额外的 2bit/entry 的开销可能是不值得的，在我们的前期评估中也没有观察到明显的性能提升，因此该功能的默认值为 false。

另请参考 [@sec:bpu-constants-targetcarry] [TargetCarry](index.md#sec:bpu-constants-targetcarry) 小节中关于 targetCarry 标志值的定义。

### 寄存器配置 {#sec:bpu-csr}

Table: Bpu 相关 CSR 列表 {#tbl:bpu-csr}

+---------+-------+----------+------+----------------------------------------------------------------------+
| 寄存器  | 地址  | 复位值   | 属性 | 描述                                                                 |
+=========+=======+==========+======+======================================================================+
| sbpctl  | 0x5C0 | 64'd0    | RW   | bit0: ubtb 使能信号                                                  |
|         |       |          |      |                                                                      |
|         |       |          |      | bit1: abtb 使能信号                                                  |
|         |       |          |      |                                                                      |
|         |       |          |      | bit2: mbtb 使能信号                                                  |
|         |       |          |      |                                                                      |
|         |       |          |      | bit3: Tage 使能信号                                                  |
|         |       |          |      |                                                                      |
|         |       |          |      | bit4: Sc 使能信号                                                    |
|         |       |          |      |                                                                      |
|         |       |          |      | bit5: Ittage 使能信号                                                |
|         |       |          |      |                                                                      |
|         |       |          |      | bit6: Ras 使能信号                                                   |
|         |       |          |      |                                                                      |
|         |       |          |      | 需要注意：虽然这个寄存器可以任意配置，但预测器间存在依赖关系，例如： |
|         |       |          |      |                                                                      |
|         |       |          |      | - Tage、Sc、Ittage、Ras 依赖 mbtb；                                  |
|         |       |          |      |                                                                      |
|         |       |          |      | - Sc 依赖 Tage。                                                     |
|         |       |          |      |                                                                      |
|         |       |          |      | 当预测器依赖的预测器被禁用时，其自身也会被禁用，                     |
|         |       |          |      |                                                                      |
|         |       |          |      | 这**不会**反映在该 CSR 的值上。                                      |
+---------+-------+----------+------+----------------------------------------------------------------------+

注：RO——只读寄存器；RW——可读可写寄存器。

### 常量类型 {#sec:bpu-constants}

#### BranchAttribute {#sec:bpu-constants-branchattribute}

用于表示分支属性，具有以下两个域：

- `.branchType`：分支类型
    - `0`：非分支指令/表项无效
    - `1`：条件分支（e.g. `bne`）
    - `2`：直接跳转（e.g. `jal`）
    - `3`：间接跳转（e.g. `jalr`）
- `.rasAction`：RAS 动作，另请参考 RISC-V 指令集手册 Return-address stack prediction hints
    - `0`：无动作（非分支指令、表项无效、条件分支）
    - `1`：pop（return，e.g. `jalr zero, offset(ra)`）
    - `2`：push（call，e.g. `jal ra, offset`）
    - `3`：pop and push（return and call，e.g. `jalr ra, offset(ra)`）

#### TargetCarry {#sec:bpu-constants-targetcarry}

用于表示跳转目标地址的低位进位/借位标记：

- `0`：fit，即无进位/借位，`target = Cat(targetUpper, targetLower)`
- `1`：overflow，需要进位，i.e. `target = Cat(targetUpper + 1, targetLower)`
- `2`：underflow，需要借位，i.e. `target = Cat(targetUpper - 1, targetLower)`

另请参考 [@sec:bpu-target-fix] [目标地址修正](#sec:bpu-target-fix) 一节中关于该标记的使用说明。

## 参考文件 {#sec:bpu-references}

1. Reinman G, Austin T, Calder B. A scalable front-end architecture for fast instruction delivery[J]. ACM SIGARCH Computer Architecture News, 1999, 27(2): 234-245.
2. Perais A, Sheikh R, Yen L, et al. Elastic instruction fetching[C]//2019 IEEE International Symposium on High Performance Computer Architecture (HPCA). IEEE, 2019: 478-490.
3. Software Optimization Guide for AMD Family 19h Processors (PUB), Chap. 2.8.1.5, <https://www.amd.com/system/files/TechDocs/56665.zip>
4. Seznec A, Michaud P. A case for (partially) TAgged GEometric history length branch prediction[J]. The Journal of Instruction-Level Parallelism, 2006, 8: 23.
5. Seznec A. A 256 kbits l-tage branch predictor[J]. Journal of Instruction-Level Parallelism (JILP) Special Issue: The Second Championship Branch Prediction Competition (CBP-2), 2007, 9: 1-6.
6. Seznec A. A new case for the tage branch predictor[C]//Proceedings of the 44th Annual IEEE/ACM International Symposium on Microarchitecture. 2011: 117-127.
7. Seznec A. The O-GEHL branch predictor[J]. The 1st JILP Championship Branch Prediction Competition (CBP-1), 2004.
8. Jiménez D A, Lin C. Dynamic branch prediction with perceptrons[C]//Proceedings HPCA Seventh International Symposium on High-Performance Computer Architecture. IEEE, 2001: 197-206.
9. Seznec A. A 64-Kbytes ITTAGE indirect branch predictor[C]//JWAC-2: Championship Branch Prediction. 2011.
