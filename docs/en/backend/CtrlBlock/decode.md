# XiangShan Decode Design Document.

- Version: V2R2
- Status: OK
- Date: 2025/02/28.
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Glossary of Terms

Table: Terminology Explanation

| Abbreviation | Full name       | Description                                                                  |
| ------------ | --------------- | ---------------------------------------------------------------------------- |
| -            | Decode Unit     | Decode unit                                                                  |
| uop          | Micro Operation | Micro-operation                                                              |
| -            | numOfUop        | Number of uops split from one instruction                                    |
| -            | numOfWB         | The number of uops requiring writeback among those split from an instruction |
| -            | vtypeArch       | Latest committed vector instruction vtype configuration                      |
| -            | vtypeSpec       | Current vector instruction vtype configuration.                              |
| -            | walkVType       | The vtype rolled back and restored upon redirection.                         |


## Submodule List

Table: Submodule List

| Submodule       | Description                                              |
| --------------- | -------------------------------------------------------- |
| DecodeUnit      | Decode unit                                              |
| DecodeUnitComp  | Vector instruction splitting and processing module.      |
| FPDecoder       | Floating-point instruction decoding module               |
| UopInfoGen      | Instruction split type and quantity generation unit      |
| VecDecoder      | Vector instruction decoding module                       |
| VecExceptionGen | Vector exception check module                            |
| VTypeGen        | Vector instruction vtype configuration generation module |

## Design specifications

- Added vector configuration generation module, vector decoding module, vector
  instruction splitting module, and vector exception checking module. All vector
  instructions undergo instruction splitting and enter decoderComp.
- Supports decoding 6 scalar instructions simultaneously in a single cycle
- Supports decoding up to 1 vector instruction per cycle.
- Some instructions undergo translation processing.
  - The zimop instruction, translated as an addi instruction with src as x0 and
    imm as 0.
  - Read vlenb instruction, translated to an addi instruction with src as x0 and
    imm as VLEN/8
  - Read vl instruction, translated into a vset instruction that reads the vl
    register and writes to a scalar register.
- When reading a read-only csr, the waitForward and blockBackward signals are no
  longer set, supporting out-of-order execution.
- Other functions are the same as Nanhu

## Function

Decode the instruction, converting the 32-bit encoding into control signals. If
the instruction is a vector instruction or an AMO_CAS instruction, it undergoes
instruction splitting. The splitting process divides the instruction into one or
more uops and reassigns source register numbers, source register types,
destination register numbers, destination register types, functional units used,
and operation types based on the split type. After decoding, the instruction
with control information is passed to the rename module, which allocates
physical registers based on source register numbers and types. During the decode
stage, exception instructions and virtualization exception instructions are
checked, and the corresponding signals in exceptionVec are raised.

## Overall design

The decoding process instantiates 6 DecodeUnit modules to decode input
instructions. The DecodeUnit outputs a signal indicating whether the instruction
is a vector instruction. If it is a vector instruction, it is passed to the
complex decoder, decoderComp, for instruction splitting. Due to the longer
critical path caused by vector instructions undergoing decoding in both
DecodeUnit and UopInfoGen before entering the complex decoder, instructions are
temporarily stored for one cycle upon entering the complex decoder. In the next
cycle, vector exception checks and instruction splitting are performed,
converting the instruction into one or more uops. If the uops exceed 6, multiple
cycles are required to complete decoding. If the remaining uops can be decoded
in the current cycle, the vector instruction needing decoding is passed to
decoderComp in the same cycle. Assuming rename is ready, the following scenarios
can occur based on the order of incoming instructions:

  1. Scalar instructions: Directly decoded
  2. Vector instructions: When decoderComp is ready, vector instructions are
     passed to decoderComp for instruction splitting, capable of processing only
     one vector instruction at a time
  3. Vector instruction + scalar instruction: When decoderComp is ready, the
     vector instruction is passed to decoderComp for splitting; it can only
     handle one vector instruction at a time and cannot process scalar
     instructions simultaneously.
  4. Scalar instruction + vector instruction: Scalar instructions preceding
     vector instructions are decoded directly. When decoderComp is ready, vector
     instructions are passed to decoderComp for instruction splitting, which can
     only handle one vector instruction at a time
  5. uops after instruction splitting + scalar instruction: Assume there are n
     split uops needing rename and m scalar instructions needing rename in the
     current cycle. If n + m ≤ 6, decoding proceeds directly; otherwise, only 6
     - n scalar instructions are decoded.
  6. uop + vector instruction after splitting: Handles cases where uops split
     from vector instructions are vector-like
  7. uops after instruction splitting + vector instruction + scalar instruction:
     same as the case of scalar instruction + vector instruction
  8. Uop + scalar instruction + vector instruction after instruction splitting:
     Scalar instructions are handled the same as uop + scalar instruction cases
     after splitting, and vector instructions are handled the same as vector
     instruction cases.

