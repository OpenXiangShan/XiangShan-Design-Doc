# FpFunctionUnit

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

The scalar memory access functional units include ldu, stu, mou; the
instructions supported by each functional unit are listed in the following
table:

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
