# MCfgGen

- 版本：V2R2A
- 状态：OK
- 日期：2026/10/13
- commit：[XSAI e8fb1a14](https://github.com/OpenXiangShan/XSAI/tree/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f)

## 术语说明

Table: 术语说明

| 名称 | 描述 |
| ---- | ---- |
| mcfg | 与一个矩阵寄存器对应的数据类型配置 |
| mcfgArch | 已提交的矩阵类型配置表 |
| mcfgSpec | 当前译码使用的矩阵类型配置表 |
| MCfgBuffer | 从 ROB commit、walk 信息生成配置更新的模块 |

## 设计规格

- 维护 8 个 XLEN 位配置项，分别对应 4 个 tile register 和 4 个 accumulator register。
- 支持 `msetcfg` 写入、`mgetcfg` 原样读回。
- 配置的低 8 位决定数据类型，高位保留并透传。
- 发生重定向时，从体系结构配置和 ROB walk 信息恢复当前配置。

## 功能

MCfgGen 位于 DecodeStage 内，输出当前译码需要的 mcfg 表。`msetcfg` 的值来自整数寄存器，译码阶段不能直接获得新值。因此，`msetcfg` 阻塞后继指令进入 ROB，并在提交后冲刷流水线；MCfgGen 接收提交值，再为重新译码的后继指令提供新配置。

普通矩阵访存指令读取其矩阵寄存器对应的一个配置项。`mmacc` 读取 ms1、ms2、md 对应的三个配置项。读取值随指令进入后端，执行阶段使用该快照进行类型检查和 AMU 控制信息生成。

## 配置格式

Table: mcfg 格式

| 位域 | 名称 | 描述 |
| ---- | ---- | ---- |
| [3:0] | type_code | 数据类型编码 |
| [7:4] | table_sel | 类型表选择，当前仅支持 0 |
| [XLEN-1:8] | payload | 原样保存与读回，当前执行语义不解释 |

Table: 当前合法的数据类型编码

| type_code | 类型 | type_code | 类型 |
| --------- | ---- | --------- | ---- |
| 0 | int4 | 7 | fp8e5m2 |
| 1 | uint4 | 8 | fp8e4m3 |
| 2 | int8 | 9 | fp16 |
| 3 | uint8 | 10 | bf16 |
| 4 | int32 | 11 | tf32 |
| 5 | nvfp4 | 12 | fp32 |
| 6 | mxfp4 | 13–15 | 未实现 |

`Mcfg` 功能单元对不受支持的 `msetcfg` 产生非法指令异常。类型编码合法与矩阵乘法组合受支持是两个条件，后者还由 `MatrixIsaParams` 控制。默认 `DefaultMatrixConfig` 启用 int8/uint8 到 int32、同类型 FP8 到 FP32、BF16 到 FP32。

## 状态更新

mcfgArch、mcfgSpec 均复位为 0。正常提交时，MCfgBuffer 从 ROB 提交项中筛出合法的 `msetcfg`，更新选择的表项。同拍多个更新按提交顺序处理，较后的更新覆盖同一表项的较早更新。

进入 walk 时，MCfgGen 以包含当拍提交结果的 mcfgArch 为恢复起点，再按 walk 信息重建 mcfgSpec。walk 更新优先于普通 mcfgSpec 提交更新。恢复期间 DecodeStage 暂停接收与输出指令，避免使用尚未恢复完成的类型配置。

MCfgBuffer 只整理 ROB 中的配置更新信息，不维护另一套独立配置表。未受支持的 `msetcfg` 不进入 commit/walk 配置更新。

## 接口列表

Table: MCfgGen 接口

| 接口 | 方向 | 描述 |
| ---- | ---- | ---- |
| commitMcfg | 输入 | CommitWidth 路配置提交信息 |
| walkToArchMcfg | 输入 | 从体系结构配置开始恢复 |
| walkMcfg | 输入 | CommitWidth 路配置 walk 信息 |
| mcfg | 输出 | 当前译码使用的配置表 |

实现见 [MCfgGen.scala](https://github.com/OpenXiangShan/XSAI/blob/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f/src/main/scala/xiangshan/backend/decode/MCfgGen.scala) 和 [MCfgBuffer.scala](https://github.com/OpenXiangShan/XSAI/blob/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f/src/main/scala/xiangshan/backend/rob/MCfgBuffer.scala)。
