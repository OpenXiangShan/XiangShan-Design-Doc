# BPU Submodule uFTB

## Functional Overview

The uFTB serves as the BPU's next-line predictor, providing the processor with
bubble-free basic predictions to continuously generate the next speculative PC
value.

### uFTB Request Reception

Each time a valid stage 0 request is made, bits 16 to 1 of the predicted block's
starting PC are extracted to generate a tag, which is sent to the fully
associative uFTB within the module for reading the FTB entry. The contents of
the FTB entry are as previously described. Each bank in the uFTB contains 32
fully associative entries implemented with registers. Due to the register-based
implementation, each entry can generate a hit signal and the read FTB entry data
in the current cycle based on whether the stored data is valid and whether the
stored tag matches the incoming information. However, this data is not used in
the current cycle but in the next cycle.

### uFTB Data Read and Return

In the next cycle, the uFTB memory bank returns the hit signal and read data.
The predictor enters Stage 1. In this stage, at most one hit entry is selected
from the returned hit signals, and the prediction result is generated using this
hit entry. The algorithm for generating the complete prediction result is
detailed in the subsequent FTB module. Here, the uFTB has an additional counter
mechanism, where each entry in the uFTB can have up to two branch instructions
with a 2-bit counter. If the counter is greater than 1 or the always_taken flag
in the FTB entry is valid (the latter mechanism also exists in the FTB module),
the prediction result is a jump. Additionally, the hit signal and the selected
hit way number from this stage are used as meta information for this predictor,
waiting to be sent out along with other predictors in Stage 3, and stored in the
FTQ along with the final prediction result. This predictor has no additional
actions in Stages 2 and 3.

### uFTB Data Update

When all instructions corresponding to the prediction block are committed, the
update channel from FTQ to BPU, which directly connects to this module, will
include the FTB entry updated by the FTQ module based on instruction commit
information. Since the fully associative uFTB is entirely built with registers,
write operations do not affect parallel read operations, and the incoming update
information will always be applied. When the update channel is valid, the
current cycle will use the incoming update PC value to generate a tag and match
it with existing entries in the uFTB, producing match signals and the matched
way signals. In the next cycle, if a match exists, the write signal for the
matched way will be asserted; otherwise, the pseudo-LRU replacement algorithm
will select a way to be replaced, and the corresponding write signal will be
asserted. The data to be written is the updated FTB entry.

Maintenance of the counters for each branch instruction is also updated when the
update channel is asserted. In the cycle following the update channel assertion,
the counters for the branching instructions within the updated FTB entry and
those before it are updated. If the branch is taken, the counter is incremented
by 1; if not taken, it is decremented by 1. If the counter is saturated (0 or
all 1s), the current value is maintained.

The pseudo-LRU algorithm also requires data updates, with two data sources: one
is the way encoding of the hit during prediction, and the other is the way
encoding to be written during uFTB updates. If either is valid, its information
is used to update the pseudo-LRU state. If both are valid in the same cycle,
combinational logic is used to update the state sequentially with both pieces of
information.

### SRAM specifications

The module does not use SRAM internally but contains numerous register
concatenation structures, listed as follows.

The module contains 32 ways of data, each consisting of two 2-bit wide
saturating counters for basic branch direction prediction; a 60-bit FTB entry,
with the same meaning as in the FTB module (see the FTB SRAM specification for
details); a 16-bit tag; and a 1-bit way valid signal.

## Overall Block Diagram

![Overall Block Diagram](../figure/BPU/uFTB/structure.png)

TODO: The diagram does not match Kunming Lake and needs to be updated.

## Interface timing

### Result output interface

![Result Output Interface](../figure/BPU/uFTB/port1.png)

The above diagram shows a valid uFTB output, with the next predicted block
starting at address 0x80002000.

### Update Interface

![Update interface](../figure/BPU/uFTB/port2.png)

The above diagram illustrates a valid update request, modifying the FTB entry at
address 0x80003b9a.
