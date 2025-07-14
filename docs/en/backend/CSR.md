# CSR

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Glossary of Terms

Table: Terminology Explanation

| Abbreviation | Full name                     | Description                                                                                        |
| ------------ | ----------------------------- | -------------------------------------------------------------------------------------------------- |
| CSR          | Control and Status Register   | Control and status registers                                                                       |
| Trap         | Trap                          | Collective term for traps, interrupts, and exceptions                                              |
| ROB          | Reorder Buffer                | Reorder Buffer                                                                                     |
| PRVM         | Privilege Mode                | Privilege levels, including M, S, U                                                                |
| VM/V         | Virtual Mode                  | Virtualization mode, which includes VS and VU privilege levels when in virtualization mode         |
| EX_II        | Illegal Instruction Exception | Illegal instruction exception                                                                      |
| EX_VI        | Virtual Instruction Exception | Virtual instruction exception                                                                      |
| TVEC         | Trap Vector                   | Trap handler entry configuration registers, independently configured for m/hs/vs modes             |
| IMSIC        | Incoming MSI Controller       | Incoming Message-based Interrupt Controller, defined in The RISC-V Advanced Interrupt Architecture |

## Design specifications

Support for executing CSR instructions

Supports execution of CSR read-only instructions

Supports out-of-order execution of CSR read-only instructions

Support execution of system-level instructions such as mret, sret, ecall,
ebreak, wfi, etc.

Supports receiving interrupts, selects the highest-priority interrupt, and sends
it to the ROB for processing

Supports generating EX_II and EX_VI exceptions

Supports receiving and handling traps from ROB Trap (interrupts + exceptions)

Support for CSR implementation compliant with the riscv-privileged-spec

Supports interrupt and exception delegation

Supports Smaia and Ssaia extensions

Supports Sdtrig and Sdext extensions

Supports the H extension

Supports virtualization interrupts

Supports receiving and processing external interrupts

## Function

As a functional unit (FU), CSR is located in the same ExeUnit as fence and div
within the intExuBlock. The CSR primarily consists of four submodules: csrMod,
trapInstMod, trapTvalMod, and imsic. csrMod serves as the main functional
component of CSR.

The trapTvalMod module is mainly responsible for managing and updating the
trap-related target value tval. It updates or clears tval based on input signals
such as flush, targetPc, and clear, ensuring tval is valid when cleared. The
module also includes state logic to ensure tval is updated correctly under
specific conditions. This module needs to select the source from targetPc issued
by csrMod and fullTarget from flush, and decide whether to update or clear by
comparing the order of robIdx, ultimately outputting the tval information.

The trapInstMod module is primarily responsible for managing and updating the
instruction encoding information of traps. It updates or clears trap instruction
information based on input signals (such as flush, faultCsrUop, and readClear),
ensuring correct updates under specific conditions. The module also includes
state logic to guarantee proper updates to trap instruction information when
required. It selects the source from either instruction information provided by
decode (including instruction encoding, FtqPtr, and FtqOffset) or CSR
instruction information derived from CSR itself through combinatorial
concatenation. By comparing the sequence of FtqPtr and FtqOffset, it determines
whether to update or clear, as well as the update source. The module invalidates
the information when a flush or readClear is needed. Ultimately, it outputs
trap-related instruction encoding along with the corresponding FtqPtr and
FtqOffset.

The imsic (Incoming MSI Controller) module primarily interacts with csrMod when
accessing IMSIC content through indirect alias CSRs (mireg/sireg/vsireg),
providing necessary information such as the accessed CSR address, privilege
level mode, write data, etc., and then waits for imsic's output response. If
csrMod's own permission check has already determined that an exception should be
raised, it will not send a request to imsic.

The CSR is responsible for executing CSR-type instructions and system-type
instructions such as mret, sret, ecall, ebreak, and wfi. It receives instruction
uops and data information from the Backend, and outputs data and jump addresses
upon completion. If an exception occurs, it sets EX_II or EX_VI according to the
rules.

