# Error Handling and Custom Fault Injection Instructions

## Functional Description

The CtrlUnit is used to control ECC error injection in the DCache. Each core's
L1 DCache is configured with a memory-mapped register-controlled controller, and
each hardware unit supporting ECC is assigned a Control Bank. The configuration
registers in the CtrlUnit are accessed via MMIO load/store instructions. Once
the registers are configured, the L1 DCache will trigger an ECC error on the
first read operation (e.g., a load instruction or MainPipe access).

### Feature 1: Address Space

* The address space 0x38022000-0x3802207F, totaling 128 bytes, is the local
  space for each hart.

### Feature 2: DCache Control Bank

* As shown in Figure \ref{fig:CtrlBank}, each Control Bank contains the
  following registers: ECCCTL, ECCEID, and ECCMASK, each of which is 8 bytes in
  size.

![CtrlBank Layout](./figure/DCache-ECCCtrlBank.svg){#fig:CtrlBank width=17%}

* ECCCTL (ECC Control): ECC injection control register

  ![ECCCTL](./figure/DCache-ECCCTL.svg){#fig:EccCtrl width=50%}

  * ese (error signaling enable): Indicates that the injection is valid,
    initialized to 0. When the injection is successful, ese will be pulled low.

  * pst: Injection support signal. When pst=1, after the ECCEID counter
    decrements to 0 and injection is successful, the injection timer is reset to
    the previously set ECCEID value for re-injection; when pst==0, injection
    occurs only once.

  * ede (error delay enable): Indicates the counter is active, initialized to 0.
    If

    * If ese==1 and ede==0, error injection takes effect immediately.

    * When ese==1 and ede==1, the injection becomes effective only after ECCEID
      decrements to 0.

  * cmp (component): Indicates the injection target, initialized to 0.

    * 1’b0: Injection target is tag

    * 1’b1: Injection target is data

  * bank: Bank valid signal, initialized to 0. When a bit in the bank is set,
    the corresponding mask becomes active.

* ECCEID (ECC Error Inject Delay): ECC injection delay controller.

  ![ECCEID](./figure/DCache-ECCEID.svg){#fig:EccEid width=50%}

  * When ese==1 and ede==1, the decrement starts until it reaches 0. Currently,
    the same clock frequency as the core is used, but it can also be divided.
    Since ECC injection depends on DCache access, the timing of EID and ECC
    error triggering may not align.

* ECCMASK (ECC Mask): ECC injection mask register.

  ![ECCMASK](./figure/DCache-ECCMASK.svg){#fig:EccMask width=50%}

  * 0 indicates no inversion, 1 indicates inversion. Tag injection only uses the
    bits corresponding to the tag length in ECCMASK0; any excess bits have no
    effect.

### Feature 3: Bus Error Unit Controller

* DCache的ECC错误将统一发送到Bus Error Unit控制器处理。Bus Error Unit控制器保存信息有：

  Table: Bus Error Unit保存的信息

  | Field            | Descrption                          | Initial value | Address    |
  | ---------------- | ----------------------------------- | ------------- | ---------- |
  | cause            | Cause of the error event            | 0             | 0x38010000 |
  | value            | Physical address of the error event | Undefined     | 0x38010008 |
  | enable           | Event valid mask                    | 1             | 0x38010010 |
  | global_interrupt | Global interrupt enable mask        | 0             | 0x38010018 |
  | accrued          | 累积事件掩码                              | 0             | 0x38010020 |
  | local_interrupt  | Hart local interrupt enable mask    | 0             | 0x38010028 |

  * Address space

    The physical address space of the Bus Error Unit is: 0x38010000 - 0x38010fff

  * Supported error types

    * ICache ECC Error

    * DCache Ecc Error

    * L2Cache Ecc Error

  * Controlled interrupt

    * 局部中断：只能报告给Bus Error Unit所在的Hart, 上报至后端，有后端负责中断处理，目前采用NMI_31中断。

    * Global interrupt: If a global interrupt occurs, the Bus Error Unit sends
      the interrupt information to the PLIC, which is responsible for reporting
      the interrupt.

### Feature 4: L1 DCache ECC Error Handling Process

* Report error

  * Tag ECC error: An ECC error is determined as long as it occurs in any path.

    Table: Tag ECC Error and Tag Hit Relationship

    | Hit | Error                | Tag Error        |
    | --- | -------------------- | ---------------- |
    | N   | N                    | N                |
    | N   | Y                    | Y (probably hit) |
    | Y   | N                    | N                |
    | Y   | Y(hit with error)    | Y                |
    | Y   | Y(hit with no error) | N                |

    表中Tag Hit 和 Tag ECC Error 与判断结果之间的关系

    * Data ECC 错误：命中行如果出现 ECC 错误，则认为出现 ECC 错误，如果不命中则不处理。

    * If an instruction access triggers an ECC error, it is considered a
      Hardware error and an exception is reported.

    * Any triggered error must send error information to the BEU. When hardware
      detects an error, it reports to the BEU, triggering an NMI external
      interrupt.

* Regular memory access instruction

  * For regular memory access instructions such as Load, execution will only
    trigger tag or data ECC errors, which are reported to the BEU along with a
    Hardware Error (19).

* Probe/Snoop

  * For Probe/Snoop

    * If a tag ECC error occurs, there is no need to change the cache state, and
      a ProbeAck request with corrupt=1 must be returned to L2.

    * 如果出现 data ecc error，按规则更改 cache 状态，如果需要返回数据，则需要向 l2 返回 corrupt=1 的
      ProbeAckData请求。

* Replace/Evict

  * 对于 Replace/Evict，

    * If a tag ECC error occurs, a Release request with corrupt=1 must be
      returned to L2.

    * If a data ECC error occurs, a ReleaseData request with corrupt=1 must be
      returned to L2.

* Store to DCache

  * For Sbuffer writing data to DCache

    * If a tag ECC error occurs, the cacheline is released according to the
      Replace/Evict process, and the data is written into the DCache without
      reporting the error to L2.

    * If a data ECC error occurs, the data is written directly without reporting
      the error to L2.

* Atomics

  * For Atomic operations, exceptions are reported, but errors are not forwarded
    to L2.

* 多错误选择

  * If multiple errors occur simultaneously, the priority order is ldu0 > ldu1 >
    ldu2 > MainPipe

\newpage
## Overall Block Diagram

![Error架构](./figure/DCache-CtrlUnit.svg){#fig:CtrlUnit width=40%}

## 接口时序

### Configuration register timing

* Configuration registers can be read and written via the tilelink interface, as
  shown in Figure \ref{fig:DCache-Error-Config-Timing}, with the write address
  and data transmitted on the A channel.

  * Configure the EccMask0 register at address 0x38022010 with the data value
    0xff;

  * Configure the EccEid register at address 0x38022008 with a write value of
    0x4.

  * Configure the EccCtl register at address 0x38022000 with the data value 0x5

![Configuration Register
Timing](./figure/DCache-Error-Config-Timing.svg){#fig:DCache-Error-Config-Timing
width=80%}

### Tag Injection Timing

* As shown in Figure \ref{fig:DCache-Error-TagInj-Timing}, after configuring the
  registers (EccCtl, EccEid, and EccMask0), injection begins when the timer
  counts down to 0:

  * The tag injection interface io_pseudoError_0_valid is asserted.

  * Upon successful injection (i.e., when io_pseudoError_0_valid &&
    io_pseudoError_0_ready == 1), the ese bit of EccCtl will be cleared, ending
    the injection.

  * Taking MainPipe as an example, the s1_tag_error, s2_tag_error, and
    s3_tag_error signals are sequentially raised, and finally, the error
    information is reported to the BEU through the io_error port.

![Tag Injection
Timing](./figure/DCache-Error-TagInj-Timing.svg){#fig:DCache-Error-TagInj-Timing
width=80%}

\newpage

### Data injection timing

* 如图\ref{fig:DCache-Error-DataInj-Timing}所示，当配置好寄存器（EccCtl,
  EccEid和EccMask2）之后，当计时器计时到0，开始注入：

  * The tag injection interface io_pseudoError_1_valid is asserted,

  * Upon successful injection (i.e., when io_pseudoError_1_valid &&
    io_pseudoError_1_ready == 1), the ese bit of EccCtl will be cleared, ending
    the injection;

  * Taking MainPipe as an example, s2_data_error and s3_data_error are
    sequentially raised, and finally, error information is reported to the BEU
    via the io_error port.

![Data Injection
Timing](./figure/DCache-Error-DataInj-Timing.svg){#fig:DCache-Error-DataInj-Timing
width=80%}
