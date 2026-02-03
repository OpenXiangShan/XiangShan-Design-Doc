# BPU Submodule TAGE-SC

## Function

TAGE-SC is the main predictor for conditional branches in the Nanhu
architecture, classified as an Accurate Predictor (APD). TAGE leverages multiple
prediction tables with varying history lengths to exploit extremely long branch
history information, while SC serves as a statistical corrector.

TAGE 由一个基预测表和多个历史表组成，基预测表用 PC 索引，而历史表用 PC
和一定长度的分支历史折叠后的结果异或索引，不同历史表使用的分支历史长度不同。在预测时，还会用 PC 和每个历史表对应的分支历史的另一种折叠结果异或计算
tag，与表中读出的 tag 进行匹配，如果匹配成功则该表命中。最终的结果取决于命中的历史长度最长的预测表的结果。

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

- 对于每个预测表中的表项添加了 tag 数据。在传统的优先分支预测器中，往往仅采用分支历史以及当前分支指令的 PC
  值作为依据来对预测表进行取指。这种情况会导致多条不同的分支指令指向同一个预测表表项的情况(aliasing)产生，而这种情况对混合式预测器中采取的分支历史长度较短的部分预测表所给出的分支预测准确率影响尤为显著。因此，在
  TAGE 的设计中，通过 partial tagging 的方法，可以更好地将当前指令与预测表中的表项进行实际的匹配，从而较大程度地避免上述情况的产生。
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

TAGE 是高精度条件分支方向预测器。使用不同长度的分支历史和当前 PC 值寻址多个 SRAM
表，当在多个表中出现命中时，优先选择命中的历史长度最长的对应表项的预测结果作为最终结果。

![TAGE Principle](../figure/BPU/TAGE-SC/principle.png)

The structural schematic of TAGE is shown in the figure above, featuring a
baseline predictor T0 and four tagged prediction tables T1-T4. Basic information
about the baseline predictor and the tagged prediction tables is provided in the
table below.

| **predictor**           | ** with tag** | ** function **                                                                                            | ** entry composition **                                                                    | **item count**                |
| ----------------------- | ------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | ----------------------------- |
| Baseline Predictor T0   | No            | Used to provide prediction results when none of the four local tag prediction tables' tags match.         | ctr is 2 bits (the highest bit provides the prediction result: 1 for jump, 0 for no jump). | set 2048way 2                 |
| Prediction tables T1-T4 | Yes           | When there is a tag match, the one with the longest history is selected to provide the prediction result. | valid 1bit, tag 8bits, ctr 3bits（最高位给出预测结果，1 跳转，0 不跳）us: 1bit（usefulness 计数器）              | T1-T4 each have 4096 entries. |

注：上表中的 way 是 Chisel 里 SRAMTemplate 类的参数名字，这个参数的值表达在 SRAM 里面存储几份同样类型的数据，不一定代表通常意义
上的需要 tag 匹配的 way。T0 有两个 way 是因为预测块内最多两条分支指令，不同的 way 是为了分别对预测块内两条不同的分支指令进行预测。

The prediction contents for the two jump instructions in each prediction block
are stored and updated separately. The 4096 entries of the tagged prediction
tables T1-T4 are evenly divided into two banks for up to two branches per
prediction block, with each bank containing 2048 entries. Thus, the index for
tables T1-T4 is only 11 bits, calculated as log2(number of table entries/2). The
two branch instructions in the same prediction block share the same index but
access different banks, potentially resulting in one hit and one miss when
reading prediction results from both banks simultaneously.

TAGE 类预测器的每一个预测表都有特定的历史长度。为了让原本很长的全局分支历史表能够与 PC 异或后进行预测表的索引或 tag
匹配，原本很长的分支历史序列需要被分成很多段，然后全部异或起来。每一段的长度一般等于历史表深度的对数。由于异或的次数一般较多，为了避免预测路径上多级异或的时延，我们会直接存储折叠后的历史。

Each prediction table has three corresponding folded branch histories: one for
indexing the prediction table and two for tag matching. The BPU module maintains
a 256-bit global branch history ghv and separately maintains folded branch
histories for each of TAGE's four tagged prediction tables. The specific
configuration is shown in the table below (see TageTableInfos), where ghv is a
circular queue, and the "lower" n bits refer to the lower bits starting from the
position indicated by ptr:

