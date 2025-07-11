# 向量 Segment 访存指令处理单元 VSegmentUnit

## 功能描述

主体是一个 8 项的队列，每一项有一个 128-bits 的地址寄存器、128-bits 的数据寄存器、index/stride 寄存器和用于存储不同 uop
的物理寄存器号、写使能、uopidx 等信息的寄存器。除此之外还有一个用于存储整条指令译码信息的寄存器。内部使用一个状态机控制实现按照 segment
顺序进行拆分。

在 VSegmentUnit.scala 中写有与代码结合的注释，可以结合注释与代码阅读下文，理解 SegmentUnit 的相关逻辑。

在 Segment 指令执行时，需要由流水线乱序后端保证：前面的指令都执行结束，后面的指令都不能进入流水线（与原子指令的等待机制类似），同时需要保证指令的
uop 按照拆分顺序进入 SegmentUnit。此时 SegmentUnit 对 Segment 指令的顺序才能得到保证。

### 特性 1：进行 Segment 指令的拆分

![alt text](./figure/VSegment-split.png)

- segmentIdx： segment的序号，segmentIdx <= vl。用于表示当前发送到哪个segment，也用于选择数据、合并数据。
- fieldIdx：field的序号，用于标识当前segment是否发送结束。 fieldIdx<nfields。
- fieldOffset：同一个segment下各个元素的相对偏移，实现为一个为1的累加器。
- segmentOffset：
  用于记录不同Segment之间的偏移，对于stride指令来说是以stride为粒度的累加器；对于unit-stride来说是以nfield*eew为粒度的累加器；对于index来说是segmentIdx对应的索引寄存器元素。
- vaddr = baseaddr + (fieldIdx << eew) + segmentOffset

上图为队列指针跳转示例，展示了当lmul=1， nf=2，vl=16
配置下的示例，segmentIdx指向当前拆分的segment，SplitPtr指向拆分的field寄存器。
上图中segmentIdx为0，splitPtr为0，将第一个uop的第一个元素拆分并且访存之后，SplitPtr +
nf，进行segment0的field1元素的访存。
当进行了field2的访存之后，当前segment的元素访问结束，segmentIdx+1，同时SplitPtr跳转到下一个segment的field0所在的寄存器。
当segmentIdx递增到8时，对应于field0的寄存器组来说是下一个uop的第一个元素（对应上图中每个field寄存器的第二个）。
当segmentIdx=16，并且进行完field2元素的访存之后，指令执行结束。 对于segment
Index来说，还有一个指针用于选择索引寄存器，实现方式与上述选择同一field的不同寄存器类似。

### 特性 2：fault only first 修改 VL 寄存器的 uop 单独写回

对于 fault only first 指令，VSegmentUnit 不使用 VfofBuffer 进行写回额外的 uop。 而是自己转进到
s_fof_fix_vl 写回修改 VL 寄存器的uop。

### 特性 3：支持 Segment 的非对齐访存

VSegmentUnit 指令自己单独执行非对齐访存，无需借助 MisalignBuffer。 由 VSegmentUnit
自身进行非对齐指令的拆分与数据的合并。

## 状态转换图

![alt text](./figure/VSegmentUnit-FSM.svg)

**状态介绍**

|                        状态 | 说明                                              |
| ------------------------: | ----------------------------------------------- |
|                    s_idle | 等待 SegmentUnit uop 进入                           |
|       s_flush_sbuffer_req | flush sbuffer                                   |
| s_wait_flush_sbuffer_resp | 等待 Sbuffer 和 StoreQueue 为空                      |
|                 s_tlb_req | 查询 DTLB                                         |
|           s_wait_tlb_resp | 等待 DTLB 响应                                      |
|                      s_pm | 检查执行权限                                          |
|               s_cache_req | 请求读取 DCache                                     |
|              s_cache_resp | DCache 响应                                       |
|     s_misalign_merge_data | 合并非对齐的 Load Data                                |
|    s_latch_and_merge_data | 将每个元素的 Data 合并成完整的 uop 粒度的 Data                 |
|               s_send_data | 发送数据至 Sbuffer                                   |
|         s_wait_to_sbuffer | 等待发送至 Sbuffer 的流水级清空，即真正的发送到 Sbuffer            |
|                  s_finish | 该指令执行完成，开始以 uop 为粒度写回至后端                        |
|              s_fof_fix_vl | fault only first 指令数据 uop 已经写回，写回修改 VL 寄存器的 uop |

## 译码实例

### Segment Unit-Stride/Stride

