# HPM

- 版本：V2R2
- 状态：OK
- 日期：2025/02/27
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## 基本信息

### 术语说明

Table: 术语说明

| 缩写 | 全称                         | 描述             |
| ---- | ---------------------------- | ---------------- |
| HPM  | Hardware performance monitor | 硬件性能计数单元 |

### 子模块列表

Table: 子模块列表

| 子模块       | 描述                 |
| ------------ | -------------------- |
| HPerfCounter | 单个计数器模块       |
| HPerfMonitor | 计数器组织模块       |
| PFEvent      | Hpmevent寄存器的副本 |

### 设计规格

- 基于 RISC-V 特权手册实现了基本的硬件性能监测功能，并额外支持 sstc 以及 sscofpmf 拓展
- 硬件线程执行的时钟周期数 (cycle)
- 硬件线程已提交的指令数 (minstret)
- 硬件定时器 (time)
- 计数器溢出标志 (time)
- 29个硬件性能计数器 (hpmcounter3 - hpmcouonter3)
- 29个硬件性能事件选择器 (mhpmcounter3 - mhpmcounter31)
- 支持最多定义 2^10 种性能事件

### 功能

HPM 的基本功能如下：

* 通过 mcountinhibit 寄存器关闭所有性能事件监测。
* 初始化各个监测单元性能事件计数器，包括：mcycle, minstret, mhpmcounter3 - mhpmcounter31。
* 配置各个监测单元性能事件选择器，包括: mhpmcounter3 - mhpmcounter31。香山昆明湖架构对每个事件选择器可以配置最多四种事件组合，将事件索引值、事件组合方法、采样特权级写入事件选择器后，即可在规定的采样特权级下对配置的事件正常计数，并根据组合后结果累加到事件计数器中。
* 配置 xcounteren 进行访问权限授权
* 通过 mcountinhibit 寄存器开启所有性能事件监测，开始计数。

#### HPM 事件溢出中断

昆明湖性能监测单元发起的溢出中断 LCOFIP，统一中断向量号为12，中断的使能以及处理过程与普通私有中断一致

## 总体设计

在各个子模块中定义性能事件，子模块通过调用 generatePerfEvent 将性能事件组装为io_perf输出到四个主要模块：Frontend, Backend, MemBlock, CoupledL2。

上述四个模块通过调用 get_perf 方法获取子模块的性能事件输出，同时各个主要模块中例化 PFEvent 模块，作为CSR中 mhpmevent 的副本，将所需要的性能事件选择器数据以及子模块的性能事件输出集合，接入 HPerfMonitor 模块，计算应用到性能事件计数器的增量结果。

最后，CSR 收集来自四个顶层模块的性能事件计数器的增量结果，分别输入到CSR寄存器 mhpmcounter3-31 中，进行累计计数。

特别的，CoupledL2 的性能事件会直接输入到 CSR 模块中，根据 mhpmevent 寄存器读出的事件选择信息，经过 CSR 中例化的 HPerfMonitor 模块处理，输入到CSR寄存器 mhpmcounter26-31 中累计计数。

具体 HPM 总体设计框图见[@fig:HPM]：

