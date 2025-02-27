# Uncache 处理单元 Uncache

| 更新时间   | 代码版本                                                                                                                                             | 更新人                                      | 备注     |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- | -------- |
| 2025.02.26 | [eca6983](https://github.com/OpenXiangShan/XiangShan/blob/eca6983f19d9c20aa907987dff616649c3d204a2/src/main/scala/xiangshan/cache/dcache/Uncache.scala) | [Maxpicca-Li](https://github.com/Maxpicca-Li/) | 完成初版 |
|            |                                                                                                                                                      |                                             |          |

## 功能描述

Uncache 作为LSQ和总线的桥梁，主要用于处理 uncache 访问到总线的请求和响应。目前 Uncache 不支持向量访问、非对齐访问、原子访问。

Uncache 的功能概述如下：

1. 接收 LSQ 传过来的 uncache 请求，包括 LoadQueueUncache 传来的 uncache load 请求 和 StoreQueue 传来的 uncache store 请求
2. 选择候机的 uncache 请求发送到总线，等待并接收总线回复
3. 将处理完的 uncache 请求返回给 LSQ
4. 前递寄存的 uncache store 请求的数据给 LoadUnit 中正在执行的 load

Uncache Buffer 结构上，目前有 4 项（项数可配）Entries 和 States，一个总的状态 `uState`。下列为各项具体细节。

Uncache 的 Entry 结构如下：

* `cmd`：标识请求是 load 还是 store，当前版本0为load，1为store。
* `addr`：请求物理地址。
* `vaddr`：请求虚拟地址。主要用于前递时判断虚实地址是否 match
* `data`：store 要写入的数据，或 load 要读取的数据，目前仅支持 64 bits 以内的数据访问。
* `mask`：请求访问掩码，每 byte 使用一位来表示当前有没有数据，共 8 位。
* `nc`：请求是否是 NC 访问。
* `atomic`：请求是否是原子访问。
* `memBackTypeMM`：请求所访问的地址，是否是 PMA 为 main memory 类型，但 PBMT 为 NC 类型。主要用于 L2 Cache NC 相关逻辑。
* `resp_nderr`：总线告知 Uncache，该请求是否能处理。

Uncache 的 State 结构如下：

* `valid`：该项是否有效。
* `inflight`：1 表示该项请求已经发往总线。
* `waitSame`：1 表示当前 buffer 里存在与该项请求所访问数据块重合的其他请求，已经发往总线。
* `waitReturn`：1 表示该项的请求已经接收到总线回复，等待写回 LSQ。

Uncache 的 `uState`，表征忽视 outstanding 时一个请求项的各个状态：

* `s_idle` 默认状态
* `s_inflight` 已经发送了一个请求到总线上，但还未收到回复
* `s_wait_return` 已经收到回复，但还未返回给 LSQ

状态转换如下：

![ustate 状态转换示意图](./figure/Uncache-uState.svg)

### 特性 1：入队逻辑

（1）每一拍最多处理 1 个从 LSQ 发来的请求，然后检查请求是否能进入 Buffer，若能，则检查是合并到老项还是分配新项。该请求的入队行为有：

1. 分配新项，标记 valid

   1. 无相同块地址项
2. 分配新项，标记 valid 和 waitSame

   1. 有相同块地址项：满足首要合并条件，不满足次要合并条件。
3. 合并到老项

   1. 有相同块地址项：满足首要合并条件，满足次要合并条件。
4. 拒绝

   1. ubuffer 满
   2. 有相同块地址项：不满足首要合并条件

其中，块地址，即 blockAddr，为每 8 Bytes 的起始地址。首要合并条件指，来项和老项均为 NC 访问、各个属性相同、与老项合并后的 mask 满足连续且自然对齐、且该项当拍没有**正在或已经**完成了总线访问。次要合并条件是指老项有效、还没有发送总线访问、也没有当拍被选中发往总线访问（因为如果一旦正在或已经发往总线，总线请求已经无法更改，只能分配新项，等待老项收到总线请求后再发送该请求）。

另外，分配新项，会设置 entry 的各个内容；合并老项，会更新 mask，data, addr 等内容。其中 addr 更新需要保证自然对齐。

> 由于总线访问不一定保序，尤其是 outstanding 时，总线上会同时处理多个 uncache 访问请求。故相同地址的请求不能同时出现在总线中，以保证该地址数据块的被访问顺序。故只有新项满足首要和次要的合并条件，才能合并到老项。

（2）下一拍，返回所分配的 Uncache Buffer 项目 ID。由 LoadQueueUncache 或 StoreQueue 保管该 ID，用于映射 uncache 返回的 resp。因为 Uncache Buffer 有合并功能，即其返回的 resp 可能对应 LoadQueueUncache 中的多个项。

### 特性 2：出队逻辑

从当拍已经完成总线访问的项（即状态高位有 `valid` 和 `waitReturn`）中，选择一项，返回给 LSQ，并清除所有 state 标识位。

### 特性 3：总线交互和 outstanding 逻辑

总线交互和 outstanding 逻辑分以下两个部分：

（1）发起请求

无 outstanding 时，仅当 `ustate` 为 `s_idle` 时才能发送请求到总线上。从各个项中选出一个目前可以发往总线的请求，即各状态位仅 `valid` 置 1 ，发往总线。有 outstanding 时，可无视 `ustate` 即选择请求项，并发往总线。其中 `source` 位为该请求项的 id。

当请求发往总线时，需要遍历请求项，将相同块地址的其他项的 `waitSame` 置位。

（2）收到回复

当收到总线回复时，根据 `source` 位确定该请求对应的 buffer 项，更新数据并置位 `waitReturn`。

此外，需要遍历请求项，将当前相同块地址的 `waitSame` 清除。

### 特性 4：前递逻辑

理论需求上，前递逻辑主要针对 NC 访问。当开启 outstanding 时，uncache NC store 从 StoreQueue 成功写入 Uncache Buffer 后，StoreQueue 便会将该项出队，不在维护。故此时的 Uncache Buffer 将承担前递该 store 数据的责任。由于 Uncache Buffer 的入队逻辑存在合并，同一时间，相同地址在 Uncache Buffer 中最多出现 2 项。若出现 2 项，其中一项一定为 `inflight`，另一项一定为 `waitSame`。因为 StoreQueue 的顺序出队，前者数据更老，后者数据更新。

实际处理上，当 uncache NC load 向 Uncache Buffer 发起前递请求时，Uncache 会比较现有项的块地址，有可能会找到匹配的项，这个项可能是已经发往总线的，也可能是还未发往总线的。前者数据更老，后者数据更新即优先级更高。在第一拍 `f0` 主要进行虚拟块地址匹配，以在当拍返回 `forwardMaskFast`，在第二拍 `f1` 进行的物理块地址匹配和数据合并，并返回结果。

### 特性 5：刷新逻辑

刷新，是指将 Uncache Buffer 内的所有项全部完成总线访问并返回给 LSQ 后才能接受新项的进入。当产生 fence \ atomic \ cmo 或前递出现虚实地址不匹配时，会刷新 Uncache Buffer。此时 `do_uarch_drain` 置位，不再接受新项的进入。当所有项都完成任务后，`do_uarch_drain` 清除，开始正常接受新项的进入。

## 整体框图

<!-- 请使用 svg -->

![ubuffer整体框图](./figure/Uncache.svg)

## 接口时序

// TODO

### XXXX 接口时序实例

### XXXX 接口时序实例

### XXXX 接口时序实例