unit-stride 按照 stride = eew * nf 的 stride 指令处理。 这一类指令用到的偏移量寄存器是标量寄存器，uop 数量取决于
data 寄存器的数量，所以 uop 拆分数量 = emul * nf 比如，emul = 2，nf = 4，则 uop 编号如下： uopIdx =
0，基地址 rs1，步长 rs2，目的寄存器 vd uopIdx = 1，基地址 rs1，步长 rs2，目的寄存器 vd+1 uopIdx = 2，基地址
rs1，步长 rs2，目的寄存器 vd+2 ...... uopIdx = 7，基地址 rs1，步长 rs2，目的寄存器 vd+7

### Segment Index

- 拆分数量为： Max（lmul*nf， emul），需要保证从第一个field的寄存器组按序开始拆分。

- 例如：emul=4， lmul=2， nf=2，uop拆分如下：
    - uopidx=0， 基地址src， 偏移量vs2， 目的寄存器vd
    - uopidx=1， 基地址（dontCare）， 偏移量vs2+1， 目的寄存器vd+1
    - uopidx=2， 基地址（dontCare）， 偏移量vs2+2， 目的寄存器vd+2
    - uopidx=3， 基地址（dontCare）， 偏移量vs2+3， 目的寄存器vd+3

- 再例如：emul=2， luml=1， nf=3，uop拆分如下：
    - uopidx=0， 基地址src， 偏移量vs2， 目的寄存器vd
    - uopidx=1， 基地址（dontCare）， 偏移量vs2+1， 目的寄存器vd+1
    - uopidx=2， 基地址（dontCare）， 偏移量（dontCare）， 目的寄存器vd+2

- 再例如：emul=8， lmul=1， nf=8， uop拆分如下：
    - uopidx=0， 基地址src， 偏移量vs2， 目的寄存器vd
    - uopidx=1， 基地址（dontCare）， 偏移量vs2+1， 目的寄存器vd+1
    - uopidx=2， 基地址（dontCare）， 偏移量vs2+2， 目的寄存器vd+2
    - uopidx=3， 基地址（dontCare）， 偏移量vs2+3， 目的寄存器vd+3
    - uopidx=4， 基地址（dontCare）， 偏移量vs2+4， 目的寄存器vd+4
    - uopidx=5， 基地址（dontCare）， 偏移量vs2+5， 目的寄存器vd+5
    - uopidx=6， 基地址（dontCare）， 偏移量vs2+6， 目的寄存器vd+6
    - uopidx=7， 基地址（dontCare）， 偏移量vs2+7， 目的寄存器vd+7

## 主要端口

|                 | 方向     | 说明                                     |
| --------------: | ------ | -------------------------------------- |
|              in | In     | 接收来自 Issue Queue 的 uop 发射              |
|    uopwriteback | In     | 将执行结束的 uop 写回后端                        |
|         rdcache | In/Out | DCache 请求/响应                           |
|         sbuffer | Out    | 写 Sbuffer 请求                           |
| vecDifftestInfo | Out    | sbuffer 中 DifftestStoreEvent 所需信息      |
|            dtlb | In/out | 读写 DTLB 请求/响应                          |
|         pmpResp | In     | 接收来自 PMP 的访问权限信息                       |
|   flush_sbuffer | Out    | 冲刷 sbuffer 请求                          |
|        feedback | Out    | 反馈至 Issue Queue 模块                     |
|        redirect | In     | 重定向端口                                  |
|   exceptionInfo | Out    | 输出 Exception 信息，参与 MemBlock 中写回异常信息的仲裁 |
|  fromCsrTrigger | In     | 接收来自 CSR 的 Trigger 相关数据                |

## 接口时序

接口时序较简单，只提供文字描述。
|                 | 说明                                   |
| --------------: | ------------------------------------ |
|              in | 具备 Valid、Ready。数据同 Valid && ready 有效 |
|    uopwriteback | 具备 Valid、Ready。数据同 Valid && ready 有效 |
|         rdcache | 具备 Valid、Ready。数据同 Valid && ready 有效 |
|         sbuffer | 具备 Valid、Ready。数据同 Valid && ready 有效 |
| vecDifftestInfo | 与 sbuffer 端口同时有效                     |
|            dtlb | 具备 Valid、Ready。数据同 Valid && ready 有效 |
|         pmpResp | 具备 Valid、Ready。数据同 有效                |
|   flush_sbuffer | 具备 Valid。数据同 Valid 有效                |
|        feedback | 具备 Valid。数据同 Valid 有效                |
|        redirect | 具备 Valid。数据同 Valid 有效                |
|   exceptionInfo | 具备 Valid。数据同 Valid 有效                |
|  fromCsrTrigger | 不具备 Valid，数据始终视为有效，对应信号产生即响应         |
