# IntFunctionUnit

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

整数功能单元包括 jmp, brh ,i2f ,i2v ,f2v ,csr ,alu ,mul ,div, fence, bku;
每个功能单元支持的指令如下表：

## jmp

table: jmp fu 支持的指令

| 功能单元 | 支持指令  | 扩展  | 描述     |
| ---- | ----- | --- | ------ |
| jmp  | AUIPC | I   | scalar |
| jmp  | JAL   | I   | scalar |
| jmp  | JALR  | I   | scalar |

## brh

table: brh fu 支持的指令

| 功能单元 | 支持指令 | 扩展  | 描述     |
| ---- | ---- | --- | ------ |
| brh  | BEQ  | I   | scalar |
| brh  | BNE  | I   | scalar |
| brh  | BGE  | I   | scalar |
| brh  | BGEU | I   | scalar |
| brh  | BLT  | I   | scalar |
| brh  | BLTU | I   | scalar |

## i2f

table: i2f fu 支持的指令

| 功能单元 | 支持指令      | 扩展  | 描述     |
| ---- | --------- | --- | ------ |
| i2f  | FCVT.S.W  | F   | scalar |
| i2f  | FCVT.S.WU | F   | scalar |
| i2f  | FCVT.S.L  | F   | scalar |
| i2f  | FCVT.S.LU | F   | scalar |
| i2f  | FCVT.D.W  | D   | scalar |
| i2f  | FCVT.D.WU | D   | scalar |
| i2f  | FCVT.D.L  | D   | scalar |
| i2f  | FCVT.D.LU | D   | scalar |
| i2f  | FCVT.H.W  | Zfh | scalar |
| i2f  | FCVT.H.WU | Zfh | scalar |
| i2f  | FCVT.H.L  | Zfh | scalar |
| i2f  | FCVT.H.LU | Zfh | scalar |

## i2v

table: i2v fu 支持的指令

| 功能单元 | 支持指令    | 扩展  | 描述     |
| ---- | ------- | --- | ------ |
| i2v  | FMV.D.X | D   | scalar |
| i2v  | FMV.W.X | F   | scalar |
| i2v  | FMV.H.X | Zfh | scalar |

另外作为向量指令拆分的 uop（具体拆分方式请参考 decode），支持的 UopSplitType 为 VSET，VEC_0XV，VEC_VXV，
VEC_VXW，VEC_WXW， VEC_WXV，VEC_VXM，VEC_SLIDE1UP， VEC_SLIDE1DOWN， VEC_SLIDEUP，
VEC_SLIDEDOWN， VEC_RGATHER_VX， VEC_US_LDST，
VEC_US_FF_LD，VEC_S_LDST，VEC_I_LDST。支持：

* 整数到向量的 move

## f2v

table: f2v fu 支持的指令

| 功能单元 | 支持指令  | 扩展  | 描述  |
| ---- | ----- | --- | --- |
| f2v  | FLI.H | I   | zfa |
| f2v  | FLI.S | I   | zfa |
| f2v  | FLI.D | I   | zfa |

另外作为向量指令拆分的uop（具体拆分方式请参考 decode），支持的 UopSplitType 为 VEC_VFV, VEC_0XV, VEC_VFW,
VEC_WFW, VEC_VFM, VEC_FSLIDE1UP, VEC_FSLIDE1DOWN。支持：

* 浮点到向量的 move

## csr

table: csr fu 支持的指令

| 功能单元 | 支持指令    | 扩展    | 描述     |
| ---- | ------- | ----- | ------ |
| csr  | csrrw   | I     | scalar |
| csr  | csrrs   | I     | scalar |
| csr  | csrrc   | I     | scalar |
| csr  | csrrwi  | I     | scalar |
| csr  | csrrsi  | I     | scalar |
| csr  | csrrci  | I     | scalar |
| csr  | ebreak  | I     | scalar |
| csr  | ecall   | I     | scalar |
| csr  | sret    | I     | scalar |
| csr  | mret    | I     | scalar |
| csr  | mnret   | smdt  | scalar |
| csr  | dret    | debug | scalar |
| csr  | wfi     |       | scalar |
| csr  | wrs.nto | zawrs | scalar |
| csr  | wrs.sto | zawrs | scalar |

