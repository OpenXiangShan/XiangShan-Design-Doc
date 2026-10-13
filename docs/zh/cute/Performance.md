# 性能事件与调试

## 总体设计

CUTE 将 TaskController 的任务状态与 LocalMMU 的请求状态组成 `CutePerfToCoreIO`，上送控制核 HPM。接口包含 9 个 backend events 和 12 个 mem events，每项宽度为 6 bit；顶层对整组事件打一拍。事件索引是 CUTE 本地接口中的位置，最终通过控制核事件选择逻辑接入 HPM，不应直接当作 CSR 事件编码。

任务事件用于观察任务占用、完成和退休，请求事件用于观察 LocalMMU 已握手的外部请求。它们的统计对象不同：一个任务可以产生多条请求，多个模块可以同周期活动，而一次矩阵指令在 CPU 的提交时点也不等于 CUTE 的任务完成时点。

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

`mteActive` 覆盖 Compute 任务占用期间，包括供数等待和流水线排空；它不表示该周期 64 个 PE 都接受了一组有效输入。`ownedWork` 同样表示控制器持有工作，不表示每周期发射成功。

默认配置不执行 FP16 或 TF32 计算，对应类型事件为零。FP8 计算包括在 `compDone` 中，但这组事件没有独立的 FP8 完成项。不能用后三个浮点格式事件之和代替全部浮点任务完成数。

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

AML 完成项可能来自普通 A 加载、转置 A、转置 B 或 ZeroTr；CML load 完成项也可能来自 ZeroAcc。它们按执行资源归属计数，不是对架构 MLA、MLB、MLC 指令逐类计数。清零不访问外部存储器，仍会产生对应 loader 占用与完成事件。

`rdReq`、`wrReq` 是有请求握手的周期数。当多个通道同周期握手时仍只计 1；请求条数不能仅由这两项得到。32 B 项则在各通道求和：默认全掩码 64 B 请求每条贡献 2，因此同周期多条请求可贡献更大的值。

## 请求量与带宽的解释

对一段观察区间，`32 × sum(rd32BReq)` 和 `32 × sum(wr32BReq)` 分别表示按请求掩码累计的字节量。除以观察周期可得到 CUTE 该请求接口的平均请求字节/周期；再乘实际运行频率才得到对应接口速率。

这些事件不统计响应到达字节，不区分 HBL2 命中、缺失或缓存到内存的流量，也不代表 DDR 有效带宽。默认读请求按完整 64 B 发出，即使只有部分字节最终写入 MatrixReg，请求量也包含整个 beat。C store 的尾部补零同样属于完整写请求。

Compute 占用、loader 占用和请求周期可以重叠，因此把它们相加不会得到总执行时间。分析停顿时应先确定要观察的对象：TaskController 尚未发射、FU 已占用但等待输入、阵列反压、返回缓冲阻塞、写应答未齐分别属于不同阶段。

## ChiselDB 任务事件

TaskController 定义四类基本任务表，将发射和完成事件关联到同一任务。

Table: CUTE ChiselDB 任务表 {#tbl:cute-chiseldb-tables}

| 表 | 主要字段和用途 |
| --- | --- |
| `CUTELoadEvent` | `eventType`、寄存器、行列数、转置、A/B/C mask、`fifoIdx`、`slotId`、`seqId`；关联分配、发射、物理 loader 完成 |
| `CUTEComputeEvent` | A/B/C 编号、M/N/K、类型、`slotId`、`seqId`；区分计算发射、A 读完、B 读完、C 写完 |
| `CUTEStoreEvent` | C 编号、行列数、转置、`slotId`、`seqId`；关联存储发射与 ACK 收齐 |
| `CUTEReleaseEvent` | 同步寄存器编号、`slotId`、`seqId`；关联 Release 的调度与完成 |

`slotId` 是窗口槽号，退休后会复用；`seqId` 是 16 bit 序号，运行足够长后也会回绕。分析长时间追踪应同时结合时间和任务属性，不能将单个槽号视为全程唯一指令 ID。不同任务类别的 `fifoIdx` 也分别推进，不能跨类别直接比较年龄。

这些表是 ChiselDB 调试输出，是否生成和记录由仿真/调试配置决定；它们不是软件直接读取的架构计数器。

## 矩阵预取相关观察

默认 `EnableMatrixPrefetch=false`，不生成矩阵预取描述符、控制输出或请求预取标签。静态开启后，可生成 `CUTEMatrixPrefetchDesc`、独立的 `CUTECStoreDesc` 以及 Cute2TL 的 `CUTEMemoryTrace`。

load 描述符包含任务 ID、流类别、基地址、外层 stride、外层数量、内层 beat 数、有效行字节数、分组宽度和转置属性，用于将访问序列关联到任务。C store 有独立描述符用于追踪重建，但不训练 L2 矩阵预取器；调试 trace tag 也不作为 TileLink 预取字段发送。

预取开关、HBL2 预取配置和有效访问形状需要分别满足，不能把调试表存在理解为默认启用矩阵预取。

## 实现对应

本节对应 [性能接口 Bundle](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/Bundles.scala)、[TaskController 事件](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/TaskController.scala)、[LocalMMU 请求计数](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/LocalMMU.scala)、[顶层事件映射](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTETOP.scala) 和 [Cute2TL 追踪](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTE2YGJK.scala)。
