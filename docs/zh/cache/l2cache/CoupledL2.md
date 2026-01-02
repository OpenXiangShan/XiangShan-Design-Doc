# 二级缓存 CoupledL2

## 子模块列表

CoupledL2 顶层分为（默认）4 个 Slice 、MMIOBridge、预取器。

预取器包括 L2 本地的预取器 Best-Offset Prefetch（BOP），和 L1 DCache 预取接收器，用于接收在 DCache 训练但是需要取到 L2 的预取请求。

MMIOBridge 即 MMIO 请求转接桥，用于将 TileLink 总线的 MMIO 请求转换为 CHI 请求，并和 cacheable 地址空间的 CHI 请求做仲裁，从统一的 CHI 接口接入互联总线。

CoupledL2 的 4 个 Slice 按照地址低位划分，不同地址的请求或预取地址会被分散到不同的 Slice。

每个 Slice 中的子模块列表如下：

| 子模块 | 描述 |
| --- | --- |
| SinkA | 上游 TileLink 总线 A 通道控制器 |
| SinkC | 上游 TileLink 总线 C 通道控制器 |
| GrantBuffer | 上游 TileLink 总线 D/E 通道控制器 |
| TXREQ | 下游 CHI 总线 TXREQ 通道控制器 |
| TXDAT | 下游 CHI 总线 TXDAT 通道控制器 |
| TXRSP | 下游 CHI 总线 TXRSP 通道控制器 |
| RXSNP | 下游 CHI 总线 RXSNP 通道控制器 |
| RXDAT | 下游 CHI 总线 RXDAT 通道控制器 |
| RXRSP | 下游 CHI 总线 RXRSP 通道控制器 |
| Directory | 目录，保存元数据信息的 SRAM |
| DataStorage | 数据 SRAM |
| RefillBuffer | 回填数据寄存器堆 |
| ReleaseBuffer | 释放数据寄存器堆 |
| RequestBuffer | A 通道请求缓冲 |
| RequestArb | 请求仲裁器，主流水线 s0~s2 流水级 |
| MainPipe | 主流水线 s3~s5 流水级 |
| MSHRCtl | MSHR（Miss Status Handling Registers）控制模块，默认包含 16 项 MSHR |


## 设计规格

- 与上游 L1Cache / PTW 互联采用 TileLink 总线协议
- 与下游 HN-F 采用 CHI 总线协议，支持 B/C/E.b 3 个 CHI 总线版本（默认 E.b）
- 支持如下 CHI Read 事务：
  
    - ReadNoSnp（B/C/E.b）（仅用于 MMIO 与 Uncache 请求）
    - ReadNotSharedDirty（B/C/E.b）
    - ReadUnique（B/C/E.b）
  
- 支持如下 CHI Dataless 事务：
  
    - MakeUnique（B/C/E.b）
    - Evict（B/C/E.b）
    - CleanShared（B/C/E.b）
    - CleanInvalid（B/C/E.b）
    - MakeInvalid（B/C/E.b）
  
- 支持如下 CHI Write 事务：
  
    - WriteNoSnpPtl（B/C/E.b）（仅用于 MMIO 与 Uncache 请求）
    - WriteBackFull（B/C/E.b）
    - WriteCleanFull（B/C/E.b）
    - WriteEvictOrEvict（E.b）

- 支持如下 CHI Snoop 事务：

    - SnpOnceFwd（B/C/E.b）
    - SnpOnce（B/C/E.b）
    - SnpStashUnique（B/C/E.b）
    - SnpStashShared（B/C/E.b）
    - SnpCleanFwd（B/C/E.b）
    - SnpClean（B/C/E.b）
    - SnpNotSharedDirtyFwd（B/C/E.b）
    - SnpNotSharedDirty（B/C/E.b）
    - SnpSharedFwd（B/C/E.b）
    - SnpShared（B/C/E.b）
    - SnpUniqueFwd（B/C/E.b）
    - SnpUnique（B/C/E.b）
    - SnpUniqueStash（B/C/E.b）
    - SnpCleanShared（B/C/E.b）
    - SnpCleanInvalid（B/C/E.b）
    - SnpMakeInvalid（B/C/E.b）
    - SnpMakeInvalidStash（B/C/E.b）
    - SnpQuery（E.b）

