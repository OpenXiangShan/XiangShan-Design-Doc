# CSR

- 版本：V2R2
- 状态：OK
- 日期：2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## 术语说明

Table: 术语说明

| 缩写    | 全称                            | 描述                                                       |
| ----- | ----------------------------- | -------------------------------------------------------- |
| CSR   | Control and Status Register   | 控制和状态寄存器                                                 |
| Trap  | Trap                          | 陷入，中断和异常的合称                                              |
| ROB   | Reorder Buffer                | 重排序缓存                                                    |
| PRVM  | Privilege Mode                | 特权级模式，包括M、S、U                                            |
| VM/V  | Virtual Mode                  | 虚拟化模式，处于虚拟化模式具有VS和VU两个特权级                                |
| EX_II | Illegal Instruction Exception | 非法指令异常                                                   |
| EX_VI | Virtual Instruction Exception | 虚拟指令异常                                                   |
| TVEC  | Trap Vector                   | Trap处理程序的入口配置寄存器，m/hs/vs三个模式独立                           |
| IMSIC | Incoming MSI Controller       | 传入消息中断控制器，定义在 The RISC-V Advanced Interrupt Architecture |

## 设计规格

支持执行CSR指令

支持执行CSR只读指令

支持 CSR 只读指令乱序

支持执行mret、sret、ecall、ebreak、wfi等系统级指令

支持接收中断，取优先级最高的中断发送到ROB处理

支持产生EX_II和EX_VI两类异常

支持接收来自ROB Trap（中断+异常）并处理Trap

支持符合 riscv-privileged-spec 规范的CSR实现

支持中断和异常代理

支持Smaia和Ssaia扩展

支持Sdtrig和Sdext扩展

支持H扩展

支持虚拟化中断

支持传入并处理外部中断

## 功能

CSR 作为一个功能单元 FU，与 fence 和 div 位于 intExuBlock 中的同一个 ExeUnit。CSR 内主要包含四个子模块，分别是
csrMod、trapInstMod、trapTvalMod 和 imsic。csrMod 是 CSR 的主要功能部件。

trapTvalMod 模块主要用于管理和更新与 trap 相关的目标值 tval。它根据输入信号 flush、targetPc 和 clear 等来更新或清除
tval，并确保在 clear 时 tval 是有效的。模块还包含一些状态逻辑，以确保在特定条件下正确更新 tval。这个模块需要从来自 csrMod 发出的
targetPc 以及来自于 flush 的 fullTarget 中选择来源，并且通过比较 robIdx 的先后来选择更新或是清除，最终输出 tval 信息。

trapInstMod 模块主要用于管理和更新 trap 的指令编码信息。它根据输入信号（如 flush、faultCsrUop 和
readClear）来更新或清除陷阱指令信息，并确保在特定条件下正确更新陷阱指令。模块还包含一些状态逻辑，以确保在特定条件下正确更新陷阱指令信息。这个模块需要从来自
decode 的指令信息（包括指令编码、FtqPtr 和 FtqOffset），以及来自 CSR 本身组合拼接出的 CSR
指令的指令信息中选择来源，并且通过比较 FtqPtr 和 FtqOffset 的先后来选择更新或是清除，以及更新的来源。在需要被 flush 或者
readClear 时设为无效。最终输出 trap 相关的指令编码，以及对应的 FtqPtr 和 FtqOffset。

imsic（Incoming MSI Controller） 模块主要用于 csrMod 在通过 indirect alias
CSR（mireg/sireg/vsireg）访问 IMSIC 的内容时进行交互，输入imsic 其必要的信息，如访问的 CSR
地址，所处于的特权级模式，写数据等，然后等到 imsic 的输出返回。如果 csrMod 本身的权限检查已经发现其应该产生异常，则不再向 imisc 发送请求。

CSR 负责执行 CSR 类别的指令和 mret、sret、ecall、ebreak、wfi 等系统类别的指令，接收来自 Backend 的指令 uop
和数据信息，在执行完成后将数据和跳转地址输出。若发生异常，则根据规则设置 EX_II 或 EX_VI。

