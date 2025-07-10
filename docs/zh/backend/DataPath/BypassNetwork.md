# BypassNetwork

### - 版本：V2R2

- 状态：OK
- 日期：2025/02/27
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## 术语说明

Table: 术语说明

| 全称          | 描述     |
| ------------- | -------- |
| BypassNetWork | 旁路网络 |

## 子模块列表

Table: 子模块列表

| 子模块        | 描述           |
| ------------- | -------------- |
| ImmExtracter  | 立即数生成模块 |
| UIntExtracter | UInt解码模块   |

## 功能

BypassNetWork 位于 DataPath，Exu 流水级之间，主要用于为功能单元提供源操作数。目前27个功能单元，总计71个源操作数

首先对于可以前递/旁路/两级旁路的源操作数：

根据 Datapath 输入的 ExuSource 信息，由 UintExtract 提取出独热码，选取可能的来自功能单元的旁路数据，具体现有的唤醒配置见下表。

Table: 现有唤醒配置1

| Source | Sink                                                                                     |
| ------ | ---------------------------------------------------------------------------------------- |
| ALU0   | ALU0, BJU0, ALU1, BJU1, ALU2, BJU2, ALU3, BJU3, LDU0, LDU1, LDU2, STA0, STA1, STD0, STD1 |
| ALU1   | ALU0, BJU0, ALU1, BJU1, ALU2, BJU2, ALU3, BJU3, LDU0, LDU1, LDU2, STA0, STA1, STD0, STD1 |
| ALU2   | ALU0, BJU0, ALU1, BJU1, ALU2, BJU2, ALU3, BJU3, LDU0, LDU1, LDU2, STA0, STA1, STD0, STD1 |
| ALU3   | ALU0, BJU0, ALU1, BJU1, ALU2, BJU2, ALU3, BJU3, LDU0, LDU1, LDU2, STA0, STA1, STD0, STD1 |
| LDU0   | ALU0, BJU0, ALU1, BJU1, ALU2, BJU2, ALU3, BJU3, LDU0, LDU1, LDU2, STA0, STA1, STD0, STD1 |
| LDU1   | ALU0, BJU0, ALU1, BJU1, ALU2, BJU2, ALU3, BJU3, LDU0, LDU1, LDU2, STA0, STA1, STD0, STD1 |
| LDU2   | ALU0, BJU0, ALU1, BJU1, ALU2, BJU2, ALU3, BJU3, LDU0, LDU1, LDU2, STA0, STA1, STD0, STD1 |

Table: 现有唤醒配置2

| Source | Sink                         |
| ------ | ---------------------------- |
| FEX0   | FEX0, FEX1, FEX2, FEX3, FEX4 |
| FEX2   | FEX0, FEX1, FEX2, FEX3, FEX4 |
| FEX4   | FEX0, FEX1, FEX2, FEX3, FEX4 |

    其中作用于向量浮点以及访存单元之间的二级旁路，目前暂时取消。

其次对于源操作数是立即数部分，根据来自 datapath 的立即数信息，由 ImmExtracto r组装生成64bit立即数。

最后根据datapath中 data source 信息，从所有可能的数据来源（前递，旁路，二级旁路，v0，寄存器堆，立即数，regcache，0号寄存器）中选取源操作数，传入功能单元。

另外，对于跳转功能单元，部分 pcoffset 逻辑也放在旁路网络中，立即数信息同样由 ImmExtractor 组装生成。

具体设计见[@fig:BypassNetwork]：

![BypassNetwork](./figure/BypassNetwork.svg){#fig:BypassNetwork}

## 模块设计

### 二级模块 ImmExtracter

该模块负责生成 64bit 立即数，首先根据下述映射，将立即数映射为 32bit 形式，之后再对结果进行符号拓展成 64bit 立即数。

Table: 立即数映射

|    SelImm    | ImmUnion | Immlen | extracter                       |
| :----------: | :------: | :----: | ------------------------------- |
|    IMM_I    |    I    |   12   | SignExt(imm(len - 1, 0), 32)    |
|    IMM_S    |    S    |   12   | SignExt(imm, 32)                |
|    IMM_SB    |    B    |   12   | SignExt(Cat(imm, 0.U(1.W)), 32) |
|    IMM_U    |    U    |   20   | Cat(imm(len - 1, 0), 0.U(12.W)) |
|    IMM_UJ    |    J    |   20   | SignExt(Cat(imm, 0.U(1.W)), 32) |
|      Z      |    Z    |   22   | imm                             |
|    IMM_B6    |    B6    |   6   | ZeroExt(imm, 32)                |
| IMM_VSETVLI | VSETVLI |   11   | SignExt(imm, 32)                |
| IMM_VSETIVLI | VSETIVLI |   15   | SignExt(imm, 32)                |
|  IMM_OPIVIS  |  OPIVIS  |   5   | SignExt(imm, 32)                |
|  IMM_OPIVIU  |  OPIVIU  |   5   | ZeroExt(imm, 32)                |
|  IMM_LUI32  |  LUI32  |   32   | imm(31, 0)                      |
|  IMM_VRORVI  |  VRORVI  |   6   | ZeroExt(imm, 32)                |

### 二级模块 UIntExtracter

该模块服务于 toExuOH 功能：负责将压缩成UInt的源操作数旁路来源的 exuidx 解码为one-hot形式。

记录源操作数旁路来源的 exusource 中的功能单元标号在发射阶段经历了两次压缩：

* 首先将标志27个功能单元的独热码，根据旁路唤醒可能的来源，压缩为7/3个功能单元的独热码
* 其次将7/3个功能单元的独热码，压缩为UInt形式，共3/2bit UInt

因此在旁路网络中需要对来自 DataPath 的压缩后 exusource 进行两次解压缩：

* 首先将 3/2 bit的 exusource 解压为独热码
* 其次将 压缩后的独热码，根据当前功能单元可能的唤醒来源，解压为标志27个功能单元的独热码

对于第一步解压操作，在 toExuOH 中只需要简单通过移位（唤醒源与源操作数是一一对应的）完成

UIntExtracter 负责第二步解压操作，完成下述映射：

Table: 唤醒源独热码映射(1)

| EncodedExuOH | ExtractExuOH |
| :----------: | :----------: |
|   ALU0(0)   |      0      |
|   ALU1(1)   |      2      |
|   ALU2(2)   |      4      |
|   ALU3(3)   |      6      |
|   LDU0(4)   |      20      |
|   LDU1(5)   |      21      |
|   LDU2(6)   |      22      |

Table: 唤醒源独热码映射(1)

| EncodedExuOH | ExtractExuOH |
| :----------: | :----------: |
|   FEX0(0)   |      8      |
|   FEX1(1)   |      10      |
|   FEX2(2)   |      12      |
