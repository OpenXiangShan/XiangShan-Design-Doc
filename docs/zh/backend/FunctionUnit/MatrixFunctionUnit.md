# MatrixFunctionUnit

- 版本：V2R2A
- 状态：OK
- 日期：2026/10/13
- commit：[XSAI e8fb1a14](https://github.com/OpenXiangShan/XSAI/tree/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f)

## 设计规格

矩阵功能单元负责规模状态读写、数据类型检查以及 AMU 控制请求生成。mx 寄存器堆保存矩阵规模，CUTE 保存矩阵数据并执行乘法累加。

Table: 矩阵功能单元

| 功能单元 | 所在执行资源 | 功能 | FU 延迟配置 |
| -------- | ------------ | ---- | ----------- |
| MSetMtilexRiWmf | Int MSET0 | 整数或立即数写 mtilem/n/k | CertainLatency(0) |
| MSetMtilexRmfWmf | Mf MSET1 | 读 mtilem/n/k 写整数 rd | CertainLatency(0) |
| Mcfg | Int BJU3 | msetcfg、mgetcfg | CertainLatency(0) |
| Mma | Mf MEX0 | mmacc 参数检查与请求生成 | CertainLatency(0) |
| Marith | Mf MEX1 | mzero 请求生成 | CertainLatency(0) |
| Mrelease | Int MRELEASE | release 请求生成 | CertainLatency(0) |
| MLSU | Mem MLSU0 | 地址、权限与矩阵访存参数检查 | UncertainLatency(3) |

FU 延迟配置用于控制核的调度与写回。Mma、Marith、Mrelease 和 MLSU 生成的请求经 [AmuCtrlBuffer](../CtrlBlock/AMUCtrlBuffer.md) 等待 ROB 提交后输出，随后由 CUTE 执行对应任务。

## 规模配置

`msettilem/n/k` 读取整数寄存器，立即数形式读取 instr[24:15] 的 10 位无符号数，原样写入对应 mx 物理项。Mma、MLSU 在使用规模时检查相应操作的规模上限。

`csrr mtilem/n/k` 在译码时转为 MSetMtilexRmfWmf，读取对应 mx 项并写整数目的寄存器。该读写通路采用普通寄存器依赖关系，支持规模设置与其消费者的乱序调度。

## 类型配置

`msetcfg` 检查 type_code 和 table_sel，非法值产生 illegalInstr；合法值写回 ROB 后通过 MCfgBuffer 提交到 [MCfgGen](../CtrlBlock/MCfgGen.md)。`mgetcfg` 返回译码阶段快照的原始值。高位 payload 原样保留。

## Mma

Mma 读取 mx 中的 M、N、K 和指令携带的三个 mcfg 快照，检查矩阵寄存器类别、类型组合与规模，然后构造 AmuMmaIO。

Table: Mma 合法性检查

| 检查 | 条件 |
| ---- | ---- |
| 源矩阵号 | ms1、ms2 的 3 位 selector 为 0–3 |
| 目的矩阵号 | md 的 3 位 selector 为 4–7 |
| 配置项 | 三个 mcfg 项均为当前支持的编码 |
| 类型组合 | MatrixIsaParams 开启对应的 A/B/C 组合 |
| M | M <= ROWNUM |
| N | N <= ROWNUM，且 N <= ARLEN / C 元素位宽 |
| K | K <= TRLEN / A 元素位宽 |

`ROWNUM=TLEN/TRLEN`，`ARLEN=ROWNUM×MELEN`。规模检查比较上限，0 尺寸也满足上述条件。非法条件取或后写入 exceptionVec.illegalInstr。

CUTE 的 ADC、BDC 共享 AB 读端口，两个源必须选择不同的矩阵寄存器。Mma 的非法指令检查未包含 `ms1 != ms2` 约束；两路同时读取同一寄存器时，CUTE 触发端口冲突断言。端口组织见 [矩阵寄存器](../../cute/MatrixReg.md)。

AmuMmaIO 包含 md、ms1、ms2、M/N/K、三个元素类型、isfp、rm 和 sat。目的类型为浮点时，rm 取 mfrm，否则取 mxrm；sat 取 msaten。CUTE 的计算通路尚未使用 rm、sat 字段，实际计算行为见 [计算数据通路](../../cute/Compute.md)。

## Marith

Marith 的有效译码为 `mzero`，控制信息包含目的矩阵号和 opType。指令无 mx 规模源，mcfg 保持原值。Marith wrapper 直接生成清零请求，未设置寄存器类别和类型组合检查。

## AMU 控制接口

Table: AmuCtrlIO

| 字段 | 位宽 | 描述 |
| ---- | ---- | ---- |
| op | 2 | 0=MMA，1=MLS，2=release，3=arith |
| data | 150 | 按 op 解释的控制参数，不足部分补零 |
| pc、coreid | 配置相关 | 仅开启 DiffTest 时存在 |

规模字段均为 9 位时，MMA 的有效 payload 为 53 位，MLS 为 126 位，arith 为 13 位。正向 release 请求携带 log2Ceil(MsyncRegs) 位索引，反向完成接口携带 MsyncRegs 位事件向量。

矩阵访存的地址翻译与重放见 [MLSU](../../memblock/LSU/MLSU.md)，数据搬运、任务调度与完成返回由 CUTE 实现。矩阵同步指令的 Fence 实现见 [IntFunctionUnit](./IntFunctionUnit.md#sec:matrix-sync)。

实现见 [Mma.scala](https://github.com/OpenXiangShan/XSAI/blob/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f/src/main/scala/xiangshan/backend/fu/wrapper/Mma.scala) 和 [矩阵接口 Bundle](https://github.com/OpenXiangShan/XSAI/blob/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f/src/main/scala/xiangshan/backend/fu/matrix/Bundles.scala)。