CSR 负责接收来自外部中断控制器 CLINT 和 IMSIC 的 MSIP、MTIP、MEIP、SEIP、VSTIP、VSEIP 等中断
pending，根据当前特权级及其全局中断使能位决定是否响应，并对相应中断按优先级排序，选出优先级最高的中断交给 ROB 处理。

CSR 负责接收来自 ROB 的 Trap
信息，根据代理情况（m[e|i]deleg和h[e|i]deleg）将特权级模式（PRVM）和虚拟化模式（V）设置为处理 Trap 的特权级，修改相关 CSR
状态，并改变执行流为 TVEC 对应的 Trap Handler 的起始地址。

CSR
负责保存控制浮点和向量执行的配置信息（Frm、Vstart、Vl、Vtype、Vxrm等），并存储浮点和向量指令执行产生的额外结果（Fflags、Vxsat等）。

CSR 负责和 IMSIC 通过自定义数据线交互，读写配置在 IMSIC 中的 mireg、sireg 和 vsireg 的**部分**寄存器（external
interrupts部分）。

CSR 负责配置和更新 TLB 的相关信号，以确保 TLB 能够正确地进行虚拟地址到物理地址的转换。包括检测 ASID 和 VMID
的变化，satp/vsatp/hgatp 等寄存器值的传递，mstatus/vsstatus 中的 mxr/sum，menvcfg/henvcfg 中的 pmm
等权限和控制位的传递，虚拟内存模式的选择以及物理内存保护扩展的配置。通过这些配置，TLB 能够在不同的虚拟内存模式下正确地执行地址转换。

CSR 负责根据当前的特权模式和寄存器的状态，设置和传递与指令 decode
相关的非法指令和虚拟指令的标志。这些标志用于指示某些指令在特定的特权模式下是否是非法的或虚拟的。通过这些标志，硬件可以在指令解码阶段正确地处理这些指令。

## 自定义 CSR

除去 RISC-V 手册定义的 CSR 外，我们还实现了 7 个自定义的
CSR：sbpctl、spfctl、slvpredctl、smblockctl、srnctl、mcorepwr 和 mflushpwr。

其中，sbpctl、spfctl、slvpredctl、smblockctl 和 srnctl 这 5 个自定义 CSR 定义在 HS 模式，mcorepwr
和 mflushpwr 这 2 个自定义 CSR 定义在 M 模式。

对这些自定义 CSR 的访问除了遵循特权级（低特权不能访问高特权）的约束外，还受到 Smstateen/Ssstateen 扩展中 C
字段对自定义内容访问的控制。

以下是各个自定义 CSR 的定义。

### sbpctl

sbpctl（Speculative Branch Prediction Control register） 的地址是 0x5C0，是一个定义在 HS
模式的可读写寄存器。

Table: sbpctl 的定义

| 字段名称        | 字段位置   | 初始值 | 描述                            |
| ----------- | ------ | --- | ----------------------------- |
| UBTB_ENABLE | 0      | 1   | UBTB_ENABLE 设 1 代表开启 uftb     |
| BTB_ENABLE  | 1      | 1   | BTB_ENABLE 设 1 代表开启主 ftb      |
| BIM_ENABLE  | 2      | 1   | BIM_ENABLE 设 1 代表开启 bim 预测器   |
| TAGE_ENABLE | 3      | 1   | TAGE_ENABLE 设 1 代表开启 TAGE 预测器 |
| SC_ENABLE   | 4      | 1   | SC_ENABLE 设 1 代表开启 SC 预测器     |
| RAS_ENABLE  | 5      | 1   | RAS_ENABLE 设 1 代表开启 RAS 预测器   |
| LOOP_ENABLE | 6      | 1   | LOOP_ENABLE 设 1 代表开启 loop 预测器 |
|             | [63:7] | 0   | 保留                            |

### spfctl

