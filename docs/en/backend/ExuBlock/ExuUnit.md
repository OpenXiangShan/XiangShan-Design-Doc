# ExuUnit

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Glossary of Terms

Table: Glossary of Terms in FU

| fu         | Descrption                                             |
| ---------- | ------------------------------------------------------ |
| alu        | Arithmetic Logic Unit                                  |
| mul        | Multiplication unit                                    |
| bku        | B-extension bit manipulation and cryptography unit     |
| brh        | Conditional Branch Unit                                |
| jmp        | Direct jump unit                                       |
| i2f        | Integer to Floating-Point Conversion Unit              |
| i2v        | Integer Move to Vector Unit                            |
| VSetRiWi   | VSet unit for reading and writing integers             |
| VSetRiWvf  | The vset unit for reading integers and writing vectors |
| csr        | Control and Status Register Unit                       |
| fence      | Memory Synchronization Instruction Unit                |
| div        | Division unit                                          |
| falu       | Floating-point arithmetic logic unit                   |
| fcvt       | Floating-point conversion unit                         |
| f2v        | Floating-point move to vector unit                     |
| fmac       | Floating-point fused multiply-add                      |
| fdiv       | Floating-Point Division Unit                           |
| vfma       | Vector floating-point fused multiply-add unit          |
| vialu      | Vector Integer Arithmetic Logic Unit                   |
| vimac      | Vector integer multiply-add unit                       |
| vppu       | Vector permutation processing unit                     |
| vfalu      | Vector Floating-Point Arithmetic Logic Unit            |
| vfcvt      | Vector floating-point conversion unit                  |
| vipu       | Vector integer processing unit                         |
| VSetRvfWvf | Read vector write vector vset unit                     |
| vfdiv      | Vector floating-point division unit                    |
| vidiv      | Vector integer division unit                           |

## Input and Output

`flush` is a Redirect input with a valid signal.

`in` is the ExuInput generated according to the specific ExeUnit parameter
configuration

`out` is the ExuOutput generated based on the specific ExeUnit parameter
configuration

`csrio`, `csrin`, and `csrToDecode` only exist when `CSR` is present in the
ExeUnit.

Similarly, `fenceio` only exists when `fence` is present in the ExeUnit. `frm`
only exists when `frm` is required as a src in the ExeUnit. `vxrm` only exists
when `vxrm` is required as a src in the ExeUnit.

`vtype`, `vlIsZero`, and `vlIsVlmax` only exist when Vconfig needs to be written
in this ExeUnit.

Additionally, for cases where JmpFu or BrhFu exists in the ExeUnit, the
instruction address translation type `instrAddrTransType` must also be input

## 功能

Each ExuUnit generates a series of corresponding FU modules based on its
configuration parameters.

busy is used to indicate whether the current ExeUnit is in a busy state. For
ExeUnits with deterministic latency, the functional unit is never marked as busy
because the latency is fixed, and all tasks will complete in order. In this
case, busy is directly set to false, indicating the functional unit is always
idle. For ExeUnits with non-deterministic latency, busy is set high when input
fires and set low when output fires. Additionally, if the incoming uop or the
uop being calculated needs to be redirect flushed, busy is also set low.

Additionally, the ExeUnit checks for mixed latency types, i.e., whether there
are functional units on the same port with different latency types
(deterministic and non-deterministic). If such mixed cases exist, for functional
units with non-deterministic latency, their priority is ensured to be the
maximum. This design logic guarantees that when handling functional units with
different latency types, the write-back port priorities are appropriately
configured to avoid conflicts or inconsistencies in priority.

In addition to containing various FUs, each ExuUnit also includes a submodule
called in1ToN, which acts as a Dispatcher. Its role is to further dispatch an
ExuInput entering the ExuUnit to different FUs. It must ensure that the same
ExuInput enters exactly one FU and does not enter more than one FU.

Additionally, there is a set of registers called inPipe, which consists of
(valid, input) pairs with a size of latencyMax + 1. These record the inputs and
the computation cycle in which the input resides. For FUs that require pipeline
control, the original data can be obtained through inPipe.

Finally, the output results from different FUs need to be aggregated, and one
FU's output result is selected as the ExeUnit's output.

![ExuUnit Overview](./figure/ExuUnit-Overview.svg)

## Design specifications

There are a total of 3 ExuBlocks in the Backend: intExuBlock, fpExuBlock, and
vfExuBlock, which are the execution modules for integer, floating-point, and
vector operations, respectively. Each ExuBlock contains several ExeUnit units.

The intExuBlock contains 8 ExeUnits, each with the following functions:

Table: FUs included in each ExeUnit within intExuBlock

| ExeUnit | 功能                                      |
| ------- | --------------------------------------- |
| exus0   | alu，mul，bku                             |
| exus1   | brh，jmp                                 |
| exus2   | alu，mul，bku                             |
| exus3   | brh，jmp                                 |
| exus4   | alu                                     |
| exus5   | brh, jmp, i2f, i2v, VSetRiWi, VSetRiWvf |
| exus6   | alu                                     |
| exus7   | csr, fence, div                         |

The fpExuBlock contains 5 ExeUnits, with each ExuUnit corresponding to the
following functions:

Table: FUs included in each ExeUnit in fpExuBlock

| ExeUnit | 功能                 |
| ------- | ------------------ |
| exus0   | falu，fcvt，f2v，fmac |
| exus1   | fdiv               |
| exus2   | falu，fmac          |
| exus3   | fdiv               |
| exus4   | falu，fmac          |

The vfExuBlock contains 5 ExeUnits, each corresponding to the following
functions:

Table: FUs included in each ExeUnit in vfExuBlock

| ExeUnit | 功能                          |
| ------- | --------------------------- |
| exus0   | vfma，vialu，vimac，vppu       |
| exus1   | vfalu，vfcvt，vipu，VSetRvfWvf |
| exus2   | vfma，vialu                  |
| exus3   | vfalu                       |
| exus4   | vfdiv, vidiv                |

## Gating

The ExuUnit also supports clock gating for functional units (FUs). Power
consumption is reduced by controlling the clock enable signal clk_en of each FU.
The clock is only enabled when the FU is needed, and the clock gating enable
signal is dynamically calculated based on the FU's latency settings and whether
uncertain latency is enabled, thereby optimizing power consumption.

In simple terms, for FUs with fixed latency and a latency cycle count greater
than 0, two vectors of length latReal + 1, fuVldVec and fuRdyVec, are used. When
the FU input is valid, fuVldVec(0) is set to 1, and this 1 is shifted backward
each cycle. Additionally, the value of fuRdyVec(i) depends on fuRdyVec(i+1) and
fuVldVec(i+1). Thus, when there is a 1 in fuVldVec, it indicates there is valid
computation in progress.

For FUs with uncertain latency, the uncer_en_reg is recorded when the FU input
fires and cleared when the FU output fires.

Thus, for FUs that can use gating, the clk_en signal is asserted under the
following conditions: for zero-latency FUs when the FU input fires; for
multi-cycle latency FUs when the input fires or there is valid computation in
the current FU; for non-deterministic latency FUs when the FU input fires or
there is valid computation in the current FU. Clock gating is performed based on
these conditions.
