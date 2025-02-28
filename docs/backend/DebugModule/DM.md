# Debug Module

- 版本：V2R2
- 状态：OK
- 日期：2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## 术语说明

Table: 术语说明

| 缩写 | 全称                   | 描述         |
| ---- | ---------------------- | ------------ |
| DM   | Debug Module           | 调试模块     |
| DTM  | Debug Transport Module | 调试转换模块 |
| DMI  | Debug Module Interface | 调试模块接口 |

## 参数设计

Table: 参数设计

| 参数                 | 默认值     | 描述                     |
| -------------------- | ---------- | ------------------------ |
| baseAddress          | 0x38020800 | debug Module MMIO 基地址 |
| nDMIAddrSize         | 7          | DMI 地址宽度             |
| nProgramBufferWords  | 16         | Program Buffer 数量      |
| nAbstractDataWords   | 4          | Abstract Commands 数量   |
| hasBusMaster         | true       | system bus master        |
| maxSupportedSBAccess | 64         | sysbus 最大访存宽度      |
| supportQuickAccess   | false      | QuickAccess 支持         |
| supportHartArray     | true       | hart array 支持          |
| nHaltGroups          | 1          | halt group 数量          |
| nExtTriggers         | 0          | external triggers 数量   |
| hasHartResets        | true       | reset 选中的 harts       |
| hasImplicitEbreak    | false      | 隐式 ebreak 支持         |

## 总体设计

### 整体框图

如 [@fig:DM] 所示：