| ** history**                             | **index folded branch history length** | **tag folded branch history 1 length** | ** tag folded branch history 2 length** | ** Design principle **                                                |
| ---------------------------------------- | -------------------------------------- | -------------------------------------- | --------------------------------------- | --------------------------------------------------------------------- |
| Global branch history ghv                | 256 bits (non-folded)                  | 无                                      | 无                                       | Each bit represents whether the corresponding branch is taken or not. |
| T1 corresponds to folded branch history  | 8 比特                                   | 8 比特                                   | 7 比特                                    | ghv takes the lower 8 bits of ptr for folded XOR                      |
| T2 corresponds to folded branch history  | 11 比特                                  | 8 比特                                   | 7 比特                                    | ghv takes the lower 13 bits from ptr, folds, and XORs them.           |
| T3 corresponds to folded branch history. | 11 比特                                  | 8 比特                                   | 7 比特                                    | ghv takes the lower 32 bits of ptr for folded XOR                     |
| T4 corresponds to folded branch history  | 11 比特                                  | 8 比特                                   | 7 比特                                    | ghv takes the lower 119 bits from ptr for folded XOR.                 |

![Folded History Actual
Implementation](../figure/BPU/TAGE-SC/folded_history.png)

如上图所示，出于时序考虑，折叠分支历史的具体实现方式并不是设计原理中的折叠，而是把折叠前的分支历史最老的那一位（图中对应 h[12]）和最新的一位（图中对应
h[0]）异或到相应的位置（图中对应 c[1]和 c[4]），再做一个移位操作（图中对应变为 c[0]和 c[2]）即可，伪代码如下所示：

c[0] <= c[4] ^ h[0];

c[1] \&lt;= c[0];

c[2] <= c[1] ^ h[12];

c[3] <= c[2];

c[4] \&lt;= c[3];

分支历史表不只会在后端提交之后更新，s1~s3 中间每一级都有可能更新，更新时更新的是 pointer 和值。如果在 s1~s3 产生了新的结果就会恢复
pointer，更新新的值。但是如果预测没有错误就不会修改（因为之前已经更新过了）。

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

TAGE 表项中包含一个 usefulness 域，当 provider 预测正确而 altpred 预测错误时 provider 的 usefulness 置
1，表示该项是一个有用的项，便不会被训练时的分配算法当作空项分配出去。当 provider 产生的预测被证实为一个正确的预测，且此时的 provider 与
altpred 的预测结果不同，则 provider 的 usefulness 域被置 0； 若分支指令实际是跳转，则将对应 provider 表项的 ctr
计数器自增 1；若分支指令实际是不跳转，则将对应 provider 表项的 ctr 计数器自减 1； 若由于误预测导致 TAGE
表项需要更新，且误预测不是由使用 altpred 而抛弃了正确的 provider 导致的，则说明需要增添表项。但此时并不一定真的能够增添表项。还需要满足
provider 所源自的预测表并非所需历史长度最长的预测表，则此时执行表项增添操作。

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

再举一个例子。在最开始，预测表都是空的，不存在 provider，此时对应的 s1_providers(i)为 0， s1_provideds(i)为
false，则此时 Fill(TageNTables, s1_provideds(i).asUInt)为 0b0000，二者相与取反一定得到 0b1111，说明
T1~T4 都属于所谓的比 provider 历史长度更长的预测表。

The specific steps for adding a new table entry are as follows:

表项增添操作会首先读取所有历史长度长于 provider 的预测表的 usefulness。若此时有某表的 usefulness 域值为 0，则在该表中分配一对
应的表项；若没有找到满足 usefulness 域值为 0 的表，则分配失败。当有多个预测表（如 Tj,Tk 两项）的 usefulness 域均为 0
时，表项的分配概率是随机的，分配的时候随机把某些 table 给 mask 掉，让它不会每次都分配同一个。这个 mask 的具体实现是：待选的历史表中（长度
大于 provider 且 u 为 0 的所有历史表），使用产生的随机数随机将一些表屏蔽掉，如果 maskedEntry 的第一个不可用，那么选没 mask
的第一个。这里的表项分配的随机性是通过 Chisel 的 util 包里的 64 位线性反馈移位寄存器原语 LFSR64 生成伪随机数来实现的，在
verilog 代码中 对应 allocLFSR_lfsr 寄存器。在训练时，用 7bit 饱和计数器 bankTickCtrs
统计分配失败次数-成功次数，当分配失败的次数足够多，bankTickCtrs 计数器计数到满达到饱和时，触发全局 useful bit reset，把所有的
usefulness 域清零。

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