## Overall Block Diagram

![decode](./figure/decode.svg)

## Interface list

Refer to the interface documentation.

## Sub-module VTypeGen

The VTypeGen module is primarily used to maintain the vtype configuration
required by the currently decoded vector instruction. It updates the stored
vtype information whenever a vset instruction is executed or a rollback is
needed due to redirection.

### Input

- 32-bit instruction information from the front-end instruction stream;
- Vtype rollback information from the vtype buffer in ROB.
- vtype commit information from the vtype buffer in the rob;
- The vtype information from the backend's vsetvl instruction, as the vtype
  information of the vsetvl instruction needs to be obtained by reading
  registers rather than decoding. Therefore, when the vsetvl instruction is
  written back, the vtype information is passed to vtypeGen.

### Output

vtype information output to the Decode Unit (current vtype configuration used by
vector instructions in the decode stage)

### Design specifications

There are four scenarios for vtypeSpec updates:

1. When a vsetvl instruction commits, vtypeSpec is updated to the vtype of the
   vsetvl instruction, where the vtype value is obtained when the vsetvl
   instruction writes back. Since the vsetvl instruction flushes the pipeline,
   it does not conflict with other scenarios.

2. During the rollback process, vtypeSpec is updated to the walkVType passed by
   the vtype buffer

3. At the start of redirection, vtypeSpec is updated to Arch vtype

4. When the decoded instruction contains vsetivli or vsetvli instructions and no
   exception occurs, the vtype information of vsetivli and vsetvli instructions
   can be obtained from the immediate field. VTypeGen includes a simple decoder
   to determine if the input instruction contains these two types of
   instructions. If such vset instructions exist, the first vset instruction is
   selected via a PriorityMux, and the vtype information is parsed by the
   `VsetModule` module.

```scala
  when(io.commitVType.hasVsetvl) {
    vtypeSpecNext := io.vsetvlVType
  }.elsewhen(io.walkVType.valid) {
    vtypeSpecNext := io.walkVType.bits
  }.elsewhen(io.walkToArchVType) { 
    vtypeSpecNext := vtypeArch
  }.elsewhen(inHasVset && io.canUpdateVType) {
    vtypeSpecNext := vtypeNew
  }
```

There are two scenarios for vtypeArch updates:
1. When the vsetvl instruction is committed, the vtypeArch is updated to the
   vtype written back by the vsetvl instruction.
2. When the vsetivli or vsetvli instruction is committed, vtypeArch is updated
   with the vtype commit information passed from the vtype buffer.

## Secondary module DecodeUnit.

### Input and Output

- **Input**
     - DecodeUnitEnqIO: Instruction stream information from the frontend,
       including vtype and vstart information used by vector instructions
     - CustomCSRCtrlIO: CSR control signals
     - CSRToDecode: csr control signals
- **Output**
     - DecodeUnitDeqIO: Decoded instruction information, whether it is a vector
       instruction, and the number of instruction splits

### Function

This module is the decode unit of the Xiangshan backend. It converts control
flow into more information-rich micro-operations, including source register
numbers, source register types, destination register numbers, destination
register types, immediate types, functional unit types used, operation types,
and other information.

### Design specifications

