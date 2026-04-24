# BPU Submodule TAGE-SC

## Function

TAGE-SC is the main predictor for conditional branches in the Nanhu
architecture, classified as an Accurate Predictor (APD). TAGE leverages multiple
prediction tables with varying history lengths to exploit extremely long branch
history information, while SC serves as a statistical corrector.

TAGE consists of a base predictor and multiple history tables. The base
predictor is indexed by PC, while the history tables are indexed by the XOR
result of PC and a folded branch history of a certain length. Different history
tables use different branch history lengths. During prediction, the PC is also
XORed with another folded result of the branch history corresponding to each
history table to compute a tag, which is matched against the tag read from the
table. If a match is successful, that table hits. The final result depends on
the prediction of the table with the longest history that hits.

When SC determines that TAGE has a high probability of misprediction, it inverts
the final prediction result.

In the Nanhu architecture, each prediction can simultaneously predict up to two
conditional branch instructions. When accessing various history tables of TAGE,
the starting address of the prediction block is used as the PC, and two
prediction results are fetched simultaneously, both using the same branch
history.

### TAGE: Design Concept

As a hybrid predictor, TAGE's advantage lies in its ability to perform branch
predictions for a given branch instruction based on different lengths of branch
history sequences simultaneously. It evaluates the accuracy of the branch
instruction under various historical sequences and selects the one with the
highest historical accuracy as the final branch prediction criterion.

Compared to traditional hybrid predictors, TAGE incorporates two new design
features that significantly improve its prediction accuracy:

- Tag data is added to entries in each prediction table. In traditional priority
  branch predictors, only the branch history and the PC value of the current
  branch instruction are often used as the basis for indexing the prediction
  table. This situation can lead to aliasing, where multiple different branch
  instructions map to the same prediction table entry. This aliasing has a
  particularly significant impact on the prediction accuracy of the part of the
  hybrid predictor that uses shorter branch history lengths. Therefore, in the
  TAGE design, the partial tagging method allows for better actual matching of
  the current instruction with the entries in the prediction table, thereby
  largely avoiding the occurrence of the above situation.
- Geometrically varying branch history lengths are used to index different
  prediction tables, significantly improving the granularity of table entry
  selection during branch prediction. Additionally, a usefulness counter is
  included in each table entry to record its contribution to branch prediction
  accuracy. This design ensures that various branch instructions have a higher
  likelihood of being indexed by the most accurate branch history length for
  final prediction.

These two design features ensure that the TAGE predictor neither suffers from
reduced information effectiveness due to overly short selected branch history
lengths (which could cause multiple different instructions to map to the same
table entry) nor requires an excessively long time to become effective due to
overly long branch history lengths. Therefore, TAGE can utilize a very wide
range of branch history lengths, making it suitable for predicting branch
instructions in various code contexts.

### TAGE: Hardware Implementation

TAGE is a high-accuracy conditional branch direction predictor. It uses branch
histories of different lengths and the current PC value to index multiple SRAM
tables. When a hit occurs in multiple tables, the prediction result from the
entry with the longest matching history is selected as the final result.

![TAGE Principle](../figure/BPU/TAGE-SC/principle.png)

The structural schematic of TAGE is shown in the figure above, featuring a
baseline predictor T0 and four tagged prediction tables T1-T4. Basic information
about the baseline predictor and the tagged prediction tables is provided in the
table below.

| **predictor**           | ** with tag** | ** function **                                                                                            | ** entry composition **                                                                                                                             | **item count**                |
| ----------------------- | ------------- | --------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| Baseline Predictor T0   | No            | Used to provide prediction results when none of the four local tag prediction tables' tags match.         | ctr is 2 bits (the highest bit provides the prediction result: 1 for jump, 0 for no jump).                                                          | set 2048way 2                 |
| Prediction tables T1-T4 | Yes           | When there is a tag match, the one with the longest history is selected to provide the prediction result. | valid 1bit, tag 8bits, ctr 3bits (the most significant bit gives the prediction result: 1 for taken, 0 for not taken) us: 1bit (usefulness counter) | T1-T4 each have 4096 entries. |

Note: The way in the above table is a parameter name of the SRAMTemplate class
in Chisel. The value of this parameter represents how many copies of the same
type of data are stored in the SRAM, and does not necessarily represent the way
that requires tag matching in the usual sense. T0 has two ways because there are
at most two branch instructions within a prediction block; different ways are
used to predict two different branch instructions within the prediction block,
respectively.