spfctl（Speculative Prefetch Control register）的地址是 0x5C1，是一个定义在 HS 模式的可读写寄存器。

Table: spfctl的定义

| 字段名称                    | 字段位置    | 初始值 | 描述                                                            |
| ----------------------- | ------- | --- | ------------------------------------------------------------- |
| L1I_PF_ENABLE           | 0       | 1   | 控制 L1 指令预取器，设 1 代表开启预取                                        |
| L2_PF_ENABLE            | 1       | 1   | 控制 L2 预取器，设 1 代表开启预取                                          |
| L1D_PF_ENABLE           | 2       | 1   | 控制 SMS 预取器，设 1 代表开启预取                                         |
| L1D_PF_TRAIN_ON_HIT     | 3       | 0   | 控制 SMS 预取器是否在 hit 时接受训 练，设 1 代表 hit 也会接受训练；设 0 代表只有 miss 才会训练 |
| L1D_PF_ENABLE_AGT       | 4       | 1   | 控制 SMS 预取器的 agt 表，设 1 代表开启 agt 表                              |
| L1D_PF_ENABLE_PHT       | 5       | 1   | 控制 SMS 预取器的 pht 表，设 1 代表开启 pht 表                              |
| L1D_PF_ACTIVE_THRESHOLD | [9:6]   | 12  | 控制 SMS 预取器的 active page 阈值                                    |
| L1D_PF_ACTIVE_STRIDE    | [15:10] | 30  | 控制 SMS 预取器的 active page 跨度                                    |
| L1D_PF_ENABLE_STRIDE    | 16      | 1   | 控制 SMS 预取器是否启用跨步                                              |
| L2_PF_STORE_ONLY        | 17      | 0   | 控制 L2 预取器是否只对 store 预取                                        |
| L2_PF_RECV_ENABLE       | 18      | 1   | 控制 L2 预取器是否接收 SMS 的预取请求                                       |
| L2_PF_PBOP_ENABLE       | 19      | 1   | 控制 L2 预取器 PBOP 的启用                                            |
| L2_PF_VBOP_ENABLE       | 20      | 1   | 控制 L2 预取器 VBOP 的启用                                            |
| L2_PF_TP_ENABLE         | 21      | 1   | 控制 L2 预取器 TP 的启用                                              |
|                         | [63:22] | 0   | 保留                                                            |

### slvpredctl

slvpredctl（Speculative Load Violation Predictor Control register） 的地址是
0x5C2，是一个定义在 HS 模式的可读写寄存器。

Table: slvpredctl 的定义

| 字段名称                    | 字段位置   | 初始值 | 描述                                        |
| ----------------------- | ------ | --- | ----------------------------------------- |
| LVPRED_DISABLE          | 0      | 0   | 控制访存违例预测器是否禁用，设 1 代表禁用                    |
| NO_SPEC_LOAD            | 1      | 0   | 控制访存违例预测器是否禁止 load 指令推测执行，设 1 代表禁止        |
| STORESET_WAIT_STORE     | 2      | 0   | 控制访存违例预测器是否会阻塞 store 指令，设 1 代表会阻塞         |
| STORESET_NO_FAST_WAKEUP | 3      | 0   | 控制访存违例预测器是否支持快速唤醒，设 1 代表不会快速唤醒            |
| LVPRED_TIMEOUT          | [8:4]  | 3   | 访存违例预测器的 reset 间隔，设该位域的值为 x，则间隔为 2^(10+x) |
|                         | [63:9] | 0   | 保留                                        |

### smblockctl

smblockctl（Speculative Memory Block Control register） 的地址是 0x5C3，是一个定义在 HS
模式的可读写寄存器。

Table: smblockctl 的定义

