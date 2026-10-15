# 总体架构 {#sec:overview}

香山 AI（XSAI）在昆明湖 V2 高性能通用处理器的基础上，集成 CUTE 矩阵计算单元，并扩展控制核的矩阵配置、命令提交、访存和同步机制。控制核执行通用程序、标量及向量运算，CUTE 执行异步矩阵任务，两者通过命令接口、存储系统和同步接口协作。

本章以 `DefaultMatrixConfig` 为例，介绍 XSAI 的主要模块及其相互关系。整体架构见 [@fig:xsai-overview]。

![XSAI 整体架构与矩阵数据通路](figure/xsai-architecture.svg){#fig:xsai-overview}

[查看完整架构图](figure/xsai-architecture.svg)

## 控制核 {#sec:overview-core}

控制核沿用昆明湖 V2 的取指和乱序执行结构。前端由分支预测单元、取指目标队列、指令缓存、取指单元和指令缓冲组成，向后端提供指令流。后端完成译码、重命名、分派、调度、执行和退休，整数、浮点和向量执行资源各自配有发射队列与物理寄存器文件。

XSAI 在后端增加矩阵维度寄存器 Mx 的重命名、调度和执行通路。Mx 保存矩阵的 M、N、K 尺寸，MCfgGen 维护矩阵寄存器的数据类型配置。MSET0/MSET1 处理矩阵尺寸设置与读取，MMA 和 MZERO 根据配置与操作数生成计算或清零命令。矩阵访存指令由 MLSU 翻译并检查起始基址，再生成交给 CUTE 的访存命令。

矩阵命令在 ROB 内的 AmuCtrlBuffer 中保存，随对应指令提交后，经 AMU Arbiter 送往 CUTE。控制核的向量执行资源同时支持 BF16 格式转换、加宽乘加和以 2 为底的指数等运算，供推理程序处理矩阵乘加之外的逐元素计算。

控制核的流水线与功能单元见[后端整体介绍](backend/index.md)、[矩阵功能单元](backend/FunctionUnit/MatrixFunctionUnit.md)和[向量浮点单元](backend/VFPU.md)。

## CUTE 矩阵计算单元 {#sec:overview-cute}

CUTE 由 TaskController、矩阵寄存器、MTE、加载与存储单元及访存接口组成。TaskController 缓冲控制核下发的命令，在 Issue Window 中维护矩阵寄存器依赖和执行资源占用，向就绪的执行资源发射任务，并跟踪任务完成与退休。

AB MatrixReg 保存 A、B 操作数，对应四个共享的 tr 寄存器；C MatrixReg 保存累加值与结果，对应四个 acc 寄存器。控制核的 Mx 寄存器保存矩阵尺寸，CUTE 的 tr/acc 寄存器保存矩阵元素。

MTE 是 TaskController 调度的矩阵计算执行资源，包含操作数供给、MatrixTE 计算阵列和结果写回。默认阵列由 8×8 个 PE 组成，读取 tr 中的 A、B 操作数及 acc 中的累加值，执行 `C ← A × B + C`，并将结果写回 acc。

AML 和 BML 分别将外部 A、B 数据加载到 tr，CML 将初始累加矩阵加载到 acc，或将 acc 中的结果存回外部存储器。TaskController 按依赖关系调度这些加载、计算与存储任务，使独立任务能够重叠执行。

各执行资源通过 LocalMMU 和 Cute2TL 访问 HBL2。LocalMMU 负责请求仲裁、事务标识管理和响应分流，Cute2TL 完成 TileLink 请求转换与返回适配。各子模块的实现见 [CUTE 矩阵计算单元](cute/index.md)。

## 存储系统 {#sec:overview-memory}

控制核的 LSU/LSQ 处理标量与向量访存，通过 DCache、各级 TLB 和页表遍历单元访问存储系统。矩阵访存通路增加 MLSU、DTLB/PMP 和矩阵访存队列，负责向 CUTE 命令提供翻译后的物理基地址，并维护访存指令的异常与重放状态。

每核的 HBL2 同时连接控制核与 CUTE。矩阵请求使用缓存的目录、MSHR 和一致性机制，并通过专用矩阵读数据接口将整条缓存行送回 CUTE。默认矩阵配置的每核 HBL2 容量为 2 MiB，分为 8 个 bank；多核系统通过 CHI 接入共享 L3 和系统互连。

地址翻译与矩阵访问流程见 [MLSU](memblock/LSU/MLSU.md)，矩阵缓存接口见 [HBL2](cache/l2cache/HBL2.md)。

## 系统支持与调试 {#sec:overview-system}

CSR 和特权控制逻辑维护处理器运行状态，CLINT 提供定时器及软件中断，IMSIC 接收消息中断。Debug 模块提供外部调试访问，性能监控逻辑记录控制核、CUTE 和访存系统的运行事件，供软件调优和问题分析使用。

相关设计见 [CSR](backend/CSR.md)、[性能监控](backend/HPM.md)、[Debug 模块](backend/DebugModule/DM.md)及 [CUTE 性能事件与调试](cute/Performance.md)。

## 控制核与 CUTE 的协作 {#sec:overview-paths}

### 命令通路 {#sec:overview-command}

矩阵指令进入控制核后，经过译码、寄存器重命名、调度和执行，取得尺寸、数据类型及所需操作数。执行单元将生成的命令写入 AmuCtrlBuffer；ROB 提交对应指令后，经 AMU Arbiter 和 `AmuCtrlIO` 下发给 CUTE。TaskController 接收命令，按矩阵寄存器依赖调度实际的数据操作。

### 矩阵数据通路 {#sec:overview-data}

矩阵数据经 HBL2、Cute2TL 和 LocalMMU 到达 AML/BML/CML，再写入所选 tr 或 acc。MTE 从 tr/acc 读取操作数并将结果写回 acc；CML 经同一套访存接口将结果存回外部存储器。控制核提供命令参数，矩阵数据在 CUTE 的寄存器与加载、计算、存储资源之间流动。

### 同步通路 {#sec:overview-sync}

软件通过 `mrelease` 和 `macquire` 协调控制核与矩阵任务。CUTE 在 Release 要求的更老 Store 写应答收齐后，经 `AmuRelease` 向控制核返回同步通知；Fence 单元更新相应的 msync 计数器，`macquire` 等待计数器达到软件指定的目标值。软件据此安排依赖矩阵结果的后续操作和缓冲区复用。

三条通路的接口定义、地址处理和同步语义见[访存接口与系统集成](cute/Integration.md)。

## 阅读指引 {#sec:overview-reading}

Table: 主要模块与后续章节 {#tbl:overview-reading}

| 关注内容 | 后续章节 |
| --- | --- |
| 指令供给 | [分支预测](frontend/BPU/index.md)、[取指单元](frontend/IFU/index.md)、[指令缓存](frontend/ICache/index.md) |
| 矩阵配置、执行与提交 | [MCfgGen](backend/CtrlBlock/MCfgGen.md)、[矩阵功能单元](backend/FunctionUnit/MatrixFunctionUnit.md)、[AmuCtrlBuffer](backend/CtrlBlock/AMUCtrlBuffer.md) |
| 矩阵任务、计算与数据存储 | [TaskController](cute/TaskController.md)、[矩阵寄存器](cute/MatrixReg.md)、[计算数据通路](cute/Compute.md) |
| 矩阵数据搬运 | [MLSU](memblock/LSU/MLSU.md)、[加载与存储](cute/MemoryLoader.md)、[HBL2](cache/l2cache/HBL2.md) |
| 控制核与矩阵任务同步 | [整数功能单元](backend/FunctionUnit/IntFunctionUnit.md)、[系统集成](cute/Integration.md) |
