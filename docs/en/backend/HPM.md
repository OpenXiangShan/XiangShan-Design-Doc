# HPM

- Version: V2R2
- Status: OK
- Date: 2025/02/27
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Basic Information

### Glossary of Terms

Table: Terminology Explanation

| Abbreviation | Full name                    | Description                       |
| ------------ | ---------------------------- | --------------------------------- |
| HPM          | Hardware performance monitor | Hardware Performance Counter Unit |

### Submodule List

Table: Submodule List

| Submodule    | Description                 |
| ------------ | --------------------------- |
| HPerfCounter | Single Counter Module       |
| HPerfMonitor | Counter organization module |
| PFEvent      | Copy of Hpmevent register   |

### Design specifications

- Implemented basic hardware performance monitoring functionality based on the
  RISC-V Privileged Specification, with additional support for sstc and sscofpmf
  extensions.
- The clock cycles executed by the hart (cycle)
- Number of instructions committed by the hart (minstret)
- Hardware Timer (time)
- Counter overflow flag (time)
- 29 hardware performance counters (hpmcounter3 - hpmcounter3)
- 29 hardware performance event selectors (mhpmcounter3 - mhpmcounter31)
- Supports defining up to 2^10 types of performance events

### Function

The basic functions of HPM are as follows:

* Disable all performance event monitoring via the mcountinhibit register.
* Initialize echo performance event counters, including: mcycle, minstret,
  mhpmcounter3 - mhpmcounter31.
* Configure performance event selectors for each monitoring unit, including:
  mhpmcounter3 - mhpmcounter31. The Xiangshan Kunminghu architecture allows up
  to four event combinations per selector. After writing the event index value,
  combination method, and sampling privilege level into the selector, normal
  counting of configured events can proceed at the specified privilege level,
  with results accumulated into the event counter based on the combined outcome.
* Configure xcounteren for access permission authorization
* Enable all performance event monitoring via mcountinhibit register and start
  counting.

#### HPM event overflow interrupt

The overflow interrupt LCOFIP initiated by the Kunming Lake Performance
Monitoring Unit has a unified interrupt vector number of 12. The enabling and
handling process of the interrupt is consistent with that of ordinary private
interrupts.

## 总体设计

Performance events are defined within each submodule, which assemble them into
io_perf by calling generatePerfEvent and output to the four main modules:
Frontend, Backend, MemBlock, and CoupledL2.

The above four modules obtain the performance event outputs of submodules by
calling the get_perf method. Meanwhile, each main module instantiates the
PFEvent module as a replica of mhpmevent in CSR, aggregating the required
performance event selector data and the performance event outputs from
submodules, which are then fed into the HPerfMonitor module to calculate the
incremental results applied to the performance event counters.

Finally, the CSR collects incremental results from performance event counters of
four top-level modules and inputs them into CSR registers mhpmcounter3-31 for
cumulative counting.

特别的，CoupledL2 的性能事件会直接输入到 CSR 模块中，根据 mhpmevent 寄存器读出的事件选择信息，经过 CSR 中例化的
HPerfMonitor 模块处理，输入到CSR寄存器 mhpmcounter26-31 中累计计数。

For the detailed HPM overall design block diagram, refer to [@fig:HPM]:

