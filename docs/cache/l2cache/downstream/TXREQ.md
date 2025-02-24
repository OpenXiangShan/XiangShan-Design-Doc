# TXREQ

## 功能描述
TXREQ 模块接收来自 MainPipe 和 MSHR 两个模块发往 REQ 通道的请求，在两者之间进行仲裁，并用队列进行缓冲，最终发送到 CHI 的 TXREQ 总线通道上。来自 MainPipe 出口的请求会被无条件接收，来自 MSHR 的请求有可能会被阻塞。因此 TXREQ 模块需要对 MSHR 进行反压，同时对 MainPipe 入口进行流控，以保证 MainPipe 上的请求能够不被阻塞地进入 TXREQ。

## 关键电路
### 1.对MainPipe入口流控
为了保证 MainPipe 上的请求能够非阻塞地在 s3/s4/s5 进入 TXREQ，当【MainPipe上有可能需要进入TXREQ 的请求数 + 队列中的有效项数 ≥ 队列总项数】时，TXREQ 模块需要对 MainPipe 入口即 s0 级进行反压（由于只有 MSHR 才会往下游 TXREQ 发送请求，MSHR task 是从 s0 进入流水线的，所以只需要对 s0 的 MSHR 请求做反压）。
姑且将阻塞条件记为 noSpace。

### 2.对MSHR的反压
1. MainPipe 的仲裁优先级大于 MSHR，所以 MainPipe 出口的请求有效时，需要给 MainPipe 反压。
2. 当 noSpace 的时候需要给 MainPipe 反压，原因如下：
MSHR 发出请求的当拍 MainPipe 可能没有请求和 MSHR 竞争，但是 MainPipe 中有请求还在 s1/s2 级，MSHR 请求有可能抢占了队列中本属于 MainPipe 的空闲项，导致 MainPipe 中的请求到达 s3/s4/s5 级时队列项数不够。所以这种情况也需要阻塞住 MainPipe 的请求。

## 整体框图
![TXREQ 整体框图] (./figure/TXREQ.svg)
