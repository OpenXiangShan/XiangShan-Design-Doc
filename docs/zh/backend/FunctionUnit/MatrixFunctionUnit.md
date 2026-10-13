# MatrixFunctionUnit

- 版本：V2R2A
- 状态：OK
- 日期：2026/10/13
- commit：[XSAI e8fb1a14](https://github.com/OpenXiangShan/XSAI/tree/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f)

## 设计规格

矩阵功能单元负责规模状态读写、数据类型检查以及 AMU 控制请求生成。矩阵数据存储和乘法累加在 CUTE 中进行，控制核不通过 mx 寄存器堆搬运矩阵数据。

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

上述延迟是控制核 FU 的参数，Mma 的 0 延迟不表示 CUTE 在 0 个周期完成矩阵运算。Mma、Marith、Mrelease 和 MLSU 生成的请求经 [AmuCtrlBuffer](../CtrlBlock/AMUCtrlBuffer.md) 等待 ROB 提交后输出。

## 规模配置

`msettilem/n/k` 读取整数寄存器，立即数形式读取 instr[24:15] 的 10 位无符号数，原样写入对应 mx 物理项。规模设置单元不在写入时限制矩阵规模；使用规模的 Mma、MLSU 进行操作相关检查。

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

`ROWNUM=TLEN/TRLEN`，`ARLEN=ROWNUM×MELEN`。当前比较未额外禁止 0 尺寸。非法条件取或后写入 exceptionVec.illegalInstr。

Mma 不检查 `ms1 != ms2`。CUTE 的共享 AB 读端口不支持 ADC、BDC 同时读取同一矩阵寄存器，相关冲突会触发断言；软件需要选择不同的 AB 源矩阵号。控制核的合法性检查不能代替 [矩阵寄存器的物理端口限制](../../cute/MatrixReg.md)。

控制信息包含 md、ms1、ms2、M/N/K、三个元素类型、isfp、舍入模式和饱和使能。目的类型为浮点时使用 mfrm，否则使用 mxrm；sat 来自 msaten。当前 CUTE 不消费 rm、sat 字段，不能将其打包等同于已实现可编程舍入和饱和，详见 [计算数据通路](../../cute/Compute.md)。Mma 不在本单元内读写 CUTE 矩阵数据。

## Marith

当前有效译码只有 `mzero`，控制信息包含目的矩阵号和 opType。Mzero 不读取 mx 规模，不修改 mcfg。其 wrapper 当前没有 Mma 那组寄存器类别和类型组合检查。

## AMU 控制接口

Table: AmuCtrlIO

| 字段 | 位宽 | 描述 |
| ---- | ---- | ---- |
| op | 2 | 0=MMA，1=MLS，2=release，3=arith |
| data | 150 | 按 op 解释的控制参数，不足部分补零 |
| pc、coreid | 配置相关 | 仅开启 DiffTest 时存在 |

MMA 的有效 payload 为 53 位（规模字段均为 9 位时）；MLS 为 126 位；arith 为 13 位。正向 release 携带 log2Ceil(MsyncRegs) 位索引，反向完成接口携带 MsyncRegs 位向量，两者格式不同。

矩阵访存的地址翻译与重放见访存模块，实际数据搬运、运算调度和完成返回见 CUTE 章节。矩阵同步指令的 Fence 实现见 [IntFunctionUnit](./IntFunctionUnit.md#sec:matrix-sync)。

实现见 [Mma.scala](https://github.com/OpenXiangShan/XSAI/blob/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f/src/main/scala/xiangshan/backend/fu/wrapper/Mma.scala) 和 [矩阵接口 Bundle](https://github.com/OpenXiangShan/XSAI/blob/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f/src/main/scala/xiangshan/backend/fu/matrix/Bundles.scala)。
