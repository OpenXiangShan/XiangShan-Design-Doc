# Store 队列 StoreQueue

## 功能描述

StoreQueue是一个队列，用来装所有的 store 指令，功能如下：

* 在跟踪 store 指令的执行状态

* 存储 store 的数据，跟踪数据的状态（是否到达）

* 为load提供查询接口，让load可以forward相同地址的store

* 负责 MMIO store和NonCacheable store的执行

* 将被 ROB 提交的 store 写到 sbuffer 中

* 维护地址和数据就绪指针，用于LoadQueueRAW的释放和LoadQueueReplay的唤醒

store进行了地址与数据分离发射的优化，即 StoreUnit 是 store 的地址发射出来走的流水线，StdExeUnit 是 store
的数据发射出来走的流水线，是两个不同的保留站，store 的数据就绪了就可以发射到 StdExeUnit，store 的地址就绪了就可以发射到
StoreUnit。

* StoreQueue中每一项保存了store指令的基础信息：

Table: StoreQueue存储的基础信息

| Field       | 描述               |
| ----------- | ---------------- |
| uop         | store指令uop       |
| dataModule  | 128bits数据和数据有效掩码 |
| paddrModule | 物理地址             |
| vaddrModule | 虚拟地址             |


* StoreQueue中每一项都有若干状态位来表示这个store处于什么样的状态:

Table: StoreQueue存储的状态信息

| Field         | 描述                                               |
| ------------- | ------------------------------------------------ |
| allocated     | 设置这个entry的allocated状态，开始记录这条store 的生命周期。         |
|               | 当这条store指令被提交到Sbuffer时，allocated状态被清除。           |
| addrvalid     | 表示是否已经经过了地址转换得到物理地址，用于 load forward 检查时的 cam 比较。 |
| datavalid     | 表示store 的数据是否已经被发射出来，是否已经可用                      |
| committed     | store 是否已经被 ROB commit 了                         |
| unaligned     | 非对齐Store                                         |
| cross16Byte   | 跨16字节边界                                          |
| pending       | 在这条 store 是否是 MMIO 空间的 store，主要是用于控制 MMIO 的状态机   |
| nc            | NonCacheable store                               |
| mmio          | mmio store                                       |
| atomic        | 原子store                                          |
| memBackTypeMM | 是否是 PMA 为 main memory类                           |
| prefetch      | 当提交到Sbuffer是否需要预取                                |
| isVec         | 向量store                                          |
| vecLastFlow   | 向量store flow的最后一个uop                             |
| vecMbCommit   | 从合并缓冲区提交到 rob 的向量Store                           |
| hasException  | store指令有异常                                       |
| waitStoreS2   | 等待Store Unit s2的mmio和异常结果                        |

### 特性 1: 数据前递

* load需要查询StoreQueue来找到在它之前的相同地址的与它最近的依赖store的数据。

    * 查询总线(io.forwrd.sqIdx)和StoreQueue的enqPtr指针比较，找出所有比load指令老的StoreQueue中的entry。以flag相同或不同分为2种情况

      * 如果是same flag, 则older Store范围是 [tail, sqIdx - 1],
        如图\ref{fig:LSQ-StoreQueue-Forward-Mask} a）所示； 否则older Store范围是[tail,
        VirtualLoadQueueSize - 1]和[0,
        sqIdx]，如图\ref{fig:LSQ-StoreQueue-Forward-Mask} b）所示

      ![StoreQueue前递范围生成](./figure/LSQ-StoreQueue-Forward-Mask.svg){#fig:LSQ-StoreQueue-Forward-Mask
      width=90%}


    * 查询总线用虚拟地址和物理地址同时查询，如果发现物理地址匹配但是虚拟地址不匹配；或者虚拟地址匹配但是物理地址不匹配的情况就需要将那条 load 设置为
      replayInst，等 load 到 ROB head 后重新取指令执行。

    * 如果只发现一笔entry匹配且数据准备好，则直接forward

    * 如果只发现一笔entry匹配且数据没有准备好，就需要让保留站负责重发

    * 如果发现多笔匹配，则选择最老的一笔store前递

    * StoreQueue以1字节为单位，采用树形数据选择逻辑,如图\ref{fig:LSQ-StoreQueue-Forward}所示

  \newpage

  ![StoreQueue前递数据选择](./figure/LSQ-StoreQueue-Forward.svg){#fig:LSQ-StoreQueue-Forward
  width=80%}


