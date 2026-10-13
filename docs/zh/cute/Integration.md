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

普通 legacy AML/BML/CML 的请求使用内部通道 0；A/B 转置引擎和参数化 loader 可以使用多个物理通道。接口数量、内部 bank 数与某个任务的实际请求宽度应分别理解。

## LocalMMU 请求仲裁

LocalMMU 接收 A、B、C load、C store、A scale、B scale 六类访问流。每个物理通道独立仲裁，固定优先级为：

```text
A read > A scale read > B read > B scale read > C load > C store
```

只有被选中的流获得下游 ready。下游阻塞时，相应请求保持等待；低优先级流也可能因高优先级请求连续到来而延后。这不是轮转仲裁。默认不发 Scale 任务，但其仲裁位置仍存在于可选接口组织中。

LocalMMU 将请求地址直接交给下游，不读取页表、不查询 TLB，也不产生虚实地址转换。部分上游字段仍使用 `BaseVaddr` 命名，这个名字不表示 LocalMMU 会执行转换。地址属性和可访问范围必须由系统集成保证。

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

返回时先解出来源标签，再把去掉标签的标识交给对应 loader。标签只描述物理访问流，例如转置 B 走 AML 后使用 A read 路径，不能单凭该标签恢复架构指令类别。

### 分配式与自编码式标识

legacy A/B loader 使用 LocalMMU 的分配式 SourceID。LocalMMU 维护默认 64 项 busy 表，只有空闲项可分配；loader 以该编号保存 bank、entry、tail 的查找信息。发往缓存的原始标识还带分配式标记，返回时据此释放 busy 项并恢复 loader 所用编号。

参数化 loader 和转置引擎可直接编码 bank、entry、tail 或槽号、源行，不需要这个分配式查找表。`UseAllocatedSourceID` 区分两种方法。二者经过同一低三位来源标签和下游 `AmeIndex` 传输，不应把所有 64 bit SourceID 都解释为同一个小编号。

## Cute2TL 请求转换

Cute2TL 为默认八个通道分别创建一个 `TLClientNode`，各 client 的 TileLink `source` 范围为 `IdRange(0,1)`，请求 source 固定为 0。CUTE 内部允许区分多个在途请求所需的真实 64 bit 标识由 TileLink user 字段 `AmeIndex` 携带。

每条读请求转换为一个 64 B Get，每条写请求转换为一个 64 B PutFullData。写掩码必须全一；适配器对此有断言。CML 内部使用部分字节掩码装载寄存器，不意味着这里支持 PutPartialData。

Table: TileLink 矩阵扩展字段 {#tbl:cute-tl-fields}

| 字段 | 生成规则和用途 |
| --- | --- |
| `AmeIndex` | 保存完整 `RequestSourceID`，由返回路径带回以恢复原事务 |
| `MatrixKey` | C read 为二进制 `11`；其它矩阵请求，包括 C store，为 `01` |
| `ReqSource` | 分别标记 `MatrixRead` 或 `MatrixWrite`，用于缓存请求来源统计 |
| `MatrixPrefetchTag` | 静态启用矩阵预取时生成；默认配置不存在此字段 |

C read 的识别条件是累加寄存器访问且为读，不能把所有 C 访问都标成 `11`。调试用 `MatrixTraceTag` 不映射为 TileLink user 字段，其作用与真正参与预取的标签不同。

## 数据返回与应答合并

矩阵读数据由 HBL2 的独立 `matrix_data_in` 返回，包含 512 bit data 和 64 bit source。TileLink D 通道提供普通应答以及 `AmeIndex`。Cute2TL 在每个通道将这两路合并为内部 `MMUResponseIO`。

若本周期存在矩阵数据，优先选择该路 source 和数据；TL-D 的 ready 拉低。如果没有矩阵数据，则选择 TL-D 的 `AmeIndex` 作为响应标识。内部响应 ready 同时反压被选中的路径。C store 的 ACK 只需要标识，不消费矩阵读数据。

这个组织要求 HBL2 按矩阵扩展协议提供数据，不能把普通 TL-D.data 当作完整替代。缓存侧的请求、返回 Hint 配对及数据组织见 [二级缓存](../cache/l2cache/CoupledL2.md) 的 XSAI 集成部分。

例如，一条 A load 请求在请求握手时保存目标 entry，并把编码后的 SourceID 放到 `AmeIndex`；HBL2 完成访问后在矩阵数据通道返回 data/source；Cute2TL 合并响应，LocalMMU 去掉来源标签，AML 查表恢复 bank 和 entry，再把 64 B 拆成两次内部写入。load 完成在最后内部写之后，不能以 TileLink 请求被接收为界。

## 地址、一致性和异常边界

当前 Cute2TL 没有根据 `RequestConherent` 选择两条独立总线；返回一致性属性固定为 true，noncoherent SourceID 接口的 valid 固定为 false。实际缓存一致性行为由 HBL2 处理，不能从内部保留的 coherent/noncoherent 字段推导出两套均已实现的数据通路。

LocalMMU 不处理页故障，Cute2TL/LocalMMU 也没有将 TileLink `denied`、`corrupt` 转换为矩阵指令精确异常的路径。内部响应 Bundle 只提供数据、SourceID 和一致性属性。外部访问的错误回报能力必须按系统现有机制理解，不能将写 ACK 解释为向 CPU 返回的完整异常状态。

默认 loader 按完整 64 B 请求读取，store 按完整 64 B 写入。软件和系统应满足完整访问范围的有效性与布局要求，尤其是 [转置加载对齐与存储尾部](MemoryLoader.md)。

## 同步与忙闲

控制核向 `amuCtrl` 交付命令、CUTE 任务完成、CUTE 窗口退休、Release 更新同步寄存器是不同事件。Release 的直接依赖是更老 Store 完成；它不等待无关 Load/Compute，也不自行建立与标量访问之间的全部排序。

Cute2TL 的 `idle` 当前固定为 true，不能用于判断矩阵任务、在途内存访问或缓存请求已经清空。TaskController 的资源占用事件可以观察任务状态，但也不提供一个可以替代同步指令语义的全系统 idle 协议。

## 实现对应

本节对应 [LocalMMU](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/LocalMMU.scala)、[Cute2TL](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTE2YGJK.scala)、[请求响应 Bundle](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTEParameters.scala) 和 [CUTE 顶层接口](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTETOP.scala)。
