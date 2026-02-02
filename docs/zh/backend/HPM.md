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
| OP_TYPE1       | 49:45  | RW    | 5'b00001: 采用 and 操作组合                   | 0        |
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
| 56   | itlb_access             |
| 57   | itlb_miss               |

Table: 昆明湖后端性能事件索引表

| 索引 | 事件                                                         |
| ---- | ------------------------------------------------------------ |
| 0    | noEvent                                                      |
| 1    | decoder_fused_instr                                          |
| 2    | decoder_waitInstr                                            |
| 3    | decoder_stall_cycle                                          |
| 4    | decoder_utilization                                          |
| 5    | frontend_stall_cycle                                         |
| 6    | backend_stall_cycle                                          |
| 7    | INST_SPEC                                                    |
| 8    | RECOVERY_BUBBLE                                              |
| 9    | rename_in                                                    |
| 10   | rename_waitinstr                                             |
| 11   | rename_stall                                                 |
| 12   | rename_stall_cycle_walk                                      |
| 13   | rename_stall_cycle_dispatch                                  |
| 14   | rename_stall_cycle_int                                       |
| 15   | rename_stall_cycle_fp                                        |
| 16   | rename_stall_cycle_vec                                       |
| 17   | rename_stall_cycle_v0                                        |
| 18   | rename_stall_cycle_vl                                        |
| 19   | me_freelist_1_4_valid                                        |
| 20   | me_freelist_2_4_valid                                        |
| 21   | me_freelist_3_4_valid                                        |
| 22   | me_freelist_4_4_valid                                        |
| 23   | std_freelist_1_4_valid                                       |
| 24   | std_freelist_2_4_valid                                       |
| 25   | std_freelist_3_4_valid                                       |
| 26   | std_freelist_4_4_valid                                       |
| 27   | std_freelist_1_4_valid                                       |
| 28   | std_freelist_2_4_valid                                       |
| 29   | std_freelist_3_4_valid                                       |
| 30   | std_freelist_4_4_valid                                       |
| 31   | std_freelist_1_4_valid                                       |
| 32   | std_freelist_2_4_valid                                       |
| 33   | std_freelist_3_4_valid                                       |
| 34   | std_freelist_4_4_valid                                       |
| 35   | std_freelist_1_4_valid                                       |
| 36   | std_freelist_2_4_valid                                       |
| 37   | std_freelist_3_4_valid                                       |
| 38   | std_freelist_4_4_valid                                       |
| 39   | dispatch_in                                                  |
| 40   | dispatch_empty                                               |
| 41   | dispatch_utili                                               |
| 42   | dispatch_waitinstr                                           |
| 43   | dispatch_stall_cycle_lsq                                     |
| 44   | dispatch_stall_cycle_rob                                     |
| 45   | dispatch_stall_cycle_int_dq                                  |
| 46   | dispatch_stall_cycle_fp_dq                                   |
| 47   | dispatch_stall_cycle_ls_dq                                   |
| 48   | rob_interrupt_num                                            |
| 49   | rob_exception_num                                            |
| 50   | rob_flush_pipe_num                                           |
| 51   | rob_replay_inst_num                                          |
| 52   | rob_commitUop                                                |
| 53   | rob_commitInstr                                              |
| 54   | rob_commitInstrFused                                         |
| 55   | rob_commitInstrLoad                                          |
| 56   | rob_commitInstrBranch                                        |
| 57   | rob_commitInstrStore                                         |
| 58   | rob_walkInstr                                                |
| 59   | rob_walkCycle                                                |
| 60   | rob_1_4_valid                                                |
| 61   | rob_2_4_valid                                                |
| 62   | rob_3_4_valid                                                |
| 63   | rob_4_4_valid                                                |
| 64   | BRANCH_JUMP                                                  |
| 65   | BR_MIS_PRED                                                  |
| 66   | TOTAL_FLUSH                                                  |
| 67   | EXEC_STALL_CYCLE                                             |
| 68   | MEMSTALL_STORE                                               |
| 69   | MEMSTALL_L1MISS                                              |
| 60   | MEMSTALL_L2MISS                                              |
| 71   | MEMSTALL_L3MISS                                              |
| 72   | issueQueue_enq_fire_cnt                                      |
| 73   | IssueQueueAluMulBkuBrhJmp_full                               |
| 74   | IssueQueueAluMulBkuBrhJmp_full                               |
| 75   | IssueQueueAluBrhJmpI2fVsetriwiVsetriwvfI2v_full              |
| 76   | IssueQueueAluCsrFenceDiv_full                                |
| 77   | issueQueue_enq_fire_cnt                                      |
| 78   | IssueQueueFaluFcvtF2vFmacFdiv_full                           |
| 79   | IssueQueueFaluFmacFdiv_full                                  |
| 70   | IssueQueueFaluFmac_full                                      |
| 81   | issueQueue_enq_fire_cnt                                      |
| 82   | IssueQueueVfmaVialuFixVimacVppuVfaluVfcvtVipuVsetrvfwvf_full |
| 83   | IssueQueueVfmaVialuFixVfalu_full                             |
| 84   | IssueQueueVfdivVidiv_full                                    |
| 85   | issueQueue_enq_fire_cnt                                      |
| 86   | IssueQueueStaMou_full                                        |
| 87   | IssueQueueStaMou_full                                        |
| 88   | IssueQueueLdu_full                                           |
| 89   | IssueQueueLdu_full                                           |
| 80   | IssueQueueLdu_full                                           |
| 91   | IssueQueueVlduVstuVseglduVsegstu_full                        |
| 92   | IssueQueueVlduVstu_full                                      |
| 93   | IssueQueueStdMoud_full                                       |
| 94   | IssueQueueStdMoud_full                                       |

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
| 8    | l1D_load_hw_prf_access    |
| 9    | l1D_load_hw_prf_miss      |
| 10   | load_s0_in_fire           |
| 11   | load_to_load_forward      |
| 12   | stall_dcache              |
| 13   | load_s1_in_fire           |
| 14   | load_s1_tlb_miss          |
| 15   | load_s2_in_fire           |
| 16   | load_s2_dcache_miss       |
| 17   | l1D_load_hw_prf_access    |
| 18   | l1D_load_hw_prf_miss      |
| 19   | load_s0_in_fire           |
| 20   | load_to_load_forward      |
| 21   | stall_dcache              |
| 22   | load_s1_in_fire           |
| 23   | load_s1_tlb_miss          |
| 24   | load_s2_in_fire           |
| 25   | load_s2_dcache_miss       |
| 26   | l1D_load_hw_prf_access    |
| 27   | l1D_load_hw_prf_miss      |
| 28   | sbuffer_req_valid         |
| 29   | sbuffer_req_fire          |
| 30   | sbuffer_merge             |
| 31   | sbuffer_newline           |
| 32   | dcache_req_valid          |
| 33   | dcache_req_fire           |
| 34   | sbuffer_idle              |
| 35   | sbuffer_flush             |
| 36   | sbuffer_replace           |
| 37   | mpipe_resp_valid          |
| 38   | replay_resp_valid         |
| 39   | coh_timeout               |
| 40   | sbuffer_1_4_valid         |
| 41   | sbuffer_2_4_valid         |
| 42   | sbuffer_3_4_valid         |
| 43   | sbuffer_full_valid        |
| 44   | MEMSTALL_ANY_LOAD         |
| 45   | enq                       |
| 46   | ld_ld_violation           |
| 47   | enq                       |
| 48   | stld_rollback             |
| 49   | enq                       |
| 50   | deq                       |
| 51   | deq_block                 |
| 52   | replay_full               |
| 53   | replay_rar_nack           |
| 54   | replay_raw_nack           |
| 55   | replay_nuke               |
| 56   | replay_mem_amb            |
| 57   | replay_tlb_miss           |
| 58   | replay_bank_conflict      |
| 59   | replay_dcache_replay      |
| 60   | replay_forward_fail       |
| 61   | replay_dcache_miss        |
| 62   | full_mask_000             |
| 63   | full_mask_001             |
| 64   | full_mask_010             |
| 65   | full_mask_011             |
| 66   | full_mask_100             |
| 67   | full_mask_101             |
| 68   | full_mask_110             |
| 69   | full_mask_111             |
| 70   | nuke_rollback             |
| 71   | nack_rollback             |
| 72   | mmioCycle                 |
| 73   | mmioCnt                   |
| 74   | mmio_wb_success           |
| 75   | mmio_wb_blocked           |
| 76   | stq_1_4_valid             |
| 77   | stq_2_4_valid             |
| 78   | stq_3_4_valid             |
| 79   | stq_4_4_valid             |
| 80   | dcache_wbq_req            |
| 81   | dcache_wbq_1_4_valid      |
| 82   | dcache_wbq_2_4_valid      |
| 83   | dcache_wbq_3_4_valid      |
| 84   | dcache_wbq_4_4_valid      |
| 85   | l1D_write_dcache_access   |
| 86   | l1D_write_dcache_miss     |
| 87   | dcache_mp_req             |
| 88   | dcache_mp_total_penalty   |
| 89   | dcache_missq_req          |
| 90   | dcache_missq_1_4_valid    |
| 91   | dcache_missq_2_4_valid    |
| 92   | dcache_missq_3_4_valid    |
| 93   | dcache_missq_4_4_valid    |
| 94   | dcache_probq_req          |
| 95   | dcache_probq_1_4_valid    |
| 96   | dcache_probq_2_4_valid    |
| 97   | dcache_probq_3_4_valid    |
| 98   | dcache_probq_4_4_valid    |
| 99   | load_req                  |
| 100  | load_replay               |
| 101  | load_replay_for_data_nack |
| 102  | load_replay_for_no_mshr   |
| 103  | load_replay_for_conflict  |
| 104  | l1D_read_dcache_access    |
| 105  | l1D_read_dcache_miss      |
| 106  | load_req                  |
| 107  | load_replay               |
| 108  | load_replay_for_data_nack |
| 109  | load_replay_for_no_mshr   |
| 110  | load_replay_for_conflict  |
| 111  | l1D_read_dcache_access    |
| 112  | l1D_read_dcache_miss      |
| 113  | load_req                  |
| 114  | load_replay               |
| 115  | load_replay_for_data_nack |
| 116  | load_replay_for_no_mshr   |
| 117  | load_replay_for_conflict  |
| 118  | l1D_read_dcache_access    |
| 119  | l1D_read_dcache_miss      |
| 120  | dtlb_ld_access            |
| 121  | dtlb_ld_miss              |
| 122  | dtlb_st_access            |
| 123  | dtlb_st_miss              |
| 124  | PTW_tlbllptw_incount      |
| 125  | PTW_tlbllptw_inblock      |
| 126  | PTW_tlbllptw_memcount     |
| 127  | PTW_tlbllptw_memcycle     |
| 128  | PTW_access                |
| 129  | PTW_l2_hit                |
| 130  | PTW_l1_hit                |
| 131  | PTW_l0_hit                |
| 132  | PTW_sp_hit                |
| 133  | PTW_pte_hit               |
| 134  | PTW_rwHarzad              |
| 135  | PTW_out_blocked           |
| 136  | PTW_fsm_count             |
| 137  | PTW_fsm_busy              |
| 138  | PTW_fsm_idle              |
| 139  | PTW_resp_blocked          |
| 140  | PTW_mem_count             |
| 141  | PTW_mem_cycle             |
| 142  | PTW_mem_blocked           |
| 143  | ldDeqCount                |
| 144  | stDeqCount                |

