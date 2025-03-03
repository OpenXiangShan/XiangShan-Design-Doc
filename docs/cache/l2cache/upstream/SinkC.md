# SinkC

## 功能描述
SinkC接收来自总线C通道的请求(Release/ReleaseData/ProbeAck/ProbeAckData)，内部Buffer深度为3，用valid/ready握手协议阻塞C通道，进行如下操作：
a.如果请求是 Release(Data)，则为其分配一个 buffer项保存，等到流水线可以接收C请求的时候，就发往RequestArb进入主流水线；
  如果包含数据，则延迟两拍在请求进入到S3的时候将其数据发送给MainPipe；
b.如果请求是ProbeAckData，则直接向MSHR发送反馈，同时将其数据写入ReleaseBuf 中。

### 特性1：RefillBuffer覆盖
因为目前缺失重填操作会首先将数据返回给L1，然后再安排重填数据（在RefillBuf中）写入L2的DataStorage，二者之间存在一个时间差。
如果在此期间L1就将脏数据释放下来，为了保证写入L2的最新数据，我们就让ReleaseData也将其数据同步写入一份到RefillBuf中，覆盖原有的重填数据。

### 特性2：ReleaseBuffer覆盖
当MSHR处理一笔release需要probe L1D$时，这笔probeAckData查找匹配到MSHR中的这笔release后，会主动把数据写入到ReleaseBuf中。

## 整体框图