1. **Decoding information**
   - **XSDecode**\
     DecodeConstants defines decodeArray, which converts the 32-bit encoding of
     an instruction into XSDecode, containing the following information:

      - srcType0: Type of source register 0
      - srcType1: Source register 1 type
      - srcType2: Source register 2 type, used for fma instructions
      - fuType: functional unit type
      - fuOpType: Operation type
      - rfWen: Whether to write back to the scalar register.
      - fpWen: Whether to write back to the floating-point register
      - vfWen: Vector register write-back enable
      - isXSTrap: Whether it is an XSTrap instruction.
      - noSpecExec: Whether the instruction can execute out-of-order, i.e., does
        not need to wait for preceding instructions to commit before execution.
      - blockBackward: Whether to block subsequent instructions, i.e.,
        subsequent instructions must wait for the current instruction to commit
        before entering the ROB.
      - flushPipe: Whether the pipeline needs to be flushed, i.e., the pipeline
        must be cleared after the current instruction commits
      - canRobCompress: Whether the instruction supports ROB compression (for
        instructions that do not trigger exceptions and are not at the boundary
        of FTQ, we consider them compressible in ROB).
      - uopSplitType: Instruction splitting type. Scalar instruction splitting
        types are all UopSplitType.SCA_SIM and do not require splitting, while
        vector instructions and AMO_CAS instructions need splitting. If a vector
        instruction only needs to split into one uop and does not require
        modification of instruction control signals, the splitting type is
        UopSplitType.dummy, allowing it to enter the vector complex decoder for
        vector instruction exception checking.

   - **VPUCtrlSignals**\
     Vector and floating-point instructions require VPUCtrlSignals
     configuration. VPUCtrlSignals contains information such as sew and lmul for
     vector configuration.
     - Vector instruction: The vector configuration information comes from the
       vtype information of VtypeGen in the DecodeStage.
     - Floating-point instructions: The floating-point module is independent of
       the vector module but shares the same execution units as the vector
       module. The execution units specify the element width via sew
       information, so a dedicated decoding submodule, FPToVecDecoder, generates
       VPUCtrlSignals control signals for floating-point instructions.

   - **FPUCtrlSignals**\
     Generated in the decoding submodule FPDecoder, the rm signal is used to
     control floating-point rounding, wflags is used to control the i2f module
     and fflag updates, and the remaining signals are used to control the i2f
     module.
      ```scala
        class FPUCtrlSignals(implicit p: Parameters) extends XSBundle {
          val typeTagOut = UInt(2.W) // H S D
          val wflags = Bool()
          val typ = UInt(2.W)
          val fmt = UInt(2.W)
          val rm = UInt(3.W)
        }

      ```
    - **uopnum** `UopInfoGen` generates the number of instruction splits. Scalar
      instructions have a split count of 1, AMO_CAS instructions may split into
      2 or 4 depending on type, while vector instructions require lmul-based
      split calculation, with vector memory instructions additionally
      considering lmul, sew, and eew for split count.

2. **Translation processing**
    - **move instruction**\
      Since the move instruction is a special addi instruction, it is identified
      by the instruction field, and move elimination is performed in the
      subsequent rename stage.
    - **zimop instruction**\
      Since the zimop instruction only requires writing vd as 0, it is
      translated into an addi instruction with src as x0 and imm as 0.
    - **csrr vlenb instruction** The value of vlenb is fixed, translated into an
      addi instruction with src as x0 and imm as VLEN/8.
    - **csrr vl instruction** vl uses an independent register file, thus
      supporting renaming and out-of-order execution. Reading vl instruction is
      converted to a vset instruction that reads vl and writes to the
      corresponding rd
    - **Software prefetch instruction** Modify fuType to FuType.ldu.U and pass
      it to the corresponding functional unit for processing.

3. ** Exception handling ** DecodeUnit will handle `illegalInstr` (exception
   value 2) and `virtualInstr` (exception value 22) two types of exceptions
    - **illegalInstr**
      - Check if the immediate selection is invalid.
      - Exceptions when executing instructions under certain CSR settings.
      - Vector-related exceptions are not checked in this module but are handled
        in the complex decoder.
    - **virtualInstr**
      - Exceptions when executing instructions under certain CSR settings.

### Secondary module DecodeUnitComp

### Input and Output
Instruction splitting only modifies operand register numbers and operand types
in the instruction, so both input and output types are DecodeUnitCompInput.
Since the vtype information for vset instructions needs to be obtained through
decoding rather than vtypegen, the vtypebypass signal is used to update the
vtype used by the vset instruction to the vtype information of that vset
instruction.
  - **DecodeUnitCompIO**
  ```scala
      class DecodeUnitCompIO(implicit p: Parameters) extends XSBundle {
        val redirect = Input(Bool())
        val csrCtrl = Input(new CustomCSRCtrlIO)
        val vtypeBypass = Input(new VType)
        // When the first inst in decode vector is complex inst, pass it in
        val in = Flipped(DecoupledIO(new DecodeUnitCompInput))
        val out = new DecodeUnitCompOutput
        val complexNum = Output(UInt(3.W))
      }

  ```


### Function

This module splits a vector instruction into multiple micro-operations based on
the split type and lmul information, while modifying operand register numbers
and operand types in the micro-operations. It also performs exception checking
for vector instructions. The module uses a state machine where the ready signal
only goes high when there are no instructions being processed or when the
current instruction's processing is completed, allowing it to handle the next
instruction.

### Design specifications

Currently, there are many types of instruction splits, which will be optimized
and simplified in the future.

