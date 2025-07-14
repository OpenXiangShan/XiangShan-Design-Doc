# IFU Submodule PreDecoder

## Functional Description

### Functional Overview

The PreDecoder receives the initial instruction code and performs instruction
code generation. Each instruction code queries the pre-decoding table to produce
pre-decoding information, including whether the position is the start of a valid
instruction, the CFI instruction type, whether it is an RVC instruction, whether
it is a Call instruction, and whether it is a Ret instruction. The pre-decoder
generates two types of valid instruction start vectors: one defaults the 1st
2-byte as the start of a valid instruction, and the other defaults the 2nd
2-byte as the start. The final selection is made at the IFU side.

### Feature Descriptions

#### Feature 1: Instruction Code Generation (instr_gen)

The pre-decoder receives the initial instruction code of 17×2 bytes from the IFU
after instruction segmentation and selects a total of 16 4-byte instruction
codes using a 4-byte window and a 2-byte step length, starting from the 1st
2-byte up to the 16th 2-byte.

#### Feature 2: Valid Instruction Start Vector Generation (vec_gen)

While generating the initial instruction code, the pre-decoder also produces a
16-bit valid instruction start vector, where each bit indicates whether the
corresponding position is the start of a valid instruction. The generation logic
is as follows:

- Normal Mode: By default, the first 2 bytes are considered the start of the
  first instruction. If the (n-1)th 2-byte segment is the start of a valid
  instruction and is an RVC instruction, or if the (n-1)th 2-byte segment is not
  the start of a valid instruction (definitely the last 2 bytes of a 4-byte
  instruction), then the nth 2-byte segment is the start of a valid instruction.
- Abnormal Mode: By default, the first 2 bytes are considered the latter half of
  a 4-byte instruction, with the first valid instruction starting from the
  second 2-byte segment. Subsequent generation logic follows the same rules as
  the normal mode.

Both modes generate results in parallel, with the final selection determined by
whether there is a cross-cache-line RVI instruction within the IFU.

#### Feature 3: Pre-Decoding Information Generation (decoder)

The pre-decoder generates pre-decoding information based on the instruction
code, including: whether it is an RVC instruction, whether it is a CFI
instruction, the type of CFI instruction (branch/jal/jalr/call/ret), and the
target address calculation offset for CFI instructions. The CFI instruction
types are shown in Table 1.2.

## Overall Block Diagram

![PreDecoder Structure](../figure/IFU/PreDecoder/PreDecoder_structure.png)

## Interface timing

![PreDecode Interface Timing](../figure/IFU/PreDecoder/PreDecoder_port.png)

Since the PreDecode module consists entirely of combinational logic, both inputs
and outputs are processed within the same clock cycle.

# IFU Submodule PredChecker

## Functional Description

### Functional Overview

The branch prediction checker PredChecker receives prediction block information
from the IFU (including the position of the predicted jump instruction within
the block, the predicted jump target, pre-decoded instruction information,
instruction PC, and pre-decoded jump target offsets). It internally checks for
five types of branch prediction errors. The module is divided into two pipeline
stages, each outputting information. The first stage outputs to the F3 stage to
correct the instruction range and prediction results of the prediction block.
The second stage outputs to the WB stage to generate frontend redirection upon
detecting branch prediction errors and to write back correct prediction
information to the FTQ.

### Feature Descriptions

#### Feature 1: Jal Instruction Misprediction Check

The condition for a jal instruction prediction error is when there is a jal
instruction in the prediction block (indicated by pre-decode information), but
either the prediction block does not predict a jump, or the predicted jump
instruction in the block occurs after this jal instruction (i.e., this jal
instruction was not predicted to jump).

#### Feature 2: Ret Instruction Prediction Error Check

The condition for a ret instruction misprediction is that the prediction block
contains a ret instruction (provided by pre-decoding information), but either
the prediction block has no predicted jump, or the predicted jump instruction in
this prediction block is after the ret instruction (i.e., this ret instruction
is not predicted to jump).

#### Feature 6: Regenerate Instruction Valid Range Vector

When PredChecker detects a Jal/Ret instruction misprediction, it needs to
regenerate the instruction valid range vector, truncating the valid range to the
position of the Jal/Ret instruction and setting all subsequent bits to 0. Note
that both jal and ret instruction mispredictions will shorten the instruction
valid range, so the fixedRange must be regenerated, and the prediction result
must be corrected (i.e., canceling the original prediction and regenerating the
prediction result for this instruction block based on the jal instruction's
position).

#### Feature 3: Non-CFI Prediction Error Check

The condition for a non-CFI misprediction is that the predicted jump
instruction, according to pre-decoding information, is not a CFI instruction.

#### Feature 4: Invalid Instruction Prediction Error Check

The condition for an invalid instruction prediction error is when the predicted
instruction's position, according to the instruction valid vector in the
pre-decode information, does not indicate the start of a valid instruction.

#### Feature 5: Target Address Prediction Error Check

The condition for a target address prediction error is when the predicted
instruction is a valid jal or branch instruction, but the predicted jump target
address does not match the jump target calculated from the instruction code.

#### Feature 5: Hierarchical Output Check Results

The PredChecker results are output in two stages. As previously mentioned,
Jal/Ret instructions require regenerating the instruction valid range vector and
reassigning the predicted position, so their error results must be output
directly to the Ibuffer in the same cycle (F3) to correct instructions entering
the backend promptly. Due to timing considerations, other error information
(such as the error positions of the five types of errors and the correct jump
addresses) is returned to the IFU in the next cycle (WB) for frontend
redirection.

#### Overall Block Diagram

![PredChecker Structure](../figure/IFU/PreDecoder/PredChecker_structure.png)

#### Interface timing

![PredChecker Interface Timing](../figure/IFU/PreDecoder/PredChecker_port.png)

As shown in the figure, yellow represents the checking process of the same
prediction block in PredChecker. The 6th byte position of this prediction block
is predicted as a jump, and the original valid instruction range of the
prediction block is h7f (i.e., 0000000001111111), with the instruction valid
vector being hbfeb (i.e., 1011111111101011). However, the checker identifies
that the 1st byte position (counting from 0) is a jal instruction (brType value
is b10). Therefore, the checker first modifies the valid instruction range to h3
in stage1, sets the predicted byte position to 1 for F3 to perform Ibuffer
instruction enqueue selection, and corrects the target address to h80002120 in
the WB stage while marking the misprediction position as 6, notifying the WB
stage to perform redirection.
