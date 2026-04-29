# Load 重发队列 LoadQueueReplay

## 功能描述

LoadQueueReplay用于存储需要重发的Load指令，并根据不同的唤醒条件唤醒指令，调度指令进入LoadUnit执行，主要包括以下几个状态和存储的信息：

Table: LoadQueueReplay存储信息

| Field              | 描述                                                  |
| ------------------ | --------------------------------------------------- |
| allocated          | 是否已经被分配，也代表是否该项是否有效。                                |
| scheduled          | 是否已经被调度，代表该项已经被选出，已经或即将被发送至LoadUnit进行重发。            |
| uop                | load指令执行包括的uop信息。                                   |
| vecReplay          | 向量load指令相关信息                                        |
| vaddrModule        | Load指令的虚拟地址                                         |
| cause              | 某load replay queue项对应load指令重发的原因，包括：                |
|                    | C_MA(位0): store-load预测违例                            |
|                    | C_TM(位1): tlb miss                                  |
|                    | C_FF(位2): store-to-load-forwarding store数据为准备好，导致失败 |
|                    | C_DR(位3): 出现DCache miss，但是无法分配MSHR                  |
|                    | C_DM(位4): 出现DCache miss                             |
|                    | C_WF(位5)：路预测器预测错误                                   |
|                    | C_BC(位6): Bank冲突                                    |
|                    | C_RAR(位7)：LoadQueueRAR没有空间接受指令                      |
|                    | C_RAR(位8): LoadQueueRAW没有空间接受指令                     |
|                    | C_NK(位9): LoadUnit监测到store-to-load-forwarding违例     |
|                    | C_MF(位10)：LoadMisalignBuffer没用空间接受指令                |
| blocking           | Load指令正在被阻塞                                         |
| strict             | 访存依赖预测器判断指令是否需要等待它之前的所有store指令执行完毕进入调度阶段            |
| blockSqIdx         | 与load指令有相关性的store指令的StoreQueue Index                |
| missMSHRId         | load指令的dcache miss请求接受ID                            |
| tlbHintId          | load指令的tlb miss请求接受ID                               |
| replacementUpdated | DCcahe的替换算法是否已经更新                                   |
| replayCarry        | DCache的路预测器预测信息                                     |
| missDbUpdated      | ChiselDB中Miss相关情况更新                                 |
| dataInLastBeatReg  | Load指令需要的数据在两笔回填请求的最后一笔                             |


\newpage

### 特性 1：乱序分配

* LoadUnit
  S3传入一条load请求后，首先需要判断是否需要入队。如果不需要重发、发生异常或因redirect被冲刷，均不需要入队。LoadQueueReplay通过freelist进行队列空闲管理。Freelist的大小为load
  replay queue的项数，分配宽度为Load的宽度（LoadUnit的数量），释放宽度为4。同时，freelist可以反馈load replay
  queue的空余项，以及是否满的信息。LoadQueueReplay采用Freelist进行队列空闲管理。Freelist的大小为LoadQueueReplay的项数，分配宽度为Load的宽度（LoadUnit的数量），释放宽度为4。

  * 分配

    * LoadQueueReplay从Freelist中从空闲的项中（即图\ref{fig:LSQ-LoadQueueReplay-Freelist}中的Valid项），为每一个LoadUnit选出一个项索引（尽力而为选出空闲项，例如，有效项有5，10两项，LoadUnit0和LoadUnit2有效，则LoadUnit0分配到5,LoadUnit2分配到10），之后根据索引将指令信息填入对应的索引项中。

    ![Freelist](./figure/LSQ-LoadQueueReplay-Freelist.svg){#fig:LSQ-LoadQueueReplay-Freelist
    width=70%}

  * 回收

    * 成功重发或者被刷新的load指令占用的项，需要回收。LoadQueueReplay通过使用一个位图FreeMask保存正在释放项，，每个周期Freelist最多回收4项。

    ![Freelist回收](./figure/LSQ-LoadQueueReplay-Freelist-Recycle.svg){#fig:LSQ-LoadQueueReplay-Freelist-Recycle
    width=90%}