The prediction contents for the two jump instructions in each prediction block
are stored and updated separately. The 4096 entries of the tagged prediction
tables T1-T4 are evenly divided into two banks for up to two branches per
prediction block, with each bank containing 2048 entries. Thus, the index for
tables T1-T4 is only 11 bits, calculated as log2(number of table entries/2). The
two branch instructions in the same prediction block share the same index but
access different banks, potentially resulting in one hit and one miss when
reading prediction results from both banks simultaneously.

Each prediction table of a TAGE-class predictor has a specific history length.
To allow a very long global branch history table to be used for prediction table
indexing or tag matching after XORing with the PC, the very long branch history
sequence needs to be divided into many segments, all of which are then XORed
together. The length of each segment is generally equal to the logarithm of the
history table depth. Since the number of XOR operations is generally large, to
avoid the delay of multiple levels of XOR on the prediction path, we directly
store the folded history.

Each prediction table has three corresponding folded branch histories: one for
indexing the prediction table and two for tag matching. The BPU module maintains
a 256-bit global branch history ghv and separately maintains folded branch
histories for each of TAGE's four tagged prediction tables. The specific
configuration is shown in the table below (see TageTableInfos), where ghv is a
circular queue, and the "lower" n bits refer to the lower bits starting from the
position indicated by ptr:

| ** history**                             | **index folded branch history length** | **tag folded branch history 1 length** | ** tag folded branch history 2 length** | ** Design principle **                                                |
| ---------------------------------------- | -------------------------------------- | -------------------------------------- | --------------------------------------- | --------------------------------------------------------------------- |
| Global branch history ghv                | 256 bits (non-folded)                  | None                                   | None                                    | Each bit represents whether the corresponding branch is taken or not. |
| T1 corresponds to folded branch history  | 8 bits                                 | 8 bits                                 | 7 bits                                  | ghv takes the lower 8 bits of ptr for folded XOR                      |
| T2 corresponds to folded branch history  | 11 bits                                | 8 bits                                 | 7 bits                                  | ghv takes the lower 13 bits from ptr, folds, and XORs them.           |
| T3 corresponds to folded branch history. | 11 bits                                | 8 bits                                 | 7 bits                                  | ghv takes the lower 32 bits of ptr for folded XOR                     |
| T4 corresponds to folded branch history  | 11 bits                                | 8 bits                                 | 7 bits                                  | ghv takes the lower 119 bits from ptr for folded XOR.                 |

![Folded History Actual
Implementation](../figure/BPU/TAGE-SC/folded_history.png)

As shown in the figure above, for timing considerations, the specific
implementation of folding the branch history is not the folding described in the
design principle. Instead, the oldest bit (corresponding to h[12] in the figure)
and the newest bit (corresponding to h[0] in the figure) of the branch history
before folding are XORed into the corresponding positions (corresponding to c[1]
and c[4] in the figure), and then a shift operation is performed (corresponding
to becoming c[0] and c[2] in the figure). The pseudocode is shown below:

c[0] <= c[4] ^ h[0];

c[1] \&lt;= c[0];

c[2] <= c[1] ^ h[12];

c[3] <= c[2];

c[4] \&lt;= c[3];

The branch history table is not only updated after the backend commits. It may
be updated at every stage s1~s3. During an update, the pointer and the value are
updated. If a new result is produced in s1~s3, the pointer will be restored, and
the new value will be updated. However, if there is no prediction error, no
modification will be made (because it has already been updated before).

Note: As seen in the specific configuration table of TAGE's folded branch
history, there are two folded branch histories for tags. Both use the same
folding algorithm, differing only in the folding length. The tag folded branch
history 1 for T1-T4 is 8 bits, while tag folded branch history 2 is 7 bits.

### TAGE: Prediction Timing

During each prediction, two different hash functions are first computed in each
tagged prediction table using the pc value and their respective branch histories
(see table below). The computation results are used to calculate the final tag
for the operation and to index the prediction table.

|       | Calculation Method                                                                             |
| ----- | ---------------------------------------------------------------------------------------------- |
| Index | (index folded branch history) ^ ((pc >> 1) lower bits)                                         |
| Tag   | (tag folded branch history 1) ^ (tag folded branch history 2 << 1) ^ (lower bits of (pc >> 1)) |

