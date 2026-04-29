# 向量访存

## 子模块列表

| 子模块                               | 描述                                             |
| --------------------------------- | ---------------------------------------------- |
| [VLSplit](VLSplit.md)             | Vector Load uop 拆分模块                           |
| [VSSplit](VSSplit.md)             | Vector Store uop 拆分模块                          |
| [VLMergeBuffer](VLMergeBuffer.md) | Vector Load flow 合并模块                          |
| [VSMergeBuffer](VSMergeBuffer.md) | Vector Load flow 合并模块                          |
| [VSegmentUnit](VSegmentUnit.md)   | Vector Segment 执行模块                            |
| [VfofBuffer](VfofBuffer.md)       | Vector fault only first 指令写回 VL 寄存器 uop 收集写回模块 |


## 功能描述

- 支持 RVV 1.0 完整全部访存指令
- 支持乱序调度 Vector Load/Store 指令
- 支持乱序执行 Vector Load/Store 指令拆分的 Uop
- 支持向量乱序违例检查与恢复
- 支持 非对齐向量访存
- 不支持非 Memory 空间的向量访存

### 参数配置

|       参数       | 配置(项数) |
| :------------: | :----: |
|      VLEN      |  128   |
| VLMergeBuffer  |   16   |
| VSMergeBuffer  |   16   |
| VSegmentBuffer |   8    |
|   VFOFBuffer   |   1    |

### 功能概述

在进入 VLSIssueQueue 前，会在 Dispatch 阶段对 Load Queue 或 Store Queue 的 Index 进行分配。
向量访存指令在后端被拆分为 uop 后，会首先在 Vsplit 模块中进行译码、计算 mask 和地址偏移，同时也会申请 Mergebuffer 表项。
在新向量访存架构中，会复用标量的 LoadUnit & StoreUnit，以及 Load Queue & Store Queue。

向量 Load 与 Store 共用两个 Issue Queue。 对于向量 Load，两个 Issue Queue 对接两个 VLSplit。 对于向量
Store 两个 Issue Queue 对接两个 VSSplit。 两个 VLSplit 分布对应 LoadUnit0、LoadUnit1。 两个
VSSplit 分布对应 StoreUnit0、StoreUnit1。 当向量 Load 需要 Replay
Queue重发时，可能会被重发到其他loadunit上。在向量访存从pipe执行完毕后，会由mergebuffer汇总并写回。


## 整体框图

整体框图待更新
<!-- 请使用 svg -->
