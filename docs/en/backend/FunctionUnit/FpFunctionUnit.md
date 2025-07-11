# FpFunctionUnit

- 版本：V2R2
- 状态：OK
- 日期：2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

浮点运算功能单元包括 falu, fmac, fcvt, fDivSqrt; 每个功能单元支持的指令如下表：

## falu

table: falu 支持的指令

| 功能单元 | 支持指令     | 扩展  | 描述     |
| ---- | -------- | --- | ------ |
| falu | FMINM.H  | Zfa | scalar |
| falu | FMINM.S  | Zfa | scalar |
| falu | FMINM.D  | Zfa | scalar |
| falu | FMAXM.H  | Zfa | scalar |
| falu | FMAXM.S  | Zfa | scalar |
| falu | FMAXM.D  | Zfa | scalar |
| falu | FLEQ.H   | Zfa | scalar |
| falu | FLEQ.S   | Zfa | scalar |
| falu | FLEQ.D   | Zfa | scalar |
| falu | FLTQ.H   | Zfa | scalar |
| falu | FLTQ.S   | Zfa | scalar |
| falu | FLTQ.D   | Zfa | scalar |
| falu | FADD.H   | Zfh | scalar |
| falu | FADD.S   | F   | scalar |
| falu | FADD.D   | D   | scalar |
| falu | FSUB.H   | Zfh | scalar |
| falu | FSUB.S   | F   | scalar |
| falu | FSUB.D   | D   | scalar |
| falu | FEQ.H    | Zfh | scalar |
| falu | FEQ.S    | F   | scalar |
| falu | FEQ.D    | D   | scalar |
| falu | FLT.H    | Zfh | scalar |
| falu | FLT.S    | F   | scalar |
| falu | FLT.D    | D   | scalar |
| falu | FLE.H    | Zfh | scalar |
| falu | FLE.S    | F   | scalar |
| falu | FLE.D    | D   | scalar |
| falu | FMIN.H   | Zfh | scalar |
| falu | FMIN.S   | F   | scalar |
| falu | FMIN.D   | D   | scalar |
| falu | FCLASS.H | Zfh | scalar |
| falu | FCLASS.S | F   | scalar |
| falu | FCLASS.D | D   | scalar |
| falu | FSGNJ.H  | Zfh | scalar |
| falu | FSGNJ.S  | F   | scalar |
| falu | FSGNJ.D  | D   | scalar |
| falu | FSGNJX.H | Zfh | scalar |
| falu | FSGNJX.S | F   | scalar |
| falu | FSGNJX.D | D   | scalar |
| falu | FSGNJN.H | Zfh | scalar |
| falu | FSGNJN.S | F   | scalar |
| falu | FSGNJN.D | D   | scalar |

## fmac

table: fmac 支持的指令

| 功能单元 | 支持指令     | 扩展  | 描述     |
| ---- | -------- | --- | ------ |
| fmac | FMUL.H   | Zfh | scalar |
| fmac | FMUL.S   | F   | scalar |
| fmac | FMUL.D   | D   | scalar |
| fmac | FMADD.H  | Zfh | scalar |
| fmac | FMADD.S  | F   | scalar |
| fmac | FMADD.D  | D   | scalar |
| fmac | FMSUB.H  | Zfh | scalar |
| fmac | FMSUB.S  | F   | scalar |
| fmac | FMSUB.D  | D   | scalar |
| fmac | FNMADD.H | Zfh | scalar |
| fmac | FNMADD.S | F   | scalar |
| fmac | FNMADD.D | D   | scalar |
| fmac | FNMSUB.H | Zfh | scalar |
| fmac | FNMSUB.S | F   | scalar |
| fmac | FNMSUB.D | D   | scalar |

## fcvt

table: fcvt 支持的指令

| 功能单元 | 支持指令        | 扩展  | 描述     |
| ---- | ----------- | --- | ------ |
| fcvt | FROUND.H    | zfa | scalar |
| fcvt | FROUND.S    | zfa | scalar |
| fcvt | FROUND.D    | zfa | scalar |
| fcvt | FROUNDX.H   | zfa | scalar |
| fcvt | FROUNDX.S   | zfa | scalar |
| fcvt | FROUNDX.D   | zfa | scalar |
| fcvt | FCVTMOD.W.D | zfa | scalar |
| fcvt | FCVT.W.S    | F   | scalar |
| fcvt | FCVT.WU.S   | F   | scalar |
| fcvt | FCVT.L.S    | F   | scalar |
| fcvt | FCVT.LU.S   | F   | scalar |
| fcvt | FCVT.D.S    | D   | scalar |
| fcvt | FCVT.W.D    | D   | scalar |
| fcvt | FCVT.WU.D   | D   | scalar |
| fcvt | FCVT.L.D    | D   | scalar |
| fcvt | FCVT.LU.D   | D   | scalar |
| fcvt | FCVT.S.D    | D   | scalar |
| fcvt | FCVT.D.S    | D   | scalar |
| fcvt | FCVT.H.S    | Zfh | scalar |
| fcvt | FCVT.S.H    | Zfh | scalar |
| fcvt | FCVT.H.D    | Zfh | scalar |
| fcvt | FCVT.D.H    | Zfh | scalar |
| fcvt | FCVT.W.H    | Zfh | scalar |
| fcvt | FCVT.WU.H   | Zfh | scalar |
| fcvt | FCVT.L.H    | Zfh | scalar |
| fcvt | FCVT.LU.H   | Zfh | scalar |
| fcvt | FMV.X.D     | D   | scalar |
| fcvt | FMV.X.W     | F   | scalar |
| fcvt | FMV.X.H     | Zfh | scalar |

## fDivSqrt

table: fDivSqrt 支持的指令

| 功能单元     | 支持指令    | 扩展  | 描述     |
| -------- | ------- | --- | ------ |
| fDivSqrt | FDIV.H  | Zfh | scalar |
| fDivSqrt | FDIV.S  | F   | scalar |
| fDivSqrt | FDIV.D  | D   | scalar |
| fDivSqrt | FSQRT.H | Zfh | scalar |
| fDivSqrt | FSQRT.S | F   | scalar |
| fDivSqrt | FSQRT.D | D   | scalar |
