# XiangShan Bpu Design Document {#sec:bpu-index}

- Version: V3
- Status: draft
- Date: 2026/04/22
- commit: TODO

## Glossary of Terms {#sec:bpu-glossary}

| Abbreviation | Full name | Description |
| --- | --------- | ------------ |
| cfi | Control Flow Instruction | Including branches (e.g. `bne`) and jump instructions (e.g. `j`) |
| BTB | Branch Target Buffer | A cache structure that stores the target addresses and some metadata of branch instructions. |

## Submodule List {#sec:bpu-submodules}

| Submodule | Description |
| --- | --------- |
| [FallThrough](fallThrough.md) | S1, always predict not-taken. Provides a prediction result when all other predictors miss or predict not-taken. |
| [Ubtb](ubtb.md) | Micro Btb, S1, a small BTB implemented with registers, providing branch information. |
| [Abtb](abtb.md) | Ahead Btb, S1, a medium-sized BTB implemented with ahead-pipeline techniques, providing branch information. |
| [Utage](utage.md) | Micro Tage, S1, a small Tage, providing direction prediction. |
| [Mbtb](mbtb.md) | Main Btb, S3, the main BTB, providing more accurate branch information. |
| [Tage](tage.md) | TAgged GEometic History Length predictor, S3, providing more accurate direction prediction. |
| [Sc](sc.md) | Statistical Corrector, S3, correcting Tage predictions using statistical patterns. |
| [Ittage](ittage.md) | Indirect Target Tage, S3, indirect branch target predictor, providing indirect jump target prediction. |
| [Ras](ras.md) | Return Address Stack, S3, return address predictor, providing return address prediction. |
| [History Register](history.md) | Registers that store branch history information, used by Tage and other predictors to index storage structures. |
| [Saturate Counter](saturateCounter.md) | Saturating counter utilities used by the predictors. |

## Design Specification {#sec:bpu-design-spec}

## Parameter List {#sec:bpu-params}

## Functional Overview {#sec:bpu-functional-overview}

## Functional Details {#sec:bpu-functional-details}

### Fast Training for the S1 Predictor Group {#sec:bpu-s1-fast-train}

Under the overriding architecture, the S3 predictor group checks and corrects results from the S1 predictor group. This also means the S1 predictor group can be trained by backend execution units like the S3 predictor group, and can also be fast-trained by the S3 predictor group (similar to using them as a cache for the accurate S3 predictors). The former is more accurate, while the latter is more timely, and they may differ in overall IPC.

For each predictor specifically:

- ubtb: controlled by the `EnableFastTrain` parameter to enable fast training. Early evaluation shows some performance gain from fast training, so its default value is true.
- abtb: due to the ahead-pipeline design, abtb needs more pipeline information for training, so backend training is not possible and only fast training is supported.
- utage: TODO

### Target Address Fix-up {#sec:bpu-target-fix}

To save storage area, BTB structures do not store the full 50-bit (Sv48x4) target virtual address. Instead, only lower bits are stored (see each BTB parameter list). According to the ISA manual:

- branch: target is pc + offset, where offset is a 12-bit immediate, so only the low 14 bits of the target need to be stored (offset needs a low-bit appended 0, and carry/borrow of upper bits must also be tracked)
- jal: target is pc + offset, where offset is a 20-bit immediate, so only the low 22 bits of the target need to be stored (same as above)
- jalr: target is from a register value. Storing only low bits may cause misprediction, but we accept this trade-off to balance hardware cost and performance gain

During prediction, we directly concatenate "the high bits of fetch-block start address" with "the stored low bits of target address", which yields the correct target in most cases. However, exceptions exist at region boundaries due to carry/borrow. For example, if only low 12 bits are stored, and fetch-block start address `startPc = 0x12345ffe`, `offset = +0x20`, then the target is `0x1234601e`, but the stored 12-bit low part is `0x01e`; simple concatenation gives `0x1234501e`.

To solve this, we introduce a 2-bit `targetCarry` flag to record whether carry/borrow exists, and fix up the concatenation result during prediction. This function can be enabled/disabled by the BTB parameter `EnableTargetFix`. As analyzed above for jump ranges of each instruction type, cases requiring fix-up should be theoretically rare, and in principle can be further avoided by compiler instruction layout optimization. Therefore this extra 2-bit/entry overhead may not be worthwhile. In our early evaluation, no obvious performance gain was observed, so the default value of this function is false.

