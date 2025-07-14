# Debug Module

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Glossary of Terms

Table: Terminology Explanation

| Abbreviation | Full name              | Description             |
| ------------ | ---------------------- | ----------------------- |
| DM           | Debug Module           | Debug Module            |
| DTM          | Debug Transport Module | Debug Conversion Module |
| DMI          | Debug Module Interface | Debug module interface  |

## Parameter Design

Table: Parameter Design

| Parameters           | Default Value | Description                        |
| -------------------- | ------------- | ---------------------------------- |
| baseAddress          | 0x38020800    | Debug Module MMIO base address     |
| nDMIAddrSize         | 7             | DMI Address Width                  |
| nProgramBufferWords  | 16            | Number of Program Buffers          |
| nAbstractDataWords   | 4             | Number of Abstract Commands        |
| hasBusMaster         | true          | system bus master                  |
| maxSupportedSBAccess | 64            | sysbus maximum memory access width |
| supportQuickAccess   | false         | QuickAccess support                |
| supportHartArray     | true          | hart array support                 |
| nHaltGroups          | 1             | Number of halt groups              |
| nExtTriggers         | 0             | Number of external triggers        |
| hasHartResets        | true          | Reset selected harts               |
| hasImplicitEbreak    | false         | Implicit ebreak support            |

## Overall design

### Overall Block Diagram

As shown in [@fig:DM]:

