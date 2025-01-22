# DCach控制单元CtrlUnit

## 功能描述

CtrlUnit用于控制DCache的ECC错误注入。每一个核的L1DCache配置一个memory map的寄存器控制的控制器，每一个支持ECC的硬件单元设置一个Control Bank。Bank寄存器配置完成之后，L1DCache会对第一次读取DCache触发ecc错误。

### 特性 1：地址空间

地址空间0x38022000-0x3802207F，总共128字节空间，该空间为每个hart的局部空间。

### 特性 2：DCache Control Bank

每一个 Control Bank 包含寄存器：ECCCTL、ECCEID、ECCMASK，每一个寄存器是 8 字节。

![CtrlBank排布](./figure/DCache-ECCCtrlBank.svg)

* ECCCTL（ECC Control）：ECC 注入控制寄存器

  ![ECCCTL](./figure/DCache-ECCCTL.svg)

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

  ![ECCEID](./figure/DCache-ECCEID.svg)

  当 ese==1并且ede==1时，开始递减，直至减为0。目前采用和核频率相同的时钟，也可以分频。由于ECC注入依赖DCache的访问，所以EID的时间和ECC错误触发的时间可能不一致。

* ECCMASK（ECC Mask）：ECC注入掩码寄存器。

  ![ECCMASK](./figure/DCache-ECCMASK.svg)

  0 表示不反转，1 表示翻转。tag注入只使用ECCMASK0中对应tag长度的位。

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

  上表 Tag Hit 和 Tag ECC Error 与判断结果之间的关系
  * Data ECC 错误：命中行如果出现 ECC 错误，则认为出现 ECC 错误，如果不命中则不处理。
  * 如果指令访问触发 ECC 错误，则认为出现 Hardware error 并报告异常。
  * 只要出发错误，都需要向 BEU 发送错误信息。
  硬件检测到错误时，报送给 BEU，触发 NMI 外部中断

#### 普通访存指令

对于普通的访存指令，例如 Load 指令，在执行时只会触发 tag 或者 data 的 ECC 错误，并将错误
报送给 BEU，并且报告 Hardware Error(19)。

#### Probe/Snoop

对于 Probe/Snoop
* 如果出现 tag ecc error，不需要更改 cache 状态，并且需要向 l2 返回 corrupt=1 的 ProbeAck。
* 如果出现 data ecc error，按规则更改 cache 状态，如果需要返回数据，则需要向 l2 返回 corrupt=1 的 ProbeAckData。

#### Replace/Evict

对于 Replace/Evict，需要向 l2 返回 corrupt=1 的 ReleaseData。

#### Store to DCache

对于 Sbuffer 写入数据至 DCache
* 如果出现 tag ecc error，则根据 Repalce/Evict 流程释放 cacheline，并将数据写入 dcache 中，不向 l2 报送错误。
* 如果出现 data ecc error，则直接写入数据，不向 l2 报送错误

#### Atomics

对于 Atomic，不向 l2 报送错误

## 整体框图

![CtrlUnit架构](./figure/DCache-CtrlUnit.svg)

## 接口时序
