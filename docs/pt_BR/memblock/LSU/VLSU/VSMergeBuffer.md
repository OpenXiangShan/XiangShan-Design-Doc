# 向量 Store 合并单元 VSMergeBuffer

## 功能描述

一个基于 freelist 的队列，接收 VSSplit 模块发来的请求，为后端发射的每一个 uop 申请一个表项，保存 uop 的相关信息，收集从 Store
pipeline 上返回的数据，接收该 uop 拆分的全部访存请求之后写回后端与 Store Queue。

### 特性 1：维护 uop 的拆分访存请求

在 VSSplit 模块的 pipelin e第二阶段向 VSMergeBuffer 发起表项申请，同周期 VSMergeBuffer 向 VSSplit
返回一个表项 index，同时相应表项 allocated 置 true。 入队同时会在对应项的计数器中写入当前 uop 拆分的访存请求数量. 为每个 uop
分配一项，每一项维护所需要收集的 flow 数量。当全部收集之后标记为 uopfinish，按照 uop 为粒度写回。 在标记 uopfinish
的表项中选择一项写回后端，当有多项可以写回时index小的先写回。同时清空相应标志位。

### 特性 2：处理异常

根据流水线的输出信息，出现异常时正确的设置 ExceptionVec、vstart 等相应的数据。

### 特性 3：根据 StoreMisalignBuffer 的 flush 信号标记 uop 是否需要 flush

对于非对齐的 vector store 访存，具有特殊性，当 StoreMisalignBuffer 产生 vector store 的 flush
信号时，会送至 VSMergeBuffer。 VSMergeBuffer 会将对应的表现置为 needRSReplay，从而最终通知 Issue Queue
重发。


## 整体框图
单一模块无框图。

## 主要端口

|                    | 方向  | 说明                                  |
| -----------------: | --- | ----------------------------------- |
|       frompipeline | In  | 接收来自 Store pipeline 的读数据返回          |
|      fromSplit.req | In  | 接收来自 VSSplit 模块的表项申请                |
|     fromSplit.resp | Out | 反馈至 VSSplit 模块，是否成功分配、分配的表项         |
|       uopWriteback | Out | 将执行结束的 uop 写回后端                     |
|              toLsq | Out | 执行结束的 uop 写回后端时更新 Store queue 中表项状态 |
|           redirect | In  | 重定向端口                               |
|           feedback | Out | 反馈至后端 Issue Queue 是否需要重发            |
| fromMisalignBuffer | In  | 接收来自 StoreMisalignBuffer 的 flush 信号 |

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

