# Load 指令执行单元 LoadUnit

## 功能描述
load指令流水线，接收load发射队列发送的load指令，在流水线中处理完成后将结果写回LoadQueue和ROB，用于指令提交以及唤醒后续依赖本条指令的其他指令。同时，LoadUnit需要给发射队列、Load/StoreQueue反馈一些必要的信息。

这些信息绝大多数直接体现在接口列表中，根据输入和输出做如下描述。

* 输入
    * 接收来自CtrlBlock的redirect信号，根据重定向信号刷新load流水线。
    * Load_s0阶段接收来自ExuBlock（发射队列）发射的load指令信息，根据指令的类型、是否命中访存违例预测器需要阻塞、指令的源操作数和立即数等信息对load指令进行处理。根据指令的类型（例如ld/lw/lb）等，可以判断需要加载的size，并根据size向dcache发送查询请求，并拼接数据等；根据是否命中访存违例预测器，判断是否需要等待StoreQueue forward的地址计算好，确认不会出现访存违例再提交；根据指令的源操作数和立即数，可以计算指令的虚拟地址，并根据虚拟地址向TLB查询物理地址、向dcache索引Index。另外，Load_s0阶段需要接收预取器的预取请求，和同样在Load_s0的其他请求根据优先级进行仲裁。预取器包括SMS预取器，以及stream&stride的集成预取器。Load_s0还可能接收load to load forward请求。目前不开启。Load_s0支持软件预取请求，其中prf_i请求计算出vaddr后，不需要请求TLB和DCache，其余软件预取指令与标量load执行通路一致。
    * Load_s1阶段接收来自dtlb的回复，包括根据load指令虚拟地址查询得到的物理地址、TLB是否缺失、以及该地址是否发生page fault、access fault等信息。当TLB发生缺失时，需要交付给LoadQueueReplay等待唤醒重发，因此需要传递TLB返回的MSHRid到LoadQueueReplay，当这个MSHRid从L2 TLB被refill时，可以根据refill的MSHRid精确唤醒。同时，对于TLB mshr已满或虽然访问TLB缺失，但正在被回填的情况，LoadUnit需要将TLB反馈的立即重发信号传递给LoadQueueReplay，无需等待即可调度重发。
    * Load_s2阶段接收来自pmp检查的回复，包括这条load指令的物理地址是否发生access fault，或者属于MMIO空间。如果物理地址发生access fault，需要上报异常；如果属于MMIO空间，则将这条指令提交给LoadQueue中的LoadQueueUncache进行处理。
    * Load_s2、Load_s3接收来自dcache的回复，包括dcache的返回数据、dcache是否缺失、是否发生ecc error、缺失时的MSHR id、是否发生bank conflict、是否缺失且MSHR已满等信息。同时，对于dcache miss，但正在由L2 Cache回填的情况，需要接收L2 Cache forward的信息。
    * 对于dcache命中的情况，会在Load_s3将dcache查询得到的数据返回LoadUnit，在LoadUnit中可以根据指令的不同类型对数据进行拼接。对于dcache未命中的情况，会根据未命中的细分原因（例如发生bank conflict、MSHR已满等），将这些原因同时传递进LoadQueueReplay中，对其进行重发。如果dcache虽然缺失，但MSHR未满，dcache会将分配的MSHRid告知LoadUnit。Loadunit需要把MSHRid写入LoadQueueReplay，等待精确唤醒。另外，如果dcache发生ecc error，LoadUnit需要将这条指令写回，并上报异常。
    * Load_s2、Load_s3接收来自sbuffer和StoreQueue关于前递的回复。当LoadUnit中正在处理的指令在sbuffer或StoreQueue中与某项匹配成功时，可以前递sbuffer或StoreQueue中的数据作为load的结果，数据和匹配情况会在Load_s2返回。如果StoreQueue中出现前递的数据，或前递需要等待的某个地址没有准备好，会把这些信息同时写回LoadQueueReplay进行处理。当sbuffer和StoreQueue前递的数据均有效时，采用StoreQueue前递的数据。另外，在Load_s3会返回虚实地址匹配失败的信号，这种情况表示虽然load和store的虚拟地址相同，但物理地址不同，需要反馈从取指重发。
    * Load_s3接收LoadQueue中LoadQueueUncache的请求，将uncache的数据根据地址低位进行拼接，并写回。
    * Load_s2和Load_s3需要接收loadqueueRAW和loadqueueRAR的请求。在Load_s2会返回RAW和RAR queue是否已满的信息，需要根据这些信息交由LoadQueueReplay重发。在Load_s3会返回RAR的检查结果，如果出现load-load违例，需要从取指重发。

