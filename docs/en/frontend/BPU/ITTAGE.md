# BPU Submodule ITTAGE

## Function

In the ITTAGE, prediction requests from inside the BPU are received. It is
internally composed of a base prediction table and multiple history tables, each
entry containing a field to store the target address of an indirect jump
instruction. The base prediction table is indexed by the PC, while the history
tables are indexed by the XOR result of the PC folded with a branch history of a
certain length; different history tables use different branch history lengths.
During prediction, a tag is also computed by XORing the PC with another folding
result of the branch history corresponding to each history table, and this tag
is matched against the tag read from the table. If the match is successful, the
table hits. The final result depends on the outcome of the prediction table with
the longest history that hit. Finally, the ITTAGE outputs the prediction result
to the composer.

### Prediction of indirect jump instructions

ITTAGE is used to predict indirect jump instructions. The jump targets of
ordinary branch instructions and unconditional jump instructions are directly
encoded in the instructions, making them easy to predict. In contrast, the jump
addresses of indirect jump instructions come from runtime-variable registers,
offering multiple possible choices that require prediction based on branch
history.

For this purpose, each entry in the ITTAGE has added the predicted jump address
item based on the TAGE entry, and the final output is the selected predicted
jump address rather than the selected jump direction.

Since each FTB entry stores information for at most one indirect jump
instruction, the ITTAGE predictor can predict the target address of only one
indirect jump instruction per cycle.

The ITTAGE in the Xiangshan Kunminghu V2R2 architecture provides 5 tagged
prediction tables T1-T5. The basic information of the base predictor and the
tagged prediction tables is shown in the table below.

| **predictor**           | ** with tag** | ** function **                                                                                            | ** entry composition **                                                                                                                                                                                                                         | **item count**                                           |
| ----------------------- | ------------- | --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| Baseline Predictor T0   | No            | Used to provide prediction results when none of the tags in the tagged prediction table match.            | ITTAGE does not implement T0, but directly uses the prediction result from ftb as the baseline prediction result                                                                                                                                |                                                          |
| Prediction tables T1-T5 | Yes           | When there is a tag match, the one with the longest history is selected to provide the prediction result. | valid: 1bit; tag: 9bit; sctr: 2bits (indicates whether to output this prediction result); useful: 1bit (usefulness counter); target_offset: 20 bits (total target is 50 bits, stored separately in the high 30 bits due to area considerations) | T1-T2 each have 256 entries, T3-T5 each have 512 entries |

The BPU module maintains a 256-bit global branch history ghv and separately
manages folded branch histories for each of ITTAGE's 5 tagged prediction tables,
with the folding algorithm identical to TAGE. The specific configurations for
folded histories are detailed in the table below, where ghv is a circular queue,
and the "lower" n bits refer to the low-order bits starting from the position
indicated by ptr:

| ** history**                                | **index folded branch history length** | **tag folded branch history 1 length** | ** tag folded branch history 2 length** | ** Design principle **                                                |
| ------------------------------------------- | -------------------------------------- | -------------------------------------- | --------------------------------------- | --------------------------------------------------------------------- |
| Global branch history ghv                   | 256 bits                               | None                                   | None                                    | Each bit represents whether the corresponding branch is taken or not. |
| T1 corresponds to folded branch history     | 4 bits                                 | 4 bits                                 | 4 bits                                  | ghv takes the lower 4 bits of ptr for folded XOR                      |
| T2 corresponds to folded branch history     | 8 bits                                 | 8 bits                                 | 8 bits                                  | ghv takes the lower 8 bits of ptr for folded XOR                      |
| T3 corresponds to folded branch history.    | 9 bits                                 | 9 bits                                 | 8 bits                                  | ghv takes the lower 13 bits from ptr, folds, and XORs them.           |
| T4 corresponds to folded branch history     | 9 bits                                 | 9 bits                                 | 8 bits                                  | ghv takes the lower 16 bits of ptr for folded XOR                     |
| T5 corresponds to the folded branch history | 9 bits                                 | 9 bits                                 | 8 bits                                  | ghv takes the lower 32 bits of ptr for folded XOR                     |

