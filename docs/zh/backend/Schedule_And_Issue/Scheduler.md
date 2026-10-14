# Scheduler

- 版本：V2R2A
- 状态：OK
- 日期：2026/10/13
- commit：[XSAI e8fb1a14](https://github.com/OpenXiangShan/XSAI/tree/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f)

## 功能

Scheduler 将 IQ 包装起来，连接 Dispatch 与 DataPath。XSAI 启用矩阵扩展后有 intScheduler、fpScheduler、vfScheduler、mfScheduler 和 memScheduler 五类。mfScheduler 与整数、浮点和向量调度器一样复用 SchedulerArithImp，采用已有的入队、年龄选择、唤醒、取消和出队反馈机制。

Table: 调度器分工

| 调度器 | 主要指令 |
| ------ | -------- |
| Int | 整数、CSR、Fence、规模写、mrelease、mcfg |
| Fp | 标量浮点 |
| Vf | 向量计算与向量配置 |
| Mf | 规模读取、MMA、mzero 控制请求 |
| Mem | 标量、向量和矩阵访存 |

MemScheduler 对 sta、std 两种 IQ 的 ready 做与操作后传给 Dispatch。Dispatch 根据 IQ 的 ready 状态返回 valid，IQ 不 ready 时不会拉高其入队 valid。

## 矩阵调度资源

默认 MfScheduler 有两个 IQ，每个 16 项、2 个入队口、12 个复杂项。第一个 IQ 包含 MSET1，读取 mx 规模并写整数目的；第二个包含 MEX0 和 MEX1，分别生成 MMA 与矩阵算术请求。MSET0、MRELEASE 位于 IntScheduler，MLSU0 位于 MemScheduler。

MfScheduler 按配置监听整数和 mx 写回。MMA 等待三个规模源 ready，MemScheduler 中的普通 MLS 等待地址、stride 和两个规模源 ready。mx 写回有当拍与延迟两组唤醒接口，供发射队列的相应阶段使用。Mcfg 原始配置作为指令元数据随队列保存。

来自 CtrlBlock 的 flush、DataPath 的 OG0/OG1 取消和标量 load dependency 取消均接入 MfScheduler。LdExuCnt 统计包括 MLSU 在内的访存执行资源；LdWakeupCnt、LdPfTrainCnt 统计产生标量 load 结果的标量 load 与混合访存单元。

实现见 [Scheduler.scala](https://github.com/OpenXiangShan/XSAI/blob/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f/src/main/scala/xiangshan/backend/issue/Scheduler.scala)。