If the valid bit obtained from indexing T1-T4 is 1, and the tag matches the
result computed by the tag hash function, the highest bit of the pred provided
by that prediction table is added to the final branch prediction sequence.
Ultimately, through multi-level MUX, the prediction with the longest history
length among all tag-matched branch predictions can be selected as the final
prediction result.

If there is no match in T1-T4, T0 is used as the final prediction result. T0 is
indexed directly using the lower 11 bits of the PC.

TAGE requires a 2-cycle delay:

- The index for SRAM addressing is generated in 0 cycles. The index generation
  process involves XORing the folded history with the PC. The management of the
  folded history is handled outside ITTAGE and TAGE, within the BPU.
- 1-cycle Readout Result
- 2-cycle output prediction result

  ### TAGE: Predictor Training

First, define the predictor with the longest required history length among all
prediction tables that produce a tag match as the provider, while the remaining
prediction tables (if any) that produce a tag match are referred to as altpred.

The TAGE entry contains a usefulness field. When the provider predicts correctly
and altpred predicts incorrectly, the provider's usefulness is set to 1,
indicating that this entry is a useful entry and will not be allocated out as a
free entry by the allocation algorithm during training. When the prediction made
by the provider is confirmed to be correct, and the prediction result of the
provider differs from that of altpred at that time, the provider's usefulness
field is set to 0; if the branch instruction is actually taken, the ctr counter
of the corresponding provider entry is incremented by 1; if the branch
instruction is actually not taken, the ctr counter of the corresponding provider
entry is decremented by 1; if a misprediction necessitates an update of the TAGE
entry, and the misprediction is not caused by discarding the correct provider by
using altpred, it indicates that an entry needs to be allocated. However, an
entry may not necessarily be allocated at this time. It is also required that
the prediction table from which the provider originates is not the table with
the longest required history; only then is the entry allocation operation
performed.

Here is a logical example to determine whether the prediction table from which
the provider originates is not the one with the longest required history length:

s1_providers(i) represents the serial number of the prediction table
corresponding to the provider of the i-th branch in the prediction block.
Assuming the provider is in prediction table T2, then
LowerMask(UIntToOH(s1_providers(i)), TageNTables) is 0b0011. s1_provideds(i)
indicates whether the provider of the i-th branch in the prediction block is in
T1~T4. Based on the previous assumption, Fill(TageNTables,
s1_provideds(i).asUInt) is 0b1111. The two are ANDed to get 0b0011, then
inverted to get 0b1100, showing that T3 and T4 are prediction tables with longer
history lengths than the provider.

Take another example. Initially, the prediction tables are all empty, and there
is no provider. At this time, the corresponding s1_providers(i) is 0, and
s1_provideds(i) is false. Then Fill(TageNTables, s1_provideds(i).asUInt) is
0b0000. The bitwise AND of the two, inverted, definitely yields 0b1111,
indicating that T1~T4 all belong to tables with a longer history than the
provider.

The specific steps for adding a new table entry are as follows:

The entry allocation operation first reads the usefulness of all prediction
tables whose history length is longer than the provider's. If the usefulness
field value of a certain table is 0, then a corresponding entry is allocated in
that table; if no table with a usefulness field value of 0 is found, the
allocation fails. When the usefulness field of multiple prediction tables (e.g.,
Tj and Tk) is 0, the entry allocation probability is random. During allocation,
some tables are randomly masked so that the same table is not always allocated.
The specific implementation of this mask is: among the candidate history tables
(all history tables with a length greater than the provider and with u=0), a
random number is used to randomly mask out some tables. If the first entry of
the masked set is unavailable, the first one that is not masked is selected. The
randomness of the entry allocation here is implemented using the 64-bit Linear
Feedback Shift Register primitive LFSR64 from Chisel's util package to generate
pseudo-random numbers. In the Verilog code, this corresponds to the
allocLFSR_lfsr register. During training, a 7-bit saturating counter,
bankTickCtrs, counts the number of allocation failures minus the number of
successes. When the number of allocation failures is sufficiently high and the
bankTickCtrs saturates, a global useful bit reset is triggered, clearing all
usefulness fields.

Finally, during initialization or when allocating new entries in the TAGE table,
all ctr counters in the entries are set to 0, and all usefulness fields are set
to 0.

