# MissUnit 子模块文档

MissUnit 负责处理 ICache 缺失的请求，通过 MSHR 进行管理，通过 Tilelink 总线与 L2 Cache 进行交互，并负责向
MetaArray 和 DataArray 发送写请求，向 MainPipe 发送响应。

![MissUnit 结构](../figure/ICache/MissUnit/missunit_structure.png)

## MSHR 的管理

MissUnit 通过 MSHR 分别管理取指请求和预取请求，为了防止 flush 时取指 MSHR 不能完全释放，设置取指 MSHR 的数量为 4，预取
MSHR 的数量为 10。采用数据和地址分离的设计方法，所有的 MSHR 公用一组数据寄存器，在 MSHR 只存储请求的地址信息。

## 请求入队

MissUnit 接收来自 MainPipe 的取指请求和来自 IPrfetchPipe 的预取请求，取指请求只能被分配到
fetchMSHR，预取请求只能分配到 prefetchMSHR，入队时采用低 index 优先的分配方式。 在入队的同时对 MSHR 进行查询，如果请求已经在
MSHR 中存在，就丢弃该请求，对外接口仍表现 fire，只是不入队到 MSHR 中。在入队时向 Replacer 请求写入 waymask。

## acquire

当到 L2 的总线空闲时，选择 MSHR 表现进行处理，整体 fetchMSHR 的优先级高于 prefetchMSHR，只有没有需要处理的
fetchMSHR，才会处理 prefetchMSHR。 对于 fetchMSHR，采用低 index
优先的优先级策略，因为同时最多只有两个请求需要处理，并且只有当两个请求都处理完成时才能向下走，所有 fetchMSHR 之间的优先级并不重要。 对于
prefetchMSHR，考虑到预取请求之间具有时间顺序，采用先到先得的优先级策略，在入队时通过一个 FIFO 记录入队顺序，处理时按照入队顺序进行处理。

## grant

通过状态机与 Tilelink 的 D 通道进行交互，到 L2 的带宽为 32byte，需要分 2
次传输，并且不同的请求不会发生交织，所以只需要一组寄存器来存储数据。当一次传输完成时，根据传输的 id 选出对应的 MSHR，从 MSHR
中读取地址、掩码等信息，将相关信息写入 SRAM，同时将 MSHR 释放。