* 参与数据前递的store需要满足：

    * allocated：这条 store 还在 store queue 内，还没有写到 sbuffer

    * datavalid：这条 store 的数据已经就绪

    * addrvalid：这条 store 已经完成了虚实地址转换，得到了物理地址

    * 如果启用了访存以来预测器，则SSID (Store-Set-ID)
      标记了之前load预测执行失败历史信息，如果当前load命中之前历史中的SSID，会等之前所有older的store都执行完；如果没有命中就只会等物理地址相同的older
      Store执行完成。

### 特性 2：非对齐store指令

StoreQueue支持处理非对齐的Store指令，每一个非对齐的Store指令占用一项，并在写入dataBuffer对地址和数据对齐后写入。

### 特性 3：向量Store指令

如图\ref{fig:LSQ-StoreQueue-Vector}所示，StoreQueue会给向量store指令预分配一些项。StoreQueue通过vecMbCommit控制向量store的提交：

  * 针对每个 store，从反馈向量 fbk 中获取相应的信息。

    判断该 store 是否符合提交条件（valid 且标记为 commit 或 flush），并且检查该 store 是否与 uop(i)
    对应的指令匹配（通过 robIdx 和 uopIdx）。只有当满足所有条件时，才会将该 store
    标记为提交。判断VecStorePipelineWidth内是否有指令满足条件，满足则 判断该向量store提交，否则为提交。

  * 特殊情况处理（Store 跨页）:

    在特殊情况下（当 store 跨页且 storeMisalignBuffer 中有相同的 uop），如果该 store
    符合条件io.maControl.toStoreQueue.withSameUop，会强制将 vecMbCommit设置为 true，表示该 store
    无论如何都已提交。

![向量Store指令](./figure/LSQ-StoreQueue-Vector.svg){#fig:LSQ-StoreQueue-Vector
width=25%}


### 特性 4：CMO

StoreQueue支持CMO指令，CMO指令共用MMIO的状态机控制:

  * s_idle: 空闲状态，接收到CMO的store请求后进入到s_req状态;

  * s_req: 刷新Sbuffer，等待刷行完成之后, 通过CMOReq发送CMO操作请求, 进入s_resp状态

  * s_resp: 接受到CMOResp返回的响应，进入s_wb状态

  * s_wb: 等待ROB提交CMO指令，进入s_idle状态

### 特性 5：CBO

StoreQueue支持CBO.zero指令:

  * CBO.zero指令的数据部分将0写入dataModule

  * CBO.zero写入Sbuffer时：刷新Sbuffer，等待刷新完毕之后，通过cboZeroStout写回。

### 特性 6: MMIO与NonCacheable Store指令

* MMIO Store指令执行

  * MMIO 空间的 store 也只能等它到达 ROB 的 head 时才能执行，但是跟 load 稍微有些不同，store 到达 ROB 的 head
    时，它不一定位于 store queue 的尾部，有可能有的 store 已经提交，但是还在 store queue 中没有写入到
    sbuffer，需要等待这些 store 写到 sbuffer 之后，才能让这条 MMIO 的 store 去执行

  * 利用一个状态机去控制MMIO的store执行

    * s_idle：空闲状态，接收到MMIO的store请求后进入到s_req状态;

    * s_req：给MMIO通道发请求，请求被MMIO通道接受后进入s_resp状态;

    * s_resp：MMIO通道返回响应，接收后记录是否产生异常，并进入到 s_wb 状态

    * s_wb：将结果转化为内部信号，写回给 ROB，成功后,如果有异常，则进入s_idle, 否则进入到 s_wait 状态

    * s_wait：等待 ROB 将这条 store 指令提交，提交后重新回到 s_idle 状态

* NonCacheable Store指令执行

  * NonCacheable空间的store指令，需要等待提交之后，才能从StoreQueue按序发送请求

  * 利用一个状态机去控制NonCacheable的store执行

    * nc_idle：空闲状态，接收到NonCacheable的store请求后进入到nc_req状态;

    * nc_req：给NonCacheable通道发请求，请求被NonCachable通道接受后,
      如果启用uncacheOutstanding功能，则进入nc_idle，否则进入nc_resp状态;

    * nc_resp：接受NonCacheable通道返回响应，并进入到nc_idle状态

### 特性 7: store指令提交以及写入SBuffer

StoreQueue采用提前提交的方式
* 提前提交规则:

  * 检查进入提交阶段的条件

    * 指令有效。

    * 指令的ROB对头指针不超过待提交指针。

    * 指令不需要取消。

    * 指令不等待Store操作完成，或者是向量指令

  * 如果是CommitGroup的第一条指令, 则

    * 检查MMIO状态: 没有MMIO操作或者有MMIO操作并且MMIO store以及提交。

    * 如果是向量指令，否则需满足vecMbCommit条件，。

  * 如果不是CommitGroup的第一条指令，则：

    * 提交状态依赖于前一条指令的提交状态。

    * 如果是向量指令，需满足vecMbCommit条件。