Table: 昆明湖缓存性能事件索引表

| 索引 | 事件                            |
| ---- | ------------------------------- |
| 0    | noEvent                         |
| 1    | Slice0_l2_cache_refill          |
| 2    | Slice0_l2_cache_rd_refill       |
| 3    | Slice0_l2_cache_wr_refill       |
| 4    | Slice0_l2_cache_long_miss       |
| 5    | Slice0_l2_cache_hit             |
| 6    | Slice0_l2_cache_miss            |
| 7    | Slice0_l2_cache_access          |
| 8    | Slice0_l2_cache_l2wb            |
| 9    | Slice0_l2_cache_l1wb            |
| 10   | Slice0_l2_cache_wb_victim       |
| 11   | Slice0_l2_cache_wb_cleaning_coh |
| 12   | Slice0_l2_cache_prefetch_access |
| 13   | Slice0_l2_cache_prefetch_miss   |
| 14   | Slice0_l2_cache_access_rd       |
| 15   | Slice0_l2_cache_access_wr       |
| 16   | Slice0_l2_cache_miss_rd         |
| 17   | Slice0_l2_cache_inv             |
| 18   | Slice1_l2_cache_refill          |
| 19   | Slice1_l2_cache_rd_refill       |
| 20   | Slice1_l2_cache_wr_refill       |
| 21   | Slice1_l2_cache_long_miss       |
| 22   | Slice1_l2_cache_hit             |
| 23   | Slice1_l2_cache_miss            |
| 24   | Slice1_l2_cache_access          |
| 25   | Slice1_l2_cache_l2wb            |
| 26   | Slice1_l2_cache_l1wb            |
| 27   | Slice1_l2_cache_wb_victim       |
| 28   | Slice1_l2_cache_wb_cleaning_coh |
| 29   | Slice1_l2_cache_prefetch_access |
| 30   | Slice1_l2_cache_prefetch_miss   |
| 31   | Slice1_l2_cache_access_rd       |
| 32   | Slice1_l2_cache_access_wr       |
| 33   | Slice1_l2_cache_miss_rd         |
| 34   | Slice1_l2_cache_inv             |
| 35   | Slice2_l2_cache_refill          |
| 36   | Slice2_l2_cache_rd_refill       |
| 37   | Slice2_l2_cache_wr_refill       |
| 38   | Slice2_l2_cache_long_miss       |
| 39   | Slice2_l2_cache_hit             |
| 40   | Slice2_l2_cache_miss            |
| 41   | Slice2_l2_cache_access          |
| 42   | Slice2_l2_cache_l2wb            |
| 43   | Slice2_l2_cache_l1wb            |
| 44   | Slice2_l2_cache_wb_victim       |
| 45   | Slice2_l2_cache_wb_cleaning_coh |
| 46   | Slice2_l2_cache_prefetch_access |
| 47   | Slice2_l2_cache_prefetch_miss   |
| 48   | Slice2_l2_cache_access_rd       |
| 49   | Slice2_l2_cache_access_wr       |
| 50   | Slice2_l2_cache_miss_rd         |
| 51   | Slice2_l2_cache_inv             |
| 52   | Slice3_l2_cache_refill          |
| 53   | Slice3_l2_cache_rd_refill       |
| 54   | Slice3_l2_cache_wr_refill       |
| 55   | Slice3_l2_cache_long_miss       |
| 56   | Slice3_l2_cache_hit             |
| 57   | Slice3_l2_cache_miss            |
| 58   | Slice3_l2_cache_access          |
| 59   | Slice3_l2_cache_l2wb            |
| 60   | Slice3_l2_cache_l1wb            |
| 61   | Slice3_l2_cache_wb_victim       |
| 62   | Slice3_l2_cache_wb_cleaning_coh |
| 63   | Slice3_l2_cache_prefetch_access |
| 64   | Slice3_l2_cache_prefetch_miss   |
| 65   | Slice3_l2_cache_access_rd       |
| 66   | Slice3_l2_cache_access_wr       |
| 67   | Slice3_l2_cache_miss_rd         |
| 68   | Slice3_l2_cache_inv             |