The CSR is responsible for receiving interrupt pending signals such as MSIP,
MTIP, MEIP, SEIP, VSTIP, and VSEIP from the external interrupt controllers CLINT
and IMSIC. It determines whether to respond based on the current privilege level
and its global interrupt enable bits, prioritizes the interrupts, and selects
the highest-priority interrupt to be handled by the ROB.

The CSR is responsible for receiving Trap information from the ROB, setting the
privilege level mode (PRVM) and virtualization mode (V) to the level handling
the Trap based on delegation (m[e|i]deleg and h[e|i]deleg), modifying relevant
CSR states, and redirecting execution flow to the starting address of the Trap
Handler corresponding to TVEC.

CSRs are responsible for storing configuration information controlling
floating-point and vector execution (Frm, Vstart, Vl, Vtype, Vxrm, etc.), as
well as additional results generated by floating-point and vector instruction
execution (Fflags, Vxsat, etc.).

The CSR is responsible for interacting with the IMSIC via custom data lines,
reading and writing the ** and ** registers (external interrupts section)
configured in the IMSIC's mireg, sireg, and vsireg.

The CSR is responsible for configuring and updating TLB-related signals to
ensure the TLB correctly performs virtual-to-physical address translation. This
includes detecting changes in ASID and VMID, passing values of registers like
satp/vsatp/hgatp, transmitting permission and control bits such as mxr/sum from
mstatus/vsstatus and pmm from menvcfg/henvcfg, selecting virtual memory modes,
and configuring physical memory protection extensions. Through these
configurations, the TLB can accurately execute address translations across
different virtual memory modes.

The CSR is responsible for setting and passing flags related to illegal and
virtual instruction decoding based on the current privilege mode and register
state. These flags indicate whether certain instructions are illegal or virtual
in specific privilege modes. Through these flags, the hardware can correctly
handle such instructions during the decode stage.

## Custom CSR

In addition to the CSRs defined in the RISC-V manual, we have implemented 7
custom CSRs: sbpctl, spfctl, slvpredctl, smblockctl, srnctl, mcorepwr, and
mflushpwr.

Among these, the 5 custom CSRs—sbpctl, spfctl, slvpredctl, smblockctl, and
srnctl—are defined in HS mode, while the 2 custom CSRs—mcorepwr and
mflushpwr—are defined in M mode.

Access to these custom CSRs is not only constrained by privilege levels (lower
privileges cannot access higher ones) but also controlled by the C field in the
Smstateen/Ssstateen extensions for custom content access.

Below are the definitions of each custom CSR.

### sbpctl

The sbpctl (Speculative Branch Prediction Control register) has an address of
0x5C0 and is a readable/writable register defined in HS mode.

Table: Definition of sbpctl

| Field name  | Field position | Initial value | Description                                          |
| ----------- | -------------- | ------------- | ---------------------------------------------------- |
| UBTB_ENABLE | 0              | 1             | UBTB_ENABLE set to 1 enables uftb.                   |
| BTB_ENABLE  | 1              | 1             | Setting BTB_ENABLE to 1 enables the main ftb.        |
| BIM_ENABLE  | 2              | 1             | Setting BIM_ENABLE to 1 enables the bim predictor.   |
| TAGE_ENABLE | 3              | 1             | Setting TAGE_ENABLE to 1 enables the TAGE predictor. |
| SC_ENABLE   | 4              | 1             | SC_ENABLE set to 1 enables the SC predictor.         |
| RAS_ENABLE  | 5              | 1             | Setting RAS_ENABLE to 1 enables the RAS predictor    |
| LOOP_ENABLE | 6              | 1             | Setting LOOP_ENABLE to 1 enables the loop predictor. |
|             | [63:7]         | 0             | Reserved                                             |

### spfctl

The address of spfctl (Speculative Prefetch Control register) is 0x5C1, a
read-write register defined in HS mode.