![ HPM 总体设计](./figure/hpm.svg){#fig:HPM}

### HPerfMonitor 计数器组织模块

将输入的事件选择信息（events）输入对应的 HPerfCounter 模块，将所有的性能事件计数信息复制输入到每一个 HperfCounter 模块。

收集所有的 HperfCounter 输出。

### HperfCounter 单个计数器模块

根据输入的事件选择信息，选择需要的性能事件计数信息，并根据事件选择信息中的计数模式，对输入的性能事件进行组合输出。

### PFEvent Hpmevent寄存器的副本

CSR寄存器 mhpmevent 的副本：收集CSR写信息，同步 mhpmevent 的变化

## HPM 相关的控制寄存器

### 机器模式性能事件计数禁止寄存器 (MCOUNTINHIBIT)

机器模式性能事件计数禁止寄存器 (mcountinhibit)，是32位 WARL 寄存器，主要用与控制硬件性能监测计数器是否计数。在不需要性能分析的场景下，可以关闭计数器，以降低处理器功耗。

Table: 机器模式性能事件计数禁止寄存器说明

+--------+--------+-------+--------------------------------------------+----------+
| 名称   | 位域   | 读写  | 行为                                       | 复位值   |
+========+========+=======+============================================+==========+
| HPMx   | 31:4   | RW    | mhpmcounterx 寄存器禁止计数位:             | 0        |
|        |        |       |                                            |          |
|        |        |       | 0: 正常计数                                |          |
|        |        |       |                                            |          |
|        |        |       | 1: 禁止计数                                |          |
+--------+--------+-------+--------------------------------------------+----------+
| IR     | 3      | RW    | minstret 寄存器禁止计数位:                 | 0        |
|        |        |       |                                            |          |
|        |        |       | 0: 正常计数                                |          |
|        |        |       |                                            |          |
|        |        |       | 1: 禁止计数                                |          |
+--------+--------+-------+--------------------------------------------+----------+
| --     | 2      | RO 0  | 保留位                                     | 0        |
+--------+--------+-------+--------------------------------------------+----------+
| CY     | 1      | RW    | mcycle 寄存器禁止计数位:                   | 0        |
|        |        |       |                                            |          |
|        |        |       | 0: 正常计数                                |          |
|        |        |       |                                            |          |
|        |        |       | 1: 禁止计数                                |          |
+--------+--------+-------+--------------------------------------------+----------+

### 机器模式性能事件计数器访问授权寄存器 (MCOUNTEREN)

机器模式性能事件计数器访问授权寄存器 (mcounteren)，是32位 WARL 寄存器，主要用于控制用户态性能监测计数器在机器模式以下特权级模式 (HS-mode/VS-mode/HU-mode/VU-mode) 中的访问权限。

Table: 机器模式性能事件计数器访问授权寄存器说明

+--------+--------+-------+------------------------------------------------+----------+
| 名称   | 位域   | 读写  | 行为                                           | 复位值   |
+========+========+=======+================================================+==========+
| HPMx   | 31:4   | RW    | hpmcounterenx 寄存器 M-mode 以下访问权限位:    | 0        |
|        |        |       |                                                |          |
|        |        |       | 0: 访问 hpmcounterx 报非法指令异常             |          |
|        |        |       |                                                |          |
|        |        |       | 1: 允许正常访问 hpmcounterx                    |          |
+--------+--------+-------+------------------------------------------------+----------+
| IR     | 3      | RW    | instret 寄存器 M-mode 以下访问权限位:          | 0        |
|        |        |       |                                                |          |
|        |        |       | 0: 访问 instret 报非法指令异常                 |          |
|        |        |       |                                                |          |
|        |        |       | 1: 允许正常访问                                |          |
+--------+--------+-------+------------------------------------------------+----------+
| TM     | 2      | RW    | time/stimecmp 寄存器 M-mode 以下访问权限位:    | 0        |
|        |        |       |                                                |          |
|        |        |       | 0: 访问 time 报非法指令异常                    |          |
|        |        |       |                                                |          |
|        |        |       | 1: 允许正常访问                                |          |
+--------+--------+-------+------------------------------------------------+----------+
| CY     | 1      | RW    | cycle 寄存器 M-mode 以下访问权限位:            | 0        |
|        |        |       |                                                |          |
|        |        |       | 0: 访问 cycle 报非法指令异常                   |          |
|        |        |       |                                                |          |
|        |        |       | 1: 允许正常访问                                |          |
+--------+--------+-------+------------------------------------------------+----------+

### 监督模式性能事件计数器访问授权寄存器 (SCOUNTEREN)

监督模式性能事件计数器访问授权寄存器 (scounteren)，是32位 WARL 寄存器，主要用于控制用户态性能监测计数器在用户模式 (HU-mode/VU-mode) 中的访问权限。

Table: 监督模式性能事件计数器访问授权寄存器说明

+--------+--------+-------+------------------------------------------------+----------+
| 名称   | 位域   | 读写  | 行为                                           | 复位值   |
+========+========+=======+================================================+==========+
| HPMx   | 31:4   | RW    | hpmcounterenx 寄存器 用户模式访问权限位:       | 0        |
|        |        |       |                                                |          |
|        |        |       | 0: 访问 hpmcounterx 报非法指令异常             |          |
|        |        |       |                                                |          |
|        |        |       | 1: 允许正常访问 hpmcounterx                    |          |
+--------+--------+-------+------------------------------------------------+----------+
| IR     | 3      | RW    | instret 寄存器 用户模式访问权限位:             | 0        |
|        |        |       |                                                |          |
|        |        |       | 0: 访问 instret 报非法指令异常                 |          |
|        |        |       |                                                |          |
|        |        |       | 1: 允许正常访问                                |          |
+--------+--------+-------+------------------------------------------------+----------+
| TM     | 2      | RW    | time 寄存器 用户模式访问权限位:                | 0        |
|        |        |       |                                                |          |
|        |        |       | 0: 访问 time 报非法指令异常                    |          |
|        |        |       |                                                |          |
|        |        |       | 1: 允许正常访问                                |          |
+--------+--------+-------+------------------------------------------------+----------+
| CY     | 1      | RW    | cycle 寄存器 用户模式访问权限位:               | 0        |
|        |        |       |                                                |          |
|        |        |       | 0: 访问 cycle 报非法指令异常                   |          |
|        |        |       |                                                |          |
|        |        |       | 1: 允许正常访问                                |          |
+--------+--------+-------+------------------------------------------------+----------+

### 虚拟化模式性能事件计数器访问授权寄存器 (HCOUNTEREN)

虚拟化模式性能事件计数器访问授权寄存器 (hcounteren)，是32位 WARL 寄存器，主要用于控制用户态性能监测计数器在客户虚拟机 (VS-mode/VU-mode) 中的访问权限。

Table: 监督模式性能事件计数器访问授权寄存器说明

+--------+--------+-------+------------------------------------------------+----------+
| 名称   | 位域   | 读写  | 行为                                           | 复位值   |
+========+========+=======+================================================+==========+
| HPMx   | 31:4   | RW    | hpmcounterenx 寄存器 客户虚拟机访问权限位:     | 0        |
|        |        |       |                                                |          |
|        |        |       | 0: 访问 hpmcounterx 报非法指令异常             |          |
|        |        |       |                                                |          |
|        |        |       | 1: 允许正常访问 hpmcounterx                    |          |
+--------+--------+-------+------------------------------------------------+----------+
| IR     | 3      | RW    | instret 寄存器 客户虚拟机访问权限位:           | 0        |
|        |        |       |                                                |          |
|        |        |       | 0: 访问 instret 报非法指令异常                 |          |
|        |        |       |                                                |          |
|        |        |       | 1: 允许正常访问                                |          |
+--------+--------+-------+------------------------------------------------+----------+
| TM     | 2      | RW    | time/vstimecmp(via stimecmp) 寄存器 客户虚拟机 | 0        |
|        |        |       | 访问权限位:                                    |          |
|        |        |       |                                                |          |
|        |        |       | 0: 访问 time 报非法指令异常                    |          |
|        |        |       |                                                |          |
|        |        |       | 1: 允许正常访问                                |          |
+--------+--------+-------+------------------------------------------------+----------+
| CY     | 1      | RW    | cycle 寄存器 客户虚拟机访问权限位:             | 0        |
|        |        |       |                                                |          |
|        |        |       | 0: 访问 cycle 报非法指令异常                   |          |
|        |        |       |                                                |          |
|        |        |       | 1: 允许正常访问                                |          |
+--------+--------+-------+------------------------------------------------+----------+

### 监督模式时间比较寄存器 (STIMECMP)

监督模式时间比较寄存器 (stimecmp)， 是64位 WARL 寄存器，主要用于管理监督模式下的定时器中断 (STIP)。

STIMECMP 寄存器行为说明：

* 复位值为64位无符号数 64'hffff_ffff_ffff_ffff。
* 在 menvcfg.STCE 为 0 且当前特权级低于 M-mode (HS-mode/VS-mode/HU-mode/VU-mode) 时，访问 stimecmp 寄存器产生非法指令异常，且不产生 STIP 中断。
* stimecmp 寄存器是 STIP 中断产生源头：在进行无符号整数比较 time ≥ stimecmp 时，拉高STIP中断等待信号。
* 监督模式软件可以通过写 stimecmp 控制定时器中断的产生。

### 客户虚拟机监督模式时间比较寄存器 (VSTIMECMP)

客户虚拟机监督模式时间比较寄存器 (vstimecmp)，是64位 WARL 寄存器，主要用于管理客户虚拟机监督模式下的定时器中断 (STIP)。

VSTIMECMP 寄存器行为说明：

* 复位值为64位无符号数 64'hffff_ffff_ffff_ffff。
* 在 henvcfg.STCE 为 0 或者 hcounteren.TM 时，通过 stimecmp 寄存器访问 vstimecmp 寄存器产生 虚拟非法指令异常，且不产生 VSTIP 中断。
* vstimecmp 寄存器是 VSTIP 中断产生源头：在进行无符号整数比较 time + htimedelta ≥ vstimecmp 时，拉高VSTIP中断等待信号。
* 客户虚拟机监督模式软件可以通过写 vstimecmp 控制 VS-mode 下定时器中断的产生。

## HPM 相关的性能事件选择器

机器模式性能事件选择器 (mhpmevent3 - 31)，是64为 WARL 寄存器，用于选择每个性能事件计数器对应的性能事件。在香山昆明湖架构中，每个计数器可以配置最多四个性能事件进行组合计数。用户将事件索引值、事件组合方法、采样特权级写入指定事件选择器后，该事件选择器所匹配的事件计数器开始正常计数。

Table: 机器模式性能事件选择器说明

+----------------+--------+-------+-----------------------------------------------+----------+
| 名称           | 位域   | 读写  | 行为                                          | 复位值   |
+================+========+=======+===============================================+==========+
| OF             | 63     | RW    | 性能计数上溢标志位:                           | 0        |
|                |        |       |                                               |          |
|                |        |       | 0: 对应性能计数器溢出时置1，产生溢出中断      |          |
|                |        |       |                                               |          |
|                |        |       | 1: 对应性能计数器溢出时值不变，不产生溢出中断 |          |
+----------------+--------+-------+-----------------------------------------------+----------+
| MINH           | 62     | RW    | 置1时，禁止 M 模式采样计数                    | 0        |
+----------------+--------+-------+-----------------------------------------------+----------+
| SINH           | 61     | RW    | 置1时，禁止 S 模式采样计数                    | 0        |
+----------------+--------+-------+-----------------------------------------------+----------+
| UINH           | 60     | RW    | 置1时，禁止 U 模式采样计数                    | 0        |
+----------------+--------+-------+-----------------------------------------------+----------+
| VSINH          | 59     | RW    | 置1时，禁止 VS 模式采样计数                   | 0        |
+----------------+--------+-------+-----------------------------------------------+----------+
| VUINH          | 58     | RW    | 置1时，禁止 VU 模式采样计数                   | 0        |
+----------------+--------+-------+-----------------------------------------------+----------+
| --             | 57:55  | RW    | --                                            | 0        |
+----------------+--------+-------+-----------------------------------------------+----------+
|                |        |       | 计数器事件组合方法控制位:                     |          |
|                |        |       |                                               |          |
|                |        |       | 5'b00000: 采用 or 操作组合                    |          |
| OP_TYPE2       | 54:50  |       |                                               |          |
| OP_TYPE1       | 49:45  | RW    | 5'b00001: 采用 and 操作组合                   | 0         |
| OP_TYPE0       | 44:40  |       |                                               |          |
|                |        |       | 5'b00010: 采用 xor 操作组合                   |          |
|                |        |       |                                               |          |
|                |        |       | 5'b00100: 采用 add 操作组合                   |          |
+----------------+--------+-------+-----------------------------------------------+----------+
|                |        |       | 计数器性能事件索引值:                         |          |
| EVENT3         | 39:30  |       |                                               |          |
| EVENT2         | 29:20  | RW    | 0: 对应的事件计数器不计数                     | --       |
| EVENT1         | 19:10  |       |                                               |          |
| EVENT0         | 9:0    |       | 1: 对应的事件计数器对事件计数                 |          |
|                |        |       |                                               |          |
+----------------+--------+-------+-----------------------------------------------+----------+

其中，计数器事件的组合方法为：

* EVENT0 和 EVENT1 事件计数采用 OP_TYPE0 操作组合为 RESULT0。
* EVENT2 和 EVENT3 事件计数采用 OP_TYPE1 操作组合为 RESULT1。
* RESULT0 和 RESULT1 组合记过采用 OP_TYPE2 操作组合为 RESULT2。
* RESULT2 累加到对应事件计数器。

对性能事件选择器中事件索引值部分复位值规定为0

昆明湖架构将提供的性能事件根据来源分为四类，包括：前端，后端，访存，缓存，同时将计数器分为四部分，分别记录来自上述四个源头的性能事件：

* 前端：mhpmevent 3-10
* 后端：mhpmevent11-18
* 访存：mhpmevent19-26
* 缓存：mhpmevent27-31

Table: 昆明湖前端性能事件索引表

| 索引 | 事件                    |
| ---- | ----------------------- |
| 0    | noEvent                 |
| 1    | frontendFlush           |
| 2    | ifu_req                 |
| 3    | ifu_miss                |
| 4    | ifu_req_cacheline_0     |
| 5    | ifu_req_cacheline_1     |
| 6    | ifu_req_cacheline_0_hit |
| 7    | ifu_req_cacheline_1_hit |
| 8    | only_0_hit              |
| 9    | only_0_miss             |
| 10   | hit_0_hit_1             |
| 11   | hit_0_miss_1            |
| 12   | miss_0_hit_1            |
| 13   | miss_0_miss_1           |
| 14   | IBuffer_Flushed         |
| 15   | IBuffer_hungry          |
| 16   | IBuffer_1_4_valid       |
| 17   | IBuffer_2_4_valid       |
| 18   | IBuffer_3_4_valid       |
| 19   | IBuffer_4_4_valid       |
| 20   | IBuffer_full            |
| 21   | Front_Bubble            |
| 22   | Fetch_Latency_Bound     |
| 23   | icache_miss_cnt         |
| 24   | icache_miss_penalty     |
| 25   | bpu_s2_redirect         |
| 26   | bpu_s3_redirect         |
| 27   | bpu_to_ftq_stall        |
| 28   | mispredictRedirect      |
| 29   | replayRedirect          |
| 30   | predecodeRedirect       |
| 31   | to_ifu_bubble           |
| 32   | from_bpu_real_bubble    |
| 33   | BpInstr                 |
| 34   | BpBInstr                |
| 35   | BpRight                 |
| 36   | BpWrong                 |
| 37   | BpBRight                |
| 38   | BpBWrong                |
| 39   | BpJRight                |
| 40   | BpJWrong                |
| 41   | BpIRight                |
| 42   | BpIWrong                |
| 43   | BpCRight                |
| 44   | BpCWrong                |
| 45   | BpRRight                |
| 46   | BpRWrong                |
| 47   | ftb_false_hit           |
| 48   | ftb_hit                 |
| 49   | fauftb_commit_hit       |
| 50   | fauftb_commit_miss      |
| 51   | tage_tht_hit            |
| 52   | sc_update_on_mispred    |
| 53   | sc_update_on_unconf     |
| 54   | ftb_commit_hits         |
| 55   | ftb_commit_misses       |

Table: 昆明湖后端性能事件索引表

| 索引 | 事件                                                         |
| ---- | ------------------------------------------------------------ |
| 0    | noEvent                                                      |
| 1    | decoder_fused_instr                                          |
| 2    | decoder_waitInstr                                            |
| 3    | decoder_stall_cycle                                          |
| 4    | decoder_utilization                                          |
| 5    | INST_SPEC                                                    |
| 6    | RECOVERY_BUBBLE                                              |
| 7    | rename_in                                                    |
| 8    | rename_waitinstr                                             |
| 9    | rename_stall                                                 |
| 10   | rename_stall_cycle_walk                                      |
| 11   | rename_stall_cycle_dispatch                                  |
| 12   | rename_stall_cycle_int                                       |
| 13   | rename_stall_cycle_fp                                        |
| 14   | rename_stall_cycle_vec                                       |
| 15   | rename_stall_cycle_v0                                        |
| 16   | rename_stall_cycle_vl                                        |
| 17   | me_freelist_1_4_valid                                        |
| 18   | me_freelist_2_4_valid                                        |
| 19   | me_freelist_3_4_valid                                        |
| 20   | me_freelist_4_4_valid                                        |
| 21   | std_freelist_1_4_valid                                       |
| 22   | std_freelist_2_4_valid                                       |
| 23   | std_freelist_3_4_valid                                       |
| 24   | std_freelist_4_4_valid                                       |
| 25   | std_freelist_1_4_valid                                       |
| 26   | std_freelist_2_4_valid                                       |
| 27   | std_freelist_3_4_valid                                       |
| 28   | std_freelist_4_4_valid                                       |
| 29   | std_freelist_1_4_valid                                       |
| 30   | std_freelist_2_4_valid                                       |
| 31   | std_freelist_3_4_valid                                       |
| 32   | std_freelist_4_4_valid                                       |
| 33   | std_freelist_1_4_valid                                       |
| 34   | std_freelist_2_4_valid                                       |
| 35   | std_freelist_3_4_valid                                       |
| 36   | std_freelist_4_4_valid                                       |
| 37   | dispatch_in                                                  |
| 38   | dispatch_empty                                               |
| 39   | dispatch_utili                                               |
| 40   | dispatch_waitinstr                                           |
| 41   | dispatch_stall_cycle_lsq                                     |
| 42   | dispatch_stall_cycle_rob                                     |
| 43   | dispatch_stall_cycle_int_dq                                  |
| 44   | dispatch_stall_cycle_fp_dq                                   |
| 45   | dispatch_stall_cycle_ls_dq                                   |
| 46   | rob_interrupt_num                                            |
| 47   | rob_exception_num                                            |
| 48   | rob_flush_pipe_num                                           |
| 49   | rob_replay_inst_num                                          |
| 50   | rob_commitUop                                                |
| 51   | rob_commitInstr                                              |
| 52   | rob_commitInstrFused                                         |
| 53   | rob_commitInstrLoad                                          |
| 54   | rob_commitInstrBranch                                        |
| 55   | rob_commitInstrStore                                         |
| 56   | rob_walkInstr                                                |
| 57   | rob_walkCycle                                                |
| 58   | rob_1_4_valid                                                |
| 59   | rob_2_4_valid                                                |
| 60   | rob_3_4_valid                                                |
| 61   | rob_4_4_valid                                                |
| 62   | BR_MIS_PRED                                                  |
| 63   | TOTAL_FLUSH                                                  |
| 64   | EXEC_STALL_CYCLE                                             |
| 65   | MEMSTALL_STORE                                               |
| 66   | MEMSTALL_L1MISS                                              |
| 67   | MEMSTALL_L2MISS                                              |
| 68   | MEMSTALL_L3MISS                                              |
| 69   | issueQueue_enq_fire_cnt                                      |
| 70   | IssueQueueAluMulBkuBrhJmp_full                               |
| 71   | IssueQueueAluMulBkuBrhJmp_full                               |
| 72   | IssueQueueAluBrhJmpI2fVsetriwiVsetriwvfI2v_full              |
| 73   | IssueQueueAluCsrFenceDiv_full                                |
| 74   | issueQueue_enq_fire_cnt                                      |
| 75   | IssueQueueFaluFcvtF2vFmacFdiv_full                           |
| 76   | IssueQueueFaluFmacFdiv_full                                  |
| 77   | IssueQueueFaluFmac_full                                      |
| 78   | issueQueue_enq_fire_cnt                                      |
| 79   | IssueQueueVfmaVialuFixVimacVppuVfaluVfcvtVipuVsetrvfwvf_full |
| 80   | IssueQueueVfmaVialuFixVfalu_full                             |
| 81   | IssueQueueVfdivVidiv_full                                    |
| 82   | issueQueue_enq_fire_cnt                                      |
| 83   | IssueQueueStaMou_full                                        |
| 84   | IssueQueueStaMou_full                                        |
| 85   | IssueQueueLdu_full                                           |
| 86   | IssueQueueLdu_full                                           |
| 87   | IssueQueueLdu_full                                           |
| 88   | IssueQueueVlduVstuVseglduVsegstu_full                        |
| 89   | IssueQueueVlduVstu_full                                      |
| 90   | IssueQueueStdMoud_full                                       |
| 91   | IssueQueueStdMoud_full                                       |

Table: 昆明湖访存性能事件索引表

| 索引 | 事件                      |
| ---- | ------------------------- |
| 0    | noEvent                   |
| 1    | load_s0_in_fire           |
| 2    | load_to_load_forward      |
| 3    | stall_dcache              |
| 4    | load_s1_in_fire           |
| 5    | load_s1_tlb_miss          |
| 6    | load_s2_in_fire           |
| 7    | load_s2_dcache_miss       |
| 8    | load_s0_in_fire           |
| 9    | load_to_load_forward      |
| 10   | stall_dcache              |
| 11   | load_s1_in_fire           |
| 12   | load_s1_tlb_miss          |
| 13   | load_s2_in_fire           |
| 14   | load_s2_dcache_miss       |
| 15   | load_s0_in_fire           |
| 16   | load_to_load_forward      |
| 17   | stall_dcache              |
| 18   | load_s1_in_fire           |
| 19   | load_s1_tlb_miss          |
| 20   | load_s2_in_fire           |
| 21   | load_s2_dcache_miss       |
| 22   | sbuffer_req_valid         |
| 23   | sbuffer_req_fire          |
| 24   | sbuffer_merge             |
| 25   | sbuffer_newline           |
| 26   | dcache_req_valid          |
| 27   | dcache_req_fire           |
| 28   | sbuffer_idle              |
| 29   | sbuffer_flush             |
| 30   | sbuffer_replace           |
| 31   | mpipe_resp_valid          |
| 32   | replay_resp_valid         |
| 33   | coh_timeout               |
| 34   | sbuffer_1_4_valid         |
| 35   | sbuffer_2_4_valid         |
| 36   | sbuffer_3_4_valid         |
| 37   | sbuffer_full_valid        |
| 38   | MEMSTALL_ANY_LOAD         |
| 39   | enq                       |
| 40   | ld_ld_violation           |
| 41   | enq                       |
| 42   | stld_rollback             |
| 43   | enq                       |
| 44   | deq                       |
| 45   | deq_block                 |
| 46   | replay_full               |
| 47   | replay_rar_nack           |
| 48   | replay_raw_nack           |
| 49   | replay_nuke               |
| 50   | replay_mem_amb            |
| 51   | replay_tlb_miss           |
| 52   | replay_bank_conflict      |
| 53   | replay_dcache_replay      |
| 54   | replay_forward_fail       |
| 55   | replay_dcache_miss        |
| 56   | full_mask_000             |
| 57   | full_mask_001             |
| 58   | full_mask_010             |
| 59   | full_mask_011             |
| 60   | full_mask_100             |
| 61   | full_mask_101             |
| 62   | full_mask_110             |
| 63   | full_mask_111             |
| 64   | nuke_rollback             |
| 65   | nack_rollback             |
| 66   | mmioCycle                 |
| 67   | mmioCnt                   |
| 68   | mmio_wb_success           |
| 69   | mmio_wb_blocked           |
| 70   | stq_1_4_valid             |
| 71   | stq_2_4_valid             |
| 72   | stq_3_4_valid             |
| 73   | stq_4_4_valid             |
| 74   | dcache_wbq_req            |
| 75   | dcache_wbq_1_4_valid      |
| 76   | dcache_wbq_2_4_valid      |
| 77   | dcache_wbq_3_4_valid      |
| 78   | dcache_wbq_4_4_valid      |
| 79   | dcache_mp_req             |
| 80   | dcache_mp_total_penalty   |
| 81   | dcache_missq_req          |
| 82   | dcache_missq_1_4_valid    |
| 83   | dcache_missq_2_4_valid    |
| 84   | dcache_missq_3_4_valid    |
| 85   | dcache_missq_4_4_valid    |
| 86   | dcache_probq_req          |
| 87   | dcache_probq_1_4_valid    |
| 88   | dcache_probq_2_4_valid    |
| 89   | dcache_probq_3_4_valid    |
| 90   | dcache_probq_4_4_valid    |
| 91   | load_req                  |
| 92   | load_replay               |
| 93   | load_replay_for_data_nack |
| 94   | load_replay_for_no_mshr   |
| 95   | load_replay_for_conflict  |
| 96   | load_req                  |
| 97   | load_replay               |
| 98   | load_replay_for_data_nack |
| 99   | load_replay_for_no_mshr   |
| 100  | load_replay_for_conflict  |
| 101  | load_req                  |
| 102  | load_replay               |
| 103  | load_replay_for_data_nack |
| 104  | load_replay_for_no_mshr   |
| 105  | load_replay_for_conflict  |
| 106  | PTW_tlbllptw_incount      |
| 107  | PTW_tlbllptw_inblock      |
| 108  | PTW_tlbllptw_memcount     |
| 109  | PTW_tlbllptw_memcycle     |
| 110  | PTW_access                |
| 111  | PTW_l2_hit                |
| 112  | PTW_l1_hit                |
| 113  | PTW_l0_hit                |
| 114  | PTW_sp_hit                |
| 115  | PTW_pte_hit               |
| 116  | PTW_rwHarzad              |
| 117  | PTW_out_blocked           |
| 118  | PTW_fsm_count             |
| 119  | PTW_fsm_busy              |
| 120  | PTW_fsm_idle              |
| 121  | PTW_resp_blocked          |
| 122  | PTW_mem_count             |
| 123  | PTW_mem_cycle             |
| 124  | PTW_mem_blocked           |
| 125  | ldDeqCount                |
| 126  | stDeqCount                |

Table: 昆明湖缓存性能事件索引表

| 索引 | 事件                            |
| ---- | ------------------------------- |
| 0    | noEvent                         |
| 1    | Slice0_l2_cache_refill          |
| 2    | Slice0_l2_cache_rd_refill       |
| 3    | Slice0_l2_cache_wr_refill       |
| 4    | Slice0_l2_cache_long_miss       |
| 5    | Slice0_l2_cache_access          |
| 6    | Slice0_l2_cache_l2wb            |
| 7    | Slice0_l2_cache_l1wb            |
| 8    | Slice0_l2_cache_wb_victim       |
| 9    | Slice0_l2_cache_wb_cleaning_coh |
| 10   | Slice0_l2_cache_access_rd       |
| 11   | Slice0_l2_cache_access_wr       |
| 12   | Slice0_l2_cache_inv             |
| 13   | Slice1_l2_cache_refill          |
| 14   | Slice1_l2_cache_rd_refill       |
| 15   | Slice1_l2_cache_wr_refill       |
| 16   | Slice1_l2_cache_long_miss       |
| 17   | Slice1_l2_cache_access          |
| 18   | Slice1_l2_cache_l2wb            |
| 19   | Slice1_l2_cache_l1wb            |
| 20   | Slice1_l2_cache_wb_victim       |
| 21   | Slice1_l2_cache_wb_cleaning_coh |
| 22   | Slice1_l2_cache_access_rd       |
| 23   | Slice1_l2_cache_access_wr       |
| 24   | Slice1_l2_cache_inv             |
| 25   | Slice2_l2_cache_refill          |
| 26   | Slice2_l2_cache_rd_refill       |
| 27   | Slice2_l2_cache_wr_refill       |
| 28   | Slice2_l2_cache_long_miss       |
| 29   | Slice2_l2_cache_access          |
| 30   | Slice2_l2_cache_l2wb            |
| 31   | Slice2_l2_cache_l1wb            |
| 32   | Slice2_l2_cache_wb_victim       |
| 33   | Slice2_l2_cache_wb_cleaning_coh |
| 34   | Slice2_l2_cache_access_rd       |
| 35   | Slice2_l2_cache_access_wr       |
| 36   | Slice2_l2_cache_inv             |
| 37   | Slice3_l2_cache_refill          |
| 38   | Slice3_l2_cache_rd_refill       |
| 39   | Slice3_l2_cache_wr_refill       |
| 40   | Slice3_l2_cache_long_miss       |
| 41   | Slice3_l2_cache_access          |
| 42   | Slice3_l2_cache_l2wb            |
| 43   | Slice3_l2_cache_l1wb            |
| 44   | Slice3_l2_cache_wb_victim       |
| 45   | Slice3_l2_cache_wb_cleaning_coh |
| 46   | Slice3_l2_cache_access_rd       |
| 47   | Slice3_l2_cache_access_wr       |
| 48   | Slice3_l2_cache_inv             |

## HPM 相关的性能事件计数器

香山昆明湖架构的性能事件计数器共分为两组，分别是：机器模式事件计数器、监督模式事件计数器、用户模式事件计数器

Table: 机器模式事件计数器列表

| 名称            | 索引        | 读写 | 介绍                   | 复位值 |
| --------------- | ----------- | ---- | ---------------------- | ------ |
| MCYCLE          | 0xB00       | RW   | 机器模式时钟周期计数器 | -      |
| MINSTRET        | 0xB02       | RW   | 机器模式退休指令计数器 | -      |
| MHPMCOUNTER3-31 | 0XB03-0XB1F | RW   | 机器模式性能事件计数器 | 0      |

其中 MHPMCOUNTERx 计数器相应由 MHPMEVENTx 控制，指定计数相应的性能事件。

监督模式事件计数器包括监督模式计数器上溢中断标志寄存器(SCOUNTOVF)

Table: 监督模式计数器上溢中断标志寄存器(SCOUNTOVF)说明

+------------+--------+-------+-----------------------------------------------+--------+
| 名称       | 位域   | 读写  | 行为                                          | 复位值 |
+============+========+=======+===============================================+========+
| OFVEC      | 31:3   | RO    | mhpmcounterx 寄存器上溢标志位:                | 0      |
|            |        |       |                                               |        |
|            |        |       | 1： 发生上溢                                  |        |
|            |        |       |                                               |        |
|            |        |       | 0： 没有发生上溢                              |        |
+------------+--------+-------+-----------------------------------------------+--------+
| --         | 2:0    | RO 0  | --                                            | 0      |
+------------+--------+-------+-----------------------------------------------+--------+

scountovf 作为 mhpmcounter 寄存器 OF 位的只读映射，受 xcounteren 控制:

* M-mode 访问 scountovf 可读正确值。
* HS-mode 访问 scountovf ：mcounteren.HPMx 为1时，对应 OFVECx 可读正确值；否则只读0。
* VS-mode 访问 scountovf : mcounteren.HPMx 以及 hcounteren.HPMx 均为1时，对应 OFVECx 可读正确值；否则只读0。

Table: 用户模式事件计数器列表

| 名称           | 索引        | 读写 | 介绍                                   | 复位值 |
| -------------- | ----------- | ---- | -------------------------------------- | ------ |
| CYCLE          | 0xC00       | RO   | mcycle 寄存器用户模式只读副本          | -      |
| TIME           | 0xC01       | RO   | 内存映射寄存器 mtime 用户模式只读副本  | -      |
| INSTRET        | 0xC02       | RO   | minstret 寄存器用户模式只读副本        | -      |
| HPMCOUNTER3-31 | 0XC03-0XC1F | RO   | mhpmcounter3-31 寄存器用户模式只读副本 | 0      |