### Topdown PMU

Topdown 性能分析是一种自顶向下的分析方法，用来快速分析CPU的性能瓶颈，其核心思想是从高层次的性能分类逐步向下分解，逐层细化问题，最终精准定位根本原因。我们实现了三层 Topdown 性能事件，如下所示：

Table: 三层 Topdown 性能事件

+-------------+-------------+-------------+--------------+---------------------------------------+
| Level 1     | Level 2     | Level 3     | 介绍         | 公式                                  |
+=============+=============+=============+==============+=======================================+
| Retiring    | -           | -           | 指令提交影响 | INST_RETIRED /                        |
|             |             |             |              | (IssueBW * CPU_CYCLES)                |
+-------------+-------------+-------------+--------------+---------------------------------------+
| FrontEnd    | -           | -           | 前端影响     | IF_FETCH_BUBBLE /                     |
| Bound       |             |             |              | (IssueBW * CPU_CYCLES)                |
+-------------+-------------+-------------+--------------+---------------------------------------+
| -           | Fetch       | -           |              |                                       |
|             | Latency     |             | 取指延迟影响 | IF_FETCH_BUBBLE_EQ_MAX /              |
|             | Bound       |             |              | CPU_CYCLES                            |
+-------------+-------------+-------------+--------------+---------------------------------------+
|             | Fetch       |             |              | FrontEnd Bound -                      |
| -           | Bandwidth   | -           | 取指带宽影响 | Fetch Latency Bound                   |
|             | Bound       |             |              |                                       |
+-------------+-------------+-------------+--------------+---------------------------------------+
| Bad         |             |             |              | (INST_SPEC - INST_RETIRED+            |
| Speculation | -           | -           | 错误预测影响 | RECOVERY_BUBBLE) /                    |
|             |             |             |              | (IssueBW * CPU_CYCLES)                |
+-------------+-------------+-------------+--------------+---------------------------------------+
| -           | Branch      | -           | 错误预测的   | Bad Speculation *                     |
|             | Misspredict |             | 分支指令影响 | BR_MIS_PRED / TOTAL_FLUSH             |
+-------------+-------------+-------------+--------------+---------------------------------------+
| -           | Machine     | -           | 机器清除     | Bad Speculation - Branch Misspredict  |
|             | Clears      |             | 事件影响     |                                       |
+-------------+-------------+-------------+--------------+---------------------------------------+
| BackEnd     | -           | -           | 后端影响     | 1 - (FrontEnd Bound +                 |
| Bound       |             |             |              | Bad Speculation + Retiring)           |
+-------------+-------------+-------------+--------------+---------------------------------------+
| -           | Core        | -           | 内核影响     | (EXEC_STALL_CYCLE - MEMSTALL_ANYLOAD -|
|             | Bound       |             |              | MEMSTALL_STORE) / CPU_CYCLE           |
+-------------+-------------+-------------+--------------+---------------------------------------+
| -           | Memory      | -           | 访存影响     | (MEMSTALL_ANYLOAD + MEMSTALL_STORE) / |
|             | Bound       |             |              | CPU_CYCLES                            |
+-------------+-------------+-------------+--------------+---------------------------------------+
| -           | -           | L1 Bound    | L1影响       | (MEMSTALL_ANYLOAD - MEMSTALL_L1MISS) /|
|             |             |             |              | CPU_CYCLES                            |
+-------------+-------------+-------------+--------------+---------------------------------------+
| -           | -           | L2 Bound    | L2影响       | (MEMSTALL_L1MISS - MEMSTALL_L2MISS) / |
|             |             |             |              | CPU_CYCLES                            |
+-------------+-------------+-------------+--------------+---------------------------------------+
| -           | -           | L3 Bound    | L3影响       | (MEMSTALL_L2MISS - MEMSTALL_L3MISS) / |
|             |             |             |              | CPU_CYCLES                            |
+-------------+-------------+-------------+--------------+---------------------------------------+
| -           | -           | Mem Bound   | 外部内存影响 | MEMSTALL_L3MISS / CPU_CYCLES          |
+-------------+-------------+-------------+--------------+---------------------------------------+
| -           | -           | Store Bound | 存储指令影响 | MEMSTALL_STORE / CPU_CYCLES           |
+-------------+-------------+-------------+--------------+---------------------------------------+

