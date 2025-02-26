# 错误处理与自定义故障注入指令

## 功能描述

CtrlUnit用于控制DCache的ECC错误注入。每一个核的L1DCache配置一个memory map的寄存器控制的控制器，每一个支持ECC的硬件单元设置一个Control Bank。通过MMIO访存指令读写CtrlUnit中的配置寄存器。寄存器配置完成之后，L1 DCache会对第一次读取DCache触发ecc错误（比如load指令或者MainPipe）。

### 特性 1：地址空间

地址空间0x38022000-0x3802207F，总共128字节空间，该空间为每个hart的局部空间。

### 特性 2：DCache Control Bank

如图\ref{fig:CtrlBank}所示，每一个 Control Bank 包含寄存器：ECCCTL、ECCEID、ECCMASK，每一个寄存器是 8 字节。

![CtrlBank排布](./figure/DCache-ECCCtrlBank.svg){#fig:CtrlBank width=17%}

* ECCCTL（ECC Control）：ECC 注入控制寄存器

  ![ECCCTL](./figure/DCache-ECCCTL.svg){#fig:EccCtrl width=50%}

  * ese（error signaling enable）：表示注入有效，初始化为 0。当注入成功后，ese将拉低。

  * pst：支持注入信号。当pst=1时，ECCEID计数器减到0并且成功注入后，注入计时器会被恢复到上一次设置的ECCEID，重新注入；当pst==0时，只注入一次。

  * ede（error delay enable）：表示counter有效，初始化为0。如果

    * ese==1并且ede==0，则error注入立即有效。

    * ese==1并且ede==1，则需要等到ECCEID递减到0之后，注入才有效。

  * cmp（component）：表示注入对象，初始化为 0。

    * 1’b0: 注入对象为tag

    * 1’b1: 注入对象为data

  * bank：bank有效信号，初始化为0，bank中的位置位时，对应mask有效

* ECCEID（ECC Error Inject Delay）：ECC 注入延迟控制器。

  ![ECCEID](./figure/DCache-ECCEID.svg){#fig:EccEid width=50%}

  * 当 ese==1并且ede==1时，开始递减，直至减为0。目前采用和核频率相同的时钟，也可以分频。由于ECC注入依赖DCache的访问，所以EID的时间和ECC错误触发的时间可能不一致。

* ECCMASK（ECC Mask）：ECC注入掩码寄存器。

  ![ECCMASK](./figure/DCache-ECCMASK.svg){#fig:EccMask width=50%}

  * 0 表示不反转，1 表示翻转。tag注入只使用ECCMASK0中对应tag长度的位, 超出部分不起作用。

### 特性 3：L1 DCache Ecc 错误处理流程

#### 报告错误

* Tag ECC 错误：只要某一路出现 ECC 错误，就判断出现了 ECC 错误。

  | Hit |  Error | Tag Error|
  |-----|--------|----------|
  |N    |N       | N        |
  |N    |Y       |Y (probably hit) |
  |Y    |N       |N         |
  |Y    |Y(hit with error) | Y |
  |Y    |Y(hit with no error) | N |

  表中Tag Hit 和 Tag ECC Error 与判断结果之间的关系

  * Data ECC 错误：命中行如果出现 ECC 错误，则认为出现 ECC 错误，如果不命中则不处理。

  * 如果指令访问触发 ECC 错误，则认为出现 Hardware error 并报告异常。

  * 只要出发错误，都需要向 BEU 发送错误信息。
  硬件检测到错误时，报送给 BEU，触发 NMI 外部中断

#### 普通访存指令

* 对于普通的访存指令，例如 Load 指令，在执行时只会触发tag或者data的ECC 错误，并将错误
报送给 BEU，并且报告 Hardware Error(19)。

#### Probe/Snoop

* 对于 Probe/Snoop

  * 如果出现 tag ecc error，不需要更改 cache 状态，并且需要向 l2 返回 corrupt=1 的 ProbeAck请求。

  * 如果出现 data ecc error，按规则更改 cache 状态，如果需要返回数据，则需要向 l2 返回 corrupt=1 的 ProbeAckData请求。

#### Replace/Evict

* 对于 Replace/Evict，

  * 如果出现 tag ecc error, 需要向l2返回corrupt=1的Release请求。

  * 如果出现 data ecc error, 需要向 l2 返回 corrupt=1 的 ReleaseData请求。

#### Store to DCache

* 对于 Sbuffer 写入数据至 DCache

  * 如果出现 tag ecc error，则根据 Repalce/Evict 流程释放 cacheline，并将数据写入 dcache 中，不向 l2 报送错误。

  * 如果出现 data ecc error，则直接写入数据，不向 l2 报送错误

#### Atomics

* 对于 Atomic，不向 l2 报送错误

## 整体框图

![Error架构](./figure/DCache-CtrlUnit.svg){#fig:CtrlUnit width=40%}

## 接口时序

### 配置寄存器时序

* 可以通过tilelink接口读写配置寄存器，如图\ref{fig:DCache-Error-Config-Timing}, A通道传递写地址和数据。

  * 配置地址为0x38022010的EccMask0寄存器，写入的数据为0xff;

  * 配置地址为0x38022008的EccEid寄存器，写入的数据为0x4;

  * 配置地址为0x38022000的EccCtl寄存器，写入的数据为0x5

![配置寄存器时序](./figure/DCache-Error-Config-Timing.svg){#fig:DCache-Error-Config-Timing width=80%}

### Tag注入时序

* 如图\ref{fig:DCache-Error-TagInj-Timing}所示，当配置好寄存器（EccCtl, EccEid和EccMask0）之后，当计时器计时到0，开始注入：

  * tag注入接口io_pseudoError_0_valid拉高，

  * 当注入成功后（即io_pseudoError_0_valid && io_pseudoError_0_ready == 1），EccCtl的ese位将清零，结束注入；

  * 以MainPipe为例，s1_tag_error、s2_tag_error和s3_tag_error逐级拉高，最后通过io_error端口向BEU报告错误信息

![Tag注入时序](./figure/DCache-Error-TagInj-Timing.svg){#fig:DCache-Error-TagInj-Timing width=80%}

\newpage

### Data注入时序

* 如图\ref{fig:DCache-Error-DataInj-Timing}所示，当配置好寄存器（EccCtl, EccEid和EccMask2）之后，当计时器计时到0，开始注入：

  * tag注入接口io_pseudoError_1_valid拉高，

  * 当注入成功后（即io_pseudoError_1_valid && io_pseudoError_1_ready == 1），EccCtl的ese位将清零，结束注入；

  * 以MainPipe为例，s2_data_error和s3_data_error逐级拉高，最后通过io_error端口向BEU报告错误信息

![Data注入时序](./figure/DCache-Error-DataInj-Timing.svg){#fig:DCache-Error-DataInj-Timing width=80%}
