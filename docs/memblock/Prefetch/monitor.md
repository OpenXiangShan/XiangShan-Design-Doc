# 预取监视器

| 更新时间   | 代码版本                                                                                                                                                        | 更新人                                      | 备注 |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- | ---- |
| 2025.10.20 | [40f1bc8c](https://github.com/OpenXiangShan/XiangShan/blob/40f1bc8c2cf781adf54bcd6bffe1d1f0d4f338e8/src/main/scala/xiangshan/mem/prefetch/PrefetcherMonitor.scala) | [Maxpicca-Li](https://github.com/Maxpicca-Li/) | v0   |
|            |                                                                                                                                                                 |                                             |      |

## 功能描述

预取监视器负责监控和分析预取器的行为，以便于优化预取策略和提高系统性能。它通过收集和分析预取请求、命中率、Miss率等信息，为预取器的训练和调整提供依据。

## L1 预取监视器之 PrefetcherMonitor

主要用于统计及时性、准确率等指标，并基于指标反馈给预取器进行调整。

### 统计指标

| 指标名称                    | 说明                                       | 现有计算方式                                                           |
| --------------------------- | ------------------------------------------ | ---------------------------------------------------------------------- |
| timely.total\_prefetch      | 预取器发出的总的请求                       | loadpipe.map(\_.io.prefetch\_info.naive.total\_prefetch).reduce(\_     |
| timely.late\_hit\_prefetch  | 预取器发出的请求命中 Cache                 | loadpipe.map(\_.io.prefetch\_info.naive.late\_hit\_prefetch).reduce(\_ |
| timely.late\_miss\_prefetch | 预取器发出的请求命中 MissQueue             | missQueue.io.prefetch\_info.naive.late\_miss\_prefetch                 |
| timely.prefetch\_hit        | 需求请求命中 Cache 预取块                  | PopCount(loadpipe.map(\_.io.prefetch\_info.naive.prefetch\_hit))       |
| validity.good\_prefetch     | 在替换时，Cache 预取块曾被需求访问命中过   | Mainpipe 更新 PrefetchArray 前读出原有预取标识并判定                   |
| validity.bad\_prefetch      | 在替换时，Cache 预取块未曾被需求访问命中过 | Mainpipe 更新 PrefetchArray 前读出原有预取标识并判定                   |

### 预取控制

**（1）控制内容**

* dynamic_depth: stream 从触发的默认值到预取地址的距离，默认为 32；
* flush: 清空预取器的存储内容；
* enable: 启用预取器；
* confidence: 预取器的置信度；

**（2）控制策略**

* 以 `TIMELY_CHECK_INTERVAL` （默认为1000）为一个周期，由预取次数计数。周期末，检查 late_miss_prefetch_cnt 的值，超过 LATE_MISS_THRESHOLD（默认为 200）则将预取深度 dynamic_depth 加倍，最高为 512；检查 late_hit_prefetch_cnt 的值，超过 LATE_HIT_THRESHOLD（默认为 400）则将预取器 enable 置为 false，confidence 置为 0，即低置信度。
* `VALIDITY_CHECK_INTERVAL`（默认为1000）为一个周期，由预取块换出次数计数。周期末，检查 bad_prefetch 的值，超过 BAD_THRESHOLD（默认为400）则将预取深度 dynamic_depth 减半，最低为 1；超过 DISABLE_THRESHOLD（默认为900）则将预取器 flush 置为 true，enable 置为 false，confidence 置为 0，即低置信度。
* `BACK_OFF_INTERVAL`（默认为100000）为一个周期，如果预取器关闭的时钟周期超过该值，则重置预取器的 enable 为 true。
* `LOW_CONF_INTERVAL`（默认为200000）为一个周期，如果预取器的低置信度的时钟周期超过该值，则重置预取器的 confidence 为 1，即高置信度。

> **注意**：当前环境中， dynamic_depth 和 flush 关闭了预取控制，一直为默认值 32 和 false。

## L1 预取监视器之 FDP

### 统计指标

| 指标名称                  | 说明                                                                 | 现有计算方式                                                                            |
| ------------------------- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| refill                    | MissQueue 回填到 DCache 的次数                                       | missQueue.io.main\_pipe\_req.fire                                                         |
| accuracy.total\_prefetch   | MissQueue 分配给预取请求的项数                                       | alloc && io.req.valid && !io.req.bits.cancel && isFromL1Prefetch(io.req.bits.pf\_source) |
| accuracy.useful\_prefetch  | 需求请求命中 Cache 预取块                                            | loadpipe 命中判定                                                                       |
| timely.late\_prefetch      | 预取器发出的请求命中 MissQueue                                       | missQueue 项分派判定                                                                    |
| pollution.demand\_miss     | 首次发出的需求访问缺失                                               | loadpipe 缺失判定                                                                       |
| pollution.cache\_pollution | 首次发出的需求访问缺失，但命中了因预取请求而换出的缓存行布隆过滤器中 | loadpipe 缺失和 bloomFilter 命中判定                                                    |

以 refill 8192 次为一次预取信息统计间隔。

以 1000 条指令提交为一次 rolling 统计间隔。

### 预取控制

当前不做任何预取控制。

## L2 预取监视器之 TopDownMonitor

### 统计指标

**（1）瓶颈**：rob 头部为访存请求，且其物理地址在 L2 Cache 中 miss 而阻塞的周期数。

| 指标名称 | 说明                                                               | 现有计算方式                              |
| :-------: | ------------------------------------------------------------------ | ----------------------------------------- |
| MissMatch | rob 头部为访存请求，且其物理地址在 L2 Cache 中 miss 而阻塞的周期数 | MSHR 中所有项与 robHeadPaddr 进行匹配判定 |

**（2）带宽占比**：统计 L2 Cache MSHR 中 A 通道（发送请求通道）中 demand 缺失请求和 prefetch 缺失请求的周期占比。

| 指标名称                             | 说明                                           | 现有计算方式    |
| ------------------------------------ | ---------------------------------------------- | --------------- |
| XSPerfHistogram.parallel\_misses\_CPU  | L2 Cache MSHR 中 demand 缺失请求的持有周期数   | MSHR 中各项判定 |
| XSPerfHistogram.parallel\_misses\_Pref | L2 Cache MSHR 中 prefetch 缺失请求的持有周期数 | MSHR 中各项判定 |
| XSPerfHistogram.parallel\_misses\_All  | L2 Cache MSHR 中各项缺失的持有周期数           | MSHR 中各项判定 |

**（3）预取**：在返回 dirResult 时统计 A 通道（channel 为 1）的不同来源访问数量、缺失数量；总的需求访问数量、预取发送数量、预取有用数量、预取迟到数量；以及不同预取器的发送数量 `Sent`、有用数量、迟到数量。

| 指标名称                  | 说明                              | 现有计算方式                                 |
| ------------------------- | --------------------------------- | -------------------------------------------- |
| E2\_L2AReqSource\_XXX\_Total | XXX 发起的 A 通道请求数量         | dirResult 判定                               |
| E2\_L2AReqSource\_XXX\_Miss  | XXX 发起的 A 通道请求但缺失的数量 | dirResult 判定                               |
| demandRequest             | 来自 CPU 的请求数量               | dirResult 判定                               |
| l2prefetchSentXXX         | XXX预取器的预取发送数量           | dirResult 判定                               |
| l2prefetchUsefulXXX       | XXX预取器的有用数量               | dirResult 判定                               |
| l2prefetchLateXXX         | XXX预取器的迟到数量               | RequestBuffer 中的请求命中了 MSHR 中的预取项 |

### 预取控制

当前不做任何预取控制。
