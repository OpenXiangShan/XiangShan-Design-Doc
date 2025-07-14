# FpFunctionUnit

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

The floating-point arithmetic functional units include falu, fmac, fcvt,
fDivSqrt; the instructions supported by each functional unit are listed in the
following table:

## falu

Table: Instructions Supported by FALU

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| falu            | FMINM.H                | Zfa       | scalar      |
| falu            | FMINM.S                | Zfa       | scalar      |
| falu            | FMINM.D                | Zfa       | scalar      |
| falu            | FMAXM.H                | Zfa       | scalar      |
| falu            | FMAXM.S                | Zfa       | scalar      |
| falu            | FMAXM.D                | Zfa       | scalar      |
| falu            | FLEQ.H                 | Zfa       | scalar      |
| falu            | FLEQ.S                 | Zfa       | scalar      |
| falu            | FLEQ.D                 | Zfa       | scalar      |
| falu            | FLTQ.H                 | Zfa       | scalar      |
| falu            | FLTQ.S                 | Zfa       | scalar      |
| falu            | FLTQ.D                 | Zfa       | scalar      |
| falu            | FADD.H                 | Zfh       | scalar      |
| falu            | FADD.S                 | F         | scalar      |
| falu            | FADD.D                 | D         | scalar      |
| falu            | FSUB.H                 | Zfh       | scalar      |
| falu            | FSUB.S                 | F         | scalar      |
| falu            | FSUB.D                 | D         | scalar      |
| falu            | FEQ.H                  | Zfh       | scalar      |
| falu            | FEQ.S                  | F         | scalar      |
| falu            | FEQ.D                  | D         | scalar      |
| falu            | FLT.H                  | Zfh       | scalar      |
| falu            | FLT.S                  | F         | scalar      |
| falu            | FLT.D                  | D         | scalar      |
| falu            | FLE.H                  | Zfh       | scalar      |
| falu            | FLE.S                  | F         | scalar      |
| falu            | FLE.D                  | D         | scalar      |
| falu            | FMIN.H                 | Zfh       | scalar      |
| falu            | FMIN.S                 | F         | scalar      |
| falu            | FMIN.D                 | D         | scalar      |
| falu            | FCLASS.H               | Zfh       | scalar      |
| falu            | FCLASS.S               | F         | scalar      |
| falu            | FCLASS.D               | D         | scalar      |
| falu            | FSGNJ.H                | Zfh       | scalar      |
| falu            | FSGNJ.S                | F         | scalar      |
| falu            | FSGNJ.D                | D         | scalar      |
| falu            | FSGNJX.H               | Zfh       | scalar      |
| falu            | FSGNJX.S               | F         | scalar      |
| falu            | FSGNJX.D               | D         | scalar      |
| falu            | FSGNJN.H               | Zfh       | scalar      |
| falu            | FSGNJN.S               | F         | scalar      |
| falu            | FSGNJN.D               | D         | scalar      |

## fmac

table: fmac supported instructions

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| fmac            | FMUL.H                 | Zfh       | scalar      |
| fmac            | FMUL.S                 | F         | scalar      |
| fmac            | FMUL.D                 | D         | scalar      |
| fmac            | FMADD.H                | Zfh       | scalar      |
| fmac            | FMADD.S                | F         | scalar      |
| fmac            | FMADD.D                | D         | scalar      |
| fmac            | FMSUB.H                | Zfh       | scalar      |
| fmac            | FMSUB.S                | F         | scalar      |
| fmac            | FMSUB.D                | D         | scalar      |
| fmac            | FNMADD.H               | Zfh       | scalar      |
| fmac            | FNMADD.S               | F         | scalar      |
| fmac            | FNMADD.D               | D         | scalar      |
| fmac            | FNMSUB.H               | Zfh       | scalar      |
| fmac            | FNMSUB.S               | F         | scalar      |
| fmac            | FNMSUB.D               | D         | scalar      |

## fcvt

table: fcvt supported instructions

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| fcvt            | FROUND.H               | zfa       | scalar      |
| fcvt            | FROUND.S               | zfa       | scalar      |
| fcvt            | FROUND.D               | zfa       | scalar      |
| fcvt            | FROUNDX.H              | zfa       | scalar      |
| fcvt            | FROUNDX.S              | zfa       | scalar      |
| fcvt            | FROUNDX.D              | zfa       | scalar      |
| fcvt            | FCVTMOD.W.D            | zfa       | scalar      |
| fcvt            | FCVT.W.S               | F         | scalar      |
| fcvt            | FCVT.WU.S              | F         | scalar      |
| fcvt            | FCVT.L.S               | F         | scalar      |
| fcvt            | FCVT.LU.S              | F         | scalar      |
| fcvt            | FCVT.D.S               | D         | scalar      |
| fcvt            | FCVT.W.D               | D         | scalar      |
| fcvt            | FCVT.WU.D              | D         | scalar      |
| fcvt            | FCVT.L.D               | D         | scalar      |
| fcvt            | FCVT.LU.D              | D         | scalar      |
| fcvt            | FCVT.S.D               | D         | scalar      |
| fcvt            | FCVT.D.S               | D         | scalar      |
| fcvt            | FCVT.H.S               | Zfh       | scalar      |
| fcvt            | FCVT.S.H               | Zfh       | scalar      |
| fcvt            | FCVT.H.D               | Zfh       | scalar      |
| fcvt            | FCVT.D.H               | Zfh       | scalar      |
| fcvt            | FCVT.W.H               | Zfh       | scalar      |
| fcvt            | FCVT.WU.H              | Zfh       | scalar      |
| fcvt            | FCVT.L.H               | Zfh       | scalar      |
| fcvt            | FCVT.LU.H              | Zfh       | scalar      |
| fcvt            | FMV.X.D                | D         | scalar      |
| fcvt            | FMV.X.W                | F         | scalar      |
| fcvt            | FMV.X.H                | Zfh       | scalar      |

## fDivSqrt

Table: Instructions Supported by fDivSqrt

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| fDivSqrt        | FDIV.H                 | Zfh       | scalar      |
| fDivSqrt        | FDIV.S                 | F         | scalar      |
| fDivSqrt        | FDIV.D                 | D         | scalar      |
| fDivSqrt        | FSQRT.H                | Zfh       | scalar      |
| fDivSqrt        | FSQRT.S                | F         | scalar      |
| fDivSqrt        | FSQRT.D                | D         | scalar      |
