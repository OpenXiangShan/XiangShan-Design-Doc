# Probe 队列 ProbeQueue

## 功能描述
负责接收并处理来自L2的一致性请求，包含8项ProbeEntry，每一项负责一个Probe请求, 将Probe请求转成内部信号后发送到MainPipe,
由MainPipe修改被Probe块的权限，等MainPipe返回应答后释放ProbeEntry。

ProbeQueue只和L2通过B通道交互，以及与MainPipe互连。内部由8项ProbeEntry组成，每一项通过一组状态寄存器控制请求信号的接收、转换以及发送。

### 特征 1： 别名问题

Kunminghu架构采用了64KB的VIPT cache，从而引入了cache别名问题。为解决别名问题，L2
Cache的目录会维护在DCache中保存的每一个物理块对应的别名位。当DCache在某个物理地址上想要获取另一别名位的块时，L2
Cache会发起Probe请求，将DCache中原有的别名块probe下来，并且在TileLink
B通道中记录其别名位。ProbeQueue收到请求后会将别名位和页偏移部分进行拼接，转成内部信号发送到MainPipe, 由
MainPipe访问DCache存储模块读取数据。

### 特征 2：由原子指令引发的阻塞

由于原子操作 (包括 lr-sc)
在DCache中完成，执行LR指令时会保证目标地址已经在DCache中，此时为了简化设计，LR在MainPipe中会注册一个reservation
set，记录LR的地址, 并阻塞对该地址的Probe。为了避免带来死锁, MainPipe会在等待SC一定时间后不再阻塞Probe(由参数 LRSCCycles
和 LRSCBackOff 决定), 此时再收到SC指令则均被视为SC fail. 因此, 在LR注册reservation
set后等待SC配对的时间里需要阻塞Probe请求对DCache进行操作。

## 整体框图

ProbeQueue整体架构如[@fig:DCache-ProbeSnoop]所示。

![ProbeSnoop流程图](./figure/DCache-ProbeSnoop.svg){#fig:DCache-ProbeSnoop}



## 接口时序
### 请求接口时序实例

[@fig:DCache-ProbeSnoop-Timing]展示了Probe Queue处理一个probe请求的接口时序，Probe
Queue首先收到来自L2的probe请求，转换成内部请求并为其分配一项空的ProbeEntry；经过一拍的状态转换可以向MainPipe 发送probe请求,
但由于时序考虑该请求会再被延迟一拍（ProbeQueue里选择一项有一个arbiter，
MainPipe入口也有一个arbiter选择各来源的请求，两次仲裁在一拍完成比较困难，因此在这里先锁存一拍），因此两拍后pipe_req_valid拉高；后续等接收到MainPipe的resp后，释放ProbeEntry。

![ProbeSnoop时序](./figure/DCache-ProbeSnoop-Timing.png){#fig:DCache-ProbeSnoop-Timing}

## ProbeEntry模块

Probe
Entry由一系列状态寄存器进行控制，由一个状态机进行Probe事务的执行。[@tbl:ProbeEntry-state]展示了每个Entry中包含的三个状态寄存器的含义，状态机设计如[@fig:DCache-ProbeEntry]所示：

Table: ProbeEntry状态寄存器含义 {#tbl:ProbeEntry-state}

| 状态          | Descrption                       |
| ----------- | -------------------------------- |
| s_invalid   | 复位状态，该Probe Entry为空项             |
| s_pipe_req  | 已分配Probe请求，正在发送Main Pipe请求       |
| s_wait_resp | 已完成Main Pipe请求的发送，等待Main Pipe的应答 |

![ProbeEntry状态机](./figure/DCache-ProbeEntry.svg){#fig:DCache-ProbeEntry}

