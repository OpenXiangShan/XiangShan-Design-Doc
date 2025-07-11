# TXDAT

## 功能描述
TXDAT 模块无条件接收来自 MainPipe 发往 WDAT 通道的请求，并用队列进行缓冲，最终发送到 CHI 的 TXDAT 总线通道上。 TXDAT
模块需要对 MainPipe 入口进行流控，以保证 MainPipe 上的请求能够不被阻塞地进入 TXDAT。

## 功能描述
### 特性1：对MainPipe的反压
为了保证 MainPipe 上的请求能够非阻塞地在 s3/s4/s5 进入 TXDAT，当【MainPipe 上有可能需要进入 TXDAT 的请求数 +
队列中的有效项数 ≥ 队列总项数】时， TXDAT 模块需要对 MainPipe 入口即 s0/s1 级进行反压。
1. 对 s1 级反压是因为 RXSNP 收到的 snoop 可能会直接在 MainPipe 上完成处理，然后进入 TXDAT 通道，所以需要对 s1 的
   sinkB 请求做反压
2. 对 s0 级反压是因为一部分 MSHR task 需要进入 TXDAT 通道，MSHR task 是在 s0 进入流水线的，所以需要对 s0 的
   mshrTask 做反压

![TXDAT](./figure/TXDAT.svg)
