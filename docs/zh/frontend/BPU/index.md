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