### 特性 2：唤醒

* 不同的阻塞条件，有不同的唤醒的条件：

  * C_MA：如果strict==1，则需要等待load指令之前的所有store指令地址计算完成之后才能唤醒，否则只需要等待blockSqIdx对应的Store指令的地址计算完成之后唤醒。

  * C_TM：如果TLB没有多余空间处理miss请求，则可以标记为可重发状态，等待调度；否则需要等待TLB返回tlbHintId匹配的hint信号唤醒。

  * C_FF: 需要等待blockSqIdx对应的Store指令的数据准备之后唤醒。

  * C_DR: 可以标记为可重发状态，等待调度。

  * C_DM: 等待与missMSHRId匹配的L2 Hint信号唤醒。

  * C_WF: 可以标记为可重发状态，等待调度。

  * C_BC: 可以标记为可重发状态，等待调度。

  * C_RAR: 等待LoadQueueRAR有空闲空间或者该条指令是最老的load指令时，可以唤醒。

  * C_RAW: 等待LoadQueueRAW有空闲空间或者该条load指令在之前的store指令的地址都计算完成之后，可以唤醒。

  * C_MF：等待LoadMisalignBuffer有空闲空间，可以唤醒。

### 特征 3: 选择调度

* LoadQueueReplay有3种选择调度方式：

  * 根据入队年龄

    * LoadQueueReplay使用3个年龄矩阵(每一个Bank对应一个年龄矩阵)，来记录入队的时间。年龄矩阵会从已经准备好可以重发的指令中，选择一个入队时间最长的指令调度重发。

  * 根据Load指令的年龄

    * LoadQueuReplay可以根据LqPtr判断靠近最老的load指令重发，判断宽度为OldestSelectStride=4。

  * DCache数据相关的load指令优先调度

    * LoadQueueReply首先调度因L2 Hint调度的重发（当dcache miss后，需要继续查询下级缓存L2 Cache。在L2
      Cache回填前的2或3拍，L2 Cache会提前给LoadQueueReplay唤醒信号，称为L2 Hint）当收到L2
      Hint后，LoadQueueReplay可以更早地唤醒这条因dcache miss而阻塞的Load指令进行重发。

    * 如果不存在L2 Hint情况，会将其余Load Replay的原因分为高优先级和低优先级。高优先级包括因dcache缺失或st-ld
      forward导致的重发，而将其他原因归纳为低优先级。如果能够从LoadQueueReplay中找出一条满足重发条件的Load指令（有效、未被调度、且不被阻塞等待唤醒），则选择该Load指令重发，否则按照入队顺序，通过AgeDetector模块寻找一系列load
      replay queue项中最早入队的一项进行重发。

\newpage

## 整体框图

![LoadQueueReplay整体框图](./figure/LSQ-LoadQueueReplay.svg){#fig:LSQ-LoadQueueReplay}

## 接口时序

### 入队时序

  * 重发入队

![LoadQueueReplay重发入队时序图](./figure/LSQ-LoadQueueReplay-Enq-Timing.svg){#fig:LSQ-LoadQueueReplay-Enq-Timing}

\newpage

  * 非重发入队

![LoadQueueReplay非重发入队时序图](./figure/LSQ-LoadQueueReplay-NoEnq-Timing.svg){#fig:LSQ-LoadQueueReplay-NoEnq-Timing}

### 重发时序

![LoadQueueReplay重发队时序图](./figure/LSQ-LoadQueueReplay-Deq-Timing.svg){#fig:LSQ-LoadQueueReplay-Deq-Timing}

\newpage

### Freelist时序

  * 分配时序

![Freelist分配时序图](./figure/LSQ-Freelist-Alloc-Timing.svg){#fig:LSQ-Freelist-Alloc-Timing}

  * 回收时序

![Freelist回收时序图](./figure/LSQ-Freelist-DeAlloc-Timing.svg){#fig:LSQ-Freelist-DeAlloc-Timing}
