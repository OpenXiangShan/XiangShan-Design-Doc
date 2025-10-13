# 昆明湖 IFU 模块文档

- 版本：V3
- 状态：draft
- 日期：2025/10/08
- commit：[7d889d887f665295eec9cdb987e037e008f875a6](https://github.com/OpenXiangShan/XiangShan/tree/7d889d887f665295eec9cdb987e037e008f875a6)

## 术语说明

| 缩写         | 全称                                     | 描述                                       |
| ------------ | ---------------------------------------- | ------------------------------------------ |
| CRU          | Clock Reset Unit                         | 时钟复位单元                               |
| RVC          | RISC-V Compressed Instructions           | RISC-V 手册"C"扩展规定的 16 位长度压缩指令  |
| RVI          | RISC-V Integer Instructions              | RISC-V 手册规定的 32 位基本整型指令         |
| IFU          | Instruction Fetch Unit                   | 取指令单元                                 |
| FTQ          | Fetch Target Queue                       | 取指目标队列                               |
| PreDecode    | Predecoder Module                        | 预译码器                                   |
| PredChecker  | Prediction Check Module                  | 分支预测结果检查器                         |
| ICache       | L1 Instruction Cache                     | 一级指令缓存                               |
| IBuffer      | Instruction Buffer                       | 指令缓冲                                   |
| CFI          | Control Flow Instruction                 | 控制流指令                                 |
| PC           | Program Counter                          | 程序计数器                                 |
| InstrUncache | Instruction Ucache Module                | 指令 uncache 取指处理单元                  |

## 子模块列表

| 子模块                       | 描述                   |
| --------------------------- | ---------------------- |
| [PreDecoder]                | 预译码模块               |
| [IfuUncacheUnit]            | uncahce 指令取指处理单元 |
| [PredChecker]               | 预译码检查模块，结合预译码信息，及早纠正部分指令流 |
| [InstrBoundary]             | 指令定界模块，负责分析指令块数据中每条指令的位置   |
| [RvcExpander]               | C指令扩展，负责将16位的指令扩展为32位指令         |

## 功能描述
IFU（Instruction Fetch Unit）是前端流水线中负责组织供指数据的重要模块，位于分支预测和指令缓存之后。在预测路径和 ICache 命中结果确定后，IFU 需要完成指令对齐、打包、简单的预译码等操作，并将处理好的指令送入后续模块（如 IBuffer）。

由于 IFU 处于供指链路的下游，其处理延迟将影响整个前端的取指响应能力，尤其在发生重定向（如分支预测错误）时，IFU 的执行周期会成为恢复路径的重要延迟点。因此，在功能完整和时序允许的前提下，尽量减少 IFU 的处理周期，有助于提升供指效率和预测失败恢复速度。

### 功能细化
- IFU负责将ICache传输过来的指令数据进行切分。确定预测块中每一条指令的位置，获得对应的有效指令数据。
- IFU负责进行预译码，获取每条分支指令对应的分支类型，以及对应的jumpOffset。从性能角度考虑，IFU还会进行预译码检查，及早纠正能够发现的预测错误。
- IFU负责将C指令扩展为32位指令，并进行C指令的非法指令检查。
- IFU负责MMIO/pbmt的取指，并阻止MMIO取指的推测执行。
- IFU负责将ICache传递过的异常信息与指令进行对应。
- IFU需要配合IBuffer的入队，以减轻IBuffer的入队逻辑压力。
- IFU支持同时对两个预测块进行指令位置定界、预译码、预译码检查、以及同时入队IBuffer。

### 设计的考量
IFU涉及到多个模块的交互，存在不少需要考虑的设计细节。从可行性角度讲，IFU的压力来源于时序和成本。IFU需要平衡指令位置定界，IBuffer入队的时序紧张问题。另外从ICache读取32条指令的时序压力也是存在的。大量的指令并行处理和时序优化将导致面积和功耗的上升。需要注意的是大量的数据、紧耦合的数据处理将会带来物理端布局布线的压力并劣化时序。IFU的时序压力将随着前端供指量的增大而大幅上升。

## 总体设计

![IFU 的结构图](../figure/IFU/ifu-structure.svg)

### 主体结构的确定
IFU与多个模块都有信息交互，分别是FTQ、ICache、IBuffer、以及MMIO总线。1. IFU会接收来自FTQ的取指请求和重定向信号。相应的当IFU发现预译码与预测结果不符时，也会向FTQ发送重定向信号。2. IFU在完成预译码信息整理后，会将指令数据传递给IBuffer。3. FTQ向IFU发送取指请求的同时，也会向ICache发送取指请求。理论ICache能够在下一拍返回指令数据给IFU，但时序不好，IFU内部需要再打一拍。相当于IFU从接收取指请求时，需要打两拍才能正式处理ICache Data。指令数据需要进行划分和预译码，至少需要再打一拍才能送入IBuffer。

所以我们可以得出几个结论，如果目前V3的结构不变动的话。IFU最快需要在S2阶段进行预译码，S3阶段才能将整理的指令数据传输给IBuffer。目前IFU的预测检查我们放在S4阶段，在评估性价后也许能够放在S3。所以IFU的主流水线是3级结构（不考虑特殊的uncache状态机）。

### IFU的每一级功能确定与时序预估
目前S0级与S1级之间主要是计算预测块的指令范围，计算预测块的指令大小。计划还会计算一些PC序列低位的信息，因为第二个预测块拼接在第一个预测块后面，所以第二个预测块的PC信息是需要偏移的。

目前S1级与S2级之间主要是进行指令定界，以及计算指令密集排布需要的指令索引。因为ICache的返回的原始数据不与预测块的首地址进行对齐操作的。这将导致IFU本身需要做移位操作，为了减轻这个一块的压力，ICache可能需要承担部分移位操作，至少是指令定界相关的移位操作。

目前s2级与s3级之间的提取指令数据，供有32个读口，据推测这将导致物理布局布线的压力。所以我们进行dup的备份操作，分散读口。

对于S3级存在的IBuffer入队时序压力，我们进行了两点优化。一是划分Valid序列和enqEnable序列，Valid序列直接提供给IBuffer的entry用于计算选择需要的有效指令，enqEnable用于最终确定有效指令是否写入IBuffer，因为enqEnable是经过predChecker缩减了有效指令的范围，有额外的组合逻辑需要处理。二是IFU与IBuffer进行了特殊的入队操作约定，IFU的特殊准备将能够缓解时序上的压力。

需要注意的是，目前设计的想法主要在解决时序问题和功能实现上，对于面积和时钟门控没有过多考虑。计划在代码相对稳定后进行优化。