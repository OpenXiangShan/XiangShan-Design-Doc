# 数据高速缓存 DCache

<!-- TODO: 填写版本信息 -->

- 版本：V2R2
- 状态：WIP
- 日期：2025/02/28
  <!-- TODO: 填写 commit -->
- commit：[b6c14329cbd4a204593ce03d130052f820439a08](https://github.com/OpenXiangShan/XiangShan/tree/b6c14329cbd4a204593ce03d130052f820439a08)

## 术语说明

| 缩写   | 全称   | 描述   |
| ---- | ---- | ---- |
| TODO | TODO | TODO |

## 子模块列表

| 子模块             | 描述                |
| --------------- | ----------------- |
| BankedDataArray | 数据和ECC SRAM       |
| MetaArray       | 元数据寄存器堆           |
| TagArray        | Tag和ECC SRAM      |
| ErrorArray      | 错误标志寄存器堆          |
| PrefetchArray   | 预取元数据寄存器堆         |
| AccessArray     | 访问元数据寄存器堆         |
| LoadPipe        | Load访问DCache流水线   |
| StorePipe       | Store访问DCache流水线  |
| MainPipe        | DCache主流水线        |
| MissQueue       | DCache Miss状态处理队列 |
| WritebackQueue  | DCache数据写回请求处理队列  |
| ProbeQueue      | Probe/Snoop请求处理队列 |
| CtrlUnit        | DCache ECC注入控制器   |
| AtomicsUnits    | 原子指令运算单元          |

## DCache设计规格

| Feature     | 描述                                         |
| ----------- | ------------------------------------------ |
| Data Cache  | 64KB，4way组相联，256组，每组8bank                  |
|             | Virtually Indexed, Physically Tagged（VIPT） |
|             | Tag和每个bank采用SEC-DED ECC                    |
| Cacheline   | 64Bytes                                    |
| Replacement | Pseudo-Least Recently Used（PLRU）           |
| 读写接口        | 3*128 bits读流水线                             |
|             | 1*512 bits写流水线                             |

### Data RAM

对于每个访问DCache Data的请求，对DCache Data SRAM的返回数据，如下表表示的格式。

| 位域       | 描述               |
| -------- | ---------------- |
| [71, 64] | 64bits数据 ECC编码结果 |
| [63, 0]  | 64bits数据         |

### Tag RAM

对于每个访问DCache Tag的请求，对DCache Tag SRAM的返回数据，如下表表示的格式。

| 位域       | 描述                 |
| -------- | ------------------ |
| [42, 36] | 36bits tag ECC编码结果 |
| [35, 0]  | 36bits tag         |

### Meta

对于每个访问DCache Meta的请求，对DCache Meta的返回数据，如下表表示的格式。

| 位域      | 描述                     |
| ------- | ---------------------- |
| [1 : 0] | Cacheline coherence元数据 |
|         | 2'b00 Nothing          |
|         | 2'b01 Branch           |
|         | 2'b10 Trunk            |
|         | 2'b11 Dirty            |

## 整体框图

DCache模块整体架构如 [@fig:DCache-DCache] 所示。

![DCache整体架构](./figure/DCache-DCache.svg){#fig:DCache-DCache}

## 功能描述
### 特征 1：Load请求处理

对于普通的Load请求，DCache从LoadUnit接收一条load指令后（实现的Load流水线有三条，可以并行处理三个load请求），根据计算得到的地址查询tagArray和metaArray，比较判断是否命中：若命中缓存行则返回数据响应；若缺失则分配MSHR
(MissEntry) 项，将请求交给MissQueue处理，MissQueue负责向L2 Cache发送 Acquire 请求取回重填的数据，并等待L2
Cache返回的hint信号。当l2_hint到达后，向MainPipe发起回填请求，进行替换路的选取并将重填数据块写入存储单元，同时把取回的重填数据前递给LoadUnit完成响应；若被替换的块需要写回，则在WritebackQueue中向L2发送Release请求将其写回。
如果缺失的请求分配MSHR项失败，DCache会反馈一个MSHR分配失败的信号，由LoadUnit和LoadQueueReplay重新调度该load请求。

### 特征 2：Store请求处理

对于普通的Store请求，DCache从StoreBuffer接收一条store指令后，使用MainPipe流水线计算地址查询tag和meta，判断是否命中，若命中缓存行则直接更新DCache数据并返回应答；若缺失则分配MSHR将请求交给MissQueue，向L2请求要回填到Dcache的原目标数据行，并等待L2
Cache返回的hint信号。当l2_hint到达后，向MainPipe发起回填请求，进行替换路的选取并将重填数据块写入DCache存储单元，在完成对该数据的store操作后向StoreBuffer返回应答；若被替换的块需要写回，则在WritebackQueue中向L2发送Release请求将其写回。
如果缺失的请求分配MSHR项失败，DCache会反馈一个MSHR分配失败的信号，由StoreBuffer随后重新调度该store请求。

### 特征 3：原子指令处理

对于原子指令，由DCache的MainPipe流水线完成指令运算及读写操作，并返回响应。若数据缺失则同样向MissQueue发起请求，取回数据后继续执行该原子指令；对于AMO指令先完成运算操作,
再将结果写入；对于LR/SC指令，会设置/检查其 reservation
set。在原子指令执行期间，核内不会向DCache发出其他请求（参见Memblock文档）。

### 特征 4：Probe请求处理

对于Probe请求，DCache从L2 Cache接收Probe请求后，进入MainPipe流水线修改被Probe的数据块的权限，命中后下一拍返回应答。

### 特征 5：替换与写回

DCache采用write-back和write-allocate的写策略，由一个replacer模块计算决定缺失请求回填后被替换的块，可配置random、lru、plru替换策略，默认选择使用plru策略；选出替换块后将其放入WritebackQueue队列中，向L2
Cache发出Release请求；而缺失的请求则从L2读取目标数据块后填入对应Cacheline。
