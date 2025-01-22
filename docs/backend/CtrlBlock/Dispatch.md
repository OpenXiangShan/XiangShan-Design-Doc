# XiangShan CtrlBlock 设计文档

- 版本：V2R2
- 状态：OK
- 日期：2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## 术语说明

Table: 术语说明

| 缩写 | 全称 | 描述 |
| --- | --- | --- |
| - | renameIn | rename 模块输入的 uop 信息 |
| - | fromRename | rename 模块输出后经过打拍的 uop 信息 |
| - | toRenameAllFire | 所有 uop 分派完成的信号 |
| - | enqRob | 传给 rob 的信号，会在 ctrlblock 打一拍再进入 rob |
| - | IQValidNumVec | IQ 中每个 Exu 对应的指令数量 |
| - | toIssueQueues | 分派给所有 IQ 的 uop 信息 |
| - | XXBusyTable | 寄存器堆状态表 |
| - | wbPregsXX | 写回寄存器堆的信息，用与更新 BusyTable |
| - | wakeUpXX | 快速唤醒的信息，用与推测更新 BusyTable |
| - | og0Cancel | 表示在 og0 阶段，该 uop 被 cancel |
| - | ldCancel | 表示访存 uop 执行到 s3 阶段（s0-s3），该 uop 被 cancel |
| - | fromMem | 来自访存的信号，包括 lsq commit 和 cancel 的数量 |
| - | toMem | 发给访存的信号，包括 lsqEnqIO |

## 子模块列表

Table: 子模块列表

| 子模块 | 描述 |
| --- | --- |
| XXBusyTable | 寄存器堆状态表，包括5个：Int（整数）Fp（浮点）Vec（向量，不含 V0）V0（向量V0）Vl（vcsr 的 vl） |
| rcTagTable | 整数 reg cache（寄存器堆缓存）的 Tag 表 |
| lsqEnqCtrl | 控制进入 load/store queue 指针的模块 |

## 设计规格

- 支持将 uop 按照负载均衡的策略分派给所有 IQ
- 支持更新维护 BusyTable 并在分派时写到 srcState 中
- 支持更新维护进入 lsq 的指针并在分派时写到 lqidx sqidx 中
- 支持 uop 根据顺序进行阻塞
- 支持分派给 IQ 时屏蔽发生异常的指令

## 功能

Dispatch 模块包含各个寄存器堆的 BusyTable、rcTagTable、lsqEnqCtrl，根据写回寄存器堆、快速唤醒、og0Cancel 和 ldCancel 来更新 BusyTable 和 rcTagTable，lsqEnqCtrl 模块则会控制 load/store queue 的入队指针 lqidx/sqidx，当 lsq 容量不足时，会拉低 io_enq_CanAccept 来阻塞分派。

Dispatch 模块在每个时钟周期会将经过 rename 之后的至多 6 个 uop 分派给各个 IQ，所有待分派的 uop 全部分派出去后拉高握手信号 toRenameAllFire，rename 模块收到握手信号后更新下一组 uop 给 Dispatch 模块。

Dispatch 模块在每个时钟周期会统计各个 IQ 中每个 Exu 对应的指令数量，针对每种 fu ，包含它的所有 Exu 所在的 IQ 之间都会进行负载比较，严格按照负载顺序生成分派策略，存到寄存器中。

Dispatch 模块收集 rename 的输入信号和输出打拍后的信号，根据输入信号中的 fuType 计算出每个 uop 之前的 uop（idx 比自己小的）和自己 fu 相同的数量，根据两个信息查表得到分派的IQ，第一个信息是 fu 的类型，第二个信息是在它之前有几个 uop 与自身相同的 fu 类型，根据 IQ 负载从低到高的顺序进行分派，把第一条该 fu 的指令分给负载最低的 IQ，第二条该 fu 的指令分给负载次低的 IQ ，以此类推。

Dispatch 模块会接收各个模块的控制信号来阻塞指令的分派，阻塞原因主要包括：分派到的 IQ 不 ready，分派到同一个 IQ 的指令数量超过了 IQ 的入口数量，rob 不能接收指令，lsq 不能接收指令，该指令之前有指令需要 blockBackward，该指令自身或它之前有指令需要 waitForward。阻塞时按顺序阻塞，一条指令被阻塞，这条指令之后的指令也要一起被阻塞。一旦发生阻塞，toRenameAllFire 就会拉低，需等待阻塞住的指令分派完才能分派下一组指令。

Dispatch 模块会将一些异常情况的指令屏蔽掉（将发送给 IQ 的 valid 置低），不分派给 IQ ，比如该指令译码出现异常，或者该指令被挂了 singleStep 。


## 总体设计

### 整体框图

![整体框图](./figure/dispatch.svg)

### 接口列表

见接口文档

## 模块设计

### 二级模块 BusyTable

#### 功能

BusyTable 模块负责记录寄存器堆繁忙状态，dispatch 的同时需要用 psrc 读 BusyTable 得到源操作数的就绪状态。

每一个寄存器堆对应一个 BusyTable 模块，BusyTable 的项数和寄存器堆保持一致，初始化为 0（空闲状态），当指令经过重命名后，对应的 pdest 信息通过 allocPregs 输入，此时将对应项由 0 变成 1 ；BusyTable 同时接收推测唤醒的信号 wakeUpXX，当被唤醒时，对应项由 1 变成 0 ；推测唤醒的指令有可能会被取消，此时通过 og0Cancel 将对应项由 0 变成 1（可能和 wakeup 是同一拍的，优先级比 wakeup 高），如果是整数的 BusyTable ，还需要额外响应 ldCancel 。

BusyTable 模块的读口数量根据指令集定义的一条指令需要的对应寄存器操作数数量乘以发射宽度，如 6 发射时整数 BusyTable 读口数量 2 * 6 = 12，浮点和向量都是 18 个，V0 和 Vl 是 6 个。

#### 整体框图

![整体框图](./figure/busyTable.svg)

#### 接口列表

见接口文档

### 二级模块 rcTagTable

#### 功能

rcTagTable 是整数寄存器堆缓存的 tag ，和整数的 BusyTable 模块十分相似，读口也是 12 个。


#### 接口列表

见接口文档

### 二级模块 lsqEnqCtrl

lsqEnqCtrl 模块负责维护进入 lsq 的指针，并将 uop 发送给 lsq ，根据每条指令的 needAlloc（ 2 比特，低位拉高表示需要进 load queue，高位拉高表示要进 store queue）和 numLsElem（需要占几项）进行指针的维护，当 io_enq_iqAccept 拉高时（表示 uop 被 IQ 接收）发送给 lsq 。


#### 接口列表

见接口文档