Table: Definition of spfctl

| Field name              | Field position | Initial value | Description                                                                                                                                                                   |
| ----------------------- | -------------- | ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| L1I_PF_ENABLE           | 0              | 1             | Controls the L1 instruction prefetcher, where setting 1 enables prefetching                                                                                                   |
| L2_PF_ENABLE            | 1              | 1             | Control the L2 prefetcher, where 1 represents enabling prefetch                                                                                                               |
| L1D_PF_ENABLE           | 2              | 1             | Controls the SMS prefetcher, setting 1 enables prefetching                                                                                                                    |
| L1D_PF_TRAIN_ON_HIT     | 3              | 0             | Controls whether the SMS prefetcher accepts training on hits. Setting it to 1 means hits will also trigger training; setting it to 0 means only misses will trigger training. |
| L1D_PF_ENABLE_AGT       | 4              | 1             | Controls the agt table of the SMS prefetcher. Setting to 1 enables the agt table.                                                                                             |
| L1D_PF_ENABLE_PHT       | 5              | 1             | Controls the pht table of the SMS prefetcher, setting 1 enables the pht table                                                                                                 |
| L1D_PF_ACTIVE_THRESHOLD | [9:6]          | 12            | Controls the active page threshold for the SMS prefetcher                                                                                                                     |
| L1D_PF_ACTIVE_STRIDE    | [15:10]        | 30            | Controls the active page span of the SMS prefetcher                                                                                                                           |
| L1D_PF_ENABLE_STRIDE    | 16             | 1             | Control whether the SMS prefetcher enables stride                                                                                                                             |
| L2_PF_STORE_ONLY        | 17             | 0             | Control whether the L2 prefetcher only prefetches for stores                                                                                                                  |
| L2_PF_RECV_ENABLE       | 18             | 1             | Control whether the L2 prefetcher accepts prefetch requests from SMS                                                                                                          |
| L2_PF_PBOP_ENABLE       | 19             | 1             | Control the enabling of the L2 prefetcher PBOP                                                                                                                                |
| L2_PF_VBOP_ENABLE       | 20             | 1             | Control the enablement of L2 prefetcher VBOP                                                                                                                                  |
| L2_PF_TP_ENABLE         | 21             | 1             | Controls the enabling of the L2 prefetcher TP.                                                                                                                                |
|                         | [63:22]        | 0             | Reserved                                                                                                                                                                      |

### slvpredctl

The address of slvpredctl (Speculative Load Violation Predictor Control
register) is 0x5C2, a read-write register defined in HS mode.

Table: Definition of slvpredctl

| Field name              | Field position | Initial value | Description                                                                                                                      |
| ----------------------- | -------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| LVPRED_DISABLE          | 0              | 0             | Controls whether the memory access violation predictor is disabled. Set to 1 to disable.                                         |
| NO_SPEC_LOAD            | 1              | 0             | Controls whether the memory violation predictor prohibits speculative execution of load instructions. Setting to 1 prohibits it. |
| STORESET_WAIT_STORE     | 2              | 0             | Controls whether the memory access violation predictor blocks store instructions, where 1 indicates blocking                     |
| STORESET_NO_FAST_WAKEUP | 3              | 0             | Controls whether the memory violation predictor supports fast wake-up. Setting to 1 means no fast wake-up.                       |
| LVPRED_TIMEOUT          | [8:4]          | 3             | Memory access violation predictor reset interval. If the value of this field is x, the interval is 2^(10+x)                      |
|                         | [63:9]         | 0             | Reserved                                                                                                                         |

### smblockctl

The address of smblockctl (Speculative Memory Block Control register) is 0x5C3,
which is a read-write register defined in HS-mode.

Table: Definition of smblockctl

