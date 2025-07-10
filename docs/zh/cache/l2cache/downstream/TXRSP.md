# TXRSP

## 功能描述
TXRSP 模块接收来自 MainPipe 和 MSHR 两个模块发往 TXRSP 通道的请求，在两者之间进行仲裁，并用队列进行缓冲，最终发送到 CHI 的 TXRSP 总线通道上。其中来自 MainPipe 出口的请求会被无条件接收，来自 MSHR 的请求有可能会被阻塞。因此 TXRSP 模块需要对 MSHR 进行反压，同时对 MainPipe 入口进行流控，以保证 MainPipe 上的请求能够不被阻塞地进入 TXRSP。

### 特性1：对 MainPipe入口的流控
1. 为了保证 MainPipe 上的请求能够非阻塞地在 s3/s4/s5 进入 TXRSP，当【MainPipe 上有可能需要进入 TXRSP 的请求数 + 队列中的有效项数 ≥ 队列总项数】时，TXREQ 模块需要对 MainPipe 入口即 s0/s1 级进行反压。
2. 其中，对 s1 级反压是因为 RXSNP 收到的 snoop 可能会直接在 MainPipe 上完成处理，然后进入 TXRSP 通道，所以需要对 s1 的 sinkB 请求做反压；对 s0 级反压是因为一部分 MSHR task 需要进入 TXRSP 通道，MSHR task 是在 s0 进入流水线的，所以需要对 s0 的 mshrTask 做反压。
姑且将阻塞条件记为 noSpace。

### 特性2：对 MSHR 的反压逻辑
1. MainPipe 的仲裁优先级大于 MSHR，所以 MainPipe 出口的请求有效时，需要给 MainPipe 反压。
2. 当 noSpace 的时候需要给 MainPipe 反压，原因如下：
MSHR 发出请求的当拍 MainPipe 可能没有请求和 MSHR 竞争，但是 MainPipe 中有请求还在 s1/s2 级，MSHR 请求有可能抢占了队列中本属于 MainPipe 的空闲项，导致 MainPipe 中的请求到达 s3/s4/s5 级时队列项数不够。所以这种情况也需要阻塞住 MainPipe 的请求。

## 整体框图
![TXRSP](./figure/TXRSP.svg)

