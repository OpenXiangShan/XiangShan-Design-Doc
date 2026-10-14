# 性能事件与调试

## 总体设计

CUTE 将 TaskController 的任务状态与 LocalMMU 的请求状态组成 `CutePerfToCoreIO`，上送控制核 HPM。接口包含 9 个 backend events 和 12 个 mem events，每项宽度为 6 bit；顶层对整组事件打一拍。下表索引对应 CUTE 本地接口中的位置，控制核通过事件选择逻辑将这些输入映射到 HPM 计数器。

任务事件记录任务占用、完成和退休，请求事件记录 LocalMMU 已握手的外部请求。一条任务可以产生多条请求，多个模块可以同周期活动。控制核先提交矩阵指令再交付命令，CUTE 的完成和退休事件在后续异步执行过程中产生。

## 后端事件

Table: CUTE backendEvents {#tbl:cute-backend-events}

| 本地索引 | 来源 | 计数语义 |
| --- | --- | --- |
| 0 | `ownedWork` | decoded FIFO 头有效或发射窗口非空的周期 |
| 1 | `retire` | 窗口头任务退休，一次退休计 1 |
| 2 | `compDone` | CDC 完成写回，Compute 整体完成计 1 |
| 3 | `releaseDone` | Release 发射并产生同步寄存器完成脉冲计 1 |
| 4 | `mteActive` | Compute FU tracker busy 的周期 |
| 5 | `mmaNonfpDone` | 完成的 Compute 为非浮点类型计 1 |
| 6 | `mmaFp16Done` | 完成的 Compute 类型为 FP16×FP16→FP32 计 1 |
| 7 | `mmaBf16Done` | 完成的 Compute 类型为 BF16×BF16→FP32 计 1 |
| 8 | `mmaTf32Done` | 完成的 Compute 类型为 TF32×TF32→FP32 计 1 |

`mteActive` 在 Compute FU tracker busy 时计数，覆盖供数等待、有效计算和流水线排空。`ownedWork` 在 decoded FIFO 头有效或发射窗口非空时计数，覆盖任务等待、执行和等待退休的周期。

默认配置中 FP16 和 TF32 关闭，对应类型事件为零。FP8 与其它计算一样计入 `compDone`，类型细分项则只覆盖非浮点、FP16、BF16 和 TF32。因此 FP8 完成数需要结合计算类型追踪记录统计。

## 访存事件

Table: CUTE memEvents {#tbl:cute-mem-events}

| 本地索引 | 来源 | 计数语义 |
| --- | --- | --- |
| 0 | `loadADone` | 物理 AML 任务完成计 1 |
| 1 | `loadBDone` | 物理 BML 任务完成计 1 |
| 2 | `loadCDone` | 物理 CML load 任务完成计 1 |
| 3 | `storeDone` | CML store 所需写 ACK 全部收齐后完成计 1 |
| 4 | `amlActive` | AML FU tracker busy 的周期 |
| 5 | `bmlActive` | BML FU tracker busy 的周期 |
| 6 | `cmlLoadActive` | CML load FU tracker busy 的周期 |
| 7 | `cmlStoreActive` | CML store FU tracker busy 的周期 |
| 8 | `rdReq` | 本周期至少一个 LocalMMU 下游读请求握手时计 1 |
| 9 | `wrReq` | 本周期至少一个 LocalMMU 下游写请求握手时计 1 |
| 10 | `rd32BReq` | 所有已握手读请求的 `popcount(RequestMask)>>5` 之和 |
| 11 | `wr32BReq` | 所有已握手写请求的 `popcount(RequestMask)>>5` 之和 |

AML 完成项覆盖普通 A 加载、转置 A、转置 B 和 ZeroTr，CML load 完成项覆盖 C 加载与 ZeroAcc。完成事件按物理执行资源计数，架构指令类别可由任务追踪记录区分。清零在 MatrixReg 内部执行，产生对应 loader 的占用与完成事件，外部请求计数保持不变。

`rdReq`、`wrReq` 对各通道握手信号进行或运算，统计有请求握手的周期数，多个通道同周期握手仍计 1。32 B 项对各通道的掩码字节数求和：默认全掩码 64 B 请求每条贡献 2，同周期多条请求按条数累加。

## 请求计数与带宽统计

对一段观察区间，`32 × sum(rd32BReq)` 和 `32 × sum(wr32BReq)` 分别表示按请求掩码累计的字节量。除以观察周期可得到 CUTE 该请求接口的平均请求字节/周期；再乘实际运行频率才得到对应接口速率。

计数位置位于 LocalMMU 下游请求接口，累计的是 CUTE 发往缓存的请求字节。响应字节数、HBL2 命中或缺失流量以及 DDR 流量需要使用对应接口的事件统计。默认读请求覆盖完整 64 B，请求量包含最后一个 beat 中未写入 MatrixReg 的字节；C store 的尾部补零也计入完整写请求。

Compute、loader 和外部请求可以同周期活动，其占用计数分别覆盖各自执行阶段。任务停顿发生在入窗后的依赖或资源等待、FU 供数等待、阵列反压、返回缓冲阻塞、写应答等待等位置；任务追踪记录中的发射、读完和完成时点可用于划分这些阶段。

## ChiselDB 任务事件

TaskController 定义四类基本任务表，将发射和完成事件关联到同一任务。

Table: CUTE ChiselDB 任务表 {#tbl:cute-chiseldb-tables}

| 表 | 主要字段和用途 |
| --- | --- |
| `CUTELoadEvent` | `eventType`、寄存器、行列数、转置、A/B/C mask、`fifoIdx`、`slotId`、`seqId`；关联分配、发射、物理 loader 完成 |
| `CUTEComputeEvent` | A/B/C 编号、M/N/K、类型、`slotId`、`seqId`；区分计算发射、A 读完、B 读完、C 写完 |
| `CUTEStoreEvent` | C 编号、行列数、转置、`slotId`、`seqId`；关联存储发射与 ACK 收齐 |
| `CUTEReleaseEvent` | 同步寄存器编号、`slotId`、`seqId`；关联 Release 的调度与完成 |

`slotId` 是窗口槽号，退休后复用；`seqId` 是 16 bit 序号，按任务分配推进并在溢出时回绕。任务关联使用时间、序号和任务属性共同定位。`fifoIdx` 按任务类别分别推进，记录该类别内部的顺序；窗口年龄由入窗顺序决定。

这些表通过 ChiselDB 输出，生成和记录由仿真/调试配置决定。控制核 HPM 计数器则由 `CutePerfToCoreIO` 事件驱动，二者分别提供任务明细和累计统计。

## 矩阵预取相关观察

默认 `EnableMatrixPrefetch=false`，不生成矩阵预取描述符、控制输出或请求预取标签。静态开启后，可生成 `CUTEMatrixPrefetchDesc`、独立的 `CUTECStoreDesc` 以及 Cute2TL 的 `CUTEMemoryTrace`。

load 描述符包含任务 ID、流类别、基地址、外层 stride、外层数量、内层 beat 数、有效行字节数、分组宽度和转置属性，既关联任务访问序列，也为预取控制提供信息。C store 的独立描述符用于追踪重建，L2 矩阵预取器的训练输入来自 load 路径。TileLink 请求携带预取标签，调试 trace tag 保存在 Cute2TL 追踪表中。

矩阵预取由 CUTE 与 HBL2 的静态配置共同启用，并使用描述符支持的访问形状生成后续请求。

## 实现对应

本节对应 [性能接口 Bundle](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/Bundles.scala)、[TaskController 事件](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/TaskController.scala)、[LocalMMU 请求计数](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/LocalMMU.scala)、[顶层事件映射](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTETOP.scala) 和 [Cute2TL 追踪](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTE2YGJK.scala)。
