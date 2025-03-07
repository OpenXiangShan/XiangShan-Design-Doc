# 向量 FOF 指令单元 VfofBuffer

## 功能描述

处理并写回向量 Fault only frist (fof) 指令的修改 VL 寄存器的 uop。对于 fof 指令，我们会额外拆分出单独的负责修改 VL 寄存器的 uop。目前，我们对 fof 指令采取非推测执行的方式。

### 特性 1：收集访存 uop 写回信息

VfofBuffer 负责收集 fof 指令访存 uop 的写回信息，且只有一项。如果需要更新 VL 寄存器，则更新 VfofBuffer 中维护的信息。
当一条 Fault only frist 指令被发射时，除了正常的进入 VLSplit 之外，还会在 vfofBuffer 中分配一项。
这一项会监听来自 VLMergeBuffer 的同 RobIdx 的 uop 的写回，并不会阻止这些 uop 写回后端，只是会收集这些 uop 的相关元数据来更新维护自身的 VL。
VLMergeBuffer 写回至后端的 uop 会携带异常信息与 VL 等，我们需要根据这些写回的信息来判断这个 uop 是否应该导致 VL 发生变化，如果需要 VL 发现变化，则与 VfofBuffer 中维护的 VL 比较，更新为更小的 VL。

### 特性 2：写回修改 VL 寄存器的 uop

VfofBuffer 会在该指令的所有访存 uop 写回之后，再写回修改 VL 寄存器的  uop。
即使不需要修改 VL 寄存器，该 uop 依然会写回，只是不会使能写入信号。

## 整体框图

该模块极为简单，无框图表示。
<!-- 请使用 svg -->

## 主要端口

|                   | 方向 | 说明                              |
| ----------------: | :--- | :-------------------------------- |
|          redirect | In   | 重定向端口                        |
|                in | In   | 接收来自 Issue Queue 的 uop 发射  |
| mergeUopWriteback | In   | 接收 VLMergeBuffer 写回的数据 uop |
|      uopWriteback | Out  | 写回修改 VL 的 uop 至后端         |


## 接口时序

接口时序较简单，只提供文字描述。

|                   | 说明                                          |
| ----------------: | :-------------------------------------------- |
|          redirect | 具备 Valid。数据同 Valid 有效                 |
|                in | 具备 Valid、Ready。数据同 Valid && ready 有效 |
| mergeUopWriteback | 具备 Valid、Ready。数据同 Valid && ready 有效 |
|      uopWriteback | 具备 Valid、Ready。数据同 Valid && ready 有效 |