Note: The usefulness values corresponding to two branch instructions in the same
prediction block are not necessarily equal. If the first branch prediction of
altpred jumps and the second does not, while the provider's predictions both
jump, only the first u needs to be set to one.

Note: Meta refers to the data used by the predictor during prediction, which is
retrieved during updates for training. It is called meta because the composer
integrates all predictors with a common interface named meta for external
interaction. The specific composition of TAGE's meta is shown in the figure
below:

![TAGE Meta Structure](../figure/BPU/TAGE-SC/tage_meta.png)

### TAGE: Alternative Prediction Logic (USE ALT ON NA)

When the confidence counter ctr of a tag-matched entry is 0, altpred can
sometimes be more accurate than the regular prediction. Thus, a 4-bit counter
useAltCtr is implemented to dynamically decide whether to use the alternative
prediction when the longest-history match lacks confidence. For timing
considerations, the base prediction table's result is always used as the
alternative prediction, resulting in minimal accuracy loss.

The specific implementation of the alternative prediction logic is as follows:

ProviderUnconf indicates insufficient confidence in the longest history match
result. When the ctr value corresponding to the provider is 0b100 or 0b011, it
indicates that the confidence in the longest history match result is sufficient;
at this time, providerUnconf is false. When the ctr value corresponding to the
provider is 0b01 or 0b10, it indicates that the confidence in the longest
history match result is insufficient; at this time, providerUnconf is true.

useAltOnNaCtrs is a counter array consisting of 128 4-bit saturating counters,
each initialized to 0b1000. When TAGE receives a training update request, if in
the prediction being trained, it is found that the provider's prediction result
differs from altpred, and the confidence in the provider's prediction result is
insufficient, then it evaluates whether the alternate prediction result is
correct. If the alternate prediction is correct and the provider is wrong, the
corresponding useAltOnNaCtrs counter value is incremented by 1; if the alternate
prediction is wrong and the provider is correct, the corresponding
useAltOnNaCtrs counter value is decremented by 1. Since useAltOnNaCtrs is a
saturating counter, when its value is already 0b1111 and the case is correct, or
when it is already 0b0000 and the case is wrong, the useAltOnNaCtrs value
remains unchanged.

useAltOnNa is obtained by indexing the useAltOnNaCtrs counter group with pc(7,
1), i.e., the corresponding lower bits of the PC, and taking the highest bit of
the resulting count.