提交之后可以按顺序写到 sbuffer, 先将这些 store 写到 dataBuffer 中，dataBuffer
是一个两项的缓冲区（0，1通道），用来处理从大项数 store queue
中的读出延迟。只有0通道可以编写未对齐的指令,同时为了简化设计，即使两个端口出现异常，但仍然只有一个未对齐出队。

* 写入有效信号生成:

  * 0通道指令存在非对齐且跨越16字节边界时：

    * 0通道的指令已分配和提交

    * dataBuffer的0，1通道能同时接受指令，

    * 0通道的指令不是向量指令，并且地址和数据有效；或者是向量且vsMergeBuffer以及提交。

    * 没有跨越4K页表；或者跨越4K页表但是可以被出队,并且1）如果是0通道：允许有异常的数据写入; 2）如果是1通道：不允许有异常的数据写入。

    * 之前的指令没有NonCacheable指令，如果是第一条指令，自身不能是Noncacheable指令

  * 否则，需要满足

    * 指令已分配和提交。

    * 不是向量且地址和数据有效，或者是向量且vsMergeBuffer以及提交。

    * 之前的指令没有NonCacheable和MMIO指令，如果是第一条指令，自身不能是Noncacheable和MMIO指令。

    * 如果未对齐store，则不能跨越16字节边界，且地址和数据有效或有异常

* 地址和数据生成:

  * 地址拆分为高低两部分：

    * 低位地址：8字节对齐地址

    * 高位地址：低位地址加上8偏移量

  * 数据拆分为高低两部分：

    * 跨16字节边界数据：原始数据左移地址低4位偏移量包含的字节数

    * 低位数据：跨16字节边界数据的低128位；

    * 高位数据：跨16字节边界数据的高128位；

  * 写入选择逻辑:

    * 如果dataBuffer能接受非对齐指令写入,通道0的指令是非对齐并且跨越了16字节边界，则

      * 检查是否跨4K页表同时跨4K页表可以出队: 通道0使用低位地址和低位数据写入dataBuffer;
        通道1使用StoreMisaligBuffer的物理地址和高位数据写入dataBuffer

      * 否则: 通道0使用低位地址和低位数据写入dataBuffer; 通道1使用高位地址和高位数据写入dataBuffer

    * 如果通道指令没有跨越16字节并且非对齐，则使用16字节对齐地址和对齐数据写入dataBuffer

    * 否则，将原始数据和地址写给dataBuffer

### 特征 7：强制刷新Sbuffer

StoreQueue采用双阈值的方法控制强制刷新Sbuffer：上阈值和下阈值。当StoreQueue的有效项数大于上阈值时，
StoreQueue强制刷新Sbuffer，直到StoreQueue的有效项数小于下阈值时，停止刷新Sbuffer，

\newpage

## 整体框图

![StoreQueue整体框架](./figure/LSQ-StoreQueue.svg){#fig:LSQ-StoreQueue width=90%}

## 接口时序

### 入队接口时序实例

![StoreQueue整体框架](./figure/LSQ-StoreQueue-Enq-Timing.svg){#fig:LSQ-StoreQueue-Enq-Timing
width=90%}

\newpage

### 数据更新接口时序

![数据更新接口时序](./figure/LSQ-StoreQueue-Data-Timing.svg){#fig:LSQ-StoreQueue-Data-Timing
width=90%}

### 地址更新接口时序

StoreQueue地址更新和数据更新类似，StoreUnit通过s1阶段的io_lsq更新地址，在s2阶段通过io_lsq_replenish更新异常，与数据更新不同的是，更新地址只需要一拍，而不是两拍

### MMIO接口时序实例

![MMIO接口时序实例](./figure/LSQ-StoreQueue-MMIO-Timing.svg){#fig:LSQ-StoreQueue-MMIO-Timing
width=90%}

\newpage
### NonCacheable接口时序实例

![NonCacheable接口时序实例](./figure/LSQ-StoreQueue-NC-Timing.svg){#fig:LSQ-StoreQueue-NC-Timing
width=90%}

### CBO接口时序实例

![CBO接口时序实例](./figure/LSQ-StoreQueue-CBO-Timing.svg){#fig:LSQ-StoreQueue-CBO-Timing
width=90%}

\newpage
### CMO接口时序实例

![CMO接口时序实例](./figure/LSQ-StoreQueue-CMO-Timing.svg){#fig:LSQ-StoreQueue-CMO-Timing
width=90%}