* 输出
    * Load_s1阶段如果确定某条Load指令可以被顺利执行（满足不会发生dcache或 TLB miss，不会被冲刷等条件），则可以向Backend发送fast_uop信号，表示发射队列的快速唤醒有效信号。如果是prf_i软件预取指令，则将vaddr和valid发送到前端。Load_s3阶段会向后端返回feedback_slow信号，表示反馈，当feedback_slow中hit为true时无需后端重发，否则需要后端重发这条load指令。
    * Load_s3阶段时，如果一条load指令被顺利执行完毕，会通过io_ldout信号簇返回给后端进行写回。当io_ldout_valid为true时，表示有一条load指令要被写回，包括写回信息：是否产生异常以及异常种类、load指令对应的保留站信息、load指令写回的数据和需要写回的寄存器等。
    * Load_s0阶段向TLB发送查询请求，以及load指令对应的虚拟地址。同时LoadUnit还需要向TLB发送所需的页权限，对于普通的load请求或有读倾向的预取请求，均需要页表的读权限；对于有写倾向的预取请求需要页表的写权限。当硬件预取直接给出物理地址时，会发送no_translate信号，表示无需由tlb翻译。
    * Load_s0、Load_s1阶段向Dcache发送查询请求，Load_s1、Load_s2阶段可以发送kill信号，取消掉该查询请求。Load_s0阶段发送的查询请求包括控制信号valid、查询dcache所需的虚拟地址，查询请求的操作和种类、以及请求来源。Load_s1阶段发送的请求包括TLB查询返回的物理地址。另外，Load_s1阶段还包括load被唤醒重发的replay请求，以及对应的mshr项及物理地址。
    * Load_s1阶段，LoadUnit会将load指令对应的虚拟地址和物理地址发送给sbuffer，用于检测sbuffer中可能存在的st-ld forward情况。同时向StoreQueue探测是否存在 st-ld forward情况。LoadUnit需要发送给StoreQueue的信息包括load指令的虚拟地址、物理地址、读掩码、访存违例预测器相关信息，以及StoreQueue的队列信息等。
    * Load_s3阶段，LoadUnit会通过lsq_ldin信号簇对LoadQueue进行反馈。如果一条load指令未被执行完毕，无法写回，则需要等待再次重发；否则可以释放LoadQueue中资源。lsq_ldin信号簇包括一条load指令所需写回以及执行过程中的几乎所有信息，包括load指令的类型、对应的队列index、虚拟地址和物理地址、是否发生异常、是否命中访存违例预测器、是否需要重发以及重发原因等信息。另外，在Load_s3阶段还会给LoadQueue中的LoadQueueUncache发送ready信号，表示能否接收uncache请求的写回。
    * Load_s2阶段，LoadUnit需要分别写入loadqueueRAR和loadqueueRAW，检查ld-ld违例和st-ld违例。需要向两个队列均写入load指令对应的ROB和LoadQueue信息，以及load指令的物理地址、数据是否有效。当产生st-ld违例时，st-ld违例发出的重定向请求与分支预测错误的重定向请求处理方式相似, 不需要和ld-ld违例相同，等待指令到达ROB队尾才向前端发出重定向请求，因此需要额外写入loadqueueRAW关于ftq的相应信息。在Load_s3阶段可以向这两个队列发送revoke信号，撤销前一拍的写入请求。
    * Load_s3阶段，LoadUnit会向L1预取器（load stream & stride预取器）和SMS预取器发送预取请求，包括虚拟地址、物理地址等训练信息。同时，LoadUnit会在Load_s0阶段反馈给L1预取器能否接收高优先级/低优先级的预取请求。同时，Load_s0阶段还会反馈能否接收LoadQueueReplay的重发请求等控制信号。
    * Load_s3阶段，当满足快速重发条件时，LoadUnit会发送快速重发信号，直接由Load_s3->Load_s0。快速重发信号簇包括一条load指令所需写回以及执行过程中的几乎所有信息，包括load指令的类型、对应的队列index、虚拟地址和物理地址、是否发生异常、是否命中访存违例预测器等信息。
    * Load_s3阶段，当load指令因ld-ld违例、st-ld违例等原因需要重定向违例恢复时，需要返回给后端rollback信号簇，包括rob信息以及ftq信息等，用于回滚。

