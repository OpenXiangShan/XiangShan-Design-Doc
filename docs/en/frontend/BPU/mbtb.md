# Main Btb (mbtb) {#sec:bpu-mbtb}

Mbtb belongs to the S3 precise predictor group. It records metadata such as the position, target address, and branch type of branch instructions, and uses saturating counters to provide a base direction prediction (playing the role of Tage's baseTable).

For convenience, we assume the default parameters below, i.e. a fetch block size of 64B and at most 8 branches inside each 64B region.

We also define the alignment function below, with half-align as the default, i.e. alignment to 32B:

```plaintext
define aligned(addr, alignSize=32):
		return addr & ~(alignSize - 1)
```

## Parameter List {#sec:bpu-mbtb-params}

| Parameter | Default | Description | Requirement |
| ------ | --- | --------- | ------ |
| `NumEntries` | 8192 | Total number of entries | Power of 2 |
| `NumWay` | 4 | Associativity | Power of 2 |
| `NumInternalBank` | 4 | Number of internal banks | Power of 2 |
| `TagWidth` | 16 | Tag width | |
| `TargetWidth` | 20 | Low bits width of the jump target address | |
| `WriteBufferSize` | 4 | Write buffer size | Greater than or equal to `NumWay` |
| `Replacer` | "Lru" | Replacer | "Lru" or "Plru" |
| `TakenCntWidth` | 2 | Saturating counter width | |

## Table Index {#sec:bpu-mbtb-index}

This depends on the parameters. The diagram below shows the default parameter configuration. Please refer to the compile-time output for the actual values.

```plaintext
MainBtb:
	Size(set, way, align, internal): 256 * 4 * 2 * 4 = 8192
	Address fields:
		50| 49..32 | 31..16 | 15...8 | 7.............6 | ...........5 | 4.........0 |
			| unused |    tag | setIdx | internalBankIdx | alignBankIdx | alignOffset |
													| 13...................6 |
													|         replacerSetIdx |
										| 20....................................................1 |
										|                                             targetLower |
																																	| 4.......1 |
																																	|  position |
																															 | 5..........1 |
																															 |  cfiPosition |
```

Where:

- `setIdx`: set index
- `internalBankIdx`: physically split across multiple banks to reduce access conflicts; logically part of the set index and physically the bank index
- `alignBankIdx`: half-align bank index
- `tag`: tag
- `replacerSetIdx`: replacer index, same width as setIdx, but its least significant bit is aligned with `internalBankIdx` to balance area cost and replacement accuracy
- `targetLower`: low bits of the jump target address
- `position`: position of the cfi instruction within the current region; see the [Half-align](#sec:bpu-mbtb-half-align) section
- `cfiPosition`: position of the cfi instruction within the whole fetch block; see the [Half-align](#sec:bpu-mbtb-half-align) section

## Entry Structure {#sec:bpu-mbtb-entry}

- `valid`: whether the entry is valid
- `tag`: tag
- `attribute`: branch attribute, see the [BranchAttribute](index.md#branchattribute-secbpu-constants-branchattribute) section
- `position`: position of the cfi instruction within the current region; see the [Half-align](#sec:bpu-mbtb-half-align) section
- `targetCarry`: carry / borrow flag for the low bits of the jump target, see the [TargetCarry](index.md#targetcarry-secbpu-constants-targetcarry) section
- `targetLowerBits`: low bits of the jump target
- `takenCnt`: saturating counter[^takenCnt]

[^takenCnt]: Logically it is part of the mbtb entry, but it is stored separately in hardware because the other attributes of an entry are usually not updated after allocation, while the saturating counter is updated frequently. This reduces access conflicts and power consumption.

## Hierarchy {#sec:bpu-mbtb-hierarchy}

To decouple functionality and simplify each module, mbtb is divided into multiple layers.

### Top Layer {#sec:bpu-mbtb-hierarchy-top}

- Handles the VecRotate-related logic described in [Half-align](#sec:bpu-mbtb-half-align)
- Generates prediction / training requests for each AlignBank
- Provides aligned interfaces to interact with BPU
- Collects performance events

On the prediction pipeline:

- s0: receives the prediction request from the BPU top level, generates two prediction requests (the current region, i.e. `start`; and the next region, i.e. `start+32`) and sends them to two AlignBanks
- s1: empty pipeline stage for AlignBank alignment
- s2: receives prediction results from AlignBanks, merges them, and sends them back to the BPU top level
- s3: sends replacer update data to AlignBanks, see the [replacer](#sec:bpu-mbtb-replacer) section

On the training pipeline:

- t0: receives the training request from the BPU top level
- t1: generates the required training requests and sends them to the corresponding AlignBanks

The top layer instantiates `NumAlignBank = FetchBlockSize / FetchBlockAlignSize` AlignBanks (2 by default).

### Middle Layer AlignBank {#sec:bpu-mbtb-hierarchy-alignbank}

- Handles transactions inside each half-align bank
- Filters training requests
- Selects the InternalBank that needs to be predicted / trained
- Interacts with the replacer

On the prediction pipeline:

- s0: receives the prediction request from the top layer, selects the InternalBank to be predicted, and sends it to the InternalBank
- s1: receives the prediction result from the InternalBank
- s2: determines whether the prediction hits, filters out-of-range results (`cfiPc` < `startPc`), and sends them back to the top layer
- s3: updates the replacer, see the [replacer](#sec:bpu-mbtb-replacer) section

On the training pipeline:

- t1: receives the training request from the top layer, filters out cases that do not need training (if it hits and the metadata is correct, the entry does not need to be updated; if it hits and is not a conditional branch, the counter does not need to be updated), selects the InternalBank that needs training, and sends it to the InternalBank

The AlignBank instantiates `NumInternalBank` InternalBanks (4 by default) and one replacer.

### Bottom Layer InternalBank {#sec:bpu-mbtb-hierarchy-internalbank}

- Handles actual transactions with the physical SRAMs (`entrySram`, `counterSram`) and the write buffer.

For read requests:

- Cycle 0: receives the read request from the AlignBank and issues the SRAM read request
- Cycle 1: receives the SRAM read response and returns it to the AlignBank

For write requests:

- Cycle 0: receives the write request from the AlignBank and sends it to the write buffer
- Cycle x: when the SRAM is writable (i.e. when there is no current read access to the SRAM), the write buffer writes back to the SRAM.

## Half-align {#sec:bpu-mbtb-half-align}

mbtb uses a Region-BTB format, i.e. the entire address space is partitioned into multiple regions. During prediction, the region index of the current `pc` (or fetch block start address `start`) is used as the lookup index.

The simplest design is to make the region size equal to the maximum fetch block size, but that leads to a problem: when the start address falls in the later part of a region, the available prediction range becomes very small. As shown in the upper part of [@fig:mbtb-half-align], mbtb can only predict branches within the current region, and the valid prediction range is between `start` and `max=aligned(start+64, 64)`.

We might be able to query two adjacent regions simultaneously without introducing an extra SRAM read port by interleaving them. But that would also increase the number of candidate branches too much and make timing closure difficult. As shown in the middle part of [@fig:mbtb-half-align], although `max` is expanded to `aligned(start+128, 64)`, the number of candidate branches that need to be processed (e.g. range checking, invoking predictors such as Tage) doubles from 8 to 16; branches larger than `start+64` exceed the capability of ICache/IFU and are meaningless even if they are predicted.

Reducing the region size appropriately is a better trade-off. XiangShan's half-align sets the region size to half of the fetch block size (32B by default), so `max` becomes `aligned(start+64)`. The difference between it and `start+64` will not exceed 32, maximizing the prediction range without introducing extra candidate branches (we instead restrict each 32B range to at most 4 branches, so the number of candidate branches remains 8). This is shown in the lower part of [@fig:mbtb-half-align].

Of course, we could make the region even smaller, such as 16B (quarter-align?), but that would first increase implementation complexity. Worse, “at most 8 branches within each 64B” and “at most 8/x branches within each 64/x B” are not equivalent: the former allows branches to cluster around particular positions, while the latter requires branches to be distributed more evenly, otherwise utilization drops and replacement pressure increases. Considering all factors, half-align is a good compromise.

![Region design comparison](../figure/BPU/mbtb/half-align-region.png){#fig:mbtb-half-align}

In the implementation, the mbtb top layer partitions the address space into two alignBanks, storing entries whose region indices are odd and even respectively (i.e. `address` divided by 32 is odd or even).

During prediction and training, requests are rotated according to the `alignBankIdx` of `start` (i.e. if the `alignBankIdx` of `start` is 0, `req(0)` goes to `alignBank(1)` and `req(1)` goes to `alignBank(1)`; if `alignBankIdx` is 1, they are swapped), and the `internalBankIdx` of `start` is used as the index inside each alignBank.

> The design of the `VecRotate` class in the code is mainly for parameterization. If there are 4 alignBanks, when `alignBankIdx` is 0, the request indices entering the 4 alignBanks are 0, 1, 2, 3; when `alignBankIdx` is 1, the request indices entering the 4 alignBanks are 3, 0, 1, 2; and so on. See also [utils/VecRotate.md](../../utils/VecRotate.md) and [@sec:utils-vecrotate].

With this design, the `alignBankIdx` bit of the `pc` stored for each cfi instruction in an alignBank is constant, so it does not need to be stored. In other words, the highest bit of `cfiPosition` does not need to be stored. We have: `cfiPosition = Cat(reqIdx, position)`.

![rotate and cfiPosition calculation](../figure/BPU/mbtb/half-align-rotate.png){#fig:mbtb-half-align-rotate}

We do not care about the order of branches output by mbtb, so there is no need to perform a reverse rotate.

## Replacer {#sec:bpu-mbtb-replacer}

Because different alignBanks are mutually exclusive in address space, each alignBank can maintain its own replacer independently.

The replacer uses a configurable Plru / Lru replacement policy. The former has smaller storage overhead (each state is `NumWays - 1` bits), but cannot handle some of the special cases described below; the latter has higher replacement accuracy, but the area cost is quadratic (each state is `NumWays * (NumWays - 1) / 2` bits).

In the early design, the replacer defaulted to Plru, and its update logic was relatively simple:

- On prediction: if a hit is found, update that entry as the most recently used one
- On training: if it hits, update that entry as the most recently used one; otherwise update the victim selected by the replacer (i.e. the least recently used entry) as the most recently used one

However, for the mbtb use case, such a simple design cannot handle branch-dense situations (high associativity pressure). Consider the following disassembly from gcc:

```asm
cbfc2: 212bebb3 sh3add s7, s7, s2
cbfc6: 00093783 ld     a5, 0(s2)
cbfca: 854a     mv     a0, s2
cbfcc: 85a2     mv     a1, s0
cbfce: 0921     addi   s2, s2, 8
cbfd0: 00f4f563 bgeu   s1, a5, cbfda <cselib_invalidate_rtx.lto_priv.0+0xc8>
cbfd4: e8dff0ef jal    ra, cbe60 <cselib_invalidate_mem_1>
cbfd8: d559     beqz   a0, cbf66 <cselib_invalidate_rtx.lto_priv.0+0x54>
cbfda: ff7966e3 bltu   s2, s7, cbfc6 <cselib_invalidate_rtx.lto_priv.0+0xb4>
cbfde: b761     j      cbf66 <cselib_invalidate_rtx.lto_priv.0+0x54>
```

Within this 32B region there are 5 cfi instructions, and the `beqz` at `cbfd8` is a branch that almost never jumps. Therefore, for the default 4-way associativity, it should be barely sufficient (we only need to keep the other 4 frequently taken branches to hit in most cases).

But if we look at the actual behavior of Plru, as shown in [@fig:mbtb-plru-conflict]:

1. Train 3 branches into mbtb in order.
2. In the ideal case, Plru would point to the last free way for the 4th branch to enter.
3. But the code here is a small loop (`cbfda` is a branch jumping to `cbfc6`, i.e. the loop tail), which means there are many prediction updates to the replacer interleaved between training updates.
		- Note that br0, br1, and br2 are all within the current region, so they all hit during prediction
		- Under this situation, the replacer updates way0, way1, and way2 in sequence within one cycle
		- This causes Plru to incorrectly believe that way0 is the least recently used way instead of way3
		- Eventually br3 replaces br0 by mistake during training, and this repeats. br0 and br3 then compete for way0, while way3 remains unused for a long time. The effective associativity drops to 3, which cannot meet the requirement and leads to a large performance regression

![Plru conflict illustration](../figure/BPU/mbtb/plru-conflict.png){#fig:mbtb-plru-conflict}

> To avoid assuming the reader is familiar with Plru, here is a brief explanation: Plru approximates Lru with a binary tree structure. When a node is 0, it means the left subtree was used less recently than the right subtree, and vice versa for 1. On each touch, the nodes along the corresponding path are updated to point to the other subtree. Selecting the victim only requires walking from the root to a leaf according to the node values.

Therefore, mbtb's replacer uses two techniques to relieve associativity pressure:

1. Default to Lru replacement to avoid the limitations of Plru itself.
2. During prediction, do not touch all hit entries anymore, but only touch the entry that is finally predicted[^mbtb-touch-final] to be taken[^mbtb-touch-taken]. This quickly evicts frequently not-taken entries (such as `cbfd8` in the example above) from mbtb, freeing space for other hot branches [^mbtb-touch-fall].

[^mbtb-touch-final]: The prediction synthesized by the BPU top level from mbtb, Tage, and other predictors

[^mbtb-touch-taken]: Including unconditional jumps or branches predicted as taken

[^mbtb-touch-fall]: FallThrough can provide predictions for not-taken branches, so storing them in mbtb is of limited value