## alu

table: alu fu 支持的指令

| 功能单元 | 支持指令      | 扩展     | 描述     |
| ---- | --------- | ------ | ------ |
| alu  | LUI       | I      | scalar |
| alu  | ADDI      | I      | scalar |
| alu  | ANDI      | I      | scalar |
| alu  | ORI       | I      | scalar |
| alu  | XORI      | I      | scalar |
| alu  | SLTI      | I      | scalar |
| alu  | SLTIU     | I      | scalar |
| alu  | SLL       | I      | scalar |
| alu  | SUB       | I      | scalar |
| alu  | SLT       | I      | scalar |
| alu  | SLTU      | I      | scalar |
| alu  | AND       | I      | scalar |
| alu  | OR        | I      | scalar |
| alu  | XOR       | I      | scalar |
| alu  | SRA       | I      | scalar |
| alu  | SRL       | I      | scalar |
| alu  | SLLI      | I      | scalar |
| alu  | SRLI      | I      | scalar |
| alu  | SRAI      | I      | scalar |
| alu  | ADDIW     | I      | scalar |
| alu  | SLLIW     | I      | scalar |
| alu  | SRAIW     | I      | scalar |
| alu  | SRLIW     | I      | scalar |
| alu  | ADDW      | I      | scalar |
| alu  | SUBW      | I      | scalar |
| alu  | SLLW      | I      | scalar |
| alu  | SRAW      | I      | scalar |
| alu  | SRLW      | I      | scalar |
| alu  | ADD.UW    | Zba    | scalar |
| alu  | SH1ADD    | Zba    | scalar |
| alu  | SH1ADD.UW | Zba    | scalar |
| alu  | SH2ADD    | Zba    | scalar |
| alu  | SH2ADD.UW | Zba    | scalar |
| alu  | SH3ADD    | Zba    | scalar |
| alu  | SH3ADD.UW | Zba    | scalar |
| alu  | SLLI.UW   | Zba    | scalar |
| alu  | ANDN      | Zbb    | scalar |
| alu  | ORN       | Zbb    | scalar |
| alu  | XORN      | Zbb    | scalar |
| alu  | MAX       | Zbb    | scalar |
| alu  | MAXU      | Zbb    | scalar |
| alu  | MIN       | Zbb    | scalar |
| alu  | MINU      | Zbb    | scalar |
| alu  | SEXT.B    | Zbb    | scalar |
| alu  | SEXT.H    | Zbb    | scalar |
| alu  | ROL       | Zbb    | scalar |
| alu  | ROLW      | Zbb    | scalar |
| alu  | ROR       | Zbb    | scalar |
| alu  | RORI      | Zbb    | scalar |
| alu  | RORIW     | Zbb    | scalar |
| alu  | RORW      | Zbb    | scalar |
| alu  | ORC.B     | Zbb    | scalar |
| alu  | REV8      | Zbb    | scalar |
| alu  | BCLR      | Zbs    | scalar |
| alu  | BCLRI     | Zbs    | scalar |
| alu  | BEXT      | Zbs    | scalar |
| alu  | BEXTI     | Zbs    | scalar |
| alu  | BINV      | Zbs    | scalar |
| alu  | BINVI     | Zbs    | scalar |
| alu  | BSET      | Zbs    | scalar |
| alu  | BSETI     | Zbs    | scalar |
| alu  | PACk      | Zbkb   | scalar |
| alu  | PACKH     | Zbkb   | scalar |
| alu  | PACKW     | Zbkb   | scalar |
| alu  | BREV8     | Zbkb   | scalar |
| alu  | CZERO.EQZ | Zicond | scalar |
| alu  | CZERO.NEZ | Zicond | scalar |
| alu  | MOP.R     | Zimop  | scalar |
| alu  | MOP.RR    | Zimop  | scalar |
| alu  | TRAP      | I      | scalar |