LoadUnit一共有4级流水线，根据不同阶段流水线进行功能描述。

### 特性 1：LoadUnit 各级流水线功能

* Load_s0
    * 接收不同来源的请求，并做仲裁。
    * 得到仲裁的指令向tlb和dcache发送查询请求。
    * 流水线流给Load_s1。

    仲裁的优先级从高到低列于下表。

    Table: Load_s0仲裁优先级

    | Load_s0请求来源 |
    | --- |
    | MisalignBuffer的load请求 |
    | dcache miss导致的loadQueueReplay重发 |
    | LoadUnit的快速重发 |
    | uncache请求 |
    | nc请求 |
    | LoadQueueReplay的其他重发 |
    | 高置信度的硬件预取请求 |
    | 向量load请求 |
    | 标量load/软件预取请求 |
    | load pointchaising请求 |
    | 低置信度的硬件预取请求 |

    目前昆明湖V2默认不开启load pointchaising。

* Load_s1
    * 接收来自Load_s0的请求。
    * s1_kill：当fast replay虚实地址匹配失败，l2l fwd失败，或redirect信号有效时，会将s1_kill信号置为true。
    * 可能向tlb或dcache追发kill信号。
    * 收到tlb的回复，根据物理地址查询dcache；对于hint的情况，一并发给dcache。
    * 向storequeue && sbuffer查询st-ld forward。
    * 接收storeunit请求，判断是否存在st-ld违例。
    * 检查是否发生异常。
    * 如果是nc指令，进行PBMT 检查
    * 如果是prf_i指令，向前端发送请求

* Load_s2
    * 接收来自Load_s1的请求。
    * 接收pmp检查的回复，判断是否发生异常；同时整合异常来源。
    * 接收dcache的回复信息，判断是否需要重发等。
    * 查询LoadQueue和StoreQueue是否发生ld-ld或st-ld违例
    * 向后端发送快速唤醒信号
    * 整合重发原因
    * 如果是nc指令，进行PMA & PMP检查

* Load_s3
    * 接收来自Load_s2的请求。
    * 向SMS预取器及L1预取器发送预取请求
    * 接收dcache返回的数据或前递的数据，进行拼接和选择
    * 接收uncache的load请求写回
    * 将完成的load请求写回后端
    * 将load指令的执行状态更新至LoadQueue中
    * 向后端发送重定向请求
    * 如果是misalign_ld，且跨16byte，需要发送请求到misalignBuffer

## 整体框图
<!-- 请使用 svg -->

![LoadUnit整体框图](./figure/LoadUnit.svg)

## 接口时序

### LoadUnit接口时序实例

![LoadUnit接口时序](./figure/LoadUnit-timing.svg)

load指令进入LoadUnit后，在Load_s0 请求TLB和DCache，Load_s1得到TLB返回的paddr，Load_s2得到是否命中DCache。在Load_s2进行st-ld和ld-ld违例检查，Load_s3通过io_lsq_ldin更新LoadQueue。在Load_s3通过ldout写回。

### Load_s0不同源仲裁时序实例

![Load_s0不同源仲裁时序](./figure/LoadUnit-s0-arb.svg)

图中示例了不同来源的load指令在Load_s0的仲裁，第三个clk只有io_ldin_valid有效，且握手成功，在下一拍进入Load_s1。第五个clk中io_ldin_valid和io_replay_valid同时有效，由于replay请求比标量load的优先级高，所以replay请求获得仲裁，进入Load_s1。