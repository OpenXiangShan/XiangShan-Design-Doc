# 预取单元概述

## 术语说明

Table: 术语说明
| 缩写     | 全称                                  | 描述                    |
| -------- | ------------------------------------- | ----------------------- |
| MemBlock | Memory Block                          | 访存单元                |
| ROB      | Reorder Buffer                        | 重排序缓存              |
| Dcache   | Data cache                            | 数据缓存                |
| TLB      | Translation  Lookaside Buffer         | 地址转译后备缓冲器      |
| PC       | Program counter                       | 程序计数器              |
| SMS      | Spatial Memory  Streaming             | 空间内存流预取              |
| BOP      | Best-offset  prefetching              | 最优偏移预取            |
| FIFO     | First In First  Out                   | 先进先出                |
| MSHR     | Miss-status  Handling Registers       | Miss请求处理寄存器      |
| CAM      | Content  Addressable Memory           | 内容寻址存储器          |
| AGT      | ActiveGenerationTable                 | 活动生成表              |
| PHT      | PatternHistoryTable                   | 模式历史表              |
| Vaddr    | Virtual Address                       | 虚拟地址                |
| VIPT     | Virtually  indexed, physically tagged | 虚地址索引，物理地址tag |

## 设计规格
1. 支持虚拟地址空间预取
2. 支持可配置的预取器参数
3. 支持从load/store流水线获取训练数据
4. 支持覆盖跨步型Stride访问模式
5. 支持覆盖连续型Stream访问模式
6. 支持覆盖区域内具有空间局部性的不规则访问模式
7. 支持将数据块预取到Dcache/L2 Cache/L3 Cache

## 功能描述
### 功能概述

数据预取器模块负责提前取回访存指令所需要的数据，以覆盖较高的内存读写延迟，包括从内存读数的load指令和向内存写数的store指令。预取器通过从访存流水线处获取信息进行训练，学习访存模式，预测访存地址，将预取请求发给Dcache或者下级Cache，将数据提前取回。

### 分特性详细描述

**特性1：获取训练数据，预处理**

为了寻找到一段程序中的访存规律，需要抓取访存历史信息，并对信息进行一定的处理。训练数据从MemBlock的访存流水线处取得，具体包括访存指令的pc、物理地址、虚拟地址、是否命中Dcache、是否命中Dcache中的预取块等。

不同的预取器需要的训练数据不一定相同，如Stream预取器需要所有全局访问历史来训练，不区分是否命中Dcache，也不需要pc，而SMS预取器使用在Dcache中Miss与PrefetchHit的访问历史来训练，需要pc信息。PrefetchHit指命中的Cache块是由预取器预取上来的，将PrefetchHit也算作Miss是因为如果没有预取器的干预，访问这个Cache块应该是Miss。以Stride预取器为例，Stride流下只有将PrefetchHit考虑后预取器看到的才是完整的Stride流，才能达到100%的覆盖率。

对应MemBlock的两条或三条load/store流水线，每一条流水线在任意一个周期都有可能产生一个有效的训练数据。以两条load流水线配置下的MemBlock为例，一个周期下可能同时产生2个load训练数据，2个store训练数据。对于预取器而言，其训练本身有一些条件限制：

1. 为了降低硬件逻辑的复杂性，预取器通常一个周期只处理一个训练数据。
2. 以Cache块地址为基础的预取器（SMS、Stream、BOP）需要对训练数据做块地址过滤，而全地址预取器（Stride）则不需要对训练数据做块地址过滤。
3. 对训练数据顺序敏感的预取器（Stride、BOP）需要训练数据尽可能按照指令顺序排列，而对训练数据顺序不敏感的预取器（SMS、Stream）则没有这个限制。

TrainFilter的设计目的是尽量消除以上3个限制，TrainFilter一个周期接收多个从流水线处获取的训练数据，根据指令顺序（ROB位置的顺序）重新排列，放入到一个固定大小的FIFO队列中。TrainFilter会对Cache块地址进行过滤，如果同一个周期中的多个训练数据的虚拟地址位于同一个Cache块内，则只有指令顺序最老的那一个请求会进入FIFO队列。如果同一个周期中的多个训练请求与在FIFO队列中已有的请求存在块地址相同的情况，则对应的训练请求会被丢弃。FIFO队列按照入队顺序，每一个周期移出一个训练数据给预取器。

**特性2：训练特定算法下的预取器**

接收到经过处理后的训练数据之后，根据不同的预取算法，训练预取器，识别访存模式。

程序拥有空间与时间局部性，每条访存指令的pc不相同，从是否利用pc信息进行训练可以将预取器划分为两类。第一类是不使用pc的全局预取器（BOP，Stream），第二类是使用pc的预取器（SMS，Stride）。

BOP利用程序的全局空间局部性，在发生Dcache miss的地址中寻找覆盖率最高和及时性最好的offset，一轮训练后会得到一个最好的offset，再利用这个offset进行预取。<!-- TODO lyq（可能需要详细一些描述，再改改描述） -->

Stream利用程序的全局空间局部性，在所有的load指令访存地址序列中寻找该地址序列是否能构成X、X+1、X+2…的规律（X为Cache块地址），如果可以则将预取器变为激活状态，利用当前访问到的流地址信息进行预取。