![DebugModule 总览](./figure/DM-Overview.svg){#fig:DM}

### 多时钟域

如 [@fig:multiclock] 所示：

![DebugModule 多时钟域](./figure/MultiClock.svg){#fig:multiclock}

### Debug MMIO

如 [@tbl:debug-mmio] 所示：

Table: debug MMIO 地址空间 {#tbl:debug-mmio}

| 地址(基地址0x3802_0000)    | 名称  | 描述 | 该地址里存放的内容 |
| -------------------------------- | ------------------------------ | --------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| 0x800                            | debugEntry                     | debug 入口地址 /debug rom 的基地址                                     |                                                                        |
| 0x808                            | debugException                 | 在 dmode 执行时出现异常入口地址                                         |                                                                        |
| 0x100                            | HALTED                         |                                                                       | 进入 dmode 的 hart 对应的 hartid，debugmodule 会拿到                     |
| 0x104                            | GOING                          |                                                                       | whereto，最终跳转到 ABSTRACT 去执行                                      |
| 0x108                            | RESUMING                       |                                                                       | 执行 dret                                                               |
| 0x10c                            | EXCEPTION                      |                                                                       |                                                                         |
| 0x300                            | WHERETO                        | 该地址里存放的指令                                                      | dm 生成的跳转到ABSTRACT 的跳转指令                                        |
| 0x380                            | DATA                           | DATA 的基地址（for ld/st）                                             |  数据交换                                                                 |
| DATA-4*nProgBuf                  | PROGBUF                        | progbuf0 的地址                                                        | dm 生成的指令（go 之前准备好）                                            |
| DATA-4                           | IMPEBREAK                      | 隐式 ebreak 指令                                                       |                                                                         |
| PROGBUF - 4* nAbstractInst       | ABSTRACT                       | AbstractInstructions                                                  | dm 生成的指令（go 之前准备好）                                             |
| 0x400                            | FLAGS                          | hartid 对应 flag 的基地址，每个 flag 是 8bits, 0x400 代表的是 hartid=0 时的 flag 的地址 | 这个 8bits 只有低两位有效，次低位指的是 resume，最低位指的 go, 地址空间是 1k 即 0x400->（0x500-0x1） |

## 模块设计

### Debug Module

当前昆明湖 debug 实现的情况如下：

* 支持从第一条指令开始的调试，在 cpu 复位之后进入调试模式。
* 支持单核、多核（选中的核）调试的运行控制，包括 halt, resume, reset。
* 支持单步调试。
* 支持 stopcount，stoptime。
* 支持软断点( ebreak 指令)、硬断点（ trigger ）和内存断点（ trigger ）。
* 支持GPR，CSR 和内存访问，支持 progbuf 和 sysbus 两种访存方式。
* 支持通过 debug interrupt(haltreq, haltgroup, halt-on-reset), trigger fire, ebreak, singlestep, critical error 等方式进入 debug mode。

### Trigger Module

当前昆明湖 trigger module 的实现情况如下：

* 昆明湖 trigger module 当前实现的 debug 相关的 CSR 如下表所示。
* trigger 的默认配置数量是 4 (支持用户自定义配置)。
* 支持 mcontrol6 类型的指令、访存的 trigger。
* match 支持相等，大于等于，小于三种类型（向量访存当前只支持相等类型匹配）。
* 仅支持 address 匹配，不支持 data 匹配。
* 仅支持 timing = before。
* 支持一对 trigger 的 chain。
* 为了防止 trigger 的二次产生 breakpoint 的异常，支持通过 xSTATUS.xIE 控制。
* 支持H扩展的软硬件断点，watchpoint 调试手段。
* 支持原子指令的访存 trigger。

以下表格描述的是当前昆明湖支持的访存指令在微架构里的访存粒度和trigger匹配粒度：对于标量指令和以元素为粒度进行访存的向量指令来说，match type 支持 >=, =, <；对于其余向量指令来说，仅支持match type为 = 的匹配。另外对于向量访存指令来说，处理元素索引较小的指令触发的trigger fire（不管其 trigger action 是 breakpoint 还是 debug ）。

Table: 访存粒度和trigger匹配粒度

| 指令类型                        | 访存粒度                 | trigger匹配粒度                                                           |
| ------------------------------- | ------------------------ | ------------------------------------------------------------------------- |
| 标量访存指令                    | 指令（元素）             | 检查元素小端地址，支持>=, =, <                                            |
| 原子访存指令（lr/sc）           | 指令（元素）             | 检查元素小端地址，支持>=, =, <； lr 视为load，sc 视为 store（不管成功与否）   |
| 原子访存指令（amo）             | 指令（元素）             | 检查元素小端地址，支持>=, =, <；在拿到 vaddr 同时检查 load 和 store             |
| 向量访存指令（unit-stride）     | 向量寄存器宽度（128bit） | 支持该指令访存地址范围内任意地址的检查（以 8bit 为粒度），但仅仅支持 = 匹配 |
| 向量访存指令（whole）           | 向量寄存器宽度（128bit） | 支持该指令访存地址范围内任意地址的检查（以 8bit 为粒度），但仅仅支持 = 匹配 |
| 向量访存指令（fof unit-stride） | 向量寄存器宽度（128bit） | 支持该指令访存地址范围内任意地址的检查（以 8bit 为粒度），但仅仅支持 = 匹配 |
| 向量访存指令（segment）         | field                    | 检查每个 field 小端地址，但仅仅支持 = 匹配                                  |
| 其他类型的向量访存指令          | 元素                     | 检查每个元素小端地址，支持 >=, =, <                                        |

 table: 昆明湖实现的 debug 相关的 csr

| 名称              | 地址  | 读写 | 介绍                     | 复位值              |
| ----------------- | ----- | ---- | ------------------------ | ------------------- |
| Tselect           | 0x7A0 | RW   | trigger 选择寄存器       | 0X0                 |
| Tdata1(Mcontrol6) | 0x7A1 | RW   | trigger data1            | 0xF0000000000000000 |
| Tdata2            | 0x7A2 | RW   | trigger data2            | 0x0                 |
| Tinfo             | 0x7A4 | RO   | trigger info             | 0x40                |
| Dcsr              | 0x7B0 | RW   | Debug Control and Status | 0x40000003          |
| Dpc               | 0x7B1 | RW   | Debug PC                 | 0x0                 |
| Dscratch0         | 0x7B2 | RW   | Debug Scratch Register 0 | -                   |
| Dscratch1         | 0x7B3 | RW   | Debug Scratch Register 1 |                     |

### 调试流程举例

#### CSR 访问：

debug module CSR 访问是 abstract command 和 progbuff 配合完成的，根据 abstract command 会在 ABSTRACT 和 PROGBUFF 地址处分别生成相应的指令（这两块地址空间是连续的），让 CPU 去执行，达到访问 CSR 的目的。ABSTRAT 处生成的是 lw/st 指令，做的是 MMIO 地址与 GPR s0/s1 之间的数据交换，PROGBUFF 处生成的是 CSR 的读写指令）。
下面以访问 mstatus 寄存器为例说明 debug module 是如何访问 CSR 的：

1. 假设软件发出一个写 mstatus CSR 的命令然后该命令会依次经过 JtagProbe，JtagDTM，DMI 转化为 DMI 操作；
2. Dmi 操作经过 dmi2tl 去修改 DebugModule 内部控制信号，修改 DMI_COMMAND 为写 mstatus 寄存器的 command；
3. openocd 首先会把 s0/fp 的值读出来存着，然后往 progbuffer 写 csr 的写指令；
4. 执行 ABSTRAT（ld指令），把 DATA 写到s0；
5. 执行 progbuffer（CRS写指令），progbuff 以 ebreak 指令结尾，重新进入 parking loop；

   如果是读 csr 的话：
6. 执行 progbuffer（CRS读指令），把 csr 的值读出来给 s0；
7. 执行 ABSTRAT（st指令），把 s0 写到 DATA；

#### 硬件断点：

以下内容以打断点为例，说明在调试过程中，软硬件的协同工作流程：

1. 首先软件发出一个 halte d的命令，然后该命令会依次经过 JtagProbe，JtagDTM，DMI 转化为 DMI 操作；
2. Dmi 操作经过 dmi2tl 去修改 DebugModule 内部控制信号，向 hart 发出一个外部的 debug 中断，该中断最终会传到 hart 内部的 CSR 模块中；
3. CSR 处理来自外部的 debug 中断：hart 将 Trap 到 debugModule 的入口地址去执行（见 Debug Module MMIO ），进入 DMode；
4. Hart 进入到 DMode 之后，执行 debug ROM 里的指令，会把自己的 hartid 写到 HALTED（见第8节 Debug ROM ），告知 Debug module 自己（hart）进入了 dmode，Debugger 在 Dmode 下可以对 hart 进行调试；
5. 当软件发出一个打硬件断点的命令时，hart 会跳到 whereto，abstract 和 progbuff 相互配合，控制 hart 执行 CSR 指令（progbuffer）配置 trigger CSR 寄存器，把断点的信息写入 trigger CSR；progbuff 以 ebreak 指令结尾，执行该 ebreak 会再次跳到 debugModule 的入口地址；
6. 软件发出一个 resume 的命令，hart 会跳到 _resume 去执行 dret 指令，退出 dMode，回到1处 halted 前去执行；（ resume 之前有一个准备工作，需要先执行一次 step ，只提交一条指令，然后通过 single step 异常 trap 到 debugMode，这块可以去看 openocd 的源码）
7. 当 hart 执行程序到打断点的位置时，指令的 pc 匹配上 trigger CSR 里配置的断点地址，trigger fire，hart 会再次进入 dmode（Trap 到 debugModule 的入口地址）去执行 debug rom 里的指令，等待 debugger 调试。
