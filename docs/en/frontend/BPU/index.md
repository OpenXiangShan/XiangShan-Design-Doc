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

### CSR Configuration {#sec:bpu-csr}

Table: Bpu-related CSR list

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