SMS利用程序不同pc的空间局部性，将虚拟地址空间分为大小相同的若干region，学习一个region中的Cache块访问模式，在开启新的region访问时复刻已经学习到的模式。<!-- TODO lyq（可能需要详细一些描述，再改改描述） -->

Stride利用程序不同pc的空间局部性，检查同一个pc的load指令访存地址序列是否符合X、X+K、X+2K…的规律（X为Cache块地址，K为步长）。如果可以则按照步长信息进行预取。

**特性3：产生预取请求**
预取请求产生后，需要发给各级Cache以产生效果。例如发送给Dcache的预取请求如果没有命中Dcache则由Dcache负责将数据取回Dcache，可以达到对Dcache进行预取的效果，L2 L3 Cache原理类似。

预取器可以选择性地将预取请求发送到各级Cache，存在如下几个特性：

1. 昆明湖的数据预取器在虚拟地址空间进行训练，最终发出的预取请求也是虚拟地址空间的请求，而L2 L3 Cache只能处理物理地址空间的请求，需要在发给L2 L3 Cache之前将虚拟地址转换为物理地址。
2. Dcache的MSHR可以对请求按块地址过滤，L2 L3 Cache不会对请求按块地址过滤，如果大量给L2 L3 Cache发送重复的预取请求会造成明显的性能下降。
3. L2 L3 Cache的容量较大，Dcache容量较小，对于准确率较低的预取器，可以选择发给容错率高的下级缓存，对于准确率高的预取器可以选择发给Dcache。

Prefetch Filter可以对预取请求进行过滤，并进行虚实地址转换，最终将请求发给各级Cache。Prefetch Filter每周期接收一个预取请求，预取请求的信息包含region地址，region内需要预取的Cache块。Prefetch Filter内部以region为单位进行组织，内部是一个Buffer，每一个预取请求占用一项。接收到预取请求如果与Buffer内已有的请求重复则进行过滤，任意一个预取请求在没有得到物理地址前不能向Cache发送预取请求，Filter内部的预取请求与MemBlock的TLB进行交互，进行虚实地址转换。在完成转换得到物理地址后，依次将region内需要预取的块地址发出。

## 整体框图
<!-- TODO lyq 添加整体框图 -->

上图为预取器与其他相关模块的交互示意图，展示了预取器产生一个L1 Dcache预取请求的流程：

1. 预取器从访存流水线处拿到训练数据。
2. 训练预取器，预取器发出预取请求到访存流水线。
3. 预取请求查询Dcache，结果为miss，分配Dcache MSHR。
4. MSHR向L2 Cache发送Acquire请求。
5. L2 Cache取回数据，回填至Dcache。

对L2 L3 Cache进行预取的流程与以上流程类似，不同的是请求发送给L2 L3 Cache的Prefetch Queue，再由Cache处理，详细内容可以查看对应的验证文档。

<!-- TODO lyq: 内部各模块的关系图 -->

上图为内部各模块的关系图。

## 接口时序

<!-- TODO lyq 添加接口时序-->

## 时钟复位

Table: 时钟复位说明
| Module                  | Clock | Reset |
| ----------------------- | ----- | ----- |
| SMSPrefetcher           | Clock | Reset |
| SMSTrainFilter          | Clock | Reset |
| ActiveGenerationTable   | Clock | Reset |
| PatternHistoryTable     | Clock | Reset |
| PrefetchFilter          | Clock | Reset |
| L1Prefetcher            | Clock | Reset |
| TrainFilter             | Clock | Reset |
| StrideMetaArray         | Clock | Reset |
| StreamBitVectorArray    | Clock | Reset |
| MutiLevelPrefetchFilter | Clock | Reset |

## 寄存器配置

Table: 自定义 CSR 配置寄存器说明

| 寄存器 | 地址 | 复位值 | 属性 | 描述                                                     |
| ---------- | -------- | ---------- | -------- | ------------------------------------------------------------ |
| spfctl     | 0X5C1    | 32’d97078  | RW       | bit0:    ICache预取器开关<br />bit1:    L2Cache预取器开关<br />bit2:    L1 DCache预取器开关<br />bit3:    L1 DCache预取器在Prefetch  Train下训练<br />bit4:   SMS AGT开关<br />bit5:    SMS PHT开关<br />bit9-6:   SMS  AGT active阈值<br />bit10-15: SMS AGT active page stride<br />bit63-16: 保留 |

## 参考文档

<!-- TODO lyq 更新到各自的文件中 -->

1. PLRU替换算法
2. [Spatial Memory Streaming 论文](https://infoscience.epfl.ch/record/112674/files/spatial_memory.pdf)
3. [Best Offset Prefetch 论文](https://inria.hal.science/hal-01254863/document)
4. [Stride 预取论文](https://www.computer.org/csdl/api/v1/periodical/mags/co/1978/12/01646791/13rRUx0xPD0/download-article/pdf)
5. Stream 预取论文
6. [Feedback Direct Prefetch 论文](https://users.ece.cmu.edu/~omutlu/pub/srinath_hpca07.pdf)
