# 后端整体介绍

Backend 是香山处理器的后端，其中包括指令译码(Decode)、重命名(Rename)、分派(Dispatch)、调度(Schedule)、发射(Issue)、执行(Execute)、写回(Writeback)和退休(Retire)等多个组件，如 [@fig:backend-overall] 所示。

![后端整体框架](figure/backend.svg){#fig:backend-overall}

## 基本技术规格

- 6 宽度的译码、重命名和分派
  - 224 项整数寄存器堆、192 项浮点寄存器堆、128 项向量寄存器堆
  - Move 指令消除
  - 指令融合
- 160 项的 ROB
  - 支持 ROB 压缩（至多每项 6 个 uop）
  - 每周期最多退休 8 项
  - 快照恢复
- Rename Buffer
  - 256 项 RAB
  - 指令提交和寄存器写回
- 整数、浮点和向量计算
