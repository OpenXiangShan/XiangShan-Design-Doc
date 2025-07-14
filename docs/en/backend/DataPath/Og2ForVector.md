# Og2ForVector

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Overall design

### Overall Block Diagram

![Overall Block Diagram](./figure/Og2ForVector.svg)

### Interface list

Refer to the interface documentation.


## Function

For regular scalar instructions, after passing through the DataPath, they are
directly sent to the BypassNetwork, where the final operands are generated via
multiplexing. For vector computation and vector memory access instructions,
since the timing for reading the vector register file is tighter than for
scalars, and the vector execution unit has stringent timing requirements for the
first cycle of data, an additional OG2 stage is introduced after the DataPath
before entering the BypassNetwork for operand selection.

The Og2ForVector module only performs simple pipelining without logical
operations. Whether an instruction can proceed to the OG2 stage depends solely
on global cancellation. The Og2ForVector module contains the pipeline registers
for the OG2 stage. Instructions in the OG1 stage can advance to OG2 if they do
not encounter a load cancellation or redirection flush.

Another function of the Og2ForVector module is to send OG2-stage responses back
to the issue queue. The OG2 stage does not have cancellations due to its own
reasons. Whether an instruction can be successfully sent to the subsequent stage
depends solely on whether the latter can accept it. If the subsequent stage
cannot accept the instruction, it cannot proceed to the execution unit, and the
issue queue is notified with a "block" status, indicating that the instruction
needs to be reissued later. If the subsequent stage can accept the instruction,
vector computation instructions are guaranteed to execute successfully, and the
issue queue is notified with a "success" status, allowing the corresponding
queue entry to be cleared. For vector memory access instructions, it is only
after entering the memory execution unit that the success of execution can be
determined. Here, the issue queue is simply notified with an "uncertain" status
to remain unchanged, with subsequent clearance or reissue responses being
handled by the execution unit.