ProviderUnconf 表示最长历史匹配结果的信心不足。当 provider 对应的 ctr 值为 0b100、0b011
时，说明最长历史匹配结果的信心很足，此时 providerUnconf 为 false；当 provider 对应的 ctr 值为 0b01、0b10
时，说明最长历史匹配结果的信心不足，此时 providerUnconf 为 true。

useAltOnNaCtrs 是 128 个 4-bit 饱和计数器构成的计数器组，每个计数器都被初始化为 0b1000。在 TAGE
收到训练更新请求时，如果拿来训练的预测中，发现 provider 的预测结果与 altpred 不同，且 provider
的预测结果信心不足，则讨论备选预测结果是否正确。如果备选预测结果正确而 provider 错误，则对应 useAltOnNaCtrs
计数器的值+1；若备选预测结果错误而 provider 正确，则对应 useAltOnNaCtrs 计数器的值-1。因为 useAltOnNaCtrs
是饱和计数器，所以当 useAltOnNaCtrs 值已经为 0b1111 且正确或已经为 0b0000 且错误时，useAltOnNaCtrs 的值不变。

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

### 存储结构

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

### 索引方式

- index = pc[11:1] ^ folded_hist(11bit)
- tag = pc[11:1] ^ folded_hist(8bit) ^ (folded_hist(7bit) << 1)
- 历史采取基本的分段异或折叠
- 每项两条分支和 FTB 两个 slot 之间的两种对应关系，用 pc[1]选取，由于 FTB 项的建立机制，第一个 slot
  的使用率会大于第二个，此举可以缓解这种分布不均的情况
- The base table and use_alt_on_na directly use the lower bits of the PC for
  indexing.

### 预测流程

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

### 训练流程

![训练流程](../figure/BPU/TAGE-SC/tage_update.svg)

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
- use_alt_on_na 训练：当 provider 的 ctr 为两个最弱的值，且备选预测和 provider 方向不同时，根据备选预测的正确与否，增减
  pc 低 位索引的 use_alt_on_na 饱和计数器

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

一些应用上，一些分支行为与分支历史或路径相关性较弱，表现出一个统计上的预测偏向性。对于这些分支，相比 TAGE，使用计数器捕捉统计偏向的方法更为有效。TAGE
在预测非常相关的分支时非常有效，TAGE 未能预测有统计偏向的分支，例如只对一个方向有小偏差，但与历史路径没有强相关性的分支。

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

Wrbypass 里面有 Mem，也有 Cam，用于给更新做定序，每次 SC 更新时都会写进这个 wrbypass，同时写进对应预测表的
sram。每次更新的时候会查这个 wrbypass，如果 hit 了，那就把读出的 SC 的 ctr 值作为旧值，之前随 branch 指令带到后端再送回前端的
ctr 旧值就不要了。这样如果一个分支重复更新，那 wrbypass 可以保证某一次更新一定能拿到相邻的上一次更新的最终值。

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

### 存储结构

- Four tables with history lengths of 0, 4, 10, and 16, each containing 256
  entries. Each entry consists of four 6-bit-wide saturating counters,
  corresponding to two branches * two prediction results (T/NT) of TAGE. Each
  table has a total of 1024 counters, with a storage overhead of 3KB.
- Each table has a 16-entry write buffer (wrbypass).
- Two threshold registers, each corresponding to a branch in a slot. Each
  threshold has an 8-bit-wide threshold saturating counter and a 5-bit
  increment/decrement buffer saturating counter.

### 索引方式

- index = pc[8:1] ^ folded_hist(8bit)
- 历史采取基本的分段异或折叠
- 每项两条分支和 FTB 两个 slot 之间的两种对应关系，用 pc[1]选取，由于 FTB 项的建立机制，第一个 slot
  的使用率会大于第二个，此举可以缓解这种分布不均的情况

### 预测流程

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

### 训练流程

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

![训练流程](../figure/BPU/TAGE-SC/sc_update.svg)