- 1MB 容量，8 路组相联结构，按照地址低位划分为 4 个 Slice
- 缓存行大小 64B，总线数据位宽 32B，一次完整的缓存行传输需要 2 个 beat 的数据传输
- 采用类 MESI 的缓存一致性协议
- 和 DCache 之间采用严格包含策略，和 ICache / PTW 之间采用不严格包含策略
- 采用非阻塞主流水线结构
- 最高访问并行度为 4 × 16（每个 Slice 包含 16 项 MSHR，共 4 个 Slice），每个 Slice 中至多 15 项 MSHR 可用于 L1Cache / PTW 的访问
- 支持相同 set 请求的并行访问
- 支持在收到 L2 Cache 缺失的重填数据后再进行替换路的选取和替换
- 支持访存请求和预取请求的融合
- 支持产生 L2 Refill Hint 信号用于 Load 指令的提前唤醒
- 支持 BOP 预取器
- 支持 L1 训练并回填到 L2 的预取请求的处理
- 支持 DRRIP / PLRU 等替换算法，默认 DRRIP
- 支持硬件处理 Cache 别名
- 支持 MMIO 请求的处理，MMIO 请求在 CoupledL2 中由 TileLink 总线转换为 CHI 总线，并和 4 个 Slice 发起的 cacheable 请求做仲裁


## 功能描述

CoupledL2 接收香山核 DCache / ICache / PTW 发送的 TileLink 回填、替换请求，完成相应数据块的转移与一致性状态转移，同时在片上网络中作为 RN-F，维护香山核在片上互联系统中的缓存一致性。

CoupledL2 模块通过上游 TileLink 通道控制器（SinkA / SinkC）接收，将其转化为内部请求。请求通过请求仲裁进入主流水线，读取目录获取缓存块的状态，根据缓存块状态和请求信息判断是否能够处理：

- 若本层缓存可以直接处理该请求，则继续在主流水线中进行读数据、更新目录等操作，然后进入 GrantBuffer，转化为 TileLink 总线响应。
- 若需要和其它缓存进行交互才能处理该请求，则为其配一个MSHR。MSHR根据需求向上下层Cache发送子请求，等待收到响应并满足释放条件后，再释放任务重新进入主流水线，进行读缓冲区、读写数据、更新目录等操作，然后进入通道控制器模块，转化为 TileLink 总线响应。

当一个请求所需的全部操作在MSHR中完成时，MSHR被释放，等待接收新的请求。

### 采用类 MESI 的缓存一致性协议

香山核的缓存子系统遵循 TileLink 一致性树的规则。CoupledL2 中的缓存行状态包括 N(Nothing)、B(Branch)、T(Trunk)、TT(Tip) 4 个状态：

- N：无效
- B：只读权限
- T：当前核具有写权限，但是写权限位于上游 cache，当前 cache 层次不可读不可写
- TT：可读可写

一致性树按照内存、L3、L2、L1的顺序自下而上生长，内存作为根节点拥有可读可写的权限，子节点的权限都不能超过父节点的权限。其中TT代表拥有T权限的最上层子节点（也是T权限树的叶子节点），说明该节点上层只有N或B权限，相反T权限而不是TT权限的节点代表上层一定还有T/TT权限节点。详细规则请参考TileLink手册。

### 采用目录记录缓存行信息

CoupledL2 是基于目录结构的 Inclusive Cache（此处所指的“目录”是广义的，包含元数据和Tag）。元数据包含：状态位state / 脏位dirty / 是否在上层缓存 clients / 在上层的别名位 alias / 是否是预取上来的 prefetch / 来自哪个预取器 prefetchSrc / 是否被访问过 accessed。