| Field name                       | Field position | Initial value | Description                                                                                   |
| -------------------------------- | -------------- | ------------- | --------------------------------------------------------------------------------------------- |
| SBUFFER_THRESHOLD                | [3:0]          | 7             | Controls the flush threshold of the sbuffer                                                   |
| LDLD_VIO_CHECK_ENABLE            | 4              | 1             | Controls whether to enable ld-ld violation checking, setting 1 means enabled                  |
| SOFT_PREFETCH_ENABLE             | 5              | 1             | Controls whether soft prefetch is enabled. Setting to 1 enables it.                           |
| CACHE_ERROR_ENABLE               | 6              | 1             | Controls whether to report ECC errors occurring in the cache. Setting to 1 enables reporting. |
| UNCACHE_WRITE_OUTSTANDING_ENABLE | 7              | 0             | Controls whether uncache outstanding accesses are supported. Set to 1 to enable.              |
| HD_MISALIGN_ST_ENABLE            | 8              | 1             | Controls whether hardware-unaligned store is enabled.                                         |
| HD_MISALIGN_LD_ENABLE            | 9              | 1             | Control whether hardware-unaligned load is enabled                                            |
|                                  | [63:10]        | 0             | Reserved                                                                                      |

### srnctl

srnctl (Speculative Runtime Control register) has the address 0x5C4, a
read-write register defined in HS-mode.

Table: Definition of srnctl

| Field name    | Field position | Initial value | Description                                           |
| ------------- | -------------- | ------------- | ----------------------------------------------------- |
| FUSION_ENABLE | 0              | 1             | Whether the fusion decoder is enabled, 1 for enabled  |
|               | 1              | 0             | Reserved                                              |
| WFI_ENABLE    | 2              | 1             | Whether the wfi instruction is enabled, 1 for enabled |
|               | [63:3]         | 0             | Reserved                                              |

### mcorepwr

The address of mcorepwr (Core Power Down Status Enable) is 0xBC0, a read-write
register defined in M-mode.

Table: Definition of mcorepwr

| Field name        | Field position | Initial value | Description                                                                                            |
| ----------------- | -------------- | ------------- | ------------------------------------------------------------------------------------------------------ |
| POWER_DOWN_ENABLE | 0              | 0             | 1 indicates that when the core is in WFI (Wait For Interrupt) state, it wishes to enter low-power mode |
|                   | [63:1]         | 0             | Reserved                                                                                               |

### mflushpwr

The address of mflushpwr (Flush L2 Cache Enable) is 0xBC1, which is a read-write
register defined in M-mode.

Table: Definition of mflushpwr

| Field name      | Field position | Initial value | Description                                                                    |
| --------------- | -------------- | ------------- | ------------------------------------------------------------------------------ |
| FLUSH_L2_ENABLE | 0              | 0             | 1 indicates the core wishes to flush the L2 cache and exit the coherence state |
| L2_FLUSH_DONE   | 1              | 0             | Read-only bit, 1 indicates L2 cache flush completed and exited coherence state |
|                 | [63:2]         | 0             | Reserved                                                                       |

## CSR exception checking

The current permission checking module permitMod in CSR divides permission
checks into several submodules: xRetPermitMod, mLevelPermitMod, sLevelPermitMod,
privilegePermitMod, virtualLevelPermitMod, and indirectCSRPermitMod. permitMod
generates two types of exceptions: EX_II and EX_VI. Additionally, xRetPermitMod
differs from the other submodules as it corresponds to exceptions generated
during the execution of the xret instruction, while the other submodules serve
CSR access instructions. These two parts are mutually exclusive, meaning it is
impossible to simultaneously generate exceptions for executing the xret
instruction and CSR access instructions.

Among them, xRetPermitMod generates exceptions that may occur when executing
mnret/mret/sret/dret instructions: EX_II and EX_VI.

The mLevelPermitMod only generates EX_II, where several types of permission
checks are performed: writing to read-only CSRs; accessing floating-point/vector
CSRs when fs/vs is not enabled; and a series of accesses to lower-privilege CSRs
controlled by M-mode CSRs (such as mstateen0 and menvcfg).