ITTAGE requires a 3-cycle delay:

* Index generation takes 0 cycles.
* 1-cycle data readout
* 2-cycle selection of hit result
* 3-cycle output

### Write Buffer

Each IttageTable uses a WriteBuffer module to implement a write buffer. It is
used to temporarily store write requests during conflicts between SRAM write and
read operations to ensure data consistency. A write is performed to this
WriteBuffer each time the ITTAGE is updated; when the SRAM read port is idle,
the WriteBuffer writes the data into the SRAM.


### Predictor training

First, define the provider as the prediction table with the longest required
history length among all those producing tag matches, while the other matching
prediction tables (if any) are called altpred. When the provider's ctr is 0, the
altpred's result is chosen as the prediction.

The ITTAGE entry contains a usefulness field. When the provider predicts
correctly and the altpred predicts incorrectly, the usefulness of the provider
is set to 1, indicating that the entry is a useful entry and will not be
allocated out as an empty entry by the allocation algorithm during training.
When the prediction generated by the provider is confirmed to be a correct
prediction, and at that time the prediction results of the provider and altpred
are different, the usefulness field of the provider is set to 1.

If the predicted address matches the actual address, the ctr counter of the
corresponding provider entry is incremented by 1; if the predicted address does
not match the actual address, the ctr counter of the corresponding provider
entry is decremented by 1. In the ITTAGE, it is determined based on ctr whether
to adopt the jump target result of this prediction. When ctr is 0, the result of
altpred is selected.

Next, if the prediction table from which the provider originates is not the
prediction table with the highest required history length, the following entry
allocation operation is performed. The entry allocation operation first reads
the usefulness field of all prediction tables whose history length is longer
than that of the provider. If the usefulness field value of a certain table is
0, a corresponding entry is allocated in that table; if no table with a
usefulness field value of 0 is found, the allocation fails. When multiple
prediction tables (e.g., Tj, Tk) all have a usefulness field value of 0, the
probability of entry allocation is random. During allocation, some tables are
randomly masked so that the same one is not allocated every time. The randomness
of entry allocation here is achieved by generating pseudo-random numbers using
the LFSR64 (64-bit linear feedback shift register primitive) from Chisel's util
package, corresponding to the allocLFSR_lfsr register in the Verilog code.
During training, an 8-bit saturating counter, tickCtr, counts the number of
allocation failures minus successes. When the number of allocation failures is
sufficiently large and tickCtr reaches saturation, a global useful bit reset is
triggered, clearing all usefulness fields to zero.

Note: The saturating counter for clearing the usefulness field in ITTAGE is
named tickCtr, with a length of 8 bits. Both the name and length differ from
TAGE.

Finally, when allocating a new entry in the ITTAGE table, the ctr counter in the
new entry is set to 2, and the usefulness field is set to 0.

## Storage structure

* 5 history tables, with entry counts of 256, 256, 512, 512, and 512
  respectively, each table has no bank division.
* Each entry contains 1bit valid, 9bit tag, 2bit ctr, 20bit target_offset, and
  1bit useful, all uniformly stored using SRAM.
* Using the FTB result as the base table.
* Each history table has a write buffer (WriteBuffer) of 4 entries.

## Prediction flow

* s0 performs index calculation, and the address is sent to the SRAM.
* s1 reads the entries, performs bank selection, and determines hits, with the
  results registered to s2.
* s2 calculates the longest history match and the second-longest history match:
  * When there is a history table hit and ctr!=0, the target address from the
    longest history result is attempted.
  * When the provider has low confidence (ctr==0), if the second-longest history
    matches, the target address from the second-longest history result is
    attempted.
  * When no history table hits, the FTB result is used.
* s3 uses the target address and compares it with the s2 result within the BPU
  to determine whether the pipeline needs to be flushed.

## Training process

Basically the same as TAGE. For the target field, a new value is replaced only
when a new entry is allocated or when the original ctr is at the minimum value
of 0; otherwise, it remains unchanged.
