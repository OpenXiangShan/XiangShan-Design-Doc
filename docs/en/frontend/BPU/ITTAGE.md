# BPU Submodule ITTAGE

## Function

ITTAGE receives prediction requests from within the BPU. It consists of a base
prediction table and multiple history tables, each entry containing a field to
store the target address of indirect jump instructions. The base prediction
table is indexed by PC, while history tables are indexed by XORing the PC with a
folded result of a certain length of branch history. Different history tables
use varying lengths of branch history. During prediction, a tag is computed by
XORing the PC with another folded result of the branch history corresponding to
each history table, then matched against the tag read from the table. A match
indicates a hit. The final result depends on the outcome from the history table
with the longest matching history length. Ultimately, ITTAGE outputs the
prediction result to the composer.

### Prediction of indirect jump instructions

ITTAGE is used to predict indirect jump instructions. The jump targets of
ordinary branch instructions and unconditional jump instructions are directly
encoded in the instructions, making them easy to predict. In contrast, the jump
addresses of indirect jump instructions come from runtime-variable registers,
offering multiple possible choices that require prediction based on branch
history.

To this end, each entry in ITTAGE includes a predicted jump address field in
addition to the TAGE entry, ultimately outputting the selected predicted jump
address rather than the chosen jump direction.

Since each FTB entry stores information for at most one indirect jump
instruction, the ITTAGE predictor can predict the target address of only one
indirect jump instruction per cycle.

The ITTAGE in Xiangshan Nanhu architecture provides 5 tagged prediction tables
T1-T5. Basic information about the baseline predictor and tagged prediction
tables is shown in the table below.

| **predictor**           | ** with tag** | ** function **                                                                                            | ** entry composition **                                                                                                                               | **item count**                                           |
| ----------------------- | ------------- | --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| Baseline Predictor T0   | No            | Used to provide prediction results when none of the tags in the tagged prediction table match.            | ITTAGE does not implement T0, but directly uses the prediction result from ftb as the baseline prediction result                                      |                                                          |
| Prediction tables T1-T5 | Yes           | When there is a tag match, the one with the longest history is selected to provide the prediction result. | valid 1bit, tag 9bits, ctr 2bits (the highest bit indicates whether to output this prediction result), us: 1bit (usefulness counter), target: 39 bits | T1-T2 each have 256 entries, T3-T5 each have 512 entries |

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
| T2 corresponds to folded branch history     | 8-bit                                  | 8-bit                                  | 8-bit                                   | ghv takes the lower 8 bits of ptr for folded XOR                      |
| T3 corresponds to folded branch history.    | 9-bit                                  | 9-bit                                  | 8-bit                                   | ghv takes the lower 13 bits from ptr, folds, and XORs them.           |
| T4 corresponds to folded branch history     | 9-bit                                  | 9-bit                                  | 8-bit                                   | ghv takes the lower 16 bits of ptr for folded XOR                     |
| T5 corresponds to the folded branch history | 9-bit                                  | 9-bit                                  | 8-bit                                   | ghv takes the lower 32 bits of ptr for folded XOR                     |

ITTAGE requires a 3-cycle delay:

* Index generation takes 0 cycles.
* 1-cycle data readout
* 2-cycle selection of hit result
* 3-cycle output

  ### Wrbypass

Wrbypass contains both Mem and Cam, used to sequence updates. Every ITTAGE
update writes to this wrbypass and the corresponding prediction table's SRAM.
During each update, wrbypass is checked; if a hit occurs, the read ITTAGE ctr
value is used as the old value, discarding the old ctr value previously sent to
the backend with the branch instruction and returned to the frontend. This
ensures that if a branch is updated repeatedly, wrbypass guarantees that one
update will always obtain the final value from the immediately preceding update.

