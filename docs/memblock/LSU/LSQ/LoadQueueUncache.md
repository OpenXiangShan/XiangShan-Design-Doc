# Uncache Load 处理单元 LoadQueueUncache

| 更新时间   | 代码版本                                                                                                                                                     | 更新人 | 备注     |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------ | -------- |
| 2025.02.26 | [eca6983](https://github.com/OpenXiangShan/XiangShan/blob/eca6983f19d9c20aa907987dff616649c3d204a2/src/main/scala/xiangshan/mem/lsqueue/LoadQueueUncache.scala) | [Maxpicca-Li](https://github.com/Maxpicca-Li/) | 完成初版 |
|            |                                                                                                                                                              |        |          |

## 功能描述

LoadQueueUncache 和 Uncache 模块，对于 uncache load 访问请求来说，起到一个从 LoadUnit 流水线到总线访问的中间站作用。其中 Uncache 模块，作为靠近总线的一方，所起到的作用详见 [Uncache](../Uncache.md "Uncache 处理单元 Uncache")。LoadQueueUncache 作为靠近流水线的一方，需要承担以下责任：

1. 接收 LoadUnit 流水线传过来的 uncache load 请求。
2. 选择已准备好 uncache 访问的 uncache load 请求 发送到 Uncache  Buffer。
3. 接收来自 Uncache  Buffer 的处理完的 uncache load 请求。
4. 将处理完的 uncache load 请求 返回给 LoadUnit。

LoadQueueUncache 结构上，目前有 4 项（项数可配）UncacheEntry，每一项独立负责一个请求并利用一组状态寄存器控制其具体处理流程；有一个 FreeList，管理各项分配和回收的情况。而 LoadQueueUncache 主要是协同 4 项的新项分配、请求选择、响应分派、出队等统筹逻辑。

### 特性 1：入队逻辑

LoadQueueUncache 负责接收来自 LoadUnit 0、1、2 三个模块的请求，这些请求可以是 MMIO 请求，也可以是 NC 请求。首先，系统会根据请求的 robIdx 按照时间顺序（从最老到最新）对请求进行排序，以确保最早的请求能优先分配到空闲项，避免特殊情况下因老项回滚（rollback）而导致死锁。进入处理的条件是：请求没有重发、没有异常，并且系统会根据 FreeList 中可分配的空闲项依次为请求分配项。

当 LoadQueueUncache 达到容量上限，且仍有请求未分配到项时，系统会从这些未分配的请求中选择最早的请求进行 rollback。

### 特性 2：出队逻辑

当一个项完成 Uncache 访问操作并返回给 LoadUnit ，或被 redirect 刷新时，则该项出队并释放 FreeList 中该项的标志。同一拍可能有多个项出队。返回给 LoadUnit 的请求，会在第一拍中选出，第二拍返回。

其中，可供处理 uncache 返回请求的 LoadUnit 端口是预先设定的。当前，MMIO 只返回到 LoadUnit 2；NC 可返回到 LoadUnit 1\2。在多个端口返回的情况下，利用 uncache entry id 与端口数的余数，来指定每个项可以返回到的 LoadUnit 端口，并从该端口的候选项中选择一个项进行返回。

### 特性 3：Uncache 交互逻辑

（1）发送 `req`

第一拍先从当前已准备好 uncache 访问中选择一个，第二拍将其发送给 Uncache Buffer。发送的请求中，会标记选中项的 id，称为 `mid` 。其中是否被成功接收，可根据 `req.ready` 判断。

（2）接收 `idResp`

如果发送的请求被 Uncache Buffer 接收，那么会在接收的下一拍收到 Uncache 的 `idResp`。该响应中，包含 `mid` 和 Uncache Buffer 为该请求分配 entry id（称为 `sid`）。LoadQueueUncache 利用 `mid` 找到内部对应的项，并将 `sid` 存储在该项中。

（3）接收 `resp`

待 Uncache Buffer 完成该请求的总线访问后，会将访问结果返回给 LoadQueueUncache。该响应中，包含 `sid`。考虑到 Uncache Buffer 的合并特性（详细入队合并逻辑见 [Uncache](../Uncache.md)），一个 `sid` 可能对应 LoadQueueUncache 的多个项。LoadQueueUncache 利用 `sid` 找到内部所有相关项，并将访问结果传递给这些项。

## 整体框图

<!-- 请使用 svg -->

![LoadQueueUncache 整体框图](./figure/LoadQueueUncache.svg)

## 接口时序

### XXXX 接口时序实例

### XXXX 接口时序实例

### XXXX 接口时序实例

## UncacheEntry 模块

UncacheEntry 负责独立处理一个请求的生命周期，并利用一组状态寄存器来控制其具体的处理流程。关键结构如下：

* `req_valid`：表示该项是否有效。
* `req`：存储收到的请求的所有相关内容。
* `uncacheState`：记录该项当前的生命阶段。
* `slaveAccept`、`slaveId`：记录该项是否分配到 Uncache Buffer 以及分配的 UnCache Buffer ID。
* `needFlushReg`：指示该项是否需要延迟刷新。


### 特性 1：生命周期及状态机

每一个 UncacheEntry 的生命周期可以由 `uncacheState` 完全描述。其中包括以下几个状态：

* `s_idle`：默认状态，表示没有请求，或者请求存在但尚不具备发送到 Uncache Buffer 的条件。
* `s_req`：表示当前已经具备将请求发送到 Uncache Buffer 的条件，静待被 LoadQueueUncache 选中，并由其中间寄存器接收（理论上应由 Uncache Buffer 接收，但在 LoadQueueUncache 选中后，会先将请求存放一拍，再发送给 Uncache Buffer；若未被 Uncache Buffer 接收，则会继续寄存在中间寄存器中）。对于 UncacheEntry 来说，它并不感知中间寄存器的存在，它只知道请求已发送且成功接收。
* `s_resp`：表示该请求已被中间寄存器接收，静待 Uncache Buffer 返回访问结果。
* `s_wait`：表示已经收到 Uncache Buffer 的访问结果，静待被 LoadQueueUncache 选中并由 LoadUnit 接收。

状态转换图如下，其中黑色标识该项正常生命周期，红色标识由于 redirect 需要刷新该项而导致该项生命周期非正常结束。

![UncacheEntry 有限状态机示意图](./figure/LoadQueueUncache-Entry-FSM.svg)

对于正常的生命周期，各个触发事件详细说明如下：

* `canSendReq`: 对于 MMIO 请求，当其对应的指令到达 ROB 头部时，则可发送该 Uncache 访问。对于 NC 请求，当 `req_valid` 有效时，则可发送该 Uncache 访问。
* `uncacheReq.fire`: 该项被 LoadQueueUncache 中间寄存器接收。该项会在下一拍收到 Uncache Buffer 传递来的 `idResp`，并更新 `slaveAccept` 和 `slaveId`。
* `uncacheResq.fire`: 该项收到的 Uncache Buffer 返回的访问结果。
* `writeback`: 当处于 `s_wait` 状态时，则可以发送写回请求。其中 MMIO 请求和 NC 请求的写回信号不一样，需要区分。

### 特性 2：redirect 刷新逻辑

对于非正常生命周期的情况，通常由流水线 redirect 引起。

当接收到流水线 redirect 信号时，判断当前项是否比 redirect 项更新。如果当前项更新，则需要刷新该项，并产生 `needFlush` 信号。一般情况下，会立即刷新该项所有内容，并由 FreeList 回收该项。但 Uncache 的请求和响应需要完整对应到同一个 uncache load 请求，故如果此时该项已经发出了 uncache 请求，需要等待接收到 Uncache 回复时才能结束该项的生命周期，此时产生了“刷新延迟”的情况。因此，在 `needFlush` 信号产生时，如果不能立即刷新该项，则需要将该信号存储到 `needFlushReg` 寄存器中。等到接收到 Uncache 回复时，才会执行刷新操作，并清除 `needFlushReg。`

### 特性 3：异常情况

LoadQueueUncache 中的异常情况有：

1. 该请求发往总线时，总线返回 corrupt 或 denied 的情况。该异常需要在 UncacheEntry 写回时进行标记，并由 LoadUnit 处理。