其中 IssueBW 为发射宽度，香山昆明湖架构当前是6发射。

Table: Topdown 性能事件

+----------------------------+----------------------+---------------------------------------------+
| 名称                       | 对应性能事件         | 介绍                                        |
+============================+======================+=============================================+
| CPU_CYCLES                 |          -           | 所有指令提交后总的时钟周期                  |
+----------------------------+----------------------+---------------------------------------------+
| INST_RETIRED               | rob_commitInstr      | 成功提交的指令个数                          |
+----------------------------+----------------------+---------------------------------------------+
| INST_SPEC                  |          -           | 推测执行的指令个数                          |
+----------------------------+----------------------+---------------------------------------------+
| IF_FETCH_BUBBLE            | Front_Bubble         | 从取指缓冲区获取空泡的个数,                 |
|                            |                      | 且不存在后端停顿                            |
+----------------------------+----------------------+---------------------------------------------+
| IF_FETCH_BUBBLE_EQ_MAX     | Fetch_Latency_Bound  | 从取指缓冲区获取0条指令的周期,              |
|                            |                      | 且不存在后端停顿                            |
+----------------------------+----------------------+---------------------------------------------+
| BR_MIS_PRED                |          -           | 错误预测的分支指令个数                      |
+----------------------------+----------------------+---------------------------------------------+
| TOTAL_FLUSH                |          -           | 流水线刷新事件的个数                        |
+----------------------------+----------------------+---------------------------------------------+
| RECOVERY_BUBBLE            |          -           | 从早期的错误预测中恢复的周期数              |
+----------------------------+----------------------+---------------------------------------------+
| EXEC_STALL_CYCLE           |          -           | 发射Few个uop的周期数                        |
+----------------------------+----------------------+---------------------------------------------+
| MEMSTALL_ANY_LOAD          |          -           | 没有uop发射，并且至少有一条Load指令没有完成 |
+----------------------------+----------------------+---------------------------------------------+
| MEMSTALL_STORE             |          -           | 有非Store指令的uop发射，                    |
|                            |                      | 并且有Store指令没有完成                     |   
+----------------------------+----------------------+---------------------------------------------+
| MEMSTALL_L1MISS            |          -           | 没有uop发射，至少有一条Load指令没有完成，   |
|                            |                      | 并且发生了L1-cache Miss                     |
+----------------------------+----------------------+---------------------------------------------+
| MEMSTALL_L2MISS            |          -           | 没有uop发射，至少有一条Load指令没有完成，   |
|                            |                      | 并且发生了L2-cache Miss                     |
+----------------------------+----------------------+---------------------------------------------+
| MEMSTALL_L3MISS            |          -           | 没有uop发射，至少有一条Load指令没有完成，   |
|                            |                      | 并且发生了L3-cache Miss                     |
+----------------------------+----------------------+---------------------------------------------+

如果要统计一段时间里前端取指延迟的影响，我们可以设置 mhpmevent3 的 EVENT0 域为 22，其余位为默认值，之后进行
测试，测试完成后可以通过 CSR 读指令读取 mhpmcounter3 寄存器，
获取这段时间里前端取指延迟的周期数，然后通过计算可以得出前端取指延迟所造成的影响。

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
