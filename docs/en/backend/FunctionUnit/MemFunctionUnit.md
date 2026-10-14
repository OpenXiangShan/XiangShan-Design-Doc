# MemFunctionUnit

- Version: V2R2A
- Status: OK
- Date: 2026/10/13
- commit: [XSAI e8fb1a14](https://github.com/OpenXiangShan/XSAI/tree/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f)

The scalar memory functional units include ldu, stu, and mou. XSAI adds MLSU0 to the Mem scheduling and execution path to check addresses and parameters for matrix memory control requests. The instructions supported by each functional unit are listed below:

## ldu

table: Instructions supported by ldu fu

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| ldu             | FLD                    | D         | scalar      |
| ldu             | FLW                    | F         | scalar      |
| ldu             | LB                     | I         | scalar      |
| ldu             | LBU                    | I         | scalar      |
| ldu             | LD                     | D         | scalar      |
| ldu             | LH                     | I         | scalar      |
| ldu             | LHU                    | I         | scalar      |
| ldu             | LW                     | I         | scalar      |
| ldu             | LWU                    | I         | scalar      |
| ldu             | HLV.B                  |           | scalar      |
| ldu             | HLV.BU                 |           | scalar      |
| ldu             | HLV.D                  |           | scalar      |
| ldu             | HLV.H                  |           | scalar      |
| ldu             | HLV.HU                 |           | scalar      |
| ldu             | HLV.W                  |           | scalar      |
| ldu             | HLV.WU                 |           | scalar      |
| ldu             | HLVX.HU                |           | scalar      |
| ldu             | HLVX.WU                |           | scalar      |

## stu

Table: Instructions Supported by SDU FU

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| stu             | SB                     | I         | scalar      |
| stu             | SD                     | I         | scalar      |
| stu             | SH                     | I         | scalar      |
| stu             | SW                     | I         | scalar      |
| stu             | FSD                    | D         | scalar      |
| stu             | FSW                    | F         | scalar      |
| stu             | FSH                    | Zfh       | scalar      |
| stu             | CBO_CLEAN              | CBO       | scalar      |
| stu             | CBO_FLUSH              | CBO       | scalar      |
| stu             | CBO_INVAL              | CBO       | scalar      |
| stu             | CBO_ZERO               | CBO       | scalar      |
| stu             | HSV.B                  |           | scalar      |
| stu             | HSV.D                  |           | scalar      |
| stu             | HSV.H                  |           | scalar      |
| stu             | HSV.W                  |           | scalar      |

## mou

Table: Instructions Supported by mou fu

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| mou             | AMOADD_D               | A         | scalar      |
| mou             | AMOADD_W               | A         | scalar      |
| mou             | AMOAND_D               | A         | scalar      |
| mou             | AMOAND_W               | A         | scalar      |
| mou             | AMOMAX_D               | A         | scalar      |
| mou             | AMOMAX_W               | A         | scalar      |
| mou             | AMOMAXU_D              | A         | scalar      |
| mou             | AMOMAXU_W              | A         | scalar      |
| mou             | AMOMIN_D               | A         | scalar      |
| mou             | AMOMIN_W               | A         | scalar      |
| mou             | AMOMINU_D              | A         | scalar      |
| mou             | AMOMINU_W              | A         | scalar      |
| mou             | AMOOR_D                | A         | scalar      |
| mou             | AMOOR_W                | A         | scalar      |
| mou             | AMOSWAP_D              | A         | scalar      |
| mou             | AMOSWAP_W              | A         | scalar      |
| mou             | AMOXOR_D               | A         | scalar      |
| mou             | AMOXOR_W               | A         | scalar      |
| mou             | LR_D                   | A         | scalar      |
| mou             | LR_W                   | A         | scalar      |
| mou             | SC_D                   | A         | scalar      |
| mou             | SC_W                   | A         | scalar      |

## MLSU

MLSU0 receives matrix memory instructions, reads the integer base address, integer stride, and mx dimension state, and carries the mcfg snapshot obtained at decode. MlsUnit maps type_code to element width and connects to DTLB, PMP, the matrix memory queue, and the replay path. It checks translation and permissions for the starting base address, matrix register class, and dimensions, then writes exception information or AMU memory control parameters back to the backend. This check path does not call mcfg's `isSupported`.

Table: Instructions Supported by MLSU

| Category             | Instructions                    | Function                                     |
| -------------------- | ------------------------------- | -------------------------------------------- |
| Ordinary load        | mla, mlb, mlc                   | Load A, B, or accumulator C                  |
| Transpose load       | mla.t, mlb.t, mlc.t             | Transpose during loading                     |
| Ordinary store       | msa, msb, msc                   | Store A, B, or accumulator C                 |
| Transpose store      | msa.t, msb.t, msc.t             | Transpose during storing                     |
| Whole-register load  | mla.whole, mlb.whole, mlc.whole | Load a complete tile or accumulator register |
| Whole-register store | msc.whole                       | Store a complete accumulator register        |

For whole forms, MlsUnit derives dimensions and stride from the physical register geometry. The valid whole Store decode is msc.whole; msa.whole and msb.whole are not connected to the decode table.

The control core can decode all instructions above and generate memory descriptors. CUTE sends every Store descriptor to CML, which reads the data to store from C registers; msa / msb and their transpose forms do not yet have an A / B data store path. See [MLSU](../../memblock/LSU/MLSU.md) for the datapath.

MLSU writes its control results to [AmuCtrlBuffer](../CtrlBlock/AMUCtrlBuffer.md), which sends them to CUTE for data movement after ROB commit. See [MLSU](../../memblock/LSU/MLSU.md) for matrix memory queues, cross-page checks, and translation paths.

See [MlsUnit.scala](https://github.com/OpenXiangShan/XSAI/blob/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f/src/main/scala/xiangshan/mem/pipeline/MlsUnit.scala).
