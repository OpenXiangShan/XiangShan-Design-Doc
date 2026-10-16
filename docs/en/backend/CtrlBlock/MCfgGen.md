# MCfgGen

- Version: V2R2A
- Status: OK
- Date: 2026/10/13
- commit: [XSAI ee268923](https://github.com/OpenXiangShan/XSAI/tree/ee268923b7175d79a9d0183a0181a684ccec9487)

## Glossary of Terms

Table: Terminology Explanation

| Name       | Description                                                                      |
| ---------- | -------------------------------------------------------------------------------- |
| mcfg       | Data-type configuration for one matrix register                                  |
| mcfgArch   | Committed matrix type-configuration table                                        |
| mcfgSpec   | Matrix type-configuration table used by current decoding                         |
| MCfgBuffer | Module that generates configuration updates from ROB commit and walk information |

## Design specifications

- Maintains 8 XLEN-bit configuration entries for 4 tile registers and 4 accumulator registers.
- Supports writes through `msetcfg` and reads of the original value through `mgetcfg`.
- The low 8 configuration bits determine the data type; upper bits are retained and passed through.
- On a redirect, restores the current configuration using architectural configuration and ROB walk information.

## Function

MCfgGen resides in DecodeStage and supplies the mcfg table to DecodeUnit. During execution, `msetcfg` obtains the new configuration from an integer source, blocks subsequent instructions from entering the ROB, and flushes the pipeline after commit. MCfgGen receives the committed value and updates the type table, providing the new configuration when subsequent instructions are decoded again.

Ordinary matrix memory instructions read the configuration entry of their matrix register. Execution determines the element width from the type snapshot. `mmacc` reads the three configuration entries for ms1, ms2, and md. Mma uses these snapshots to check the type combination and generate AMU control information.

## Configuration format

Table: mcfg format

| Bits       | Name      | Description                                         |
| ---------- | --------- | --------------------------------------------------- |
| [3:0]      | type_code | Data-type encoding                                  |
| [7:4]      | table_sel | Type-table selection; currently only 0 is supported |
| [XLEN-1:8] | payload   | Reserved field, stored and read back unchanged      |

Table: Currently legal data-type encodings

| type_code | Type  | type_code | Type          |
| --------- | ----- | --------- | ------------- |
| 0         | int4  | 7         | fp8e5m2       |
| 1         | uint4 | 8         | fp8e4m3       |
| 2         | int8  | 9         | fp16          |
| 3         | uint8 | 10        | bf16          |
| 4         | int32 | 11        | tf32          |
| 5         | nvfp4 | 12        | fp32          |
| 6         | mxfp4 | 13–15     | Unimplemented |

The `Mcfg` functional unit checks the type_code and table_sel of `msetcfg`; illegal encodings cause an illegal-instruction exception. During execution, Mma also checks the A/B/C type combinations enabled by `MatrixIsaParams`. `DefaultMatrixConfig` enables int8/uint8 to int32, matching FP8 types to FP32, and BF16 to FP32.

## State updates

mcfgArch and mcfgSpec both reset to 0. During normal commit, MCfgBuffer selects legal `msetcfg` instructions from ROB commit entries and updates the selected table entries. Multiple updates in the same cycle are processed in commit order, with later updates overriding earlier updates to the same entry.

On entering walk, MCfgGen starts recovery from mcfgArch including the current cycle's commit results, then reconstructs mcfgSpec according to walk information. Walk updates take priority over ordinary mcfgSpec commit updates. DecodeStage pauses instruction acceptance and output during recovery.

MCfgBuffer generates commit/walk configuration updates from ROB entries, while MCfgGen stores the configuration tables. When generating updates, MCfgBuffer selects entries whose isMsetcfg is valid and whose configuration checks pass.

## Interface list

Table: MCfgGen interfaces

| Interface      | Direction | Description                                              |
| -------------- | --------- | -------------------------------------------------------- |
| commitMcfg     | Input     | CommitWidth channels of configuration commit information |
| walkToArchMcfg | Input     | Start recovery from the architectural configuration      |
| walkMcfg       | Input     | CommitWidth channels of configuration walk information   |
| mcfg           | Output    | Configuration table used by current decoding             |

The implementations are in [MCfgGen.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/backend/decode/MCfgGen.scala) and [MCfgBuffer.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/backend/rob/MCfgBuffer.scala).
