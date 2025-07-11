# 向量 Store 拆分单元 VSSplit

## 功能描述

接受并处理 Vector Store 指令的 uop。拆分 Uop，计算Uop相对基地址的偏移，生成标量访存 Pipeline 的控制型号。 VSSplit
总体上分为两个实现模块：VSSplitPipeline 和 VSSplitBuffer。

### 特性 1：VSSplitPipeline 为 uop 进行二次译码

Vector Store 指令的拆分流水线。接受 Vector Store 发射队列发射的 Vector Store 指令的
Uop。在流水线中进行更细粒度的译码并计算 Mask 与地址偏移后发送到 VSSplitBuffer 中。同时，VSSplitPipeline
还会根据译码计算的结果来申请 VLMergeBuffer 中的表项。 VSSplitPipeline 分为两个流水级：

#### S0：

- 通过传入的 Uop 信息进行更细粒度的译码。
- 根据指令类型生成 alignedType，使用 alignedType 指示 Store Pipeline 的访存宽度。
- 根据指令类型生成 preIsSplit 信号。preIsSplit 置高则表示不是 Unit-Stride 指令。
- 根据指令类型与vm、emul、lmul,、eew,、sew等信息生成该 Uop 的 Mask。
- 计算该条 Uop 的 VdIdx 用于后续后端数据合并写回使用。因为乱序执行的原因，同一条指令的 Uop
  并不一定会背靠背执行，因此需要在该阶段根据指令类型、emul、lmul 和 uopidx 计算出 VdIdx。

##### Mask计算：

- 首先，我们根据 vm、v0、vstart、evl 来计算生成表示该条 Vector Store 指令的SrcMask。这其中，evl
  为有效向量长度，对于不同类型的 Vector Store 指令，有不同的的 evl 计算方法：
    - 对于 Store Whole 指令，其 evl = NFIELDS*VLEN/EEW。
    - 对于 Store Unit-Stride Mask 指令，其 evl=ceil(vl/8)。
    - 对于除了上述两种指令之外的 Vector Store 指令，其 evl = vl。

- 然后，我们使用这条指令的【当前 Uop 之前的所有的Uop 的 FlowNum】和【当前 Uop 在内的的所有 Uop 的 FlowNum】与【当前 Uop
  之前的所有的 Vd 的 FlowNum】来计算真正使用的 FlowMask。 在这里，因为 Store Indexed 的特殊性，当 Indexed 指令的
  $signed(emul) > $signed(lmul) 时，我们需要保证同一个 VdIdx 的Uop的 FlowNum 在 VdIdx
  内进行偏移，具体示例如下：
    - 首先我们假定如下配置向量 vluxei 指令：
        - vsetvli t1,t0,e8,m1,ta,ma lmul = 1
        - vsuxei16.v v2,(a0),v8 emul = 2
        - vl = 9，v0 = 0x1FF

    - 在这样的配置下，因为 $signed(emul) > $signed(lmul)，因此实际上会产生两个 Uop，表示需要分别从两个向量寄存器中取出
      Index，而两个 Uop 对应的目的寄存器是同一个 Vd。也就是两个 Uop 的VdIdx
      应该是相同的，是要写入到同一个目标寄存器中的。因此在这里会产生如下的结果：
        - uopIdxInField = 0，vdIdxInField = 0, flowMask = 0x00FF, toMergeBuffMask
          = 0x01FF
        - uopIdxInField = 1，vdIdxInField = 0, flowMask = 0x0001, toMergeBuffMask
          = 0x01FF
        - uopIdxInField = 0，vdIdxInField = 0, flowMask = 0x0000, toMergeBuffMask
          = 0x0000
        - uopIdxInField = 0，vdIdxInField = 0, flowMask = 0x0000, toMergeBuffMask
          = 0x0000

    - 每一个 Uop 计算出的 FlowNum 均为8。更具体的说明可见VSplit .scala

#### S1：

- 计算 UopOffset 与 Stride。
- 计算该条 Uop 所需的 FlowNum。在这里，发送给 VMergeBuffer 的 FlowNum 与发送给 VSplitBuffer 的
  FlowNum 有所不同。MergeBuffer 中的 FlowNum 要用来判断这个 Uop 是否完成了所有有效的访存。而 VSplitBuffer
  中所使用的 FlowNum 需要用来进行拆分。
- 申请 VSMergeBuffer 表项。每个 Uop 申请一个表项。
- 发送信息到 VSSplitBuffer。

### 特性 2：VSSplitBuffer 根据 VSSplitPipeline 产生的二次译码信息进行拆分