在流水线 s1 级 RequestArb 会向目录发起读请求，读取 Tag Array 判断是否命中。如果命中则选择命中路，如果不命中则根据替换算法选择一个替换路，然后将选中路的元数据信息返回给 s3 级 MainPipe。

### 采用非阻塞流水线结构

CoupledL2 采用主流水线架构，来自各通道的请求经过仲裁进入主流水线，进行都目录操作，然后根据请求信息和目录结果安排响应的操作：

#### Acquire 请求处理流程

如 [@fig:acquire] 所示。

![Acquire 请求处理流程](./figure/CHI-CoupledL2-Acquire.svg){#fig:acquire}

#### Snoop 请求处理流程

如 [@fig:snoop] 所示。

![Snoop 请求处理流程](./figure/CHI-CoupledL2-Snoop.svg){#fig:snoop}

#### Release 请求处理流程

Release 请求处理流程如下：

1. 从 SinkC 接收来自 L1 DCache 的 Release 请求，并转化为内部请求
2. s1 Release 请求进入流水线，并查询目录
3. s3 得到查目录的结果（由于是 L1 DCache 和 L2 是严格包含关系所以 Release 一定会命中）；s3 写目录，如果有脏数据需要在 s3 写入 DataStorage
4. s3 生成 ReleaseAck 响应，在 s3~s5 的某一流水级离开流水线，进入 GrantBuffer 将 ReleaseAck 返回给 L1

### 收到重填数据后再进行替换路选取和替换

缓存在收到新请求但是set已满的时候，按照常规逻辑，需要先选择一个替换路，将其写入下级缓存，从而为即将重填的缺失数据空出位置，然后等待新数据块从下级缓存重填上来，再将其写入。但是这种方式会存在一些问题：

1. 一方面，从下级缓存重填往往需要较长的延迟（几十拍到上千拍），在这段时间内，旧的数据块已经被释放掉，新的数据块尚未收到，所以这个位置实际上是没有有效数据的，从而造成了缓存资源的空闲和浪费，降低了缓存的有效容量。

2. 另一方面，如果在这段时间内，上层缓存正好又要访问被替换的数据块，因为此时数据块已经被释放，所以只能再次向下层缓存获取，从而使得访问延迟大大增加。

CoupledL2 将替换路的选择和替换数据的释放延后到收到重填数据时。具体地，在请求进入缓存时，需要读取目录信息来判断是否命中。如果命中，则读取数据并返回（标准流程）。如果缺失，CoupledL2 不会根据读目录结果来选择一个替换块并安排替换块的释放，而只是为其分配一项 MSHR，并向下层缓存发请求获取数据。等待下层返回重填数据后，让 MSHR 任务再次读目录，此时再选出替换块，从数据存储单元读出替换块的数据，向下层缓存释放。最后再将新数据块写入存储单元。

由于与DataStorage交互只在MainPipe的s3级，且DataStorage的SRAM是单端口的，因此我们无法利用一个MSHR Task同时完成 (1) 将被替换数据块的内容读出并向下层缓存释放，和 (2) 将新数据块写入。所以这 2 步操作需要分成 MSHR Refill 和 MSHR Release 两个任务，Refill先于Release发出。又基于另外 2 点考虑：(1) 读旧数据必须要早于写新数据，(2) 必须尽快向L1返回数据，所以我们为两个MSHR Task分别安排如下任务：

- MSHR Refill：读RefillBuffer获取重填数据反馈给L1；读DataStorage获取旧数据存入ReleaseBuf；更新目录为新数据的元数据
- MSHR Release：读ReleaseBuf并将数据向L3释放；读 RefillBuffer将重填数据写入DataStorage

### 支持同 Set 请求的并行访问

CoupledL2 支持多个相同 Set 请求的并行访问。对于多个相同 Set 的请求，这些请求在收到重填数据之前是不需要选择替换路的，因此在收到重填数据之前都是可以并行访问的。收到重填数据后，MSHR 开始选择替换路，并将替换块写入下级缓存。目录在选择替换路时需要确保不会选到正在替换的路，从而保证相同 Set 的多个请求一定会选到不同的替换路。

### Load 指令提前唤醒

CoupledL2 每一次向 L1 DCache 重填数据时，都会在 GrantData 发出的前 3 拍发送 Refill Hint 信号送到核内的 LoadQueue。LoadQueueReplay 收到唤醒信号会立刻唤醒需要重发的 Load 进入 LoadUnit，Load 指令会在 LoadUnit 的 s2/s3 流水级收到重填的数据，从而减低 Load 在 L1 缺失时的访问延迟。

### 支持硬件预取

CoupledL2 的硬件预取器会同时接收 BOP 预取请求和 L1 DCache 发送的预取请求，并将这些请求送进预取队列（PrefetchQueue）。预取队列满时会自动丢弃队头最老的预取请求，让更新的预取请求入队，从而保证预取时效性。

### 支持请求融合

实验观察发现，L2 Cache 中存在占比较大的不及时预取，即预取器虽然预测到了未来需要的数据，但请求发送较晚，当预取导致的cache miss还在MSHR中等待下层缓存数据返回时，对同地址的Acquire请求已经到达L2。为了不让此类Acquire请求在RequestBuffer入口被阻塞，导致L2入口被占满，后续请求无法进入，当前L2设计了一套合并不及时的Prefetch与后续同地址Acquire的请求融合机制。请求融合功能实现如下：

1.	在SinkA通道的入口RequestBuffer中判断来自L1的A请求是否满足合并条件，条件为：新请求为 Acquire，且在 MSHRs 中存在 miss 请求为 Prefetch，并与 Acquire 地址相同
2.	若满足合并条件，则新请求不需要进入队列被阻塞，而是直接进入同地址Prefetch对应的MSHR项中，并对该项标记mergeA，新增加一系列请求状态信息，使其包含两个请求的内容
3.	当目标数据从L3返回后，MSHR项被唤醒，发送任务到主流水线进行处理。在主流水线中选择替换路并回填新数据，而数据块的meta则更新为Acquire请求处理完成后的状态，同时该请求还会将信息传入预取器作为训练
4.	在处理请求响应时，这个合并请求会从主流水线进入GrantBuffer，对于Prefetch请求，L2返回预取响应；而对于Acquire请求，L2通过grantQueue队列对发出Acquire的上游节点返回数据和响应

### 支持硬件处理 Cache 别名

香山核的 L1 Cache 均采用 VIPT 的索引方式，其中 DCache 为 64KB 的 4 路组相联结构，用于访问 DCache 的索引和块内偏移超出了 4KB 页的页偏移，由此引入 Cache 别名问题：如 [@fig:cache-alias] 所示，当两个虚拟页映射到同一个物理页时，两个虚拟页的别名位（索引超出 4KB 页偏移的部分）有较大概率是不一样的，如果不做额外处理，通过 VIPT 索引后两个虚页中的缓存块会位于 DCache 的不同 set，导致同一个物理地址在 DCache 中缓存了两份，如果 DCache 不做额外处理的话会引入缓存一致性错误。

![Cache 别名原理示意图](./figure/CHI-CoupledL2-cache-alias.svg){#fig:cache-alias}

香山核是通过 CoupledL2 以硬件方式解决 Cache 别名问题的。具体解决方式是由 CoupledL2 记录上层数据的别名位，保证一个物理地址缓存块在 L1 DCache 中最多只有一种别名位。当上层缓存发送 Acquire 请求时会带上别名位，L2 Cache 会检查目录，如果命中但是别名不一致，会向上层缓存 Probe 之前记录的别名位，并将 Acquire 的别名位写入目录。

## 总体设计

### 整体框图

XSTile（包括香山核和 CoupledL2）结构框图如 [@fig:xstile] 所示。

![XSTile 结构框图](./figure/CHI-CoupledL2-SoC.svg){#fig:xstile}


CoupledL2 微结构框图如 [@fig:coupledl2-microarch] 所示。

![CoupledL2 微结构图](./figure/CHI-CoupledL2-microArch.svg){#fig:coupledl2-microarch}