Each prediction table T1~T5 in ITTAGE has a corresponding wrbypass. In the
wrbypass of each prediction table, Mem contains 4 entries, each storing 1 ctr;
Cam has 4 entries, where inputting the updated idx and tag retrieves the
corresponding data's position in Cam. Cam and Mem are written simultaneously, so
the data's position in Cam is also its position in Mem. Thus, using this Cam, we
can check during updates whether the data corresponding to the idx is in the
wrbypass.

#### Predictor training

First, define the provider as the prediction table with the longest required
history length among all those producing tag matches, while the other matching
prediction tables (if any) are called altpred. When the provider's ctr is 0, the
altpred's result is chosen as the prediction.

The ITTAGE entry includes a usefulness field. When the provider predicts
correctly while the altpred predicts incorrectly, the provider's usefulness is
set to 1, indicating that the entry is useful and will not be allocated as an
empty entry by the training allocation algorithm. When the provider's prediction
is confirmed as correct and the provider's prediction differs from the altpred's
result, the provider's usefulness field is set. If the predicted address matches
the actual address, the ctr counter of the corresponding provider entry is
incremented by 1; if the predicted address does not match, the ctr counter is
decremented by 1. In ITTAGE, the ctr is used to determine whether to adopt the
predicted jump target result. When ctr is 0, the altpred result is chosen.

Next, if the provider originates from a prediction table that does not have the
longest required history length, the following entry addition operation is
performed. The entry addition operation first reads the usefulness field of all
prediction tables with history lengths longer than the provider. If any table's
usefulness field value is 0, an entry is allocated in that table; if no table
meets this condition, allocation fails. When multiple prediction tables (e.g.,
Tj, Tk) have usefulness fields of 0, entry allocation is random, with certain
tables masked randomly to prevent repeated allocations to the same table. The
randomness in entry allocation is achieved using a 64-bit linear feedback shift
register (LFSR) primitive from Chisel's util package, which generates
pseudo-random numbers. In the Verilog code, this corresponds to the
allocLFSR_lfsr register. During training, an 8-bit saturating counter tickCtr
tracks the difference between allocation failures and successes. When allocation
failures accumulate sufficiently to saturate the tickCtr counter, a global
useful bit reset is triggered, clearing all usefulness fields.

Note: The saturating counter for clearing the usefulness field in ITTAGE is
named tickCtr, with a length of 8 bits. Both the name and length differ from
TAGE.

Finally, during initialization or when allocating new entries in the TAGE table,
all ctr counters in the entries are set to 0, and all usefulness fields are set
to 0.

## Storage structure

* 5 history tables with entries of 256, 256, 512, 512, and 512 respectively.
  Each table is divided into 2 banks based on the lower bits of the PC, with
  each bank containing 128 sets. Each set corresponds to a maximum of 1 indirect
  jump in an FTB entry.
* Each entry contains 1 valid bit, 9 tag bits, 2 counter bits, 39 target bits,
  and 1 useful bit. The useful bit is stored independently, and the valid bit is
  stored separately using a register file.
* Using FTB results as the base table, equivalent to 2K entries (but the FTB
  target bit width is insufficient to effectively store far jump addresses)
* Each bank of the history table has a 4-entry write buffer wrbypass

## Indexing method

* index = pc[8:1] ^ folded_hist(8bit) or pc and folded_hist each 9bit
* tag = pc[17:9] (or pc[19:10]) ^ folded_hist(9bit) ^ (folded_hist(8bit) << 1)
  * Here, it might still be better to use the lower bits of the PC rather than
    another unused segment of the PC index, or...
* The history employs basic segmented XOR folding.

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
  * When attempting to use the results from the history table, they are only
    actually used if ctr>1. If ctr<=1, the results are not used.
* s3 uses the target address and compares it with the s2 result within the BPU
  to determine whether the pipeline needs to be flushed.

## Training process

Essentially the same as TAGE. For the target field, the new value is only
replaced when allocating a new entry or when the original ctr is at its minimum
value of 0; otherwise, it remains unchanged.
