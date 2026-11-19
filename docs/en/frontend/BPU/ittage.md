# Indirect Target Tage (ittage) {#sec:bpu-ittage}

ITTAGE is a precise target predictor in the BPU. It predicts target addresses for indirect jumps other than returns. For an indirect jump such as `jalr`, the fetch path may already have determined whether the instruction will execute and whether the jump will be taken, but the target comes from a register at runtime and may have multiple possible values. ITTAGE uses the PC and path history to select a target from tagged tables with different history lengths, predicting at most one indirect jump per cycle.

ITTAGE adopts TAGE's approach of using multiple history lengths, matching tags, and selecting the provider with the longest history. This section does not repeat these shared concepts. Instead, it focuses on ITTAGE's target representation, prediction selection, training, and allocation.

## Parameter List {#sec:bpu-ittage-params}

| Parameter | Default | Description | Requirement |
| --- | --- | --- | --- |
| `TableInfos` | 5 tables, see below | Specifies only the total number of rows and the history length for each table | Number of rows must be divisible by `NumBanks` |
| `NumBanks` | 2 | Number of banks in each ITTAGE table | Power of 2 |
| `TagWidth` | 9 | Tag width | Greater than 0 |
| `ConfidenceCntWidth` | 2 | Target confidence counter width | At least 2 |
| `UsefulCntWidth` | 1 | Usefulness counter width | Greater than 0 |
| `UseAltOnNaWidth` | 4 | Parameter related to alternate selection; unused by the current selection logic | Greater than 0 |
| `TargetWidth` | 20 | Width of the low target address offset; also defines the region boundary | Greater than 0 |
| `TickWidth` | 8 | Width of the tick counter for usefulness aging | Greater than 0 |
| `TableSramSize` | 128 | Reference physical depth used to configure `FoldedSRAMTemplate` | Power of 2 |
| `TableWriteBufferSize` | 4 | Write buffer depth per bank | Greater than 0 |
| `RegionNums` | 16 | Number of entries in the shared region table | Greater than 0 |
| `RegionPorts` | 2 | Number of region lookup ports used during training | Must be 2 in the current top-level implementation |
| `RegionReplacer` | `"plru"` | Region table replacement policy | `plru`, `lru`, or `random` |

Like TAGE, ITTAGE uses tables with different history lengths for prediction. In XiangShan's Kunminghu architecture, all 5 ITTAGE prediction tables, T0-T4, are tagged tables. The base predictor and tagged prediction tables are summarized below.

| Predictor | Tagged | Function | Entry Structure |
| --- | --- | --- | --- |
| Base predictor | No | Provides a prediction when none of the tagged prediction tables hit | XiangShan ITTAGE does not implement a separate untagged base predictor; it directly uses the mbtb prediction as the base prediction |
| Prediction tables T0-T4 | Yes | When tags match, the matching table with the longest history provides the prediction | `valid`: 1 bit; `tag`: 9 bits; `confidenceCnt`: 2 bits (confidence counter); `usefulCnt`: 1 bit (usefulness counter); `targetOffset`: 24 bits; `paddingBit`: 1 bit (padding) |

