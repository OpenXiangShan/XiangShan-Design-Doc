# HPM

- Version: V2R2A
- Status: OK
- Date: 2026/10/13
- commit: [XSAI e8fb1a14](https://github.com/OpenXiangShan/XSAI/tree/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f)

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

- Implements basic hardware performance monitoring based on the RISC-V Privileged Specification, with additional support for the sstc and sscofpmf extensions
- Clock cycles executed by the hart (cycle)
- Instructions committed by the hart (minstret)
- Hardware timer (time)
- Counter overflow flag (time)
- 29 hardware performance counters (hpmcounter3 - hpmcounter31)
- 29 hardware performance event selectors (mhpmevent3 - mhpmevent31)
- Supports up to 2^10 performance events

### Function

The basic functions of HPM are as follows:

* Disable all performance event monitoring via the mcountinhibit register.
* Initialize the performance event counters of each monitoring unit, including: mcycle, minstret, mhpmcounter3 - mhpmcounter31.
* Configure performance event selectors for each monitoring unit, including: mhpmcounter3 - mhpmcounter31. The Xiangshan Kunminghu architecture allows up to four event combinations per selector. After writing the event index value, combination method, and sampling privilege level into the selector, normal counting of configured events can proceed at the specified privilege level, with results accumulated into the event counter based on the combined outcome.
* Configure xcounteren for access permission authorization
* Enable all performance event monitoring via mcountinhibit register and start counting.

#### HPM event overflow interrupt

The overflow interrupt LCOFIP initiated by the Kunming Lake Performance Monitoring Unit has a unified interrupt vector number of 12. The enabling and handling process of the interrupt is consistent with that of ordinary private interrupts.

## Overall Design

Performance events are defined within each submodule, which assemble them into io_perf by calling generatePerfEvent and output to the four main modules: Frontend, Backend, MemBlock, and CoupledL2.

The above four modules obtain the performance event outputs of submodules by calling the get_perf method. Meanwhile, each main module instantiates the PFEvent module as a replica of mhpmevent in CSR, aggregating the required performance event selector data and the performance event outputs from submodules, which are then fed into the HPerfMonitor module to calculate the incremental results applied to the performance event counters.

Finally, the CSR collects incremental results from performance event counters of four top-level modules and inputs them into CSR registers mhpmcounter3-31 for cumulative counting.

CoupledL2 performance events are sent directly to the CSR module. HPerfMonitor instantiated in CSR processes them using event selection information read from mhpmevent and accumulates the resulting increments in CSR registers mhpmcounter27-31.

For the detailed HPM overall design block diagram, refer to [@fig:HPM]:

![HPM Overall Design](./figure/hpm.svg){#fig:HPM}

### XSAI Matrix Performance Events

When HasMatrixExtension is enabled and MatAcc=CUTE, CUTE's CutePerfToCoreIO sends 9 backendEvents and 12 memEvents to the control core, each 6 bits wide. XSCore connects the backend events to Backend and the memory events to MemBlock. Each group is combined and counted by its HPerfMonitor using the existing CSR performance counters.

Table: Interface Order of CUTE Backend Events

| backendEvents Index | Event Name       | Counting Condition                                                    |
| ------------------- | ---------------- | --------------------------------------------------------------------- |
| 0                   | amu_active_cycle | TaskController has work: pending input or a nonempty in-flight window |
| 1                   | amu_retire       | The task at the head of CUTE's in-flight window completes and retires |
| 2                   | amu_comp_done    | Compute results have finished writing to C                            |
| 3                   | amu_release_done | A release task satisfies its dependencies and issues                  |
| 4                   | amu_mte_active   | The compute resource is busy                                          |
| 5                   | amu_mma_nonfp    | Non-floating-point results have finished writing to C                 |
| 6                   | amu_mma_fp16     | FP16×FP16→FP32 results have finished writing to C                     |
| 7                   | amu_mma_bf16     | BF16×BF16→FP32 results have finished writing to C                     |
| 8                   | amu_mma_tf32     | TF32×TF32→FP32 results have finished writing to C                     |

Table: Interface Order of CUTE Memory Events

| memEvents Index | Event Name           | Counting Condition                                                                            |
| --------------- | -------------------- | --------------------------------------------------------------------------------------------- |
| 0               | amu_load_a_done      | A physical AML task completes, including ordinary A loads, A/B transpose loads, and ZeroTr    |
| 1               | amu_load_b_done      | A physical BML task completes, namely an ordinary B load                                      |
| 2               | amu_load_c_done      | A physical CML load task completes, including C loads and ZeroAcc                             |
| 3               | amu_store_done       | A C store completes                                                                           |
| 4               | amu_aml_active       | The A load resource is busy                                                                   |
| 5               | amu_bml_active       | The B load resource is busy                                                                   |
| 6               | amu_cml_load_active  | The C load resource is busy                                                                   |
| 7               | amu_cml_store_active | The C store resource is busy                                                                  |
| 8               | amu_mem_rd_req       | A cycle in which LocalMMU issues at least one read request to the last-level cache interface  |
| 9               | amu_mem_wr_req       | A cycle in which LocalMMU issues at least one write request to the last-level cache interface |
| 10              | amu_mem_rd_32B_req   | Valid bytes in handshaking read-request masks divided by 32, summed across banks              |
| 11              | amu_mem_wr_32B_req   | Valid bytes in handshaking write-request masks divided by 32, summed across banks             |

The backendEvents and memEvents indices identify positions in the CUTE interface. A/C load completion events include mzero completion on the corresponding load paths, so they count both data loads and register clearing. Compute type event positions remain fixed; MatrixIsaParams determines which type combinations can execute.

Backend concatenates event lists in order. The prefix contains noEvent, baseline CtrlBlock events, DataPath, the first 5 IntScheduler events, FpScheduler, VfScheduler, and the first 10 MemScheduler events. The suffix contains extended CtrlBlock events, the remaining IntScheduler events, MfScheduler, the remaining MemScheduler events, and the 9 CUTE events above. Events for the matrix dimension free list, MSET/MRELEASE, Mf IQ, and MLS IQ reside in the suffix.

MemBlock appends the 12 CUTE memory events after the memory unit, DTLB, PTW, and ldDeqCount/stDeqCount events. Absolute indices used by mhpmevent depend on the hardware configuration and the expanded lengths of the event lists. Enabling printEventCoding prints event names and indices for each group in the hardware generation log.

`rob_commitInstr` counts control-core instruction commits, while `amu_retire` counts retirement from CUTE's task window. After ROB commit, a matrix operation passes through request delivery, CUTE scheduling, and execution; it contributes to `amu_retire` when it completes at the window head.

See [Backend.scala](https://github.com/OpenXiangShan/XSAI/blob/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f/src/main/scala/xiangshan/backend/Backend.scala) and [MemBlock.scala](https://github.com/OpenXiangShan/XSAI/blob/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f/src/main/scala/xiangshan/mem/MemBlock.scala).

### HPerfMonitor Counter Organization Module

Input the event selection information (events) into the corresponding HPerfCounter module, and replicate all performance event counting information to each HperfCounter module.

Collect all HperfCounter outputs.

### HperfCounter single counter module

Based on the input event selection information, select the required performance event counting information, and according to the counting mode in the event selection information, combine and output the input performance events.

### Copy of PFEvent Hpmevent register

Copy of CSR register mhpmevent: Collects CSR write information and synchronizes changes to mhpmevent

## HPM-related control registers

### Machine-mode Performance Event Count Inhibit Register (MCOUNTINHIBIT)

The Machine-Mode Performance Event Count Inhibit Register (mcountinhibit) is a 32-bit WARL register primarily used to control whether hardware performance monitoring counters count. In scenarios where performance analysis is not required, counters can be disabled to reduce processor power consumption.

Table: Machine Mode Performance Event Count Prohibit Register Description

+------+------+------+------------------------------------------+-------+
| Name | Bits | R/W  | Behavior                                 | Reset |
+======+======+======+==========================================+=======+
| HPMx | 31:4 | RW   | mhpmcounterx register count-disable bit: | 0     |
|      |      |      |                                          |       |
|      |      |      | 0: Normal counting                       |       |
|      |      |      |                                          |       |
|      |      |      | 1: Counting disabled                     |       |
+------+------+------+------------------------------------------+-------+
| IR   | 3    | RW   | minstret register count-disable bit:     | 0     |
|      |      |      |                                          |       |
|      |      |      | 0: Normal counting                       |       |
|      |      |      |                                          |       |
|      |      |      | 1: Counting disabled                     |       |
+------+------+------+------------------------------------------+-------+
| --   | 2    | RO 0 | Reserved                                 | 0     |
+------+------+------+------------------------------------------+-------+
| CY   | 1    | RW   | mcycle register count-disable bit:       | 0     |
|      |      |      |                                          |       |
|      |      |      | 0: Normal counting                       |       |
|      |      |      |                                          |       |
|      |      |      | 1: Counting disabled                     |       |
+------+------+------+------------------------------------------+-------+

### Machine-mode Performance Counter Event Access Enable Register (MCOUNTEREN)

The Machine-mode Performance Event Counter Access Enable Register (mcounteren) is a 32-bit WARL register primarily used to control access permissions for user-mode performance monitoring counters at privilege levels below machine mode (HS-mode/VS-mode/HU-mode/VU-mode).

Table: Machine Mode Performance Event Counter Access Authorization Register Description

+------+------+-----+------------------------------------------------------------------+-------+
| Name | Bits | R/W | Behavior                                                         | Reset |
+======+======+=====+==================================================================+=======+
| HPMx | 31:4 | RW  | hpmcounterenx register access-permission bit below M-mode:       | 0     |
|      |      |     |                                                                  |       |
|      |      |     | 0: Accessing hpmcounterx raises an illegal instruction exception |       |
|      |      |     |                                                                  |       |
|      |      |     | 1: Normal access to hpmcounterx is permitted                     |       |
+------+------+-----+------------------------------------------------------------------+-------+
| IR   | 3    | RW  | instret register access-permission bit below M-mode:             | 0     |
|      |      |     |                                                                  |       |
|      |      |     | 0: Accessing instret raises an illegal instruction exception     |       |
|      |      |     |                                                                  |       |
|      |      |     | 1: Normal access is permitted                                    |       |
+------+------+-----+------------------------------------------------------------------+-------+
| TM   | 2    | RW  | time/stimecmp register access-permission bit below M-mode:       | 0     |
|      |      |     |                                                                  |       |
|      |      |     | 0: Accessing time raises an illegal instruction exception        |       |
|      |      |     |                                                                  |       |
|      |      |     | 1: Normal access is permitted                                    |       |
+------+------+-----+------------------------------------------------------------------+-------+
| CY   | 1    | RW  | cycle register access-permission bit below M-mode:               | 0     |
|      |      |     |                                                                  |       |
|      |      |     | 0: Accessing cycle raises an illegal instruction exception       |       |
|      |      |     |                                                                  |       |
|      |      |     | 1: Normal access is permitted                                    |       |
+------+------+-----+------------------------------------------------------------------+-------+

### Supervisor-mode Performance Counter Access Enable Register (SCOUNTEREN)

Supervisor-mode Performance Counter Access Enable Register (scounteren) is a 32-bit WARL register primarily used to control user-mode access permissions for performance monitoring counters in HU-mode/VU-mode.

Table: Description of access permission registers for supervisor-mode performance event counters

+------+------+-----+------------------------------------------------------------------+-------+
| Name | Bits | R/W | Behavior                                                         | Reset |
+======+======+=====+==================================================================+=======+
| HPMx | 31:4 | RW  | hpmcounterenx register user-mode access-permission bit:          | 0     |
|      |      |     |                                                                  |       |
|      |      |     | 0: Accessing hpmcounterx raises an illegal instruction exception |       |
|      |      |     |                                                                  |       |
|      |      |     | 1: Normal access to hpmcounterx is permitted                     |       |
+------+------+-----+------------------------------------------------------------------+-------+
| IR   | 3    | RW  | instret register user-mode access-permission bit:                | 0     |
|      |      |     |                                                                  |       |
|      |      |     | 0: Accessing instret raises an illegal instruction exception     |       |
|      |      |     |                                                                  |       |
|      |      |     | 1: Normal access is permitted                                    |       |
+------+------+-----+------------------------------------------------------------------+-------+
| TM   | 2    | RW  | time register user-mode access-permission bit:                   | 0     |
|      |      |     |                                                                  |       |
|      |      |     | 0: Accessing time raises an illegal instruction exception        |       |
|      |      |     |                                                                  |       |
|      |      |     | 1: Normal access is permitted                                    |       |
+------+------+-----+------------------------------------------------------------------+-------+
| CY   | 1    | RW  | cycle register user-mode access-permission bit:                  | 0     |
|      |      |     |                                                                  |       |
|      |      |     | 0: Accessing cycle raises an illegal instruction exception       |       |
|      |      |     |                                                                  |       |
|      |      |     | 1: Normal access is permitted                                    |       |
+------+------+-----+------------------------------------------------------------------+-------+

### Virtualization Mode Performance Event Counter Access Authorization Register (HCOUNTEREN)

The Virtualization Mode Performance Event Counter Access Authorization Register (hcounteren) is a 32-bit WARL register primarily used to control user-mode performance monitoring counter access permissions in guest virtual machines (VS-mode/VU-mode).

Table: Description of access permission registers for supervisor-mode performance event counters

+------+------+-----+------------------------------------------------------------------+-------+
| Name | Bits | R/W | Behavior                                                         | Reset |
+======+======+=====+==================================================================+=======+
| HPMx | 31:4 | RW  | hpmcounterenx register guest-VM access-permission bit:           | 0     |
|      |      |     |                                                                  |       |
|      |      |     | 0: Accessing hpmcounterx raises an illegal instruction exception |       |
|      |      |     |                                                                  |       |
|      |      |     | 1: Normal access to hpmcounterx is permitted                     |       |
+------+------+-----+------------------------------------------------------------------+-------+
| IR   | 3    | RW  | instret register guest-VM access-permission bit:                 | 0     |
|      |      |     |                                                                  |       |
|      |      |     | 0: Accessing instret raises an illegal instruction exception     |       |
|      |      |     |                                                                  |       |
|      |      |     | 1: Normal access is permitted                                    |       |
+------+------+-----+------------------------------------------------------------------+-------+
| TM   | 2    | RW  | time/vstimecmp(via stimecmp) register guest-VM                   | 0     |
|      |      |     | access-permission bit:                                           |       |
|      |      |     |                                                                  |       |
|      |      |     | 0: Accessing time raises an illegal instruction exception        |       |
|      |      |     |                                                                  |       |
|      |      |     | 1: Normal access is permitted                                    |       |
+------+------+-----+------------------------------------------------------------------+-------+
| CY   | 1    | RW  | cycle register guest-VM access-permission bit:                   | 0     |
|      |      |     |                                                                  |       |
|      |      |     | 0: Accessing cycle raises an illegal instruction exception       |       |
|      |      |     |                                                                  |       |
|      |      |     | 1: Normal access is permitted                                    |       |
+------+------+-----+------------------------------------------------------------------+-------+

### Supervisor Mode Time Compare Register (STIMECMP)

The Supervisor Mode Timer Compare Register (stimecmp) is a 64-bit WARL register primarily used to manage timer interrupts (STIP) in supervisor mode.

STIMECMP Register Behavior Description:

* The reset value is the 64-bit unsigned number 64'hffff_ffff_ffff_ffff.
* When menvcfg.STCE is 0 and the current privilege level is below M-mode (HS-mode/VS-mode/HU-mode/VU-mode), accessing the stimecmp register triggers an illegal instruction exception and does not generate an STIP interrupt.
* The stimecmp register is the source of STIP interrupt generation: when performing an unsigned integer comparison time ≥ stimecmp, it asserts the STIP interrupt pending signal.
* Supervisor mode software can control the generation of timer interrupts by writing to stimecmp.

### Guest Virtual Machine Supervisor Mode Time Compare Register (VSTIMECMP)

The Guest Supervisor Time Compare Register (vstimecmp) is a 64-bit WARL register primarily used to manage timer interrupts (STIP) in guest supervisor mode.

VSTIMECMP Register Behavior Description:

* The reset value is the 64-bit unsigned number 64'hffff_ffff_ffff_ffff.
* When henvcfg.STCE is 0 or hcounteren.TM is set, accessing the vstimecmp register via the stimecmp register triggers a virtual illegal instruction exception without generating a VSTIP interrupt.
* The vstimecmp register is the source of VSTIP interrupt generation: when performing an unsigned integer comparison time + htimedelta ≥ vstimecmp, the VSTIP interrupt pending signal is raised.
* Guest supervisor mode software can control the generation of timer interrupts in VS-mode by writing to vstimecmp.

## HPM-related performance event selectors

Machine-mode Performance Event Selector (mhpmevent3 - 31) is a 64-bit WARL register used to select the performance event corresponding to each performance event counter. In the Xiangshan Kunminghu architecture, each counter can be configured to count up to four performance events in combination. After users write the event index value, event combination method, and sampling privilege level into the designated event selector, the event counter matched by that selector begins normal counting.

Table: Machine Mode Performance Event Selector Description

+----------+-------+-----+---------------------------------------------------------------------------------------------+-------+
| Name     | Bits  | R/W | Behavior                                                                                    | Reset |
+==========+=======+=====+=============================================================================================+=======+
| OF       | 63    | RW  | Performance counter overflow flag:                                                          | 0     |
|          |       |     |                                                                                             |       |
|          |       |     | 0: Set to 1 on the corresponding counter's overflow; generate an overflow interrupt         |       |
|          |       |     |                                                                                             |       |
|          |       |     | 1: Unchanged on the corresponding counter's overflow; do not generate an overflow interrupt |       |
+----------+-------+-----+---------------------------------------------------------------------------------------------+-------+
| MINH     | 62    | RW  | When set, inhibit counting in M-mode                                                        | 0     |
+----------+-------+-----+---------------------------------------------------------------------------------------------+-------+
| SINH     | 61    | RW  | When set, inhibit counting in S-mode                                                        | 0     |
+----------+-------+-----+---------------------------------------------------------------------------------------------+-------+
| UINH     | 60    | RW  | When set, inhibit counting in U-mode                                                        | 0     |
+----------+-------+-----+---------------------------------------------------------------------------------------------+-------+
| VSINH    | 59    | RW  | When set, inhibit counting in VS-mode                                                       | 0     |
+----------+-------+-----+---------------------------------------------------------------------------------------------+-------+
| VUINH    | 58    | RW  | When set, inhibit counting in VU-mode                                                       | 0     |
+----------+-------+-----+---------------------------------------------------------------------------------------------+-------+
| --       | 57:55 | RW  | --                                                                                          | 0     |
+----------+-------+-----+---------------------------------------------------------------------------------------------+-------+
|          |       |     | Counter event-combination control bits:                                                     |       |
|          |       |     |                                                                                             |       |
|          |       |     | 5'b00000: Combine using or                                                                  |       |
| OP_TYPE2 | 54:50 |     |                                                                                             |       |
| OP_TYPE1 | 49:45 | RW  | 5'b00001: Combine using and                                                                 | 0     |
| OP_TYPE0 | 44:40 |     |                                                                                             |       |
|          |       |     | 5'b00010: Combine using xor                                                                 |       |
|          |       |     |                                                                                             |       |
|          |       |     | 5'b00100: Combine using add                                                                 |       |
+----------+-------+-----+---------------------------------------------------------------------------------------------+-------+
|          |       |     | Counter performance-event indices:                                                          |       |
| EVENT3   | 39:30 |     |                                                                                             |       |
| EVENT2   | 29:20 | RW  | 0: The corresponding event counter does not count                                           | --    |
| EVENT1   | 19:10 |     |                                                                                             |       |
| EVENT0   | 9:0   |     | 1: The corresponding event counter counts the event                                         |       |
|          |       |     |                                                                                             |       |
+----------+-------+-----+---------------------------------------------------------------------------------------------+-------+

The combination method for counter events is:

* EVENT0 and EVENT1 event counts use OP_TYPE0 operation combination to produce RESULT0.
* EVENT2 and EVENT3 event counts are combined using OP_TYPE1 operation to produce RESULT1.
* The combined results of RESULT0 and RESULT1 are processed using OP_TYPE2 operation to form RESULT2.
* RESULT2 is accumulated into the corresponding event counter.

The reset value for the event index portion of the performance event selector is specified as 0

The Kunming Lake architecture categorizes the provided performance events into four types based on their sources: frontend, backend, memory access, and cache. The counters are divided into four sections, each recording performance events from the aforementioned sources:

* Frontend: mhpmevent 3-10
* Backend: mhpmevent11-18
* Memory Access: mhpmevent19-26
* Cache: mhpmevent27-31

The following four tables list the kunminghu-v2 event indices. XSAI adds matrix events and changes some issue queue names. printEventCoding outputs the full event encodings for each configuration; the matrix event concatenation order is described above.

Table: kunminghu-v2 Baseline Frontend Performance Event Indices

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
| 56    | itlb_access             |
| 57    | itlb_miss               |

Table: kunminghu-v2 Baseline Backend Performance Event Indices

| Index | Event                                                        |
| ----- | ------------------------------------------------------------ |
| 0     | noEvent                                                      |
| 1     | decoder_fused_instr                                          |
| 2     | decoder_waitInstr                                            |
| 3     | decoder_stall_cycle                                          |
| 4     | decoder_utilization                                          |
| 5     | frontend_stall_cycle                                         |
| 6     | backend_stall_cycle                                          |
| 7     | INST_SPEC                                                    |
| 8     | RECOVERY_BUBBLE                                              |
| 9     | rename_in                                                    |
| 10    | rename_waitinstr                                             |
| 11    | rename_stall                                                 |
| 12    | rename_stall_cycle_walk                                      |
| 13    | rename_stall_cycle_dispatch                                  |
| 14    | rename_stall_cycle_int                                       |
| 15    | rename_stall_cycle_fp                                        |
| 16    | rename_stall_cycle_vec                                       |
| 17    | rename_stall_cycle_v0                                        |
| 18    | rename_stall_cycle_vl                                        |
| 19    | me_freelist_1_4_valid                                        |
| 20    | me_freelist_2_4_valid                                        |
| 21    | me_freelist_3_4_valid                                        |
| 22    | me_freelist_4_4_valid                                        |
| 23    | std_freelist_1_4_valid                                       |
| 24    | std_freelist_2_4_valid                                       |
| 25    | std_freelist_3_4_valid                                       |
| 26    | std_freelist_4_4_valid                                       |
| 27    | std_freelist_1_4_valid                                       |
| 28    | std_freelist_2_4_valid                                       |
| 29    | std_freelist_3_4_valid                                       |
| 30    | std_freelist_4_4_valid                                       |
| 31    | std_freelist_1_4_valid                                       |
| 32    | std_freelist_2_4_valid                                       |
| 33    | std_freelist_3_4_valid                                       |
| 34    | std_freelist_4_4_valid                                       |
| 35    | std_freelist_1_4_valid                                       |
| 36    | std_freelist_2_4_valid                                       |
| 37    | std_freelist_3_4_valid                                       |
| 38    | std_freelist_4_4_valid                                       |
| 39    | dispatch_in                                                  |
| 40    | dispatch_empty                                               |
| 41    | dispatch_utili                                               |
| 42    | dispatch_waitinstr                                           |
| 43    | dispatch_stall_cycle_lsq                                     |
| 44    | dispatch_stall_cycle_rob                                     |
| 45    | dispatch_stall_cycle_int_dq                                  |
| 46    | dispatch_stall_cycle_fp_dq                                   |
| 47    | dispatch_stall_cycle_ls_dq                                   |
| 48    | rob_interrupt_num                                            |
| 49    | rob_exception_num                                            |
| 50    | rob_flush_pipe_num                                           |
| 51    | rob_replay_inst_num                                          |
| 52    | rob_commitUop                                                |
| 53    | rob_commitInstr                                              |
| 54    | rob_commitInstrFused                                         |
| 55    | rob_commitInstrLoad                                          |
| 56    | rob_commitInstrBranch                                        |
| 57    | rob_commitInstrStore                                         |
| 58    | rob_walkInstr                                                |
| 59    | rob_walkCycle                                                |
| 60    | rob_1_4_valid                                                |
| 61    | rob_2_4_valid                                                |
| 62    | rob_3_4_valid                                                |
| 63    | rob_4_4_valid                                                |
| 64    | BRANCH_JUMP                                                  |
| 65    | BR_MIS_PRED                                                  |
| 66    | TOTAL_FLUSH                                                  |
| 67    | EXEC_STALL_CYCLE                                             |
| 68    | MEMSTALL_STORE                                               |
| 69    | MEMSTALL_L1MISS                                              |
| 70    | MEMSTALL_L2MISS                                              |
| 71    | MEMSTALL_L3MISS                                              |
| 72    | issueQueue_enq_fire_cnt                                      |
| 73    | IssueQueueAluMulBkuBrhJmp_full                               |
| 74    | IssueQueueAluMulBkuBrhJmp_full                               |
| 75    | IssueQueueAluBrhJmpI2fVsetriwiVsetriwvfI2v_full              |
| 76    | IssueQueueAluCsrFenceDiv_full                                |
| 77    | issueQueue_enq_fire_cnt                                      |
| 78    | IssueQueueFaluFcvtF2vFmacFdiv_full                           |
| 79    | IssueQueueFaluFmacFdiv_full                                  |
| 80    | IssueQueueFaluFmac_full                                      |
| 81    | issueQueue_enq_fire_cnt                                      |
| 82    | IssueQueueVfmaVialuFixVimacVppuVfaluVfcvtVipuVsetrvfwvf_full |
| 83    | IssueQueueVfmaVialuFixVfalu_full                             |
| 84    | IssueQueueVfdivVidiv_full                                    |
| 85    | issueQueue_enq_fire_cnt                                      |
| 86    | IssueQueueStaMou_full                                        |
| 87    | IssueQueueStaMou_full                                        |
| 88    | IssueQueueLdu_full                                           |
| 89    | IssueQueueLdu_full                                           |
| 90    | IssueQueueLdu_full                                           |
| 91    | IssueQueueVlduVstuVseglduVsegstu_full                        |
| 92    | IssueQueueVlduVstu_full                                      |
| 93    | IssueQueueStdMoud_full                                       |
| 94    | IssueQueueStdMoud_full                                       |

Table: kunminghu-v2 Baseline Memory Performance Event Indices

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
| 8     | l1D_load_hw_prf_access    |
| 9     | l1D_load_hw_prf_miss      |
| 10    | load_s0_in_fire           |
| 11    | load_to_load_forward      |
| 12    | stall_dcache              |
| 13    | load_s1_in_fire           |
| 14    | load_s1_tlb_miss          |
| 15    | load_s2_in_fire           |
| 16    | load_s2_dcache_miss       |
| 17    | l1D_load_hw_prf_access    |
| 18    | l1D_load_hw_prf_miss      |
| 19    | load_s0_in_fire           |
| 20    | load_to_load_forward      |
| 21    | stall_dcache              |
| 22    | load_s1_in_fire           |
| 23    | load_s1_tlb_miss          |
| 24    | load_s2_in_fire           |
| 25    | load_s2_dcache_miss       |
| 26    | l1D_load_hw_prf_access    |
| 27    | l1D_load_hw_prf_miss      |
| 28    | sbuffer_req_valid         |
| 29    | sbuffer_req_fire          |
| 30    | sbuffer_merge             |
| 31    | sbuffer_newline           |
| 32    | dcache_req_valid          |
| 33    | dcache_req_fire           |
| 34    | sbuffer_idle              |
| 35    | sbuffer_flush             |
| 36    | sbuffer_replace           |
| 37    | mpipe_resp_valid          |
| 38    | replay_resp_valid         |
| 39    | coh_timeout               |
| 40    | sbuffer_1_4_valid         |
| 41    | sbuffer_2_4_valid         |
| 42    | sbuffer_3_4_valid         |
| 43    | sbuffer_full_valid        |
| 44    | MEMSTALL_ANY_LOAD         |
| 45    | enq                       |
| 46    | ld_ld_violation           |
| 47    | enq                       |
| 48    | stld_rollback             |
| 49    | enq                       |
| 50    | deq                       |
| 51    | deq_block                 |
| 52    | replay_full               |
| 53    | replay_rar_nack           |
| 54    | replay_raw_nack           |
| 55    | replay_nuke               |
| 56    | replay_mem_amb            |
| 57    | replay_tlb_miss           |
| 58    | replay_bank_conflict      |
| 59    | replay_dcache_replay      |
| 60    | replay_forward_fail       |
| 61    | replay_dcache_miss        |
| 62    | full_mask_000             |
| 63    | full_mask_001             |
| 64    | full_mask_010             |
| 65    | full_mask_011             |
| 66    | full_mask_100             |
| 67    | full_mask_101             |
| 68    | full_mask_110             |
| 69    | full_mask_111             |
| 70    | nuke_rollback             |
| 71    | nack_rollback             |
| 72    | mmioCycle                 |
| 73    | mmioCnt                   |
| 74    | mmio_wb_success           |
| 75    | mmio_wb_blocked           |
| 76    | stq_1_4_valid             |
| 77    | stq_2_4_valid             |
| 78    | stq_3_4_valid             |
| 79    | stq_4_4_valid             |
| 80    | dcache_wbq_req            |
| 81    | dcache_wbq_1_4_valid      |
| 82    | dcache_wbq_2_4_valid      |
| 83    | dcache_wbq_3_4_valid      |
| 84    | dcache_wbq_4_4_valid      |
| 85    | l1D_write_dcache_access   |
| 86    | l1D_write_dcache_miss     |
| 87    | dcache_mp_req             |
| 88    | dcache_mp_total_penalty   |
| 89    | dcache_missq_req          |
| 90    | dcache_missq_1_4_valid    |
| 91    | dcache_missq_2_4_valid    |
| 92    | dcache_missq_3_4_valid    |
| 93    | dcache_missq_4_4_valid    |
| 94    | dcache_probq_req          |
| 95    | dcache_probq_1_4_valid    |
| 96    | dcache_probq_2_4_valid    |
| 97    | dcache_probq_3_4_valid    |
| 98    | dcache_probq_4_4_valid    |
| 99    | load_req                  |
| 100   | load_replay               |
| 101   | load_replay_for_data_nack |
| 102   | load_replay_for_no_mshr   |
| 103   | load_replay_for_conflict  |
| 104   | l1D_read_dcache_access    |
| 105   | l1D_read_dcache_miss      |
| 106   | load_req                  |
| 107   | load_replay               |
| 108   | load_replay_for_data_nack |
| 109   | load_replay_for_no_mshr   |
| 110   | load_replay_for_conflict  |
| 111   | l1D_read_dcache_access    |
| 112   | l1D_read_dcache_miss      |
| 113   | load_req                  |
| 114   | load_replay               |
| 115   | load_replay_for_data_nack |
| 116   | load_replay_for_no_mshr   |
| 117   | load_replay_for_conflict  |
| 118   | l1D_read_dcache_access    |
| 119   | l1D_read_dcache_miss      |
| 120   | dtlb_ld_access            |
| 121   | dtlb_ld_miss              |
| 122   | dtlb_st_access            |
| 123   | dtlb_st_miss              |
| 124   | PTW_tlbllptw_incount      |
| 125   | PTW_tlbllptw_inblock      |
| 126   | PTW_tlbllptw_memcount     |
| 127   | PTW_tlbllptw_memcycle     |
| 128   | PTW_access                |
| 129   | PTW_l2_hit                |
| 130   | PTW_l1_hit                |
| 131   | PTW_l0_hit                |
| 132   | PTW_sp_hit                |
| 133   | PTW_pte_hit               |
| 134   | PTW_rwHazard              |
| 135   | PTW_out_blocked           |
| 136   | PTW_fsm_count             |
| 137   | PTW_fsm_busy              |
| 138   | PTW_fsm_idle              |
| 139   | PTW_resp_blocked          |
| 140   | PTW_mem_count             |
| 141   | PTW_mem_cycle             |
| 142   | PTW_mem_blocked           |
| 143   | ldDeqCount                |
| 144   | stDeqCount                |

Table: kunminghu-v2 Baseline Cache Performance Event Indices

| Index | Event                           |
| ----- | ------------------------------- |
| 0     | noEvent                         |
| 1     | Slice0_l2_cache_refill          |
| 2     | Slice0_l2_cache_rd_refill       |
| 3     | Slice0_l2_cache_wr_refill       |
| 4     | Slice0_l2_cache_long_miss       |
| 5     | Slice0_l2_cache_hit             |
| 6     | Slice0_l2_cache_miss            |
| 7     | Slice0_l2_cache_access          |
| 8     | Slice0_l2_cache_l2wb            |
| 9     | Slice0_l2_cache_l1wb            |
| 10    | Slice0_l2_cache_wb_victim       |
| 11    | Slice0_l2_cache_wb_cleaning_coh |
| 12    | Slice0_l2_cache_prefetch_access |
| 13    | Slice0_l2_cache_prefetch_miss   |
| 14    | Slice0_l2_cache_access_rd       |
| 15    | Slice0_l2_cache_access_wr       |
| 16    | Slice0_l2_cache_miss_rd         |
| 17    | Slice0_l2_cache_inv             |
| 18    | Slice1_l2_cache_refill          |
| 19    | Slice1_l2_cache_rd_refill       |
| 20    | Slice1_l2_cache_wr_refill       |
| 21    | Slice1_l2_cache_long_miss       |
| 22    | Slice1_l2_cache_hit             |
| 23    | Slice1_l2_cache_miss            |
| 24    | Slice1_l2_cache_access          |
| 25    | Slice1_l2_cache_l2wb            |
| 26    | Slice1_l2_cache_l1wb            |
| 27    | Slice1_l2_cache_wb_victim       |
| 28    | Slice1_l2_cache_wb_cleaning_coh |
| 29    | Slice1_l2_cache_prefetch_access |
| 30    | Slice1_l2_cache_prefetch_miss   |
| 31    | Slice1_l2_cache_access_rd       |
| 32    | Slice1_l2_cache_access_wr       |
| 33    | Slice1_l2_cache_miss_rd         |
| 34    | Slice1_l2_cache_inv             |
| 35    | Slice2_l2_cache_refill          |
| 36    | Slice2_l2_cache_rd_refill       |
| 37    | Slice2_l2_cache_wr_refill       |
| 38    | Slice2_l2_cache_long_miss       |
| 39    | Slice2_l2_cache_hit             |
| 40    | Slice2_l2_cache_miss            |
| 41    | Slice2_l2_cache_access          |
| 42    | Slice2_l2_cache_l2wb            |
| 43    | Slice2_l2_cache_l1wb            |
| 44    | Slice2_l2_cache_wb_victim       |
| 45    | Slice2_l2_cache_wb_cleaning_coh |
| 46    | Slice2_l2_cache_prefetch_access |
| 47    | Slice2_l2_cache_prefetch_miss   |
| 48    | Slice2_l2_cache_access_rd       |
| 49    | Slice2_l2_cache_access_wr       |
| 50    | Slice2_l2_cache_miss_rd         |
| 51    | Slice2_l2_cache_inv             |
| 52    | Slice3_l2_cache_refill          |
| 53    | Slice3_l2_cache_rd_refill       |
| 54    | Slice3_l2_cache_wr_refill       |
| 55    | Slice3_l2_cache_long_miss       |
| 56    | Slice3_l2_cache_hit             |
| 57    | Slice3_l2_cache_miss            |
| 58    | Slice3_l2_cache_access          |
| 59    | Slice3_l2_cache_l2wb            |
| 60    | Slice3_l2_cache_l1wb            |
| 61    | Slice3_l2_cache_wb_victim       |
| 62    | Slice3_l2_cache_wb_cleaning_coh |
| 63    | Slice3_l2_cache_prefetch_access |
| 64    | Slice3_l2_cache_prefetch_miss   |
| 65    | Slice3_l2_cache_access_rd       |
| 66    | Slice3_l2_cache_access_wr       |
| 67    | Slice3_l2_cache_miss_rd         |
| 68    | Slice3_l2_cache_inv             |

### Topdown PMU

DataPath includes Mf issue in uopsIssued; EXEC_STALL_CYCLE is asserted when fewer than FewUops=4 uops issue. Memory stall conditions are delayed by two cycles and combined with LQ/SQ state and cache miss information to generate MEMSTALL_STORE, MEMSTALL_L1MISS, MEMSTALL_L2MISS, and MEMSTALL_L3MISS. These five events are output to HPM, while memStallAnyLoad remains an internal signal used to determine miss stalls at each level.

MEMSTALL_ANYLOAD in the Topdown formulas below represents any load stall. DataPath does not currently export this signal as a separate HPM event. Matrix-specific events record CUTE's internal task and resource occupancy.

Topdown performance analysis is a top-down approach designed to quickly identify CPU performance bottlenecks. Its core concept involves decomposing high-level performance categories step by step, gradually refining the issues to accurately pinpoint the root cause. We have implemented three levels of Topdown performance events, as detailed below:

Table: Three-Level Top-Down Performance Events

+-------------+-------------+-------------+---------------------------+----------------------------------------+
| Level 1     | Level 2     | Level 3     | Description               | Formula                                |
+=============+=============+=============+===========================+========================================+
| Retiring    | -           | -           | Instruction commit impact | INST_RETIRED /                         |
|             |             |             |                           | (IssueBW * CPU_CYCLES)                 |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| FrontEnd    | -           | -           | Front-end impact          | IF_FETCH_BUBBLE /                      |
| Bound       |             |             |                           | (IssueBW * CPU_CYCLES)                 |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| -           | Fetch       | -           |                           |                                        |
|             | Latency     |             | Fetch latency impact      | IF_FETCH_BUBBLE_EQ_MAX /               |
|             | Bound       |             |                           | CPU_CYCLES                             |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
|             | Fetch       |             |                           | FrontEnd Bound -                       |
| -           | Bandwidth   | -           | Fetch bandwidth impact    | Fetch Latency Bound                    |
|             | Bound       |             |                           |                                        |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| Bad         |             |             |                           | (INST_SPEC - INST_RETIRED+             |
| Speculation | -           | -           | Misprediction impact      | RECOVERY_BUBBLE) /                     |
|             |             |             |                           | (IssueBW * CPU_CYCLES)                 |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| -           | Branch      | -           | Mispredicted branch       | Bad Speculation *                      |
|             | Misspredict |             | instruction impact        | BR_MIS_PRED / TOTAL_FLUSH              |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| -           | Machine     | -           | Machine clear             | Bad Speculation - Branch Misspredict   |
|             | Clears      |             | event impact              |                                        |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| BackEnd     | -           | -           | Back-end impact           | 1 - (FrontEnd Bound +                  |
| Bound       |             |             |                           | Bad Speculation + Retiring)            |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| -           | Core        | -           | Core impact               | (EXEC_STALL_CYCLE - MEMSTALL_ANYLOAD - |
|             | Bound       |             |                           | MEMSTALL_STORE) / CPU_CYCLE            |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| -           | Memory      | -           | Memory access impact      | (MEMSTALL_ANYLOAD + MEMSTALL_STORE) /  |
|             | Bound       |             |                           | CPU_CYCLES                             |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| -           | -           | L1 Bound    | L1 impact                 | (MEMSTALL_ANYLOAD - MEMSTALL_L1MISS) / |
|             |             |             |                           | CPU_CYCLES                             |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| -           | -           | L2 Bound    | L2 impact                 | (MEMSTALL_L1MISS - MEMSTALL_L2MISS) /  |
|             |             |             |                           | CPU_CYCLES                             |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| -           | -           | L3 Bound    | L3 impact                 | (MEMSTALL_L2MISS - MEMSTALL_L3MISS) /  |
|             |             |             |                           | CPU_CYCLES                             |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| -           | -           | Mem Bound   | External memory impact    | MEMSTALL_L3MISS / CPU_CYCLES           |
+-------------+-------------+-------------+---------------------------+----------------------------------------+
| -           | -           | Store Bound | Store instruction impact  | MEMSTALL_STORE / CPU_CYCLES            |
+-------------+-------------+-------------+---------------------------+----------------------------------------+

Here, IssueBW represents the issue width, which is currently 6-issue in the Xiangshan Kunminghu architecture.

Table: Topdown Performance Events

+------------------------+---------------------+----------------------------------------------------------------+
| Name                   | Corresponding Event | Description                                                    |
+========================+=====================+================================================================+
| CPU_CYCLES             | -                   | Total clock cycles after all instructions commit               |
+------------------------+---------------------+----------------------------------------------------------------+
| INST_RETIRED           | rob_commitInstr     | Number of successfully committed instructions                  |
+------------------------+---------------------+----------------------------------------------------------------+
| INST_SPEC              | -                   | Number of speculatively executed instructions                  |
+------------------------+---------------------+----------------------------------------------------------------+
| IF_FETCH_BUBBLE        | Front_Bubble        | Number of bubbles fetched from the instruction buffer,         |
|                        |                     | with no backend stall                                          |
+------------------------+---------------------+----------------------------------------------------------------+
| IF_FETCH_BUBBLE_EQ_MAX | Fetch_Latency_Bound | Cycles fetching zero instructions from the instruction buffer, |
|                        |                     | with no backend stall                                          |
+------------------------+---------------------+----------------------------------------------------------------+
| BR_MIS_PRED            | -                   | Number of mispredicted branch instructions                     |
+------------------------+---------------------+----------------------------------------------------------------+
| TOTAL_FLUSH            | -                   | Number of pipeline flush events                                |
+------------------------+---------------------+----------------------------------------------------------------+
| RECOVERY_BUBBLE        | -                   | Number of cycles recovering from early mispredictions          |
+------------------------+---------------------+----------------------------------------------------------------+
| EXEC_STALL_CYCLE       | -                   | Number of cycles issuing few uops                              |
+------------------------+---------------------+----------------------------------------------------------------+
| MEMSTALL_ANY_LOAD      | -                   | No uops issued, and at least one Load instruction incomplete   |
+------------------------+---------------------+----------------------------------------------------------------+
| MEMSTALL_STORE         | -                   | Non-Store uops issued,                                         |
|                        |                     | and Store instructions incomplete                              |
+------------------------+---------------------+----------------------------------------------------------------+
| MEMSTALL_L1MISS        | -                   | No uops issued, at least one Load instruction incomplete,      |
|                        |                     | and an L1-cache miss occurred                                  |
+------------------------+---------------------+----------------------------------------------------------------+
| MEMSTALL_L2MISS        | -                   | No uops issued, at least one Load instruction incomplete,      |
|                        |                     | and an L2-cache miss occurred                                  |
+------------------------+---------------------+----------------------------------------------------------------+
| MEMSTALL_L3MISS        | -                   | No uops issued, at least one Load instruction incomplete,      |
|                        |                     | and an L3-cache miss occurred                                  |
+------------------------+---------------------+----------------------------------------------------------------+

To measure the impact of front-end fetch latency over a period, we can set the EVENT0 field of mhpmevent3 to 22, leaving the remaining bits at their default values, then proceed with
testing. Upon completion, a CSR read instruction can access the mhpmcounter3 register to obtain
the cycle count of front-end fetch latency during that period. The impact of front-end fetch latency can then be calculated.

## HPM-related performance event counters

The performance event counters in the Xiangshan Kunminghu architecture are divided into three groups: machine-mode event counters, supervisor-mode event counters, and user-mode event counters.

Table: Machine Mode Event Counter List

| Name            | Index       | Read/Write | Description                              | Reset Value |
| --------------- | ----------- | ---------- | ---------------------------------------- | ----------- |
| MCYCLE          | 0xB00       | RW         | Machine Mode Clock Cycle Counter         | -           |
| MINSTRET        | 0xB02       | RW         | Machine-mode retired instruction counter | -           |
| MHPMCOUNTER3-31 | 0XB03-0XB1F | RW         | Machine-mode Performance Event Counter   | 0           |

The corresponding MHPMCOUNTERx counter is controlled by MHPMEVENTx, specifying the counting of relevant performance events.

Supervisor mode event counters include the supervisor mode counter overflow interrupt flag register (SCOUNTOVF)

Table: Supervisor Mode Counter Overflow Interrupt Flag Register (SCOUNTOVF) Description

+-------+------+------+--------------------------------------+-------+
| Name  | Bits | R/W  | Behavior                             | Reset |
+=======+======+======+======================================+=======+
| OFVEC | 31:3 | RO   | mhpmcounterx register overflow flag: | 0     |
|       |      |      |                                      |       |
|       |      |      | 1: Overflow occurred                 |       |
|       |      |      |                                      |       |
|       |      |      | 0: No overflow occurred              |       |
+-------+------+------+--------------------------------------+-------+
| --    | 2:0  | RO 0 | --                                   | 0     |
+-------+------+------+--------------------------------------+-------+

scountovf serves as a read-only mapping of the OF bit in the mhpmcounter register, controlled by xcounteren:

* M-mode can read the correct value when accessing scountovf.
* HS-mode access to scountovf: When mcounteren.HPMx is 1, the corresponding OFVECx can read the correct value; otherwise, it only reads 0.
* When accessing scountovf in VS-mode: When both mcounteren.HPMx and hcounteren.HPMx are 1, the corresponding OFVECx can be read correctly; otherwise, it only reads 0.

Table: User Mode Event Counter List

| Name           | Index       | Read/Write | Description                                               | Reset Value |
| -------------- | ----------- | ---------- | --------------------------------------------------------- | ----------- |
| CYCLE          | 0xC00       | RO         | User-mode read-only copy of mcycle register               | -           |
| TIME           | 0xC01       | RO         | Memory-mapped register mtime user-mode read-only copy     | -           |
| INSTRET        | 0xC02       | RO         | User-mode read-only copy of minstret register             | -           |
| HPMCOUNTER3-31 | 0XC03-0XC1F | RO         | Read-only user-mode copy of the mhpmcounter3-31 registers | 0           |
