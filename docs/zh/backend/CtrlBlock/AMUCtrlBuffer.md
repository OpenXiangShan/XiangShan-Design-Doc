# AmuCtrlBuffer

- 版本：V2R2A
- 状态：OK
- 日期：2026/10/13
- commit：[XSAI ee268923](https://github.com/OpenXiangShan/XSAI/tree/ee268923b7175d79a9d0183a0181a684ccec9487)

## 术语说明

Table: 术语说明

| 名称 | 描述 |
| ---- | ---- |
| AMU | 矩阵加速单元控制接口 |
| amuCtrl | 矩阵运算、访存、清零或 release 的控制请求 |
| needAMU | 该项是否需要向 CUTE 发送控制请求 |
| canDeq | 该项已完成本缓冲所需的处理，可以回收 |

## 设计规格

- 与 ROB 并行，容量为 RobSize，使用相同的分配索引。
- 同步接收 ROB 分配、写回、提交和重定向信息。
- 只有已写回且已提交的矩阵控制请求才能发送到 CUTE。
- CUTE 不能接收请求时，保存请求并向 ROB 分配形成背压。
- 输出有 CommitWidth 个候选通道，由 XSCore 固定优先级仲裁器汇聚为单通道。

## 功能

控制核中的矩阵功能单元完成参数检查和控制信息生成，将 amuCtrl 写回 AmuCtrlBuffer。缓冲保存请求，等待对应指令从 ROB 正常提交后，再通过 ready/valid 握手发送到 CUTE。参数检查可在控制核中乱序执行，CUTE 按提交后的请求执行矩阵操作。

ROB 提交时设置请求的 committed 状态，CUTE 背压期间请求继续保存在缓冲中。握手后，CUTE 接收请求并执行对应任务。软件通过 mrelease / macquire 等待更老 Store 及其依赖链完成，无关 Load / Compute 可以继续在途，详见 [Release 的同步语义](../../cute/TaskController.md#sec:cute-release)。

## 整体框图

![AmuCtrlBuffer](./figure/xsai-amu-buffer.svg){width=85%}

## 表项

Table: AmuCtrlEntry 信号列表

| 信号 | 描述 |
| ---- | ---- |
| valid | 已分配该项 |
| needAMU | 需要发送 AMU 控制请求 |
| writebacked | 控制信息已写回 |
| committed | 对应 ROB 项已提交 |
| amuCtrl | 待发送的控制信息 |
| canDeq | 已完成处理，可以按序回收 |

每个有效 ROB 分配都在缓冲中占位，包括普通非矩阵指令。非矩阵指令提交时直接设置 canDeq；矩阵指令需等待控制请求握手后设置 canDeq。

## 分配与写回

分配使用 ROB 的 allocatePtr。只有 ROB 接收了该指令且没有重定向时，才清零并分配对应缓冲项。写回根据 robIdx.value 匹配表项，保存 amuCtrl 并设置 writebacked。启用 DiffTest 时，在缓冲中补入该指令的 PC 和 coreid。

缓冲根据有效项数和当前请求数判断容量。ROB 入队预留 RenameWidth 项，提前反馈给 Dispatch 的条件预留 2×RenameWidth 项，两个接收条件均寄存后输出。

## 提交与发送

ROB 正常提交后设置 committed。发送请求的条件为：

```text
valid && needAMU && writebacked && committed && !canDeq
```

从缓冲出队指针开始选择 CommitWidth 个候选项。XSCore 的固定优先级仲裁器优先选择较老的有效请求，因此每周期至多向 CUTE 发送一个请求。请求 fire 后设置 canDeq，下一次按序回收时释放该项。

出队指针按连续 canDeq 项的数量推进，每周期最多回收 CommitWidth 项。已提交的普通指令占位与已完成握手的矩阵项均参与按序回收。

## 重定向与异常

重定向时，缓冲根据 ROB 给定的环形区间直接清除受影响项。已经提交、仍等待 CUTE 的较老请求保留，CUTE 中已接受的任务继续执行。

矩阵指令的参数非法或访存异常通过异常通路进入 ROB。发生异常的指令在重定向时清除其控制信息。矩阵寄存器的保存恢复与已提交任务的完成同步由软件协议处理。

实现见 [AMUCtrlBuffer.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/backend/rob/AMUCtrlBuffer.scala)。
