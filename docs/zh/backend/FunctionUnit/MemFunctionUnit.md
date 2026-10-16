# MemFunctionUnit

- 版本：V2R2A
- 状态：OK
- 日期：2026/10/13
- commit：[XSAI ee268923](https://github.com/OpenXiangShan/XSAI/tree/ee268923b7175d79a9d0183a0181a684ccec9487)

标量访存功能单元包括 ldu, stu, mou；XSAI 另在 Mem 调度与执行通路增加 MLSU0，负责矩阵访存控制请求的地址和参数检查。每个功能单元支持的指令如下表：

## ldu

table: ldu fu 支持的指令

| 功能单元 | 支持指令 | 扩展 | 描述   |
| -------- | -------- | ---- | ------ |
| ldu      | FLD      | D    | scalar |
| ldu      | FLW      | F    | scalar |
| ldu      | LB       | I    | scalar |
| ldu      | LBU      | I    | scalar |
| ldu      | LD       | D    | scalar |
| ldu      | LH       | I    | scalar |
| ldu      | LHU      | I    | scalar |
| ldu      | LW       | I    | scalar |
| ldu      | LWU      | I    | scalar |
| ldu      | HLV.B    |      | scalar |
| ldu      | HLV.BU   |      | scalar |
| ldu      | HLV.D    |      | scalar |
| ldu      | HLV.H    |      | scalar |
| ldu      | HLV.HU   |      | scalar |
| ldu      | HLV.W    |      | scalar |
| ldu      | HLV.WU   |      | scalar |
| ldu      | HLVX.HU  |      | scalar |
| ldu      | HLVX.WU  |      | scalar |

## stu

table: sdu fu 支持的指令

| 功能单元 | 支持指令  | 扩展 | 描述   |
| -------- | --------- | ---- | ------ |
| stu      | SB        | I    | scalar |
| stu      | SD        | I    | scalar |
| stu      | SH        | I    | scalar |
| stu      | SW        | I    | scalar |
| stu      | FSD       | D    | scalar |
| stu      | FSW       | F    | scalar |
| stu      | FSH       | Zfh  | scalar |
| stu      | CBO_CLEAN | CBO  | scalar |
| stu      | CBO_FLUSH | CBO  | scalar |
| stu      | CBO_INVAL | CBO  | scalar |
| stu      | CBO_ZERO  | CBO  | scalar |
| stu      | HSV.B     |      | scalar |
| stu      | HSV.D     |      | scalar |
| stu      | HSV.H     |      | scalar |
| stu      | HSV.W     |      | scalar |

## mou

table: mou fu 支持的指令

| 功能单元 | 支持指令  | 扩展 | 描述   |
| -------- | --------- | ---- | ------ |
| mou      | AMOADD_D  | A    | scalar |
| mou      | AMOADD_W  | A    | scalar |
| mou      | AMOAND_D  | A    | scalar |
| mou      | AMOAND_W  | A    | scalar |
| mou      | AMOMAX_D  | A    | scalar |
| mou      | AMOMAX_W  | A    | scalar |
| mou      | AMOMAXU_D | A    | scalar |
| mou      | AMOMAXU_W | A    | scalar |
| mou      | AMOMIN_D  | A    | scalar |
| mou      | AMOMIN_W  | A    | scalar |
| mou      | AMOMINU_D | A    | scalar |
| mou      | AMOMINU_W | A    | scalar |
| mou      | AMOOR_D   | A    | scalar |
| mou      | AMOOR_W   | A    | scalar |
| mou      | AMOSWAP_D | A    | scalar |
| mou      | AMOSWAP_W | A    | scalar |
| mou      | AMOXOR_D  | A    | scalar |
| mou      | AMOXOR_W  | A    | scalar |
| mou      | LR_D      | A    | scalar |
| mou      | LR_W      | A    | scalar |
| mou      | SC_D      | A    | scalar |
| mou      | SC_W      | A    | scalar |

## MLSU

MLSU0 接收矩阵访存指令，读取整数基址、整数步长与 mx 规模状态，并携带译码阶段取得的 mcfg 快照。MlsUnit 按 type_code 映射元素位宽，接入 DTLB、PMP、矩阵访存队列和重发通路，检查起始基址的翻译、访问权限、矩阵寄存器类别及规模，再向后端写回异常信息或 AMU 访存控制参数。该检查路径未调用 mcfg 的 `isSupported`。

Table: MLSU 支持的指令

| 类别 | 指令 | 功能 |
| ---- | ---- | ---- |
| 普通装载 | mla、mlb、mlc | 装载 A、B 或累加器 C |
| 转置装载 | mla.t、mlb.t、mlc.t | 装载时转置 |
| 普通存储 | msa、msb、msc | 存储 A、B 或累加器 C |
| 转置存储 | msa.t、msb.t、msc.t | 存储时转置 |
| 整寄存器装载 | mla.whole、mlb.whole、mlc.whole | 装载完整 tile 或累加器寄存器 |
| 整寄存器存储 | msc.whole | 存储完整累加器寄存器 |

whole 形式在 MlsUnit 中按寄存器物理几何确定规模和步长。有效译码中的 whole Store 为 msc.whole，msa.whole 和 msb.whole 未接入译码表。

上述指令均可在控制核中译码并生成访存描述符。CUTE 的 Store 描述符统一送往 CML，从 C 寄存器读取待存数据；msa / msb 及其转置形式尚无 A / B 数据存储通路。详细的数据通路见 [MLSU](../../memblock/LSU/MLSU.md)。

MLSU 的控制结果写入 [AmuCtrlBuffer](../CtrlBlock/AMUCtrlBuffer.md)，待 ROB 提交后送往 CUTE 执行数据搬运。矩阵访存的队列、跨页检查和翻译路径见 [MLSU](../../memblock/LSU/MLSU.md)。

实现见 [MlsUnit.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/mem/pipeline/MlsUnit.scala)。