| 字段名称                             | 字段位置    | 初始值 | 描述                                       |
| -------------------------------- | ------- | --- | ---------------------------------------- |
| SBUFFER_THRESHOLD                | [3:0]   | 7   | 控制 sbuffer 的 flush 阈值                    |
| LDLD_VIO_CHECK_ENABLE            | 4       | 1   | 控制是否开启 ld-ld 违例检查，设 1 代表开启               |
| SOFT_PREFETCH_ENABLE             | 5       | 1   | 控制是否开启 soft prefetch，设 1 代表开启            |
| CACHE_ERROR_ENABLE               | 6       | 1   | 控制是否上报 cache 发生的 ecc 错误，设 1 代表开启         |
| UNCACHE_WRITE_OUTSTANDING_ENABLE | 7       | 0   | 控制是否支持 uncache 的 outstanding 访问，设 1 代表开启 |
| HD_MISALIGN_ST_ENABLE            | 8       | 1   | 控制是否启用硬件非对齐 store                        |
| HD_MISALIGN_LD_ENABLE            | 9       | 1   | 控制是否启用硬件非对齐 load                         |
|                                  | [63:10] | 0   | 保留                                       |

### srnctl

srnctl（Speculative Runtime Control register） 的地址是 0x5C4，是一个定义在 HS 模式的可读写寄存器。

Table: srnctl 的定义

| 字段名称          | 字段位置   | 初始值 | 描述                     |
| ------------- | ------ | --- | ---------------------- |
| FUSION_ENABLE | 0      | 1   | fusion decoder是否开启，1开启 |
|               | 1      | 0   | 保留                     |
| WFI_ENABLE    | 2      | 1   | wfi 指令是否开启，1开启         |
|               | [63:3] | 0   | 保留                     |

### mcorepwr

mcorepwr（Core Power Down Status Enable） 的地址是 0xBC0，是一个定义在 M 模式的可读写寄存器。

Table: mcorepwr 的定义

| 字段名称              | 字段位置   | 初始值 | 描述                                 |
| ----------------- | ------ | --- | ---------------------------------- |
| POWER_DOWN_ENABLE | 0      | 0   | 1 表示当核心处于 WFI（等待中断）状态时，核心希望进入低功耗模式 |
|                   | [63:1] | 0   | 保留                                 |

### mflushpwr

mflushpwr（Flush L2 Cache Enable） 的地址是 0xBC1，是一个定义在 M 模式的可读写寄存器。

Table: mflushpwr 的定义

| 字段名称            | 字段位置   | 初始值 | 描述                         |
| --------------- | ------ | --- | -------------------------- |
| FLUSH_L2_ENABLE | 0      | 0   | 1 表示核心希望刷新 L2 缓存并退出一致性状态   |
| L2_FLUSH_DONE   | 1      | 0   | 只读位，1 表示 L2 缓存刷新完成并退出一致性状态 |
|                 | [63:2] | 0   | 保留                         |

## CSR 异常检查

当前 CSR 中的权限检查模块 permitMod
将权限检查分为了多个子模块：xRetPermitMod、mLevelPermitMod、sLevelPermitMod、privilegePermitMod、virtualLevelPermitMod
和 indirectCSRPermitMod。permitMod 会产生 EX_II 和 EX_VI 两种异常。另外，xRetPermitMod
不同于其余子模块，其对应执行 xret 指令时产生的异常，而其余子模块则服务于 CSR 访问指令，这两个部分是互斥的，即不可能同时产生执行 xret
指令的异常和执行 CSR 访问指令的异常。

其中，xRetPermitMod 会生成执行 mnret/mret/sret/dret 指令时可能产生的异常：EX_II 和 EX_VI。

mLevelPermitMod 中只会产生 EX_II，在其中会进行几种类型的权限检查：写只读 CSR；在 fs/vs 未开启时访问浮点/向量
CSR；以及一系列由 M 模式 CSR（如 mstateen0 和 menvcfg） 控制的对其他低特权级 CSR 的访问。

sLevelPermitMod 中同样只会产生 EX_II，在其中会进行一系列由 HS 模式 CSR（如 sstateen0 和 scounteren）
控制的对其他低特权级 CSR 的访问。

