# 向量 Load 合并单元 VLMergeBuffer

## 功能描述

一个基于 freelist 的队列，接收 VLSplit 模块发来的请求，为后端发射的每一个 uop 申请一个表项，保存 uop 的相关信息，收集从 Load
pipeline 上返回的数据，接收该 uop 拆分的全部访存请求之后写回后端与 Load Queue。

### 特性 1：维护 uop 的拆分访存请求

在 VLSplit 模块的 pipeline 第二阶段向 VLMergeBuffer 发起表项申请，同周期 VLMergeBuffer 向 VLSplit
返回一个表项 index ，同时相应表项 allocated 置 true。 入队同时会在对应项的计数器中写入当前 uop 拆分的访存请求数量. 为每个 uop
分配一项，每一项维护所需要收集的 flow 数量。当全部收集之后标记为 uopfinish，按照 uop 为粒度写回。 在标记 uopfinish
的表项中选择一项写回后端，当有多项可以写回时index小的先写回。同时清空相应标志位。

### 特性 2：合并数据

根据 Load 流水线输出信息，以 uop 为粒度合并数据。合并时候根据是否有异常、元素位置、mask 等进行合并。

### 特性 3：处理异常

根据流水线的输出信息，出现异常时正确的设置 ExceptionVec、vstart 等相应的数据。

### 特性 4：阈值反压 {#sec:VLM-THRESHOLD}

为了避免卡死，当 VLMergeBuffer 的空闲表项小于等于 6 项时，产生 threshold 反应信号至 VLSplit。反压 VLSplit
Pipe。 参见 [@sec:VLS-THRESHOLD] [根据 VLMergeBuffer 的 Threshold 信号进行反压](VLSplit.md)。

## 整体框图

单一模块无框图

## 主要端口

|                | 方向  | 说明                                 |
| -------------: | --- | ---------------------------------- |
|   frompipeline | In  | 接收来自 Load pipeline 的读数据返回          |
|  fromSplit.req | In  | 接收来自 VLSplit 模块的表项申请               |
| fromSplit.resp | Out | 反馈至 VLSplit 模块，是否成功分配、分配的表项        |
|   uopWriteback | Out | 将执行结束的 uop 写回后端                    |
|          toLsq | Out | 执行结束的 uop 写回后端时更新 Load queue 中表项状态 |
|       redirect | In  | 重定向端口                              |
|       feedback | Out | 反馈至后端 Issue Queue，目前后端不做任何处理       |
|        toSplit | Out | 反馈至 VLSplit 模块，VLMergeBuffer即将达到阈值 |

## 接口时序

接口时序较简单，只提供文字描述。

|                    | 说明                                   |
| -----------------: | ------------------------------------ |
|       frompipeline | 具备 Valid、Ready。数据同 Valid && ready 有效 |
|      fromSplit.req | 具备 Valid、Ready。数据同 Valid && ready 有效 |
|     fromSplit.resp | 具备 Valid。数据同 Valid 有效                |
|       uopWriteback | 具备 Valid、Ready。数据同 Valid && ready 有效 |
|              toLsq | 具备 Valid。数据同 Valid 有效                |
|           redirect | 具备 Valid。数据同 Valid 有效                |
|           feedback | 具备 Valid。数据同 Valid 有效                |
| fromMisalignBuffer | 不具备 Valid，数据始终视为有效，对应信号产生即响应         |

