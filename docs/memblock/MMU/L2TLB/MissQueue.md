# 三级模块 Miss Queue

Miss Queue 指的是如下模块：

* L2TlbMissQueue missQueue

## 设计规格

1. 缓冲请求等待资源

## 功能

### 缓冲请求等待资源

Miss Queue 的本质是一个队列，接收来自 Page Cache 和 Last Level Page Table Walker 的请求，发送给 Page Cache。当 Page Cache 发送给 PTW 但请求是 isFirst 或者 PTW busy，则发送给 Miss Queue，当 Page Cache 发送给 LLPTW 但 LLPTW busy，则发送给 Miss Queue。

## 整体框图

Miss Queue 的整体结构较为简单，不再赘述。关于 Miss Queue 与其他 L2 TLB 中模块的连接关系，参见 5.3.3 节。

## 接口时序

Miss Queue 的本质是一个队列，接口时序比较简单，不再赘述，