In sLevelPermitMod, only EX_II will be generated, where a series of accesses to
other lower-privilege CSRs controlled by HS-mode CSRs (such as sstateen0 and
scounteren) will be performed.

privilegePermitMod ensures that lower privilege modes cannot access higher
privilege mode CSRs and generates EX_II and EX_VI exceptions based on the
current privilege level and the target CSR privilege level being accessed.

Table: Privilege level access permission checks for CSR

|         | M-Level CSR | H/VS-Level CSR | S-Level CSR | U-Level CSR |
| ------- | ----------- | -------------- | ----------- | ----------- |
| MODE_M  | OK          | OK             | OK          | OK          |
| MODE_VS | EX_II       | EX_VI          | OK          | OK          |
| MODE_VU | EX_II       | EX_VI          | EX_VI       | OK          |
| MODE_HS | EX_II       | OK             | OK          | OK          |
| MODE_HU | EX_II       | EX_II          | EX_II       | OK          |

virtualLevelPermitMod can generate two types of exceptions, EX_II and EX_VI,
during which a series of accesses to other CSRs controlled by H-mode CSRs (such
as hstateen0 and henvcfg) will be performed.

The indirectCSRPermitMod also generates EX_II and EX_VI exceptions, performing a
series of permission checks for accessing alias CSRs (mireg, sireg, and vsireg)
of Alisa.

Additionally, for exceptions generated during CSR access, we prioritize the
results from mLevelPermitMod, sLevelPermitMod, privilegePermitMod, and
virtualLevelPermitMod—i.e., the exception results from direct access—before
considering the exception results from indirect access via indirectCSRPermitMod.

In the exception results generated by direct access, we need to ensure that
mLevelPermitMod takes the highest priority, followed by sLevelPermitMod, then
privilegePermitMod, and finally virtualLevelPermitMod. This restriction also
ensures that EX_II takes precedence over EX_VI.

## Out-of-order execution of CSR read-only instructions

We also support out-of-order execution for CSR read-only instructions. We note
that for the vast majority of CSRs, CSRR instructions do not need to wait for
preceding instructions. For all CSRs, CSRR instructions also do not block
subsequent instructions. It is important to note that isCsrr includes not only
CSRR instructions but also other CSR instructions that do not require writing to
CSRs.

Currently, CSRR instructions for the following CSRs require waiting for
preceding instructions to complete, executing in order: fflags, fcsr, vxsat,
vcsr, vstart, mstatus, sstatus, hstatus, vsstatus, mnstatus, dcsr. This is
because these CSRs may be modified by user-level instructions without requiring
a fence, and out-of-order execution could lead to incorrect results. Hence, CSRR
instructions for these CSRs must be executed sequentially.

Additionally, since a fence instruction must be executed before reading any PMC
CSR, there is no need to enforce instruction ordering for PMC CSR accesses.

CSR instructions were previously executed without pipelining, so the CSR module
did not require a state machine internally. After adding the optimization to
pipeline-accelerate certain CSR read-only instructions, a state machine became
necessary because the integer register file arbiter must allow write requests
before CSRR instructions can successfully execute.

This finite state machine has three states: idle (s_idle), waiting for IMSIC
(s_waitIMSIC), and completion (s_finish).

When the current state is s_idle, if there is a valid input with a flush signal,
the next state remains s_idle; if there is a valid input requiring asynchronous
AIA access, the next state transitions to s_waitIMSIC; if there is a valid
input, the next state transitions to s_finish; otherwise, it stays in s_idle.

When the current state is s_waitIMSIC, if a flush signal is received, the next
state returns to s_idle; if a valid read signal from AIA is received and the
output is ready, the next state reverts to s_idle. Otherwise, if the output is
not ready, the next state transitions to s_finish to await output. In all other
cases, the state remains s_waitIMSIC.

When the current state is s_finish, if there is a flush signal or an output
ready signal, the next state will revert to s_idle; otherwise, it remains in
s_finish.
