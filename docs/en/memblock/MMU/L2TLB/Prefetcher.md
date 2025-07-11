# 三级模块 Prefetcher

Prefetcher 指的是如下模块：

* L2TlbPrefetch prefetch

## 设计规格

1. 支持 Next-line 预取算法
2. 支持过滤重复的历史请求

## 功能

### 发出预取请求

当满足如下两种情况之一时会发出预取请求：

1.  Page Cache 发生 miss
2.  Page Cache hit，但命中的是预取项

Prefetcher 采用 Next-Line 预取算法，预取结果会保存在 Page Cache 中，并不会返回给 L1 TLB。由于 Page Table
Walker 的访存能力较弱，预取请求并不会进入 Page Table Walker 或 Miss
Queue，而是会被直接丢弃。当预取请求只差最后一级页表缺失时，可以访问 LLPTW。同时，在 Prefetcher 中添加了 Filter
Buffer，可以起到过滤重复的预取请求的目的。

### 过滤重复的历史请求

为避免重复的请求浪费 L2 TLB 的资源，同时提高 Prefetcher 的利用率，当满足 5.3.11.2
节描述的两种情况，发出预取请求时，会判断相同地址的预取请求是否已经发出，如果发出则丢弃新收到的预取请求。当前 Prefetcher 模块会过滤最近的 4
条请求。

## 整体框图

Prefetcher 的整体框图如 [@fig:MMU-prefetcher-overall] 所示。当 Page Cache 发生 miss 或 Page
Cache hit，但命中的是预取项时，会产生预取请求。通过 Filter Buffer 可以过滤重复的预取请求。

![Prefetcher 的整体框图](../figure/image44.png){#fig:MMU-prefetcher-overall}

## 接口时序

Prefetcher 是一个 next-line 预取器，接口时序较为简单，这里不再赘述。