See also [@sec:bpu-constants-targetcarry] [TargetCarry](index.md#sec:bpu-constants-targetcarry) for the definition of `targetCarry` flag values.

### CSR Configuration {#sec:bpu-csr}

Table: Bpu-related CSR list {#tbl:bpu-csr}

+---------+-------+----------+------+----------------------------------------------------------------------+
| Reg     | Addr  | Reset    | Attr | Description                                                          |
+=========+=======+==========+======+======================================================================+
| sbpctl  | 0x5C0 | 64'd0    | RW   | bit0: ubtb enable signal                                             |
|         |       |          |      |                                                                      |
|         |       |          |      | bit1: abtb enable signal                                             |
|         |       |          |      |                                                                      |
|         |       |          |      | bit2: mbtb enable signal                                             |
|         |       |          |      |                                                                      |
|         |       |          |      | bit3: Tage enable signal                                             |
|         |       |          |      |                                                                      |
|         |       |          |      | bit4: Sc enable signal                                               |
|         |       |          |      |                                                                      |
|         |       |          |      | bit5: Ittage enable signal                                           |
|         |       |          |      |                                                                      |
|         |       |          |      | bit6: Ras enable signal                                              |
|         |       |          |      |                                                                      |
|         |       |          |      | Note that although this register can be configured arbitrarily,      |
|         |       |          |      | there are dependencies between predictors, for example:              |
|         |       |          |      |                                                                      |
|         |       |          |      | - Tage, Sc, Ittage, and Ras depend on mbtb;                          |
|         |       |          |      |                                                                      |
|         |       |          |      | - Sc depends on Tage.                                                |
|         |       |          |      |                                                                      |
|         |       |          |      | When a predictor's dependency is disabled, the predictor itself is   |
|         |       |          |      | also disabled, but this **will not** be reflected in the value of    |
|         |       |          |      | this CSR.                                                            |
+---------+-------+----------+------+----------------------------------------------------------------------+

Note: RO means read-only register; RW means read-write register.

### Constant Types {#sec:bpu-constants}

#### BranchAttribute {#sec:bpu-constants-branchattribute}

Used to represent branch attributes. It has the following two fields:

- `.branchType`: branch type
    - `0`: non-branch instruction / invalid entry
    - `1`: conditional branch (e.g. `bne`)
    - `2`: direct jump (e.g. `jal`)
    - `3`: indirect jump (e.g. `jalr`)
- `.rasAction`: RAS action, see the RISC-V ISA manual for Return-address stack prediction hints
    - `0`: no action (non-branch instruction, invalid entry, conditional branch)
    - `1`: pop (return, e.g. `jalr zero, offset(ra)`)
    - `2`: push (call, e.g. `jal ra, offset`)
    - `3`: pop and push (return and call, e.g. `jalr ra, offset(ra)`)

#### TargetCarry {#sec:bpu-constants-targetcarry}

Used to represent the carry / borrow flag of the low bits of a jump target address:

- `0`: fit, i.e. no carry / borrow, `target = Cat(targetUpper, targetLower)`
- `1`: overflow, requires carry, i.e. `target = Cat(targetUpper + 1, targetLower)`
- `2`: underflow, requires borrow, i.e. `target = Cat(targetUpper - 1, targetLower)`

See also [@sec:bpu-target-fix] [Target Address Fix-up](#sec:bpu-target-fix) for usage of this flag.

## References {#sec:bpu-references}

1. Reinman G, Austin T, Calder B. A scalable front-end architecture for fast instruction delivery[J]. ACM SIGARCH Computer Architecture News, 1999, 27(2): 234-245.
2. Perais A, Sheikh R, Yen L, et al. Elastic instruction fetching[C]//2019 IEEE International Symposium on High Performance Computer Architecture (HPCA). IEEE, 2019: 478-490.
3. Software Optimization Guide for AMD Family 19h Processors (PUB), Chap. 2.8.1.5, <https://www.amd.com/system/files/TechDocs/56665.zip>
4. Seznec A, Michaud P. A case for (partially) TAgged GEometric history length branch prediction[J]. The Journal of Instruction-Level Parallelism, 2006, 8: 23.
5. Seznec A. A 256 kbits l-tage branch predictor[J]. Journal of Instruction-Level Parallelism (JILP) Special Issue: The Second Championship Branch Prediction Competition (CBP-2), 2007, 9: 1-6.
6. Seznec A. A new case for the tage branch predictor[C]//Proceedings of the 44th Annual IEEE/ACM International Symposium on Microarchitecture. 2011: 117-127.
7. Seznec A. The O-GEHL branch predictor[J]. The 1st JILP Championship Branch Prediction Competition (CBP-1), 2004.
8. Jiménez D A, Lin C. Dynamic branch prediction with perceptrons[C]//Proceedings HPCA Seventh International Symposium on High-Performance Computer Architecture. IEEE, 2001: 197-206.
9. Seznec A. A 64-Kbytes ITTAGE indirect branch predictor[C]//JWAC-2: Championship Branch Prediction. 2011.
