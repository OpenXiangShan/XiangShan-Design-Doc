# Scheduler

- 版本：V2R2
- 状态：OK
- 日期：2025/01/15
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

不同种类的 Scheduler 及其策略的描述等。

Scheduler 模块的主要作用是将IQ包装起来连接 Dispatch 模块和 DataPath模块，共有
intScheduler、fpScheduler、vfScheduler、memScheduler
四个，分别对应整数、浮点、向量、访存（包括标量访存和向量访存），特别需要注意的是在 memScheduler 内对 sta 和 std 两种 IQ 的
ready 做了与操作后传给了 Dispatch，Disptch 会根据 IQ 的 ready 状态回 valid，如果 IQ 不 ready 那
Dispatch 给 IQ enq 的 valid 会拉低。