| Splitting type                                                  | Corresponding instruction type                                                                                                                               |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| AMO_CAS_W/AMO_CAS_D/AMO_CAS_Q                                   | AMO_CAS instruction                                                                                                                                          |
| VSET                                                            | vset instruction                                                                                                                                             |
| VEC_VVV.                                                        | Instructions where both source registers and destination registers are vector registers                                                                      |
| VEC_VFV                                                         | An instruction where one source register is a floating-point register, and both the other source register and the destination register are vector registers. |
| VEC_EXT2/VEC_EXT4/VEC_EXT8                                      | Vector sign-extension instruction.                                                                                                                           |
| VEC_0XV                                                         | Scalar-to-vector move instruction                                                                                                                            |
| VEC_VXV                                                         | An instruction where one source register is a scalar register, and both the other source register and the destination register are vector registers.         |
| VEC_VVW/VEC_VFW/VEC_WVW/VEC_VXW/VEC_WXW/VEC_WVV/VEC_WFW/VEC_WXV | widening/narrowing vector instructions                                                                                                                       |
| VEC_VVM/VEC_VFM/VEC_VXM                                         | Vector instruction with destination register as mask register                                                                                                |
| VEC_SLIDE1UP                                                    | vslide1up instruction                                                                                                                                        |
| VEC_FSLIDE1UP                                                   | vfslide1up instruction                                                                                                                                       |
| VEC_SLIDE1DOWN                                                  | vslide1down instruction                                                                                                                                      |
| VEC_FSLIDE1DOWN.                                                | vfslide1down instruction                                                                                                                                     |
| VEC_VRED                                                        | Scalar reduction instruction                                                                                                                                 |
| VEC_VFRED                                                       | Out-of-order floating-point reduction instruction.                                                                                                           |
| VEC_VFREDOSUM                                                   | Sequential floating-point reduction instruction                                                                                                              |
| VEC_SLIDEUP                                                     | vslideup instruction                                                                                                                                         |
| VEC_SLIDEDOWN                                                   | vslidedown instruction                                                                                                                                       |
| VEC_M0X                                                         | vcpop instruction                                                                                                                                            |
| VEC_MVV                                                         | vid/viota instruction                                                                                                                                        |
| VEC_VWW.                                                        | Scalar widening reduction instructions                                                                                                                       |
| VEC_RGATHER                                                     | vrgather instruction.                                                                                                                                        |
| VEC_RGATHER_VX                                                  | vrgather instruction with one operand from a scalar register                                                                                                 |
| VEC_RGATHEREI16                                                 | vrgatherei16 instruction                                                                                                                                     |
| VEC_COMPRESS                                                    | vcompress instruction                                                                                                                                        |
| VEC_MVNR                                                        | vmvnr instruction.                                                                                                                                           |
| VEC_US_LDST                                                     | Unit-stride load/store instruction                                                                                                                           |
| VEC_S_LDST                                                      | strided load/store instructions.                                                                                                                             |
| VEC_I_LDST                                                      | indexed load/store instructions                                                                                                                              |

## Secondary module VecExceptionGen.

- **Inputs:**
  - `inst`: 32-bit instruction
  - `decodedInst`: Decoded instruction information
  - `vtype`: vtype information
  - `vstart`: vstart information

- **Output:**
  - `illegalInst`: Whether the instruction is illegal

### Function

Check for exceptions in vector instructions; all exceptions except those related
to vector memory access are checked during the decode stage.

### Design specifications

Vector instruction-related exceptions are categorized into the following eight
types:

| Exception name    | Description                                                                                                                                      |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| inst Illegal      | Reserved instruction raises an exception.                                                                                                        |
| vill Illegal      | When the vill field of vtype is 1, executing any vector instruction other than vset raises an exception.                                         |
| EEW Illegal       | Vector floating-point instructions, sign-extension instructions, widening instructions, and narrowing instructions eew exception.                |
| EMUL Illegal      | Vector memory instructions, sign-extension instructions, widening instructions, narrowing instructions, vrgatherei16 instruction elmul exception |
| Reg Number Align. | vs1, vs2, vd not aligned to lmul                                                                                                                 |
| v0 Overlap        | Exception is raised when certain instructions read the v0 register while simultaneously modifying v0.                                            |
| Src Reg Overlap   | Exception is raised when instructions vs1, vs2, and vd partially overlap                                                                         |
| vstart Illegal    | When vstart is not equal to 0, executing vector instructions other than vset and vector memory access instructions will raise an exception.      |

If one of them triggers an exception, the exception signal is raised.