VSplitBuffer 是只有一项的 Buffer，接受 VSSplitPipeline 发来的相关信息，缓存需要拆分的 Vector Store Uop。

VSSplitBuffer 会根据 Uop 的信息将一个 Uop 拆分成多个可以发送到标量 Store PipeLine 流水线上的信息，并发送到标量
Store PipeLine 流水线进行实际访存。


**入队逻辑：**

VSSplitBuffer 接受 VSSplitPipeline 发来的表项申请与相关信息，当 VSSplitBuffer 表项有空闲时会为每个申请分配一个
VSSplitBuffer 表项，并将相应表项的 Valid 置高。

**出队逻辑：**

VSSplitBuffer 接受 VSSplitPipeline 发来的表项申请与相关信息，当 VSSplitBuffer 表项有空闲时会为每个申请分配一个
VSSplitBuffer 表项，并将相应表项的 Valid 置高。


**拆分：**

- VsSplitBuffer 会根据指令类型进行拆分。
- 对于 Unit-Stride 指令：
- 当基地址对齐（不跨 CacheLine ）时会一次访问 128 Bit。
- 当基地址非对齐（跨 CacheLine ）时候，我们会进行拆分，发起两次 128Bit 的访存。
- 对于其他的 Vector Store 指令，我们根据指令语义的要求按照元素进行拆分，并按照元素进行访存。
- 每次拆分都会将拆分后产生的相关信息发送到标量 Store PipeLine 流水线进行实际访存。
- 拆分根据 splitIdx 计数器进行判断，splitIdx 表示当前表项已经进行拆分的数量。当 splitIdx 小于需要拆分的数量并且可以发送到标量
  Store PipeLine 流水线时，会进行一次拆分，每次拆分会增加 splitIdx 计数器的值。当 splitIdx
  大于等于需要拆分的数量时，拆分结束，该表项出队，splitIdx 计算器归零。

**地址计算：**

- 在拆分时还需要计算将要发送到标量 Store PipeLine 流水线的相关信息，主要是计算每次拆分后需要进行访存的虚拟地址。
- 虚拟地址根据指令类型拆分方式的不同有不同的计算方式。

- 对于 Unit-Stride 指令：
    - 当基地址对齐（不跨 CacheLine ）时直接进行一次 128Bit 对齐的访问即可。。
    - 当基地址非对齐（跨 CacheLine ）时候，我们会进行拆分，使用两个连续的 128Bit 对齐的地址进行访问。

- 对于其他的 Vector Store 指令，我们根据指令语义的要求按照元素进行拆分，虚拟地址会根据元素以及语义进行计算。

**数据计算：**

- 在拆分时还需要计算将要发送到 Store Queue 的相关信息，主要是计算每次拆分后的需要存储的数据。
- 需要存储的数据根据指令类型拆分方式的不同有不同的计算方式。具体可见上述地址计算部分要求，只需要与地址的粒度对齐即可。

**重定向与异常处理：**

当重定向信号到来时，会根据重定向相关信息冲刷掉 VSSplitBuffer 的相关表项。

## 整体框图

单一模块无框图。

## 主要端口

只列出 VSSplit 对外接口，不包括内部 VSSplitPipe 与 VSSplitBuffer 接口。

|                    | 方向  | 说明                                                    |
| -----------------: | --- | ----------------------------------------------------- |
|           redirect | In  | 重定向端口                                                 |
|                 in | In  | 接收来自 Issue Queue 的 uop 发射                             |
|  toMergeBuffer.req | Out | 请求 MergeBuffer 表项                                     |
| toMergeBuffer.resp | In  | MergeBuffer 的响应                                       |
|                out | Out | 发送访存请求至 Store Unit                                    |
|               vstd | Out | 执行结束的 uop 写回后端时更新 Store queue 中表项状态                   |
|       vstdMisalign | In  | 接收 Store Unit 与 Store Misalign Buffer 的 misalign 相关信号 |

## 接口时序

接口时序较简单，只提供文字描述。

|                    | 说明                                   |
| -----------------: | ------------------------------------ |
|           redirect | 具备 Valid。数据同 Valid 有效                |
|                 in | 具备 Valid、Ready。数据同 Valid && ready 有效 |
|  toMergeBuffer.req | 具备 Valid、Ready。数据同 Valid && ready 有效 |
| toMergeBuffer.resp | 具备 Valid。数据同 Valid 有效                |
|                out | 具备 Valid、Ready。数据同 Valid && ready 有效 |
|               vstd | 具备 Valid、Ready。数据同 Valid && ready 有效 |
|       vstdMisalign | 不具备 Valid，数据始终视为有效，对应信号产生即响应         |
