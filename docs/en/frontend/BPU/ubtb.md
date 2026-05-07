# Micro Btb (ubtb) {#sec:bpu-ubtb}

ubtb belongs to the S1 fast predictor group. It can be regarded as a small, fully associative, register-based mbtb cache (or L0-mbtb), responsible for recording metadata such as branch instruction position, target address, and branch type.

Unlike mbtb / abtb, ubtb adopts an Instruction-BTB design rather than a Region-BTB design. For one startPc, it can provide prediction for at most one branch. Therefore, we want this branch to be taken whenever possible (a not-taken branch can get basic prediction from fallThrough, so recording extra metadata such as branch type in ubtb has limited value). Further, we require all branches trained into ubtb to be taken, and assume they are still taken at prediction time, so no extra saturating counter is needed for direction prediction. See also the explanation of useful in [@sec:bpu-ubtb-replacement] [Replacement Policy](#sec:bpu-ubtb-replacement).

## Parameter List {#sec:bpu-ubtb-params}

| Parameter | Default | Description | Requirement |
| ------ | --- | --------- | ------ |
| `NumEntries` | 32 | Total number of entries | |
| `TagWidth` | 22 | Tag width | |
| `TargetWidth` | 22 | Low-bit width of target address | |
| `UsefulCntWidth` | 2 | Width of the "useful" counter | |
| `Replacer` | "plru" | Replacer | Algorithms supported by rocket-chip ReplacementPolicy, currently including "random", "lru", "plru" |
| `UseFastTrain` | true | Whether to enable fast training. See [@sec:bpu-s1-fast-train] [Fast Training for the S1 Predictor Group](#sec:bpu-s1-fast-train) | |
| `EnableTargetFix` | false | Whether to record target carry/borrow information and fix it up. See [@sec:bpu-target-fix] [Target Address Fix-up](#sec:bpu-target-fix) | |

## Entry Structure {#sec:bpu-ubtb-entry}

- `tag`: tag
- `usefulCnt`: "useful" counter. See [@sec:bpu-ubtb-replacement] [Replacement Policy](#sec:bpu-ubtb-replacement)
- `slot1/2.position`: position of the cfi instruction in the current region (although ubtb itself is not a region-btb, to avoid extra computation logic it still uses the same position semantics as mbtb / abtb)
- `slot1/2.attribute`: branch attributes. See [@sec:bpu-constants-branchattribute] [BranchAttribute](index.md#sec:bpu-constants-branchattribute)
- `slot1/2.target`: low bits of jump target[^target-fix]
- `slot1/2.targetCarry`: carry/borrow marker of low bits of jump target. Only exists when `EnableTargetFix` is true.[^target-fix]
- `slot1.isStaticTarget`: stable jump target (a branch/direct jump with fixed target, or an indirect jump instruction for which no different target has been seen since training), used to determine whether 2-taken training can be applied
- `slot2.valid`: whether the second branch in 2-taken is valid
- `slot2.taken`: whether the second branch in 2-taken is taken

[^target-fix]: See [@sec:bpu-target-fix] [Target Address Fix-up](#sec:bpu-target-fix) for the calculation of target addresses.

## Replacement Policy {#sec:bpu-ubtb-replacement}

ubtb uses a replacement policy that combines a useful counter and replacement algorithm. Each entry has a useful counter indicating how "useful" the entry is; a larger counter value means more useful. During replacement, an entry with useful counter value 0 is selected first. If none exists, one entry is selected by the replacement algorithm (plru by default).

During training, the update policy of the useful counter is:

- On miss (new allocation), initialize to the maximum value
- On prediction error (wrong branch attribute, wrong position, wrong target, or actually not taken)
	- If it has already decreased to 0, treat as miss, allocate a new entry, and initialize to the maximum value
	- Otherwise, decrement by 1
- On correct prediction and taken, increment by 1

With this policy, the useful counter effectively serves as both a valid bit and a taken counter. When useful is 0, the entry is invalid, misses in prediction (predicted taken), and is preferred for replacement during training. When useful is greater than 0, the entry is valid and predicts always-taken. It can be understood as `valid = taken = (useful > 0)`.

## 2-taken {#sec:bpu-ubtb-2-taken}

TODO: not yet implemented in the current RTL version; the design is under discussion
