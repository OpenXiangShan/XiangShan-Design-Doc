# 访存接口与系统集成

## 接口列表

CUTE 的控制入口与矩阵数据访问分别连接控制核和 HBL2。控制核决定何时将矩阵命令交给 CUTE；CUTE 内部的 TaskController 决定各命令的数据操作何时开始和完成。存储一致性由实际接入的缓存系统处理，LocalMMU 只负责 CUTE 内部访问流组织。

Table: CUTE 顶层和适配接口 {#tbl:cute-integration-io}

| 接口 | 方向和握手 | 功能 |
| --- | --- | --- |
| `ctrl2top.amuCtrl` | 控制核→CUTE，Decoupled | 异步矩阵命令及操作数 |
| `ctrl2top.mrelease` | CUTE→控制核，Valid | 指定同步寄存器的 Release 完成脉冲 |
| `mmu2llc.Request` | CUTE→Cute2TL，八个 Decoupled 通道 | 地址、读写类型、写数据、掩码、64 bit SourceID 和矩阵属性 |
| `mmu2llc.Response` | Cute2TL→CUTE，八个 Decoupled 通道 | 64 bit SourceID、返回数据和一致性属性 |
| `Cute2TL.node` | 八个独立 TileLink client | 64 B Get/PutFullData 请求与普通应答 |
| `Cute2TL.matrix_data_in` | HBL2→Cute2TL，八个 Decoupled 通道 | 每通道 512 bit 矩阵读数据和 64 bit source |
| `perf` | CUTE→控制核 | 9 个后端事件和 12 个访存事件，顶层打一拍 |
| `matrixPrefetch` | 可选，CUTE→缓存预取控制 | 静态启用时生成描述符和控制信息；默认关闭 |

普通 legacy AML/BML/CML 的请求使用内部通道 0；A/B 转置引擎和参数化 loader 按通道配置分配请求，可以使用多个物理通道。每个任务的请求宽度由所选 loader 实现决定。

## LocalMMU 请求仲裁

LocalMMU 接收 A、B、C load、C store、A scale、B scale 六类访问流。每个物理通道独立仲裁，固定优先级为：

```text
A read > A scale read > B read > B scale read > C load > C store
```

只有被选中的流获得下游 ready。下游阻塞时，相应请求保持等待；高优先级流连续请求时，低优先级流持续等待。默认 Scale 任务 valid 为 false，仲裁器仍为静态开启的 Scale 访问预留上述优先级位置。

控制核 MLSU 将翻译后的物理基地址写入命令的 `baseAddr`。loader 在该地址上叠加行 stride 和 beat 偏移，LocalMMU 将生成的请求地址直接交给下游。上游配置中命名为 `BaseVaddr` 的字段也保存这条命令提供的地址；CUTE 内部没有 TLB 或 PTW，后续各行和 beat 访问需要落在系统提供的有效物理地址范围内。

## 事务标识

### 来源标签

LocalMMU 用 SourceID 的低三位区分访问流，高位保存该流的原始事务标识：

```text
encodedSourceId = (origId << 3) | sourceTag
```

Table: LocalMMU 来源标签 {#tbl:cute-source-tags}

| 访问流 | sourceTag |
| --- | --- |
| A read | 0 |
| B read | 1 |
| C load | 2 |
| C store | 3 |
| A scale read | 4 |
| B scale read | 5 |

返回时先解出来源标签，再把去掉标签的标识交给对应 loader。标签按物理访问流分配，例如转置 B 通过 AML 的 A read 路径发出，使用标签 0；架构指令类别保存在任务记录中。

### 分配式与自编码式标识

legacy A/B loader 使用 LocalMMU 的分配式 SourceID。LocalMMU 维护默认 64 项 busy 表，只有空闲项可分配；loader 以该编号保存 bank、entry、tail 的查找信息。发往缓存的原始标识还带分配式标记，返回时据此释放 busy 项并恢复 loader 所用编号。

参数化 loader 和转置引擎直接将 bank、entry、tail 或槽号、源行编码到原始标识中。`UseAllocatedSourceID` 选择分配式编号或自编码标识，两种标识都附加低三位来源标签，再通过下游 `AmeIndex` 传输。

## Cute2TL 请求转换

Cute2TL 为默认八个通道分别创建一个 `TLClientNode`，各 client 的 TileLink `source` 范围为 `IdRange(0,1)`，请求 source 固定为 0。CUTE 内部允许区分多个在途请求所需的真实 64 bit 标识由 TileLink user 字段 `AmeIndex` 携带。

每条读请求转换为一个 64 B Get，每条写请求转换为一个 64 B PutFullData。写掩码必须全一，适配器对此有断言。MatrixReg 的部分字节更新在 loader 内部完成；外部写接口覆盖整条 64 B 数据。

Table: TileLink 矩阵扩展字段 {#tbl:cute-tl-fields}

| 字段 | 生成规则和用途 |
| --- | --- |
| `AmeIndex` | 保存完整 `RequestSourceID`，由返回路径带回以恢复原事务 |
| `MatrixKey` | C read 为二进制 `11`；其它矩阵请求，包括 C store，为 `01` |
| `ReqSource` | 分别标记 `MatrixRead` 或 `MatrixWrite`，用于缓存请求来源统计 |
| `MatrixPrefetchTag` | 静态启用矩阵预取时生成；默认配置不存在此字段 |

`MatrixIsAcc && !RequestType_isWrite` 选择 C read 的 `11` 编码，C store 使用 `01`。`MatrixPrefetchTag` 随请求进入缓存，`MatrixTraceTag` 留在 Cute2TL 的调试记录中用于关联任务。

## 数据返回与应答合并

矩阵读数据由 HBL2 的独立 `matrix_data_in` 返回，包含 512 bit data 和 64 bit source。TileLink D 通道提供普通应答以及 `AmeIndex`。Cute2TL 在每个通道将这两路合并为内部 `MMUResponseIO`。

若本周期存在矩阵数据，优先选择该路 source 和数据；TL-D 的 ready 拉低。如果没有矩阵数据，则选择 TL-D 的 `AmeIndex` 作为响应标识。内部响应 ready 同时反压被选中的路径。C store 的 ACK 只需要标识，不消费矩阵读数据。

Cute2TL 的 `ReseponseData` 直接连接 `matrix_data_in.data`，TL-D 提供应答标识，因此 HBL2 需要按矩阵扩展协议返回读数据。缓存侧的请求、返回 Hint 配对及数据组织见 [二级缓存](../cache/l2cache/CoupledL2.md) 的 XSAI 集成部分。

例如，一条 A load 请求在请求握手时保存目标 entry，并把编码后的 SourceID 放到 `AmeIndex`；HBL2 完成访问后在矩阵数据通道返回 data/source；Cute2TL 合并响应，LocalMMU 去掉来源标签，AML 查表恢复 bank 和 entry，再把 64 B 拆成两次内部写入。AML 在最后一次内部写入结束后报告 load 完成。

## 地址、一致性和异常边界

Cute2TL 的全部请求进入同一组 TileLink client，`RequestConherent` 不参与总线选择。返回一致性属性固定为 true，noncoherent SourceID 接口的 valid 固定为 false；缓存一致性行为由 HBL2 处理。

地址翻译阶段的异常由控制核处理。Cute2TL/LocalMMU 的内部响应 Bundle 提供数据、SourceID 和一致性属性，未将 TileLink `denied`、`corrupt` 转换为矩阵指令精确异常。CML store 依据写 ACK 标识释放在途状态，其完成接口报告应答收齐。

默认 loader 按完整 64 B 请求读取，store 按完整 64 B 写入。软件和系统应满足完整访问范围的有效性与布局要求，尤其是 [转置加载对齐与存储尾部](MemoryLoader.md)。

## 同步与忙闲

控制核在 ROB 提交后向 `amuCtrl` 交付命令，CUTE 在数据操作结束后完成任务，并按窗口顺序退休。Release 在更老 Store 的 ACK 收齐后向控制核发送完成向量，Fence 据此更新同步计数器；此时无关 Load/Compute 可以继续运行。`macquire` 等待计数器达到目标值，`mfence` 则请求标量 SBuffer 排空并等待 `sbIsEmpty`，两者分别处理矩阵任务完成和标量存储排序。详见[矩阵同步](../backend/FunctionUnit/IntFunctionUnit.md#sec:matrix-sync)。

Cute2TL 的 `idle` 固定为 true，其值独立于任务和在途访问状态。TaskController 的资源占用事件反映各执行模块状态；软件同步使用 Release 和控制核同步寄存器协议，具体语义见 [Release](TaskController.md#sec:cute-release)。

## 实现对应

本节对应 [LocalMMU](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/LocalMMU.scala)、[Cute2TL](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTE2YGJK.scala)、[请求响应 Bundle](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTEParameters.scala) 和 [CUTE 顶层接口](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTETOP.scala)。