## mul

table: mul fu 支持的指令

| 功能单元 | 支持指令   | 扩展  | 描述     |
| ---- | ------ | --- | ------ |
| mul  | MUL    | M   | scalar |
| mul  | MULH   | M   | scalar |
| mul  | MULHU  | M   | scalar |
| mul  | MULHSU | M   | scalar |
| mul  | MULW   | M   | scalar |

## div

table: div fu 支持的指令

| 功能单元 | 支持指令  | 扩展  | 描述     |
| ---- | ----- | --- | ------ |
| div  | DIV   | M   | scalar |
| div  | DIVU  | M   | scalar |
| div  | REM   | M   | scalar |
| div  | REMU  | M   | scalar |
| div  | DIVW  | M   | scalar |
| div  | DIVUW | M   | scalar |
| div  | REMW  | M   | scalar |
| div  | REMUW | M   | scalar |

## fence

table: fence fu 支持的指令

| 功能单元  | 支持指令            | 扩展      | 描述     |
| ----- | --------------- | ------- | ------ |
| fence | SFENCE.VMA      |         | scalar |
| fence | SFENCE.I        |         | scalar |
| fence | FENCE           |         | scalar |
| fence | PAUSE           |         | scalar |
| fence | SINVAL.VMA      | Svinval | scalar |
| fence | SFENCE.W.INVAL  | Svinval | scalar |
| fence | SFENCE.INVAL.IR | Svinval | scalar |
| fence | HFENCE.GVMA     |         | scalar |
| fence | HFENCE.VVMA     |         | scalar |
| fence | HINVAL.GVMA     |         | scalar |
| fence | HINVAL.VVMA     |         | scalar |

## bku

table: bku fu 支持的指令

| 功能单元 | 支持指令       | 扩展    | 描述     |
| ---- | ---------- | ----- | ------ |
| bku  | CLZ        | Zbb   | scalar |
| bku  | CLZW       | Zbb   | scalar |
| bku  | CTZ        | Zbb   | scalar |
| bku  | CTZW       | Zbb   | scalar |
| bku  | CPOP       | Zbb   | scalar |
| bku  | CPOPW      | Zbb   | scalar |
| bku  | CLMUL      | Zbc   | scalar |
| bku  | CLMULH     | Zbc   | scalar |
| bku  | CLMULH     | Zbc   | scalar |
| bku  | XPERM4     | Zbkx  | scalar |
| bku  | XPERM8     | Zbkx  | scalar |
| bku  | AES64DS    | Zknd  | scalar |
| bku  | AES64DSM   | Zknd  | scalar |
| bku  | AES64IM    | Zknd  | scalar |
| bku  | AES64KS1I  | Zknd  | scalar |
| bku  | AES64KS2   | Zknd  | scalar |
| bku  | AES64ES    | Zkne  | scalar |
| bku  | AES64ESM   | Zkne  | scalar |
| bku  | SHA256SIG0 | Zknh  | scalar |
| bku  | SHA256SIG1 | Zknh  | scalar |
| bku  | SHA256SUM0 | Zknh  | scalar |
| bku  | SHA256SUM1 | Zknh  | scalar |
| bku  | SHA512SIG0 | Zknh  | scalar |
| bku  | SHA512SIG1 | Zknh  | scalar |
| bku  | SHA512SUM0 | Zknh  | scalar |
| bku  | SHA512SUM1 | Zknh  | scalar |
| bku  | SM4ED0     | Zksed | scalar |
| bku  | SM4ED1     | Zksed | scalar |
| bku  | SM4ED2     | Zksed | scalar |
| bku  | SM4ED3     | Zksed | scalar |
| bku  | SM4KS0     | Zksed | scalar |
| bku  | SM4KS1     | Zksed | scalar |
| bku  | SM4KS2     | Zksed | scalar |
| bku  | SM4KS3     | Zksed | scalar |
| bku  | SM3P0      | Zksh  | scalar |
| bku  | SM3P1      | Zksh  | scalar |