The `targetOffset` stored in SRAM is not a complete target address. The high address bits must be read from `RegionWays` or taken from `startPc`, then concatenated with `offset`. See the [@sec:bpu-ittage-target] [Target Address Representation](#sec:bpu-ittage-target) section below.

The Bpu module maintains a global path history register (PHR), which is 532 bits long with the default configuration. Folded histories are maintained for each of the 5 ITTAGE prediction tables using an algorithm similar to TAGE's. The prediction table configurations are listed below:

| Table | `Size` | `HistoryLength` | Number of Sets per Bank |
| --- | ---: | ---: | ---: |
| T0 | 256 | 4 | 128 |
| T1 | 256 | 8 | 128 |
| T2 | 512 | 13 | 256 |
| T3 | 512 | 16 | 256 |
| T4 | 512 | 32 | 256 |

`Size` is the total number of entries in a table. ITTAGE tables do not have multiple ways: each set in a bank contains exactly one entry, so the number of sets per bank is `Size / NumBanks`. The 5 tables contain a total of 2048 directly mapped entries.

## Entry Structure {#sec:bpu-ittage-entry}

Each ITTAGE entry contains:

- `valid`: whether the entry is valid
- `tag`: tag
- `confidenceCnt`: confidence in the stored target
- `targetOffset.offset`: low address offset of the target
- `targetOffset.pointer`: index into the shared region table, 4 bits by default
- `targetOffset.usePcRegion`: whether the high target address bits come directly from `startPc`
- `usefulCnt`: whether the entry should be protected from replacement by a newly allocated entry
- `paddingBit`: padding that aligns the entry width with the SRAM data layout

With the default parameters, the logical target offset is 20 bits wide. Since the least significant bit of a RISC-V instruction address is 0, `PrunedAddr` omits that bit from physical storage. `confidenceCnt` is a 2-bit unsigned saturating counter:

| Value | Meaning |
| ---: | --- |
| 0 | Lowest confidence; use the alternate target if an alternate exists |
| 1 | Low confidence, but still use the provider |
| 2 | Initial value for a newly allocated entry |
| 3 | Highest confidence |

## Hierarchy {#sec:bpu-ittage-design-hierarchy}

ITTAGE consists of three types of modules:

```plaintext
Bpu
 └─ ittage: Ittage
    ├─ tables(0): IttageTable
    ├─ tables(1): IttageTable
    ├─ tables(2): IttageTable
    ├─ tables(3): IttageTable
    ├─ tables(4): IttageTable
    └─ rTable   : RegionWays
```

`Ittage` handles selection across tables and coordinates prediction, training, and performance event collection. Each `IttageTable` handles indexing, SRAM accesses, and updates for its own table. `RegionWays` is shared by all 5 tables and stores the high target address regions.

### Top Layer Ittage {#sec:bpu-ittage-hierarchy-top}

On the prediction pipeline:

- s0: receives `startPc` from Bpu
- s1: receives the folded PHR from Bpu and sends read requests to all ITTAGE tables
- s2: receives the tag match results from the tables, selects the provider and alternate, queries `RegionWays`, and reconstructs the provider and alternate targets
- s3: outputs the final ITTAGE target and training metadata; the Bpu top level decides whether to use the target

On the training pipeline:

- t0: receives the training bundle from Bpu and passes the `IttageMeta` saved at prediction time to the training logic
- t1: selects indirect branches that meet the training conditions, determines updates to the provider, alternate, target, confidence, and usefulness, and attempts allocation on a misprediction

The s0/s1/s2/s3 stages in `Ittage.scala` correspond to the global BPU pipeline stages. `IttageTable.scala` also has its own s0/s1 stages, representing "compute the index and read SRAM" and "receive the SRAM response" respectively. These correspond to the global BPU s1/s2 stages.

The current implementation sets `s1_isIndirect` to the constant `true.B`. Whenever ITTAGE is enabled, requests passing through s1 issue reads to all tables. Whether the top level actually uses the ITTAGE target still depends on the branch attributes and hit results. Source comments describe a possible power optimization that uses information from fast BTBs to suppress unnecessary queries, but this optimization is not currently enabled.

### IttageTable {#sec:bpu-ittage-hierarchy-table}

Each ITTAGE table contains `NumBanks` banks, each implemented as a single-port `FoldedSRAMTemplate`. A prediction request reads only the bank selected by the PC. Writeback requests use the same index computation to locate the bank and set.

For read requests:

- Cycle 0: computes the bank, set, and tag, and issues an SRAM read request to the selected bank
- Cycle 1: receives the entry, checks `valid` and `tag`, and returns confidence, usefulness, and the encoded target to the top level

For write requests:

- `IttageTable` routes the update to the corresponding bank in each table
- The bank's write buffer holds the entry
- When the bank has no read request, the write buffer writes the entry back to SRAM, preventing updates from blocking prediction for an extended period

ITTAGE uses a bitmask to control writes to individual entry fields. Allocation writes the complete entry, while training and usefulness aging can preserve fields that do not need modification. This allows partial updates without first reading the complete entry and merging it with the new data, making it easier to share a single write path.

### RegionWays {#sec:bpu-ittage-hierarchy-region}

`RegionWays` stores the high target address regions and contains `RegionNums` entries. During prediction, each of the 5 ITTAGE tables supplies a region pointer. During training, 2 ports look up the regions of the provider and alternate targets, while 1 port accepts writes associated with new allocations. If the region to be written already exists, its entry is reused. Otherwise, an unused entry or a victim selected by the replacement policy is used.

`RegionWays` uses PLRU replacement by default and can be configured to use LRU or random replacement. The replacer is updated only when the Ittage top level issues a write request to `RegionWays`.

`RegionWays` is a shared structure with high access bandwidth. Different ITTAGE entries can therefore store independent low target address bits while sharing the same index for the high target address bits.

## Target Address Representation {#sec:bpu-ittage-target}

The target address is split into:

```plaintext
target = target region || TargetWidth low offset bits
```

The default is `TargetWidth = 20`, so an entry mainly stores a 20-bit low offset and a 4-bit region pointer instead of a complete virtual address.

The complete `GuardedPc` layout can be written as:

```plaintext
| guard(1) | target region(VAddrBits - 20) | targetOffset(20 logical bits) |
                                  The least significant offset bit is omitted in PrunedAddr storage
```

Prediction distinguishes two cases for the high address bits:

1. `usePcRegion = 1`: the target is in the same high address region as the current fetch block, so the high address region of `s2_startPc` is used directly
2. `usePcRegion = 0`: the region pointer is used to read `RegionWays`, and the returned region is concatenated with the offset

For example:

```plaintext
entry.offset      = 20'h45678
entry.pointer     = 3
entry.usePcRegion = 0
RegionWays[3]     = R

target = R || 20'h45678
```

If the region entry referenced by the pointer in `RegionWays` is invalid, or if the entry explicitly uses the current PC region, the high target address bits are taken from the region of `s2_startPc`. The final target also includes the `GuardedPc` overflow guard bit for checking crossings of valid virtual address boundaries.

During training, if the actual target is in a different region from `startPc` and at least one new entry is allocated, the training logic writes the actual target region to `RegionWays` and stores the resulting pointer in the new or updated entries. Otherwise, setting `usePcRegion = 1` is sufficient.

Note that in the current implementation, `updateRealTargetOffset.usePcRegion` is also set to 1 when no new entry is allocated in any table, even if the actual target is in a different region from `startPc`. Therefore, if a provider or alternate entry writes a new `targetOffset` because its confidence was 0 before the update, but no new entry is allocated in that training operation, the encoding still reconstructs the high target address bits from the PC region and cannot guarantee recovery of the actual target region.

## Prediction Selection {#sec:bpu-ittage-design-select}

A table hits when `valid && storedTag == calculatedTag`. Selection across tables follows the same rules as TAGE:

- The hitting table with the longest history is the provider
- The hitting table with the second-longest history is the alternate
- If no table hits, ITTAGE reports a miss

The current ITTAGE target selection logic is:

```plaintext
if provider.valid:
    if provider.confidenceCnt == 0 && alternate.valid:
        target = alternate.target
    else:
        target = provider.target
else:
    miss
```

The alternate is considered only when confidence is exactly 0. Since a new entry is initialized to 2, it uses its own target when it first becomes the provider after allocation. If there is no alternate, the provider target is used even when its confidence is 0.

`Parameters.scala` retains `UseAltOnNaWidth`, and `Ittage.scala` declares a `useAltOnNa` register, but the current selection logic neither reads nor updates this register. Switching between targets is controlled by the provider confidence counter.

`prediction.hit` means that ITTAGE has at least one valid provider; it does not mean that the ITTAGE target will necessarily be used. The Bpu top level also considers the branch attributes and RAS selection when deciding whether to use it.

## Training and Allocation {#sec:bpu-ittage-design-train}

ITTAGE training accepts only executed indirect branches that meet the following condition:

```plaintext
needIttage = isIndirect && !hasPop
```

Return-type jumps are therefore handled by the RAS, while ITTAGE primarily trains other indirect jumps.

### Provider Update {#sec:bpu-ittage-train-provider}

If the provider target equals the actual target, confidence is incremented by 1; otherwise, it is decremented by 1. Both operations use a 2-bit saturating counter, so the value cannot exceed 3 or fall below 0.

The stored target is updated with hysteresis. When confidence is not 0, an incorrect target primarily causes confidence to decrease. A new target offset is written only in either of the following cases:

- The entry is newly allocated
- The entry's confidence was already 0 before the update

This prevents an occasional target change from immediately overwriting an established mapping. The entry switches to a new target only after repeated evidence that the old target is unreliable.

If the alternate was used because the provider confidence was 0 and the final prediction was incorrect, training also updates the alternate's confidence and target state. If there is no alternate or the two targets are identical, the provider's `usefulCnt` is preserved. If the targets differ, the provider's `usefulCnt` depends on whether the provider target is correct.

### Allocation After a Misprediction {#sec:bpu-ittage-train-alloc}

An allocation candidate must satisfy all of the following conditions:

1. The table did not hit during the lookup
2. The entry read from the set at prediction time had `usefulCnt = 0`
3. The table has a longer history than the provider; if there is no provider, all tables are eligible candidates

A 15-bit LFSR mask is used to randomly select among candidate tables, reducing the bias toward always allocating in the same table. If the random mask selects no candidate, selection falls back to the candidate with the lowest index. The allocation candidate is selected in prediction stage s2 and saved in `meta`; training reads and uses the candidate directly from `meta`. A new entry stores the actual target, with confidence initialized to 2 and usefulness initialized to 0.

If the provider stored the correct target but an incorrect alternate was used because the provider confidence was 0, the current implementation suppresses allocation. This is a provider/alternate selection problem and does not require copying the same target into a table with a longer history.

### Replacement and Aging {#sec:bpu-ittage-design-replacer}

ITTAGE tables are directly mapped, with no multiway replacer within a set. The provider and allocation rules handle selection across tables with different history lengths. Within a set, tags, usefulness, and allocation on mispredictions handle conflicts.

`usefulCnt` prevents new targets from frequently overwriting entries that are still useful. If usefulness remains 1, the candidate set may be exhausted. On a relevant misprediction, the training logic increments an 8-bit tick counter if entry allocation fails and decrements it if allocation succeeds. When the counter saturates, each table scans its sets in batches and clears the usefulness field[^usefulCnt-update]. This aging process does not change confidence or targets.

[^usefulCnt-update]: Usefulness aging requests are controlled by `usefulCanReset`. Aging advances by one set only when there is neither a prediction read nor a normal update write request. `resetSet` selects the set to be aged.

Replacement in `RegionWays` is independent of the ITTAGE tables. It uses the PLRU, LRU, or random policy configured by `RegionReplacer` and reuses existing region values, allowing multiple entries to point to the same region entry.
