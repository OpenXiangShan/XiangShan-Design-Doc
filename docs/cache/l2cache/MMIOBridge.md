# MMIO 转接桥 MMIOBridge

MMIOBridge 独立于 CoupledL2 的 4 个 Slice 之外，接收来自 IFU / LSU 的 MMIO 与 Uncache 请求，通过 CHI 总线与下游 NoC / LLC 进行交互并完成外设的读写操作。默认 MMIOBridge 包含 8 项 MMIOBirdgeEntry，每一项 MMIOBridgeEntry 都是独立的状态机，用于处理一条 MMIO 或 Uncache 请求。

## 状态机

状态机项主要分为两类：

- Schedule 状态项
- Wait 状态项

Schedule 状态项又称主动动作状态项，主要用来跟踪 MMIOBridgeEntry 主动向上游 TileLink 总线、下游 CHI 总线发送任务与请求的情况。其值为低有效，表示未完成状态，即任务尚未成功离开 MMIOBridgeEntry 并被发出，其原因可能是未完成阻塞条件（有必要的前置动作未完成）或通道阻塞；值为高则表示对应任务已经成功发出，或不需要发出任务。

Wait 状态项又称被动动作状态项，主要用来跟踪 MMIOBridgeEntry 期望收到的来自下游 CHI 通道、上游 TileLink 通道的回复。其值为低有效，表示未完成状态，即对应的回复尚未回到当前 entry；值为高则表示对应回复已经收到，或不需要收到回复。

状态寄存器包括：

| 名称 | 描述 |
| --- | ------ |
| ```s_txreq``` | 向下游 TXREQ 通道发送 ReadNoSnp / WriteNoSnpPtl 请求 |
| ```s_ncbwrdata``` | （如果是写操作）向下游 TXDAT 发送 NCBWrData 数据包，发送 NCBWrData 的前提是 ```w_dbidresp``` 拉高 |
| ```s_resp``` | CHI 读 / 写事务已完成，向上游 TileLink D 通道返回 AccessAckData / AccessAck 响应 |
| ```w_comp``` | （如果是写操作）等待下游 RXRSP 通道返回的 Comp / CompDBIDResp 响应 |
| ```w_dbidresp``` | （如果是写操作）等待下游 RXRSP 通道返回的 CompDBIDResp / DBIDResp / DBIDRespOrd 响应 |
| ```w_compdata``` | （如果是读操作）等待下游 RXDAT 通道返回的 CompData |
| ```w_pcrdgrant``` | 读 / 写请求发生协议层重传，需要等待下游返回 PCrdGrant |
| ```w_readreceipt``` | （如果是读请求且 Order 不是 None）等待下游 RXRSP 通道返回的 ReadReceipt |

## 定序

MMIOBridge 发起的 CHI 请求默认 Order 为 RequestOrder 或 EndpointOrder。核内在发起 TileLink 读 / 写请求时，会在 A 通道的自定义域中带上**PMA 属性是否为 Memory**：

- 如果该地址的 PMA 属性是 Memory，但是 PBMT 属性为 IO 或 NC，发起的 CHI 事务的 Order 为 RequestOrder
- 如果该地址的 PMA 属性是 Memory，但是 PBMT 属性为 IO 或 NC，发起的 CHI 事务的 Order 为 EndpointOrder

无论是 RequestOrder 还是 EndpointOrder，发起的 ReadNoSnp 都需要下游返回 ReadReceipt 来对读操作定序。因此 MMIOBridge 会侦听各个 entry 是否在等待 ReadReceipt（即 ```w_readreceipt``` 是否拉低），如果某个 entry 在等待 ReadReceipt 那么所有 entry 都不能向下发送新的 ReadNoSnp。

## 内存属性

CHI 总线协议定义了如下 4 个维度的内存属性：

- Allocate
- Cacheable
- Device
- EWA (Early Write Acknowledgment)

对于 MMIOBridge 发起的请求，Allocate 和 Cacheable 总是 0；Device 取决于 PMA 属性，如果 PMA 属性为 Memory 则 Device 为 0，否则 Device 为 1；EWA 可以理解为该地址能否被 Buffer，如果该地址的 PMA 属性为 Memory，或者 PMA 属性不是 Memory 但是 PBMT 属性为 NC，则认为该地址可以被 Buffer，EWA 置为 1，否则 EWA 置 0。

## P-Credit 仲裁

MMIOBridge 支持 CHI 总线的协议层重传。根据 CHI 总线协议，一个事务在收到 RetryAck 和 PCrdGrant 后才能发起协议层重传。其中 RetryAck 的 TxnID 和 TXREQ 通道的请求的 TxnID 一致，因此 RetryAck 可以通过 TxnID 和 MMIOBridge 中的 entry 一一对应。然而 PCrdGrant 只要 SrcID 和 PCrdType 两个字段和 RetryAck 一致即可匹配，无法通过 TxnID 直接和 MMIOBridge 中的 entry 做匹配。

基于上述 CHI 协议的规定，CoupledL2 在收到 PCrdGrant 时，无法直接根据 PCrdGrant 的字段判断该 P-Credit 应该仲裁给 MMIOBridge 还是 4 个 Slice，更无法判断如何将 P-Credit 对应到某一项 MMIOBridgeEntry 或某一项 MSHR。因此 P-Credit 的仲裁逻辑位于 CoupledL2 的顶层。当收到 PCrdGrant 时 CoupledL2 会将其暂存在顶层的寄存器中（主要记录 SrcID 和 PCrdType 等关键字段），收到 RetryAck 的 MSHR / MIOBridgeEntry 会用 RetryAck 的 SrcID 和 PCrdType 与 PCrdGrant 寄存器堆进行匹配，如果匹配到，寄存器堆的这一项会被释放，如果没有匹配到会一直等待下游的 PCrdGrant 直到匹配成功。