privilegePermitMod 中保证了低特权模式不能访问高特权模式的 CSR，并根据当前所处的特权级和访问的目标 CSR 特权级来产生 EX_II 和
EX_VI 两种异常。

Table: 不同特权级访问 CSR 权限检查

|         | M-Level CSR | H/VS-Level CSR | S-Level CSR | U-Level CSR |
| ------- | ----------- | -------------- | ----------- | ----------- |
| MODE_M  | OK          | OK             | OK          | OK          |
| MODE_VS | EX_II       | EX_VI          | OK          | OK          |
| MODE_VU | EX_II       | EX_VI          | EX_VI       | OK          |
| MODE_HS | EX_II       | OK             | OK          | OK          |
| MODE_HU | EX_II       | EX_II          | EX_II       | OK          |

virtualLevelPermitMod 中会产生 EX_II 和 EX_VI 两种异常，在其中会进行一系列由 H 模式 CSR（如 hstateen0 和
henvcfg） 控制的对其他 CSR 的访问。

indirectCSRPermitMod 中同样会产生 EX_II 和 EX_VI 两种异常，在其中会进行一系列对 Alisa 的别名
CSR（mireg、sireg 和 vsireg）访问的权限检查。

另外，对于 CSR 访问时产生的异常，我们优先选取 mLevelPermitMod、sLevelPermitMod、privilegePermitMod 和
virtualLevelPermitMod 的结果，即直接访问产生的异常结果，其次再考虑间接访问产生的异常结果 indirectCSRPermitMod。

在直接访问产生的异常结果中，我们需要保证 mLevelPermitMod 的结果最优先，sLevelPermitMod 其次，然后是
privilegePermitMod，最后是 virtualLevelPermitMod。这一限制同时还保证了 EX_II 会优先于 EX_VI。

## CSR 只读指令乱序

我们还支持 CSR 只读指令的乱序。我们注意到，对于绝大多数 CSR，CSRR 指令不需要等待前面的指令。对于所有 CSR，CSRR
指令也不需要阻塞后面的指令。需要注意的是，isCsrr 不仅仅包含 CSRR 指令的情况，还包含其他不需要写入 CSR 的 CSR指令。

当前对于以下 CSR 执行的 CSRR 指令要求等待前面的指令，顺序执行：fflags, fcsr, vxsat, vcsr, vstart, mstatus,
sstatus, hstatus, vsstatus, mnstatus, dcsr。因为这些 CSR 可能会被用户级指令在不需要 fence
的情况下就发生修改，如果乱序执行可能会导致错误的结果，所以对这些 CSR 执行 CSRR 指令要求顺序执行。

另外，由于在读取任何 PMC CSR 之前必须执行 fence 指令，因此没有必要让对 PMC CSR 的指令顺序执行。

CSR 指令过去是在没有流水的情况下执行的，因此 CSR 模块内部不需要一个状态机。在添加了允许对一些 CSR
只读指令的流水加速优化后，就需要一个状态机了，因为整数寄存器堆的仲裁器必须允许 CSRR 指令成功执行之前写入请求。

这个有限状态机有三个状态：空闲（s_idle）、等待IMSIC（s_waitIMSIC）和完成（s_finish）。

在当前状态是 s_idle 时，如果有有效输入 valid 并且有 flush 信号时，则下一状态仍为 s_idle；如果有有效输入 valid
并且需要异步访问 AIA 时，则下一状态变为 s_waitIMSIC；如果有有效输入 valid，则下一状态变为 s_finish；其他情况下保持
s_idle。

在当前状态是 s_waitIMSIC 时，如果有 flush 信号，则下一状态恢复到 s_idle；如果收到从 AIA 回来的读有效信号，并且输出
ready，则下一状态恢复至 s_idle，否则如果输出没有 ready，则下一状态变为 s_finish，等待输出；其他情况下保持为 s_waitIMSIC。

在当前状态是 s_finish 时，如果有 flush 信号或者输出 ready 信号，则下一状态都将恢复至 s_idle；否则保持 s_finish。
