# IPrefetchPipe 子模块文档

IPrefetchPipe 为预取的流水线，为两级流水设计，负责预取请求的过滤。

![IPrefetchPipe 结构](../figure/ICache/IPrefetchPipe/iprefetchpipe_structure.png)

## S0 流水级

在 S0 流水级，接收来自 FTQ/后端的预取请求，向 MetaArray 和 ITLB 发送读请求。

## S1 流水级

首先接收 ITLB 的响应得到 paddr，然后与 MetaArray 返回的 tag 进行比较得到命中信息，将元数据（命中信息`waymask`、ITLB
信息`paddr`/`af`/`pf`）写入 WayLookup。同时进行 PMP 检查，将结果寄存到下一级流水。

由状态机进行控制：

- 初始状态为 `idle`，当 S1 流水级进入新的请求时，首先判断 ITLB 是否缺失，如果缺失，就进入 `itlbResend`；如果 ITLB
  命中但命中信息未入队 WayLookup，就进入 `enqWay`；如果 ITLB 命中且 WayLookup 入队但 S2 请求未处理完，就进入
  `enterS2`
- 在 `itlbResend` 状态，重新向 ITLB 发送读请求，此时占用 ITLB 端口（即新的进入 S0
  流水级的预取请求被阻塞），直至请求回填完成，在回填完成的当拍向 MetaArray 再次发送读请求，回填期间可能发生新的写入，如果 MetaArray
  繁忙（正在被 MSHR 写入），就进入 `metaResend`，否则进入 `enqWay`
- 在 `metaResend` 状态，重新向 MetaArray 发送读请求，发送成功后进入 `enqWay`
- 在 `enqWay` 状态，尝试将元数据入队 WayLookup，如果 WayLookup 队列已满，就阻塞至 WayLookup 入队成功，另外在
  MSHR 发生新的写入时禁止入队，主要是为了防止写入的信息与命中信息所冲突，需要对命中信息进行更新。当成功入队 WayLookup 时，如果 S2
  空闲，就直接回到 `idle`，否则进入 `enterS2`
  - 若当前请求是软件预取，不会尝试入队 WayLookup，因为该请求不需要进入 MainPipe/IFU 乃至被执行
- 在 `enterS2` 状态，尝试将请求流入下一流水级，流入后回到 `idle`

![IPrefetchPipe S1 状态机](../figure/ICache/IPrefetchPipe/iprefetchpipe_s1_fsm.png)

## S2 流水级

综合该请求的命中结果、ITLB 异常、PMP 异常，判断是否需要预取，只有不存在异常时才进行预取，因为同一个预测块可能对应两个 cacheline，所以通过
Arbiter 依次将请求发送至 MissUnit。

## 命中信息的更新 {#sec:IPrefetchPipe-hit-update}

在 S1 流水级中得到命中信息后，距离命中信息真正在 MainPipe 中被使用要经过两个阶段，分别是在 IPrefetchPipe 中等待入队
WayLookup 阶段和在 WayLookup 中等待出队阶段，在等待期间可能会发生 MSHR 对 Meta/DataArray 的更新，因此需要对 MSHR
的响应进行监听，分为两种情况：

1. 请求在 MetaArray 中未命中，监听到 MSHR 将该请求对应的 cacheline 写入了 SRAM，需要将命中信息更新为命中状态。
2. 请求在 MetaArray 中已经命中，监听到同样的位置发生了其它 cacheline 的写入，原有数据被覆盖，需要将命中信息更新为缺失状态。

为了防止更新逻辑的延迟引入到 DataArray 的访问路径上，在 MSHR 发生新的写入时禁止入队 WayLookup，在下一拍入队。
