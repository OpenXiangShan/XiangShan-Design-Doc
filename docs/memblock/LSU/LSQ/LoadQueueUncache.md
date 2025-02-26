# Uncache Load 处理单元 LoadQueueUncache

| 更新时间   | xiangshan 版本                                                                                                                                               | 更新人 | 备注     |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------ | -------- |
| 2025.02.26 | [eca6983](https://github.com/OpenXiangShan/XiangShan/blob/eca6983f19d9c20aa907987dff616649c3d204a2/src/main/scala/xiangshan/mem/lsqueue/LoadQueueUncache.scala) | 李燕琴 | 完成初版 |
|            |                                                                                                                                                              |        |          |

## 功能描述

// 全局替换：ulq: uncache load 请求

LoadQueueUncache 和 Uncache 模块，对于 uncache load 访问请求来说，起到一个从 LoadUnit 流水线到总线访问的中间站作用。其中 LoadQueueUncache 作为靠近流水线的一方，需要承担以下责任：

1. 接收 LoadUnit 流水线传过来的 ulq 并寄存。
2. 选择候机的 ulq 发送到 Uncache
3. 接收来自 Uncache 的处理完的 ulq
4. 将处理完的 ulq 返回给 LoadUnit

而 Uncache 模块，则作为靠近总线的一方，所起到的作用详见 [Uncache](../Uncache.md "Uncache 处理单元 Uncache")。

其生命周期图如下：

buffer 结构如下

## 整体框图

<!-- 请使用 svg -->

## 接口时序

### XXXX 接口时序实例

### XXXX 接口时序实例

### XXXX 接口时序实例