![DebugModule Overview](./figure/DM-Overview.svg){#fig:DM}

### Multiple clock domains

As shown in [@fig:multiclock]:

![DebugModule Multi-Clock Domain](./figure/MultiClock.svg){#fig:multiclock}

### Debug MMIO

As shown in [@tbl:debug-mmio]:

Table: debug MMIO address space {#tbl:debug-mmio}

| Address (base address 0x3802_0000) | Name           | Description                                                                                                                              | Content stored at this address                                                                                                                                                    |
| ---------------------------------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0x800                              | debugEntry     | Debug entry address / base address of debug ROM                                                                                          |                                                                                                                                                                                   |
| 0x808                              | debugException | Exception entry address when an exception occurs during execution in dmode                                                               |                                                                                                                                                                                   |
| 0x100                              | HALTED         |                                                                                                                                          | The hartid corresponding to the hart entering dmode will be obtained by the debugmodule                                                                                           |
| 0x104                              | GOING          |                                                                                                                                          | whereto, ultimately jumps to ABSTRACT for execution                                                                                                                               |
| 0x108                              | RESUMING       |                                                                                                                                          | Execute dret                                                                                                                                                                      |
| 0x10c                              | EXCEPTION      |                                                                                                                                          |                                                                                                                                                                                   |
| 0x300                              | WHERETO        | The instruction stored at this address                                                                                                   | dm-generated jump instruction to ABSTRACT                                                                                                                                         |
| 0x380                              | DATA           | Base address of DATA (for ld/st)                                                                                                         | data exchange                                                                                                                                                                     |
| DATA-4*nProgBuf                    | PROGBUF        | address of progbuf0                                                                                                                      | Instructions generated by dm (prepared before go)                                                                                                                                 |
| DATA-4                             | IMPEBREAK      | Implicit ebreak instruction                                                                                                              |                                                                                                                                                                                   |
| PROGBUF - 4* nAbstractInst         | ABSTRACT       | AbstractInstructions                                                                                                                     | Instructions generated by dm (prepared before go)                                                                                                                                 |
| 0x400                              | FLAGS          | The base address corresponding to the hartid flag, where each flag is 8 bits, and 0x400 represents the address of the flag when hartid=0 | Only the lower two bits of this 8-bit value are valid; the second lowest bit refers to resume, and the lowest bit refers to go. The address space is 1k, i.e., 0x400->(0x500-0x1) |

## Module Design

### Debug Module

The current implementation status of Kunminghu debug is as follows:

* Supports debugging from the first instruction, entering debug mode after CPU
  reset.
* Supports run control for single-core and multi-core (selected cores)
  debugging, including halt, resume, and reset.
* Supports single-step debugging.
* Supports stopcount and stoptime.
* Supports software breakpoints (ebreak instruction), hardware breakpoints
  (trigger), and memory breakpoints (trigger).
* Supports GPR, CSR, and memory access, with both progbuf and sysbus access
  methods.
* Supports entering debug mode via debug interrupt (haltreq, haltgroup,
  halt-on-reset), trigger fire, ebreak, singlestep, critical error, etc.

### Trigger Module

The current implementation status of Kunming Lake's trigger module is as
follows:

* The debug-related CSRs currently implemented in the Kunming Lake trigger
  module are shown in the table below.
* The default configuration count for triggers is 4 (supports user
  customization).
* Supports mcontrol6 type instructions and memory access triggers.
* Match supports three types: equal, greater than or equal, and less than
  (vector memory access currently only supports equal type matching).
* Only supports address matching, not data matching.
* Only supports timing = before.
* Only supports chaining for one pair of triggers.
* To prevent the secondary generation of breakpoint exceptions by triggers,
  support is provided via xSTATUS.xIE control.
* Supports H-extension software and hardware breakpoints, and watchpoint
  debugging methods.
* Supports memory triggers for atomic instructions.

The following table describes the current memory access granularity and trigger
matching granularity of Kunminghu-supported memory access instructions in the
microarchitecture: For scalar instructions and vector instructions that access
memory at element granularity, match types support >=, =, <; for other vector
instructions, only match type = is supported. Additionally, for vector memory
access instructions, trigger fires (regardless of whether the trigger action is
breakpoint or debug) are triggered by instructions with smaller element indices.

Table: Memory access granularity and trigger matching granularity

| Instruction type                                   | Memory access granularity      | Trigger Matching Granularity                                                                                                                     |
| -------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Scalar memory access instructions                  | Instruction (element)          | Check element little-endian address, supports >=, =, <                                                                                           |
| Atomic memory access instructions (lr/sc)          | Instruction (element)          | Check element little-endian address, supports >=, =, <; lr is treated as load, sc as store (regardless of success or failure)                    |
| Atomic memory access instructions (amo)            | Instruction (element)          | Check the little-endian address of elements, supporting >=, =, <; simultaneously verify load and store operations upon obtaining the vaddr.      |
| Vector memory access instructions (unit-stride)    | Vector Register Width (128bit) | Supports checking any address within the memory access range of the instruction (with 8-bit granularity), but only supports exact (=) matching.  |
| Vector memory access instructions (whole)          | Vector Register Width (128bit) | Supports checking any address within the memory access range of the instruction (with 8-bit granularity), but only supports exact (=) matching.  |
| Vector memory access instruction (fof unit-stride) | Vector Register Width (128bit) | Supports checking any address within the instruction's memory access range (with 8-bit granularity), but only supports matching the 0th element. |
| Vector memory access instructions (segment)        | Element                        | Check the little-endian address of each element, but only supports = matching                                                                    |
| Other types of vector memory access instructions   | Element                        | Check the little-endian address of each element, supports >=, =, <                                                                               |

table: Debug-related csr implemented by Kunming Lake

| Name              | Address | Read/Write | Introduction             | Reset value         |
| ----------------- | ------- | ---------- | ------------------------ | ------------------- |
| Tselect           | 0x7A0   | RW         | Trigger select register  | 0X0                 |
| Tdata1(Mcontrol6) | 0x7A1   | RW         | Trigger data1            | 0xF0000000000000000 |
| Tdata2            | 0x7A2   | RW         | trigger data2            | 0x0                 |
| Tinfo             | 0x7A4   | RO         | Trigger info             | 0x40                |
| Dcsr              | 0x7B0   | RW         | Debug Control and Status | 0x40000003          |
| Dpc               | 0x7B1   | RW         | Debug PC                 | 0x0                 |
| Dscratch0         | 0x7B2   | RW         | 调试暂存寄存器0                 | -                   |
| Dscratch1         | 0x7B3   | RW         | Debug Scratch Register 1 |                     |
| mcontext          | 0x7A8   | RW         | Machine Context          | -                   |
| hcontext          | 0x6A8   | RW         | Hypervisor Context       | -                   |
| scontext          | 0x5A8   | RW         | Supervisor Context       | -                   |

### Debug Flow Example

#### CSR Access:

Debug module CSR access is accomplished through the collaboration of abstract
commands and progbuff. Based on the abstract command, corresponding instructions
are generated at ABSTRACT and PROGBUFF addresses (these two address spaces are
contiguous) for the CPU to execute, achieving the purpose of CSR access. The
ABSTRACT generates lw/st instructions, performing data exchange between MMIO
addresses and GPR s0/s1, while PROGBUFF generates CSR read/write instructions.
Below is an example of accessing the mstatus register to illustrate how the
debug module accesses CSRs:

1. Assume the software issues a command to write the mstatus CSR, which then
   sequentially passes through JtagProbe, JtagDTM, and DMI to be converted into
   a DMI operation;
2. DMI operations modify internal control signals of the DebugModule via dmi2tl,
   changing DMI_COMMAND to the command for writing the mstatus register;
3. openocd first reads and stores the value of s0/fp, then writes the CSR write
   instruction into the progbuffer;
4. Execute ABSTRAT (ld instruction), writing DATA to s0;
5. Execute progbuffer (CRS write instruction), progbuff ends with an ebreak
   instruction, re-entering the parking loop;

   If reading a csr:
6. Execute progbuffer (CSR read instruction), reading the CSR value into s0;
7. Execute ABSTRACT (st instruction), writing s0 to DATA;

#### Hardware breakpoints:

The following content uses setting a breakpoint as an example to illustrate the
collaborative workflow between hardware and software during the debugging
process:

1. First, the software issues a halt d command, which then sequentially passes
   through JtagProbe, JtagDTM, and DMI to be converted into a DMI operation;
2. Dmi operations modify the internal control signals of DebugModule via dmi2tl,
   issuing an external debug interrupt to the hart, which ultimately propagates
   to the CSR module inside the hart;
3. CSR handles external debug interrupts: the hart will trap to the
   debugModule's entry address for execution (see Debug Module MMIO), entering
   DMode;
4. After entering DMode, the Hart executes instructions from the debug ROM,
   writes its hartid to HALTED (see Section 8 Debug ROM), notifying the Debug
   Module that it (the hart) has entered dmode. The Debugger can then debug the
   hart in Dmode;
5. When the software issues a command to set a hardware breakpoint, the hart
   will jump to whereto. The abstract and progbuff modules work in tandem to
   control the hart in executing CSR instructions (via progbuffer) to configure
   the trigger CSR registers, writing the breakpoint information into the
   trigger CSR. The progbuff concludes with an ebreak instruction, whose
   execution will again jump to the debugModule's entry address.
6. When the software issues a resume command, the hart will jump to _resume to
   execute the dret instruction, exiting dMode and returning to the halted state
   at point 1 to continue execution. (Prior to resume, there is a preparatory
   step that requires executing a single step to submit only one instruction,
   then trapping into debugMode via a single step exception. This can be
   referenced in the OpenOCD source code.)
7. When the hart executes the program to the breakpoint location, the
   instruction's pc matches the breakpoint address configured in the trigger
   CSR, the trigger fires, and the hart enters dmode again (trapping to the
   debugModule's entry address) to execute the instructions in the debug rom,
   waiting for debugger debugging.