![HPM Overall Design](./figure/hpm.svg){#fig:HPM}

### HPerfMonitor Counter Organization Module

Input the event selection information (events) into the corresponding
HPerfCounter module, and replicate all performance event counting information to
each HperfCounter module.

Collect all HperfCounter outputs.

### HperfCounter single counter module

Based on the input event selection information, select the required performance
event counting information, and according to the counting mode in the event
selection information, combine and output the input performance events.

### Copy of PFEvent Hpmevent register

Copy of CSR register mhpmevent: Collects CSR write information and synchronizes
changes to mhpmevent

## HPM-related control registers

### Machine-mode Performance Event Count Inhibit Register (MCOUNTINHIBIT)

The Machine-Mode Performance Event Count Inhibit Register (mcountinhibit) is a
32-bit WARL register primarily used to control whether hardware performance
monitoring counters count. In scenarios where performance analysis is not
required, counters can be disabled to reduce processor power consumption.

Table: Machine Mode Performance Event Count Prohibit Register Description

+--------+--------+-------+--------------------------------------------+----------+
| Name | Bitfield | R/W | Behavior | Reset Value |
+========+========+=======+============================================+==========+
| HPMx | 31:4 | RW | mhpmcounterx register count disable bit: | 0 | | | | | | |
| | | | 0: Normal counting | | | | | | | | | | | | 1: Counting disabled | |
+--------+--------+-------+--------------------------------------------+----------+
| IR | 3 | RW | minstret register count disable bit: | 0 | | | | | | | | | | |
0: Normal counting | | | | | | | | | | | | 1: Counting disabled | |
+--------+--------+-------+--------------------------------------------+----------+
| -- | 2 | RO 0 | Reserved | 0 |
+--------+--------+-------+--------------------------------------------+----------+
| CY | 1 | RW | mcycle register count disable bit: | 0 | | | | | | | | | | | 0:
Normal counting | | | | | | | | | | | | 1: Counting disabled | |
+--------+--------+-------+--------------------------------------------+----------+

### Machine-mode Performance Counter Event Access Enable Register (MCOUNTEREN)

The Machine-mode Performance Event Counter Access Enable Register (mcounteren)
is a 32-bit WARL register primarily used to control access permissions for
user-mode performance monitoring counters at privilege levels below machine mode
(HS-mode/VS-mode/HU-mode/VU-mode).

Table: Machine Mode Performance Event Counter Access Authorization Register
Description

+--------+--------+-------+------------------------------------------------+----------+
| Name | Bits | R/W | Behavior | Reset |
+========+========+=======+================================================+==========+
| HPMx | 31:4 | RW | hpmcounterenx register M-mode lower privilege access bits:
| 0 | | | | | | | | | | | 0: Accessing hpmcounterx raises illegal instruction
exception | | | | | | | | | | | | 1: Allows normal access to hpmcounterx | |
+--------+--------+-------+------------------------------------------------+----------+
| IR | 3 | RW | instret register M-mode lower privilege access bit: | 0 | | | |
| | | | | | | 0: Accessing instret raises illegal instruction exception | | | |
| | | | | | | | 1: Allows normal access | |
+--------+--------+-------+------------------------------------------------+----------+
| TM | 2 | RW | time/stimecmp register M-mode lower privilege access bit: | 0 |
| | | | | | | | | | 0: Accessing time raises illegal instruction exception | | |
| | | | | | | | | 1: Allows normal access | |
+--------+--------+-------+------------------------------------------------+----------+
| CY | 1 | RW | cycle register M-mode lower privilege access bit: | 0 | | | | |
| | | | | | 0: Accessing cycle raises illegal instruction exception | | | | | |
| | | | | | 1: Allows normal access | |
+--------+--------+-------+------------------------------------------------+----------+

### Supervisor-mode Performance Counter Access Enable Register (SCOUNTEREN)

Supervisor-mode Performance Counter Access Enable Register (scounteren) is a
32-bit WARL register primarily used to control user-mode access permissions for
performance monitoring counters in HU-mode/VU-mode.

Table: Supervisor Mode Performance Event Counter Access Authorization Register
Description

+--------+--------+-------+------------------------------------------------+----------+
| Name | Bits | R/W | Behavior | Reset |
+========+========+=======+================================================+==========+
| HPMx | 31:4 | RW | hpmcounterenx register user-mode access bit: | 0 | | | | |
| | | | | | 0: Accessing hpmcounterx raises illegal instruction exception | | |
| | | | | | | | | 1: Normal access to hpmcounterx allowed | |
+--------+--------+-------+------------------------------------------------+----------+
| IR | 3 | RW | instret register user-mode access bit: | 0 | | | | | | | | | | |
0: Accessing instret raises illegal instruction exception | | | | | | | | | | |
| 1: Normal access allowed | |
+--------+--------+-------+------------------------------------------------+----------+
| TM | 2 | RW | time register user-mode access bit: | 0 | | | | | | | | | | | 0:
Accessing time raises illegal instruction exception | | | | | | | | | | | | 1:
Normal access allowed | |
+--------+--------+-------+------------------------------------------------+----------+
| CY | 1 | RW | cycle register user-mode access bit: | 0 | | | | | | | | | | |
0: Accessing cycle raises illegal instruction exception | | | | | | | | | | | |
1: Normal access allowed | |
+--------+--------+-------+------------------------------------------------+----------+

### Virtualization Mode Performance Event Counter Access Authorization Register (HCOUNTEREN)

The Virtualization Mode Performance Event Counter Access Authorization Register
(hcounteren) is a 32-bit WARL register primarily used to control user-mode
performance monitoring counter access permissions in guest virtual machines
(VS-mode/VU-mode).

Table: Supervisor Mode Performance Event Counter Access Authorization Register
Description

+--------+--------+-------+------------------------------------------------+----------+
| Name | Bitfield | R/W | Behavior | Reset Value |
+========+========+=======+================================================+==========+
| HPMx | 31:4 | RW | hpmcounterenx register guest VM access permission bit: | 0
| | | | | | | | | | | 0: Accessing hpmcounterx raises illegal instruction
exception | | | | | | | | | | | | 1: Normal access to hpmcounterx is permitted |
|
+--------+--------+-------+------------------------------------------------+----------+
| IR | 3 | RW | instret register guest VM access permission bit: | 0 | | | | | |
| | | | | 0: Accessing instret raises illegal instruction exception | | | | | |
| | | | | | 1: Normal access is permitted | |
+--------+--------+-------+------------------------------------------------+----------+
| TM | 2 | RW | time/vstimecmp(via stimecmp) register guest VM | 0 | | | | |
access permission bit: | | | | | | | | | | | | 0: Accessing time raises illegal
instruction exception | | | | | | | | | | | | 1: Normal access is permitted | |
+--------+--------+-------+------------------------------------------------+----------+
| CY | 1 | RW | cycle register guest VM access permission bit: | 0 | | | | | | |
| | | | 0: Accessing cycle raises illegal instruction exception | | | | | | | |
| | | | 1: Normal access is permitted | |
+--------+--------+-------+------------------------------------------------+----------+

### Supervisor Mode Time Compare Register (STIMECMP)

The Supervisor Mode Timer Compare Register (stimecmp) is a 64-bit WARL register
primarily used to manage timer interrupts (STIP) in supervisor mode.

STIMECMP Register Behavior Description:

* Reset value is a 64-bit unsigned number 64'hffff_ffff_ffff_ffff.
* When menvcfg.STCE is 0 and the current privilege level is below M-mode
  (HS-mode/VS-mode/HU-mode/VU-mode), accessing the stimecmp register triggers an
  illegal instruction exception and does not generate an STIP interrupt.
* The stimecmp register is the source of STIP interrupt generation: when
  performing an unsigned integer comparison time ≥ stimecmp, it asserts the STIP
  interrupt pending signal.
* Supervisor mode software can control the generation of timer interrupts by
  writing to stimecmp.

### Guest Virtual Machine Supervisor Mode Time Compare Register (VSTIMECMP)

The Guest Supervisor Time Compare Register (vstimecmp) is a 64-bit WARL register
primarily used to manage timer interrupts (STIP) in guest supervisor mode.

VSTIMECMP Register Behavior Description:

* Reset value is a 64-bit unsigned number 64'hffff_ffff_ffff_ffff.
* When henvcfg.STCE is 0 or hcounteren.TM is set, accessing the vstimecmp
  register via the stimecmp register triggers a virtual illegal instruction
  exception without generating a VSTIP interrupt.
* The vstimecmp register is the source of VSTIP interrupt generation: when
  performing an unsigned integer comparison time + htimedelta ≥ vstimecmp, the
  VSTIP interrupt pending signal is raised.
* Guest supervisor mode software can control the generation of timer interrupts
  in VS-mode by writing to vstimecmp.

## HPM-related performance event selectors

Machine-mode Performance Event Selector (mhpmevent3 - 31) is a 64-bit WARL
register used to select the performance event corresponding to each performance
event counter. In the Xiangshan Kunminghu architecture, each counter can be
configured to count up to four performance events in combination. After users
write the event index value, event combination method, and sampling privilege
level into the designated event selector, the event counter matched by that
selector begins normal counting.

Table: Machine Mode Performance Event Selector Description

+----------------+--------+-------+-----------------------------------------------+----------+
| Name | Bits | R/W | Behavior | Reset |
+================+========+=======+===============================================+==========+
| OF | 63 | RW | Performance counter overflow flag: | 0 | | | | | | | | | | | 0:
Set to 1 when counter overflows, triggers interrupt | | | | | | | | | | | | 1:
Counter value remains unchanged on overflow, no interrupt | |
+----------------+--------+-------+-----------------------------------------------+----------+
| MINH | 62 | RW | When set to 1, disables M-mode sampling | 0 |
+----------------+--------+-------+-----------------------------------------------+----------+
| SINH | 61 | RW | When set to 1, disables S-mode sampling | 0 |
+----------------+--------+-------+-----------------------------------------------+----------+
| UINH | 60 | RW | When set to 1, disables U-mode sampling | 0 |
+----------------+--------+-------+-----------------------------------------------+----------+
| VSINH | 59 | RW | When set to 1, disables VS-mode sampling | 0 |
+----------------+--------+-------+-----------------------------------------------+----------+
| VUINH | 58 | RW | When set to 1, disables VU-mode sampling | 0 |
+----------------+--------+-------+-----------------------------------------------+----------+
| -- | 57:55 | RW | -- | 0 |
+----------------+--------+-------+-----------------------------------------------+----------+
| | | | Counter event combination method control bits: | | | | | | | | | | | |
5'b00000: OR operation combination | | | OP_TYPE2 | 54:50 | | | | | OP_TYPE1 |
49:45 | RW | 5'b00001: AND operation combination | 0 | | OP_TYPE0 | 44:40 | | |
| | | | | 5'b00010: XOR operation combination | | | | | | | | | | | | 5'b00100:
ADD operation combination | |
+----------------+--------+-------+-----------------------------------------------+----------+
| | | | Counter performance event index values: | | | EVENT3 | 39:30 | | | | |
EVENT2 | 29:20 | RW | 0: Corresponding event counter does not count | -- | |
EVENT1 | 19:10 | | | | | EVENT0 | 9:0 | | 1: Corresponding event counter counts
the event | | | | | | | |
+----------------+--------+-------+-----------------------------------------------+----------+

The combination method for counter events is:

* EVENT0 and EVENT1 event counts use OP_TYPE0 operation combination to produce
  RESULT0.
* EVENT2 and EVENT3 event counts are combined using OP_TYPE1 operation to
  produce RESULT1.
* The combined results of RESULT0 and RESULT1 are processed using OP_TYPE2
  operation to form RESULT2.
* RESULT2 is accumulated into the corresponding event counter.

The reset value for the event index portion of the performance event selector is
specified as 0

The Kunming Lake architecture categorizes the provided performance events into
four types based on their sources: frontend, backend, memory access, and cache.
The counters are divided into four sections, each recording performance events
from the aforementioned sources:

* Frontend: mhpmevent 3-10
* Backend: mhpmevent11-18
* Memory Access: mhpmevent19-26
* Cache: mhpmevent27-31

Table: Kunming Lake Frontend Performance Event Index Table

| Index | Event                   |
| ----- | ----------------------- |
| 0     | noEvent                 |
| 1     | frontendFlush           |
| 2     | ifu_req                 |
| 3     | ifu_miss                |
| 4     | ifu_req_cacheline_0     |
| 5     | ifu_req_cacheline_1     |
| 6     | ifu_req_cacheline_0_hit |
| 7     | ifu_req_cacheline_1_hit |
| 8     | only_0_hit              |
| 9     | only_0_miss             |
| 10    | hit_0_hit_1             |
| 11    | hit_0_miss_1            |
| 12    | miss_0_hit_1            |
| 13    | miss_0_miss_1           |
| 14    | IBuffer_Flushed         |
| 15    | IBuffer_hungry          |
| 16    | IBuffer_1_4_valid       |
| 17    | IBuffer_2_4_valid       |
| 18    | IBuffer_3_4_valid       |
| 19    | IBuffer_4_4_valid       |
| 20    | IBuffer_full            |
| 21    | Front_Bubble            |
| 22    | Fetch_Latency_Bound     |
| 23    | icache_miss_cnt         |
| 24    | icache_miss_penalty     |
| 25    | bpu_s2_redirect         |
| 26    | bpu_s3_redirect         |
| 27    | bpu_to_ftq_stall        |
| 28    | mispredictRedirect      |
| 29    | replayRedirect          |
| 30    | predecodeRedirect       |
| 31    | to_ifu_bubble           |
| 32    | from_bpu_real_bubble    |
| 33    | BpInstr                 |
| 34    | BpBInstr                |
| 35    | BpRight                 |
| 36    | BpWrong                 |
| 37    | BpBRight                |
| 38    | BpBWrong                |
| 39    | BpJRight                |
| 40    | BpJWrong                |
| 41    | BpIRight                |
| 42    | BpIWrong                |
| 43    | BpCRight                |
| 44    | BpCWrong                |
| 45    | BpRRight                |
| 46    | BpRWrong                |
| 47    | ftb_false_hit           |
| 48    | ftb_hit                 |
| 49    | fauftb_commit_hit       |
| 50    | fauftb_commit_miss      |
| 51    | tage_tht_hit            |
| 52    | sc_update_on_mispred    |
| 53    | sc_update_on_unconf     |
| 54    | ftb_commit_hits         |
| 55    | ftb_commit_misses       |

Table: Kunming Lake Backend Performance Event Index Table

| Index | Event                                                        |
| ----- | ------------------------------------------------------------ |
| 0     | noEvent                                                      |
| 1     | decoder_fused_instr                                          |
| 2     | decoder_waitInstr                                            |
| 3     | decoder_stall_cycle                                          |
| 4     | decoder_utilization                                          |
| 5     | INST_SPEC                                                    |
| 6     | RECOVERY_BUBBLE                                              |
| 7     | rename_in                                                    |
| 8     | rename_waitinstr                                             |
| 9     | rename_stall                                                 |
| 10    | rename_stall_cycle_walk                                      |
| 11    | rename_stall_cycle_dispatch                                  |
| 12    | rename_stall_cycle_int                                       |
| 13    | rename_stall_cycle_fp                                        |
| 14    | rename_stall_cycle_vec                                       |
| 15    | rename_stall_cycle_v0                                        |
| 16    | rename_stall_cycle_vl                                        |
| 17    | me_freelist_1_4_valid                                        |
| 18    | me_freelist_2_4_valid                                        |
| 19    | me_freelist_3_4_valid                                        |
| 20    | me_freelist_4_4_valid                                        |
| 21    | std_freelist_1_4_valid                                       |
| 22    | std_freelist_2_4_valid                                       |
| 23    | std_freelist_3_4_valid                                       |
| 24    | std_freelist_4_4_valid                                       |
| 25    | std_freelist_1_4_valid                                       |
| 26    | std_freelist_2_4_valid                                       |
| 27    | std_freelist_3_4_valid                                       |
| 28    | std_freelist_4_4_valid                                       |
| 29    | std_freelist_1_4_valid                                       |
| 30    | std_freelist_2_4_valid                                       |
| 31    | std_freelist_3_4_valid                                       |
| 32    | std_freelist_4_4_valid                                       |
| 33    | std_freelist_1_4_valid                                       |
| 34    | std_freelist_2_4_valid                                       |
| 35    | std_freelist_3_4_valid                                       |
| 36    | std_freelist_4_4_valid                                       |
| 37    | dispatch_in                                                  |
| 38    | dispatch_empty                                               |
| 39    | dispatch_utili                                               |
| 40    | dispatch_waitinstr                                           |
| 41    | dispatch_stall_cycle_lsq                                     |
| 42    | dispatch_stall_cycle_rob                                     |
| 43    | dispatch_stall_cycle_int_dq                                  |
| 44    | dispatch_stall_cycle_fp_dq                                   |
| 45    | dispatch_stall_cycle_ls_dq                                   |
| 46    | rob_interrupt_num                                            |
| 47    | rob_exception_num                                            |
| 48    | rob_flush_pipe_num                                           |
| 49    | rob_replay_inst_num                                          |
| 50    | rob_commitUop                                                |
| 51    | rob_commitInstr                                              |
| 52    | rob_commitInstrFused                                         |
| 53    | rob_commitInstrLoad                                          |
| 54    | rob_commitInstrBranch                                        |
| 55    | rob_commitInstrStore                                         |
| 56    | rob_walkInstr                                                |
| 57    | rob_walkCycle                                                |
| 58    | rob_1_4_valid                                                |
| 59    | rob_2_4_valid                                                |
| 60    | rob_3_4_valid                                                |
| 61    | rob_4_4_valid                                                |
| 62    | BR_MIS_PRED                                                  |
| 63    | TOTAL_FLUSH                                                  |
| 64    | EXEC_STALL_CYCLE                                             |
| 65    | MEMSTALL_STORE                                               |
| 66    | MEMSTALL_L1MISS                                              |
| 67    | MEMSTALL_L2MISS                                              |
| 68    | MEMSTALL_L3MISS                                              |
| 69    | issueQueue_enq_fire_cnt                                      |
| 70    | IssueQueueAluMulBkuBrhJmp_full                               |
| 71    | IssueQueueAluMulBkuBrhJmp_full                               |
| 72    | IssueQueueAluBrhJmpI2fVsetriwiVsetriwvfI2v_full              |
| 73    | IssueQueueAluCsrFenceDiv_full                                |
| 74    | issueQueue_enq_fire_cnt                                      |
| 75    | IssueQueueFaluFcvtF2vFmacFdiv_full                           |
| 76    | IssueQueueFaluFmacFdiv_full                                  |
| 77    | IssueQueueFaluFmac_full                                      |
| 78    | issueQueue_enq_fire_cnt                                      |
| 79    | IssueQueueVfmaVialuFixVimacVppuVfaluVfcvtVipuVsetrvfwvf_full |
| 80    | IssueQueueVfmaVialuFixVfalu_full                             |
| 81    | IssueQueueVfdivVidiv_full                                    |
| 82    | issueQueue_enq_fire_cnt                                      |
| 83    | IssueQueueStaMou_full                                        |
| 84    | IssueQueueStaMou_full                                        |
| 85    | IssueQueueLdu_full                                           |
| 86    | IssueQueueLdu_full                                           |
| 87    | IssueQueueLdu_full                                           |
| 88    | IssueQueueVlduVstuVseglduVsegstu_full                        |
| 89    | IssueQueueVlduVstu_full                                      |
| 90    | IssueQueueStdMoud_full                                       |
| 91    | IssueQueueStdMoud_full                                       |

Table: Kunminghu Memory Access Performance Event Index Table

| Index | Event                     |
| ----- | ------------------------- |
| 0     | noEvent                   |
| 1     | load_s0_in_fire           |
| 2     | load_to_load_forward      |
| 3     | stall_dcache              |
| 4     | load_s1_in_fire           |
| 5     | load_s1_tlb_miss          |
| 6     | load_s2_in_fire           |
| 7     | load_s2_dcache_miss       |
| 8     | load_s0_in_fire           |
| 9     | load_to_load_forward      |
| 10    | stall_dcache              |
| 11    | load_s1_in_fire           |
| 12    | load_s1_tlb_miss          |
| 13    | load_s2_in_fire           |
| 14    | load_s2_dcache_miss       |
| 15    | load_s0_in_fire           |
| 16    | load_to_load_forward      |
| 17    | stall_dcache              |
| 18    | load_s1_in_fire           |
| 19    | load_s1_tlb_miss          |
| 20    | load_s2_in_fire           |
| 21    | load_s2_dcache_miss       |
| 22    | sbuffer_req_valid         |
| 23    | sbuffer_req_fire          |
| 24    | sbuffer_merge             |
| 25    | sbuffer_newline           |
| 26    | dcache_req_valid          |
| 27    | dcache_req_fire           |
| 28    | sbuffer_idle              |
| 29    | sbuffer_flush             |
| 30    | sbuffer_replace           |
| 31    | mpipe_resp_valid          |
| 32    | replay_resp_valid         |
| 33    | coh_timeout               |
| 34    | sbuffer_1_4_valid         |
| 35    | sbuffer_2_4_valid         |
| 36    | sbuffer_3_4_valid         |
| 37    | sbuffer_full_valid        |
| 38    | MEMSTALL_ANY_LOAD         |
| 39    | enq                       |
| 40    | ld_ld_violation           |
| 41    | enq                       |
| 42    | stld_rollback             |
| 43    | enq                       |
| 44    | deq                       |
| 45    | deq_block                 |
| 46    | replay_full               |
| 47    | replay_rar_nack           |
| 48    | replay_raw_nack           |
| 49    | replay_nuke               |
| 50    | replay_mem_amb            |
| 51    | replay_tlb_miss           |
| 52    | replay_bank_conflict      |
| 53    | replay_dcache_replay      |
| 54    | replay_forward_fail       |
| 55    | replay_dcache_miss        |
| 56    | full_mask_000             |
| 57    | full_mask_001             |
| 58    | full_mask_010             |
| 59    | full_mask_011             |
| 60    | full_mask_100             |
| 61    | full_mask_101             |
| 62    | full_mask_110             |
| 63    | full_mask_111             |
| 64    | nuke_rollback             |
| 65    | nack_rollback             |
| 66    | mmioCycle                 |
| 67    | mmioCnt                   |
| 68    | mmio_wb_success           |
| 69    | mmio_wb_blocked           |
| 70    | stq_1_4_valid             |
| 71    | stq_2_4_valid             |
| 72    | stq_3_4_valid             |
| 73    | stq_4_4_valid             |
| 74    | dcache_wbq_req            |
| 75    | dcache_wbq_1_4_valid      |
| 76    | dcache_wbq_2_4_valid      |
| 77    | dcache_wbq_3_4_valid      |
| 78    | dcache_wbq_4_4_valid      |
| 79    | dcache_mp_req             |
| 80    | dcache_mp_total_penalty   |
| 81    | dcache_missq_req          |
| 82    | dcache_missq_1_4_valid    |
| 83    | dcache_missq_2_4_valid    |
| 84    | dcache_missq_3_4_valid    |
| 85    | dcache_missq_4_4_valid    |
| 86    | dcache_probq_req          |
| 87    | dcache_probq_1_4_valid    |
| 88    | dcache_probq_2_4_valid    |
| 89    | dcache_probq_3_4_valid    |
| 90    | dcache_probq_4_4_valid    |
| 91    | load_req                  |
| 92    | load_replay               |
| 93    | load_replay_for_data_nack |
| 94    | load_replay_for_no_mshr   |
| 95    | load_replay_for_conflict  |
| 96    | load_req                  |
| 97    | load_replay               |
| 98    | load_replay_for_data_nack |
| 99    | load_replay_for_no_mshr   |
| 100   | load_replay_for_conflict  |
| 101   | load_req                  |
| 102   | load_replay               |
| 103   | load_replay_for_data_nack |
| 104   | load_replay_for_no_mshr   |
| 105   | load_replay_for_conflict  |
| 106   | PTW_tlbllptw_incount      |
| 107   | PTW_tlbllptw_inblock      |
| 108   | PTW_tlbllptw_memcount     |
| 109   | PTW_tlbllptw_memcycle     |
| 110   | PTW_access                |
| 111   | PTW_l2_hit                |
| 112   | PTW_l1_hit                |
| 113   | PTW_l0_hit                |
| 114   | PTW_sp_hit                |
| 115   | PTW_pte_hit               |
| 116   | PTW_rwHazard              |
| 117   | PTW_out_blocked           |
| 118   | PTW_fsm_count             |
| 119   | PTW_fsm_busy              |
| 120   | PTW_fsm_idle              |
| 121   | PTW_resp_blocked          |
| 122   | PTW_mem_count             |
| 123   | PTW_mem_cycle             |
| 124   | PTW_mem_blocked           |
| 125   | ldDeqCount                |
| 126   | stDeqCount                |

Table: Kunming Lake Cache Performance Event Index Table

| Index | Event                           |
| ----- | ------------------------------- |
| 0     | noEvent                         |
| 1     | Slice0_l2_cache_refill          |
| 2     | Slice0_l2_cache_rd_refill       |
| 3     | Slice0_l2_cache_wr_refill       |
| 4     | Slice0_l2_cache_long_miss       |
| 5     | Slice0_l2_cache_access          |
| 6     | Slice0_l2_cache_l2wb            |
| 7     | Slice0_l2_cache_l1wb            |
| 8     | Slice0_l2_cache_wb_victim       |
| 9     | Slice0_l2_cache_wb_cleaning_coh |
| 10    | Slice0_l2_cache_access_rd       |
| 11    | Slice0_l2_cache_access_wr       |
| 12    | Slice0_l2_cache_inv             |
| 13    | Slice1_l2_cache_refill          |
| 14    | Slice1_l2_cache_rd_refill       |
| 15    | Slice1_l2_cache_wr_refill       |
| 16    | Slice1_l2_cache_long_miss       |
| 17    | Slice1_l2_cache_access          |
| 18    | Slice1_l2_cache_l2wb            |
| 19    | Slice1_l2_cache_l1wb            |
| 20    | Slice1_l2_cache_wb_victim       |
| 21    | Slice1_l2_cache_wb_cleaning_coh |
| 22    | Slice1_l2_cache_access_rd       |
| 23    | Slice1_l2_cache_access_wr       |
| 24    | Slice1_l2_cache_inv             |
| 25    | Slice2_l2_cache_refill          |
| 26    | Slice2_l2_cache_rd_refill       |
| 27    | Slice2_l2_cache_wr_refill       |
| 28    | Slice2_l2_cache_long_miss       |
| 29    | Slice2_l2_cache_access          |
| 30    | Slice2_l2_cache_l2wb            |
| 31    | Slice2_l2_cache_l1wb            |
| 32    | Slice2_l2_cache_wb_victim       |
| 33    | Slice2_l2_cache_wb_cleaning_coh |
| 34    | Slice2_l2_cache_access_rd       |
| 35    | Slice2_l2_cache_access_wr       |
| 36    | Slice2_l2_cache_inv             |
| 37    | Slice3_l2_cache_refill          |
| 38    | Slice3_l2_cache_rd_refill       |
| 39    | Slice3_l2_cache_wr_refill       |
| 40    | Slice3_l2_cache_long_miss       |
| 41    | Slice3_l2_cache_access          |
| 42    | Slice3_l2_cache_l2wb            |
| 43    | Slice3_l2_cache_l1wb            |
| 44    | Slice3_l2_cache_wb_victim       |
| 45    | Slice3_l2_cache_wb_cleaning_coh |
| 46    | Slice3_l2_cache_access_rd       |
| 47    | Slice3_l2_cache_access_wr       |
| 48    | Slice3_l2_cache_inv             |

### Topdown PMU

Topdown performance analysis is a top-down approach designed to quickly identify
CPU performance bottlenecks. Its core concept involves decomposing high-level
performance categories step by step, gradually refining the issues to accurately
pinpoint the root cause. We have implemented three levels of Topdown performance
events, as detailed below:

Table: Three-Level Top-Down Performance Events

+-------------+-------------+-------------+--------------+---------------------------------------+
| Level 1 | Level 2 | Level 3 | Description | Formula |
+=============+=============+=============+==============+=======================================+
| Retiring | - | - | Instruction commit impact | INST_RETIRED / | | | | | |
(IssueBW * CPU_CYCLES) |
+-------------+-------------+-------------+--------------+---------------------------------------+
| FrontEnd | - | - | Front-end impact | IF_FETCH_BUBBLE / | | Bound | | | |
(IssueBW * CPU_CYCLES) |
+-------------+-------------+-------------+--------------+---------------------------------------+
| - | Fetch | - | Fetch latency impact | IF_FETCH_BUBBLE_EQ_MAX / | | | Latency
| | | CPU_CYCLES | | | Bound | | | |
+-------------+-------------+-------------+--------------+---------------------------------------+
| | Fetch | | | FrontEnd Bound - | | - | Bandwidth | - | Fetch bandwidth impact
| Fetch Latency Bound | | | Bound | | | |
+-------------+-------------+-------------+--------------+---------------------------------------+
| Bad | | | | (INST_SPEC - INST_RETIRED+ | | Speculation | - | - | Misprediction
impact | RECOVERY_BUBBLE) / | | | | | | (IssueBW * CPU_CYCLES) |
+-------------+-------------+-------------+--------------+---------------------------------------+
| - | Branch | - | Branch misprediction | Bad Speculation * | | | Misspredict |
| impact | BR_MIS_PRED / TOTAL_FLUSH |
+-------------+-------------+-------------+--------------+---------------------------------------+
| - | Machine | - | Machine clear | Bad Speculation - Branch Misspredict | | |
Clears | | event impact | |
+-------------+-------------+-------------+--------------+---------------------------------------+
| BackEnd | - | - | Back-end impact | 1 - (FrontEnd Bound + | | Bound | | | |
Bad Speculation + Retiring) |
+-------------+-------------+-------------+--------------+---------------------------------------+
| - | Core | - | Core impact | (EXEC_STALL_CYCLE - MEMSTALL_ANYLOAD -| | | Bound
| | | MEMSTALL_STORE) / CPU_CYCLE |
+-------------+-------------+-------------+--------------+---------------------------------------+
| - | Memory | - | Memory access impact | (MEMSTALL_ANYLOAD + MEMSTALL_STORE) /
| | | Bound | | | CPU_CYCLES |
+-------------+-------------+-------------+--------------+---------------------------------------+
| - | - | L1 Bound | L1 impact | (MEMSTALL_ANYLOAD - MEMSTALL_L1MISS) /| | | | |
| CPU_CYCLES |
+-------------+-------------+-------------+--------------+---------------------------------------+
| - | - | L2 Bound | L2 impact | (MEMSTALL_L1MISS - MEMSTALL_L2MISS) / | | | | |
| CPU_CYCLES |
+-------------+-------------+-------------+--------------+---------------------------------------+
| - | - | L3 Bound | L3 impact | (MEMSTALL_L2MISS - MEMSTALL_L3MISS) / | | | | |
| CPU_CYCLES |
+-------------+-------------+-------------+--------------+---------------------------------------+
| - | - | Mem Bound | External memory impact | MEMSTALL_L3MISS / CPU_CYCLES |
+-------------+-------------+-------------+--------------+---------------------------------------+
| - | - | Store Bound | Store instruction impact | MEMSTALL_STORE / CPU_CYCLES |
+-------------+-------------+-------------+--------------+---------------------------------------+

Here, IssueBW represents the issue width, which is currently 6-issue in the
Xiangshan Kunminghu architecture.

Table: Topdown Performance Events

+----------------------------+----------------------+---------------------------------------------+\
| Name | Corresponding Event | Description |\
+============================+======================+=============================================+\
| CPU_CYCLES | - | Total clock cycles after all instructions commit |\
+----------------------------+----------------------+---------------------------------------------+\
| INST_RETIRED | rob_commitInstr | Number of successfully committed instructions
|\
+----------------------------+----------------------+---------------------------------------------+\
| INST_SPEC | - | Number of speculatively executed instructions |\
+----------------------------+----------------------+---------------------------------------------+\
| IF_FETCH_BUBBLE | Front_Bubble | Number of bubbles fetched from the
instruction buffer, |\
| | | with no backend stall |\
+----------------------------+----------------------+---------------------------------------------+\
| IF_FETCH_BUBBLE_EQ_MAX | Fetch_Latency_Bound | Cycles fetching zero
instructions from the instruction buffer, |\
| | | with no backend stall |\
+----------------------------+----------------------+---------------------------------------------+\
| BR_MIS_PRED | - | Number of mispredicted branch instructions |\
+----------------------------+----------------------+---------------------------------------------+\
| TOTAL_FLUSH | - | Number of pipeline flush events |\
+----------------------------+----------------------+---------------------------------------------+\
| RECOVERY_BUBBLE | - | Number of cycles recovering from early mispredictions |\
+----------------------------+----------------------+---------------------------------------------+\
| EXEC_STALL_CYCLE | - | Number of cycles issuing few uops |\
+----------------------------+----------------------+---------------------------------------------+\
| MEMSTALL_ANY_LOAD | - | No uops issued, and at least one Load instruction not
completed |\
+----------------------------+----------------------+---------------------------------------------+\
| MEMSTALL_STORE | - | Non-Store uops issued, |\
| | | and Store instructions not completed |\
+----------------------------+----------------------+---------------------------------------------+\
| MEMSTALL_L1MISS | - | No uops issued, at least one Load instruction not
completed, |\
| | | and an L1-cache Miss occurred |\
+----------------------------+----------------------+---------------------------------------------+\
| MEMSTALL_L2MISS | - | No uops issued, at least one Load instruction not
completed, |\
| | | and an L2-cache Miss occurred |\
+----------------------------+----------------------+---------------------------------------------+\
| MEMSTALL_L3MISS | - | No uops issued, at least one Load instruction not
completed, |\
| | | and an L3-cache Miss occurred |\
+----------------------------+----------------------+---------------------------------------------+

To measure the impact of front-end fetch latency over a period, we can set the
EVENT0 field of mhpmevent3 to 22, leaving the remaining bits at their default
values, then proceed with testing. Upon completion, the CSR read instruction can
be used to access the mhpmcounter3 register, obtaining the cycle count of
front-end fetch latency during that period. Through calculation, the impact
caused by front-end fetch latency can then be determined.

## HPM-related performance event counters

The performance event counters in the Xiangshan Kunminghu architecture are
divided into three groups: machine-mode event counters, supervisor-mode event
counters, and user-mode event counters.

Table: Machine Mode Event Counter List

| Name            | Index       | Read/Write | Introduction                             | Reset value |
| --------------- | ----------- | ---------- | ---------------------------------------- | ----------- |
| MCYCLE          | 0xB00       | RW         | Machine Mode Clock Cycle Counter         | -           |
| MINSTRET        | 0xB02       | RW         | Machine-mode retired instruction counter | -           |
| MHPMCOUNTER3-31 | 0XB03-0XB1F | RW         | Machine-mode Performance Event Counter   | 0           |

The corresponding MHPMCOUNTERx counter is controlled by MHPMEVENTx, specifying
the counting of relevant performance events.

Supervisor mode event counters include the supervisor mode counter overflow
interrupt flag register (SCOUNTOVF)

Table: Supervisor Mode Counter Overflow Interrupt Flag Register (SCOUNTOVF)
Description

+------------+--------+-------+-----------------------------------------------+--------+
| Name | Bits | R/W | Behavior | Reset |
+============+========+=======+===============================================+========+
| OFVEC | 31:3 | RO | mhpmcounterx register overflow flag: | 0 | | | | | | | | |
| | 1: Overflow occurred | | | | | | | | | | | | 0: No overflow occurred | |
+------------+--------+-------+-----------------------------------------------+--------+
| -- | 2:0 | RO 0 | -- | 0 |
+------------+--------+-------+-----------------------------------------------+--------+

scountovf serves as a read-only mapping of the OF bit in the mhpmcounter
register, controlled by xcounteren:

* M-mode can read the correct value when accessing scountovf.
* HS-mode access to scountovf: When mcounteren.HPMx is 1, the corresponding
  OFVECx can read the correct value; otherwise, it only reads 0.
* When accessing scountovf in VS-mode: When both mcounteren.HPMx and
  hcounteren.HPMx are 1, the corresponding OFVECx can be read correctly;
  otherwise, it only reads 0.

Table: User Mode Event Counter List

| Name           | Index       | Read/Write | Introduction                                          | Reset value |
| -------------- | ----------- | ---------- | ----------------------------------------------------- | ----------- |
| CYCLE          | 0xC00       | RO         | User-mode read-only copy of mcycle register           | -           |
| TIME           | 0xC01       | RO         | Memory-mapped register mtime user-mode read-only copy | -           |
| INSTRET        | 0xC02       | RO         | User-mode read-only copy of minstret register         | -           |
| HPMCOUNTER3-31 | 0XC03-0XC1F | RO         | mhpmcounter3-31 寄存器用户模式只读副本                           | 0           |