When providerUnconf && useAltOnNa is true, the alternative prediction result
(i.e., the base prediction table's result) is used as the final TAGE prediction
result instead of the provider's prediction result.

### TAGE: wrbypass

Wrbypass contains both Mem and Cam, used to sequence updates. Every TAGE update
is written to this wrbypass and the corresponding prediction table's SRAM.
During each update, the wrbypass is checked. If a hit occurs, the read TAGE ctr
value is used as the old value, discarding the old ctr value brought back from
the backend with the branch instruction. This ensures that if a branch is
updated repeatedly, wrbypass guarantees that one update will always obtain the
final value from the adjacent previous update.

T0 has a corresponding wrbypass, while T1~T4 each have 16. In the wrbypass
corresponding to each prediction table, Mem has 8 entries. For T0, each entry
stores 2 prediction table entries (corresponding to two banks), while for T1~T4,
each entry stores 1 (since the two banks are stored in separate wrbypasses). Cam
also has 8 entries, and inputting the update idx and tag (T0 has no tag)
retrieves the corresponding data's position in Cam. Cam and Mem are written
simultaneously, so the data's position in Cam matches its position in Mem. This
Cam allows checking during updates whether the data for a given idx is in the
wrbypass.

### Storage structure

- There are 4 history tables, each divided into 8 banks based on the lower bits
  of the PC, with each bank containing 256 sets. Each set corresponds to a
  maximum of 2 branches in an FTB entry. Each bank has 512 entries, each table
  has 4096 entries, and all tables combined have 16K entries.
- Each table entry contains 1-bit valid, 8-bit tag, 3-bit ctr, and 1-bit useful;
  the useful bit is stored independently.
- The base table has 2048 sets, with each set containing two branches, each with
  a 2-bit saturating counter, recording a total of 4K branches.
- Each bank of the history table has an 8-entry write buffer wrbypass, and the
  base table has a total of 8-entry wrbypass.
- use_alt_on_na predicts a total of 128 4-bit saturating counters

### Indexing method

- index = pc[11:1] ^ folded_hist(11bit)
- tag = pc[11:1] ^ folded_hist(8bit) ^ (folded_hist(7bit) << 1)
- History uses basic segmented XOR folding
- Two branch instructions per entry, and the two corresponding relationships
  between the two slots of the FTB. The selection is made using pc[1]. Due to
  the establishment mechanism of the FTB entry, the usage rate of the first slot
  will be higher than that of the second. This measure can alleviate this uneven
  distribution.
- The base table and use_alt_on_na directly use the lower bits of the PC for
  indexing.

### Prediction flow

- s0 performs index calculation, sends the address to SRAM, with only the
  corresponding bank enabled.
- In s1, tag matching and bank data selection are performed, along with
  reordering between two slots, to obtain the overall result for each history
  table. These results are passed to the top level for longest-history
  selection. Combined with the use_alt_on_na mechanism, selection is made
  between the longest-history match and the base table (simplifying the original
  algorithm to always use the base table as the alternative prediction). The
  prediction results for each branch are temporarily stored in s2.
- s2 uses the prediction results, compares them with the s1 results within the
  BPU, and determines whether the pipeline needs to be flushed.

### Training flow

![Training flow](../figure/BPU/TAGE-SC/tage_update.svg)

Upon receiving a training request from FTQ, updates are made based on the
information recorded during prediction. The update process is divided into two
pipeline stages, with the first stage evaluating certain update conditions
externally to the history table. Details are as follows:

- Provider update: The longest history table hit during prediction will be
  updated.
  - When the alternative prediction differs from it, the new useful bit is
    determined based on whether the provider is correct.
  - Determine the increment or decrement of ctr based on the actual direction
- alloc: Allocation occurs when there is a misprediction, excluding the
  following cases (the provider is correct, but the wrong alternative prediction
  result was chosen during prediction)
  - During allocation, a mask is generated based on the useful bit information
    recorded in all history tables during prediction. Some bits are randomly
    masked using the LFSR random number. It is then determined whether there are
    any remaining entries in history tables longer than the provider's.
    - If available, use the item with the shortest history
    - If none are available, use the LFSR to mask the allocatable entries with
      the shortest history longer than the provider's before masking.
- Useful reset counter: An 8-bit saturating counter is incremented or
  decremented based on the net success/failure of allocations. If failures
  exceed a saturation threshold, all useful bits are cleared.
  - Let n be the number of history tables longer than the provider. Those with a
    useful bit of 0 are considered successful allocations, while those with a
    useful bit of 1 are considered failures. The difference between the two
    counts serves as the absolute value for this adjustment.
- use_alt_on_na training: when provider's ctr has the two weakest values and the
  alternate prediction and provider directions differ, based on the correctness
  of the alternate prediction, increment or decrement the use_alt_on_na
  saturating counter at the low bits of pc

The second pipeline stage sends update requests into each prediction table,
attempting to write to SRAM.

- The old value of ctr may come from predictions made long ago, possibly vastly
  different from the current state of ctr in the table. To address this issue,
  the wrbypass mechanism is introduced:
  - wrbypass is a fully associative write buffer for the TAGE table. Whenever a
    write is attempted, it first queries this fully associative table based on
    the history table index. If a hit occurs, the corresponding content is
    treated as the old ctr, updated according to the branch direction, and then
    written to both SRAM and wrbypass. If a miss occurs, an entry is selected
    for replacement based on the replacement algorithm.
  - Each bank has a corresponding 8-entry fully associative wrbypass, with a
    total of 64 entries per table.
- Due to the use of single-port SRAM, read and write requests cannot be
  processed simultaneously. To avoid read-write conflicts:
  - Adopting a bank-partitioned approach
  - When saturated and the new value equals the old value, no write is
    performed.
- When read-write conflicts still occur, the write request is processed, but the
  read request is not blocked. The read result is treated as a miss by default,
  which may reduce accuracy.

### SC: Design Concept

In some applications, certain branch behaviors have a weak correlation with
branch history or path, exhibiting a statistical prediction bias. For these
branches, using counter-based methods to capture statistical bias is more
effective than TAGE. TAGE is very effective in predicting highly correlated
branches, but fails to predict branches with statistical bias, such as those
with a slight bias towards one direction but without a strong correlation with
history path.

The purpose of SC statistical correction is to detect less reliable predictions
and recover them. SC is responsible for predicting condition branch instructions
with statistical bias and reversing the TAGE predictor's result in such cases.

### SC: Hardware Implementation

SC maintains 4 prediction tables, with specific parameters detailed in the table
below.

| Serial Number | Number of entries. | ctr length | Folded history length | Design Principles                                       |
| ------------- | ------------------ | ---------- | --------------------- | ------------------------------------------------------- |
| T1            | 512                | 6          | 0                     | GHV takes the XOR of the lower 0 bits starting from ptr |
| T2            | 512                | 6          | 4                     | ghv takes the lower 4 bits of ptr for folded XOR        |
| T3            | 512                | 6          | 8                     | ghv takes the lower 10 bits of ptr, folded and XORed.   |
| T4            | 512                | 6          | 8                     | ghv takes the lower 16 bits of ptr for folded XOR       |

### SC: Prediction Timing

SC receives the prediction result pred and ctr from TAGE, folded branch history
information and PC from BPU, and indexes the SC prediction table based on
((index folded branch history) ^ (lower bits of (pc>>1))). The SC prediction
result ctr, along with TAGE's pred and ctr, dynamically determines (see HasSC)
whether to invert TAGE's prediction.

The specific logic for SC's dynamic determination is as follows:

The SC implements two banks of scThresholds register sets, with two banks
corresponding to TAGE's two banks, both because a prediction block can contain
up to two branch instructions. The dynamically determined register sets in SC
consist solely of these two. Each bank's scThresholds includes a 5-bit
saturating counter ctr (initial value 0b10000) and an 8-bit thres (initial value
6). For distinction, we later refer to TAGE's ctr passed to SC as tage_ctr, SC's
own ctr as sc_ctr, and the ctr in scThresholds as thres_ctr.

scThresholds update: When SC receives training data, if SC flipped TAGE's
prediction result and the signed carry-sum of (sc_ctr_0*2+1) + (sc_ctr_1*2+1) +
(sc_ctr_2*2+1) + (sc_ctr_3*2+1) + (2*(tage_ctr-4)+1)*8, after taking the
absolute value, falls within the range [thres-4, thres-2], then scThresholds is
updated.

- Updating ctr in scThresholds: If the prediction is correct, thres_ctr
  increments by 1; if incorrect, it decrements by 1. If thres_ctr is already
  0b11111 (correct) or 0b00000 (incorrect), it remains unchanged.
- Update of thres in ScThresholds: If the updated value of thres_ctr reaches
  0b11111 and thres <= 31, then thres + 2; if the updated value of thres_ctr is
  0 and thres >= 6, then thres - 2. In all other cases, thres remains unchanged.
- After the Thres update decision, the thres_ctr is checked again. If the
  updated thres_ctr is 0b11111 or 0, it is reset to the initial value of
  0b10000.

Define scTableSums as (sc_ctr_0*2+1) + (sc_ctr_1*2+1) + (sc_ctr_2*2+1) +
(sc_ctr_3*2+1) (signed carry addition), tagePrvdCtrCentered as
(2*(tage_ctr-4)+1)*8 (signed carry addition), and totalSum as scSum + tagePvdr
(signed carry addition). If scTableSums > (signed thres - tagePrvdCtrCentered)
and totalSum is positive, or if scTableSums < (-signed thres -
tagePrvdCtrCentered) and totalSum is negative, the threshold is exceeded, and
TAGE's prediction result is inverted. Otherwise, TAGE's prediction remains
unchanged.

SC's prediction algorithm relies on signals from TAGE, such as whether there is
a history table hit (provided) and the provider's prediction result (taken), to
determine its own prediction. The provided signal is one of the necessary
conditions for using SC prediction, while the provider's taken serves as the
choose bit to select SC's final prediction. This is because SC may yield
different predictions depending on TAGE's varying outcomes.

SC reversing TAGE's prediction result may cause the TAGE table to add new
entries.

SC requires a 3-cycle delay:

- Cycle 0: Generate the addressing index to obtain s0_idx
- 1. Read out the counter data s1_scResps corresponding to s0_idx from the
  SCTable.
- In the second cycle, determine whether the prediction result needs to be
  inverted based on s1_scResps.
- Three cycles to output the complete prediction result.

### SC: Wrbypass

Wrbypass contains both Mem and Cam, used to order updates. Each SC update writes
to this wrbypass as well as to the corresponding prediction table's SRAM. At
every update, the wrbypass is checked; if there is a hit, the read SC's ctr
value is used as the old value, and the previous ctr old value that was carried
with the branch instruction to the backend and sent back to the frontend is
discarded. This way, if a branch is repeatedly updated, the wrbypass can ensure
that a given update always retrieves the final value of the immediately
preceding update.

SC's T1~T4 each have 2 wrbypasses. In the wrbypass of each prediction table, Mem
has 16 entries, each storing 2 entries of the prediction table; Cam has 16
entries, and inputting the updated idx allows reading the corresponding data's
position in Cam. Cam and Mem are written simultaneously, so the data's position
in Cam is also its position in Mem. Using this Cam, we can check whether the
data corresponding to the idx is in the wrbypass during updates.

### SC: Predictor training.

sc_ctr (see signedSatUpdate) is a 6-bit signed saturating counter that
increments by 1 when the instruction is actually taken and decrements by 1 when
not taken, with a counting range of [-32, 31].

Note: meta refers to the data used by the predictor during prediction, which is
retrieved for updates later. All predictors are integrated by the composer using
a common interface called meta for external interaction. The specific
composition of SC's meta is shown in the following diagram:

![SC meta specific composition](../figure/BPU/TAGE-SC/sc_meta.png)

## Overall Block Diagram

![Overall Block Diagram](../figure/BPU/TAGE-SC/structure.png)

## Interface timing

s0 inputs pc and folded history timing example

![PC and Folded History Timing](../figure/BPU/TAGE-SC/port1.png)

The diagram illustrates an example of s0 input PC and folded history timing.
When io_s0_fire is high, the input io_in_bits data is valid.

### Storage structure

- Four tables with history lengths of 0, 4, 10, and 16, each containing 256
  entries. Each entry consists of four 6-bit-wide saturating counters,
  corresponding to two branches * two prediction results (T/NT) of TAGE. Each
  table has a total of 1024 counters, with a storage overhead of 3KB.
- Each table has a 16-entry write buffer (wrbypass).
- Two threshold registers, each corresponding to a branch in a slot. Each
  threshold has an 8-bit-wide threshold saturating counter and a 5-bit
  increment/decrement buffer saturating counter.

### Indexing method

- index = pc[8:1] ^ folded_hist(8bit)
- History uses basic segmented XOR folding
- Two branch instructions per entry, and the two corresponding relationships
  between the two slots of the FTB. The selection is made using pc[1]. Due to
  the establishment mechanism of the FTB entry, the usage rate of the first slot
  will be higher than that of the second. This measure can alleviate this uneven
  distribution.

### Prediction flow

- s0 performs index calculation, and the address is sent to the SRAM.
- s1 reads the saturating counters, performs reordering between slots, and
  transmits the SC ctrs corresponding to TAGE's two prediction results to the
  top level for separate addition. The results are then registered to s2.
- s2 adds SC's ctr with TAGE's provider ctr to obtain the final result, takes
  the absolute value, and if it exceeds the threshold and TAGE also has a hit,
  uses the sign of the addition result as the final predicted direction, stored
  in s3.
- s3 uses the direction result and compares it with the s2 result within the BPU
  to determine whether the pipeline needs to be flushed.

### Training flow

Upon receiving a training request from FTQ, updates are performed based on the
information recorded during prediction. The update process is divided into two
pipeline stages, with the first stage determining certain update conditions
externally to the history table. Details are as follows:

- If TAGE hits during prediction, the old SC ctr and old TAGE ctr saved during
  prediction are added again and compared against the update threshold
  (prediction threshold * 8 + 21). If the sum is below the threshold or the
  prediction result does not match the execution direction, each counter is
  trained according to the perceptron training rules, and the request is
  registered to be sent to each table in the next cycle.

The second pipeline stage sends update requests into each prediction table,
attempting to write to SRAM while still trying to query the write cache wrbypass
for the latest counter value (this could potentially be queried in the previous
pipeline stage rather than directly using the old ctr).

![Training flow](../figure/BPU/TAGE-SC/sc_update.svg)
