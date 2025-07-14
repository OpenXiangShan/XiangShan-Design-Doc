# IntFunctionUnit

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

The integer functional units include jmp, brh, i2f, i2v, f2v, csr, alu, mul,
div, fence, bku; the instructions supported by each functional unit are listed
in the following table:

## jmp

table: jmp fu supported instructions

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| jmp             | AUIPC                  | I         | scalar      |
| jmp             | JAL                    | I         | scalar      |
| jmp             | JALR                   | I         | scalar      |

## brh

Table: Instructions Supported by BRH FU

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| brh             | BEQ                    | I         | scalar      |
| brh             | BNE                    | I         | scalar      |
| brh             | BGE                    | I         | scalar      |
| brh             | BGEU                   | I         | scalar      |
| brh             | BLT                    | I         | scalar      |
| brh             | BLTU                   | I         | scalar      |

## i2f

table: i2f fu supported instructions

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| i2f             | FCVT.S.W               | F         | scalar      |
| i2f             | FCVT.S.WU              | F         | scalar      |
| i2f             | FCVT.S.L               | F         | scalar      |
| i2f             | FCVT.S.LU              | F         | scalar      |
| i2f             | FCVT.D.W               | D         | scalar      |
| i2f             | FCVT.D.WU              | D         | scalar      |
| i2f             | FCVT.D.L               | D         | scalar      |
| i2f             | FCVT.D.LU              | D         | scalar      |
| i2f             | FCVT.H.W               | Zfh       | scalar      |
| i2f             | FCVT.H.WU              | Zfh       | scalar      |
| i2f             | FCVT.H.L               | Zfh       | scalar      |
| i2f             | FCVT.H.LU              | Zfh       | scalar      |

## i2v

table: i2v fu supported instructions

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| i2v             | FMV.D.X                | D         | scalar      |
| i2v             | FMV.W.X                | F         | scalar      |
| i2v             | FMV.H.X                | Zfh       | scalar      |

Additionally, as uops split from vector instructions (for specific splitting
methods, please refer to decode), the supported UopSplitType includes VSET,
VEC_0XV, VEC_VXV, VEC_VXW, VEC_WXW, VEC_WXV, VEC_VXM, VEC_SLIDE1UP,
VEC_SLIDE1DOWN, VEC_SLIDEUP, VEC_SLIDEDOWN, VEC_RGATHER_VX, VEC_US_LDST,
VEC_US_FF_LD, VEC_S_LDST, VEC_I_LDST. Supports:

* integer to vector move

## f2v

table: f2v fu supported instructions

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| f2v             | FLI.H                  | I         | zfa         |
| f2v             | FLI.S                  | I         | zfa         |
| f2v             | FLI.D                  | I         | zfa         |

Additionally, as uops split from vector instructions (for specific splitting
methods, refer to decode), the supported UopSplitTypes are VEC_VFV, VEC_0XV,
VEC_VFW, VEC_WFW, VEC_VFM, VEC_FSLIDE1UP, VEC_FSLIDE1DOWN. Supports:

* floating-point to vector move

## csr

table: csr fu supported instructions

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| csr             | csrrw                  | I         | scalar      |
| csr             | csrrs                  | I         | scalar      |
| csr             | csrrc                  | I         | scalar      |
| csr             | csrrwi                 | I         | scalar      |
| csr             | csrrsi                 | I         | scalar      |
| csr             | csrrci                 | I         | scalar      |
| csr             | ebreak                 | I         | scalar      |
| csr             | ecall                  | I         | scalar      |
| csr             | sret                   | I         | scalar      |
| csr             | mret                   | I         | scalar      |
| csr             | mnret                  | smdt      | scalar      |
| csr             | dret                   | debug     | scalar      |
| csr             | wfi                    |           | scalar      |
| csr             | wrs.nto                | zawrs     | scalar      |
| csr             | wrs.sto                | zawrs     | scalar      |

## ALU

table: ALU FU Supported Instructions

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| ALU             | LUI                    | I         | scalar      |
| ALU             | ADDI                   | I         | scalar      |
| ALU             | ANDI                   | I         | scalar      |
| ALU             | ORI                    | I         | scalar      |
| ALU             | XORI                   | I         | scalar      |
| ALU             | SLTI                   | I         | scalar      |
| ALU             | SLTIU                  | I         | scalar      |
| ALU             | SLL                    | I         | scalar      |
| ALU             | SUB                    | I         | scalar      |
| ALU             | SLT                    | I         | scalar      |
| ALU             | SLTU                   | I         | scalar      |
| ALU             | AND                    | I         | scalar      |
| ALU             | OR                     | I         | scalar      |
| ALU             | XOR                    | I         | scalar      |
| ALU             | SRA                    | I         | scalar      |
| ALU             | SRL                    | I         | scalar      |
| ALU             | SLLI                   | I         | scalar      |
| ALU             | SRLI                   | I         | scalar      |
| ALU             | SRAI                   | I         | scalar      |
| ALU             | ADDIW                  | I         | scalar      |
| ALU             | SLLIW                  | I         | scalar      |
| ALU             | SRAIW                  | I         | scalar      |
| ALU             | SRLIW                  | I         | scalar      |
| ALU             | ADDW                   | I         | scalar      |
| ALU             | SUBW                   | I         | scalar      |
| ALU             | SLLW                   | I         | scalar      |
| ALU             | SRAW                   | I         | scalar      |
| ALU             | SRLW                   | I         | scalar      |
| ALU             | ADD.UW                 | Zba       | scalar      |
| ALU             | SH1ADD                 | Zba       | scalar      |
| ALU             | SH1ADD.UW              | Zba       | scalar      |
| ALU             | SH2ADD                 | Zba       | scalar      |
| ALU             | SH2ADD.UW              | Zba       | scalar      |
| ALU             | SH3ADD                 | Zba       | scalar      |
| ALU             | SH3ADD.UW              | Zba       | scalar      |
| ALU             | SLLI.UW                | Zba       | scalar      |
| ALU             | ANDN                   | Zbb       | scalar      |
| ALU             | ORN                    | Zbb       | scalar      |
| ALU             | XORN                   | Zbb       | scalar      |
| ALU             | MAX                    | Zbb       | scalar      |
| ALU             | MAXU                   | Zbb       | scalar      |
| ALU             | MIN                    | Zbb       | scalar      |
| ALU             | MINU                   | Zbb       | scalar      |
| ALU             | SEXT.B                 | Zbb       | scalar      |
| ALU             | SEXT.H                 | Zbb       | scalar      |
| ALU             | ROL                    | Zbb       | scalar      |
| ALU             | ROLW                   | Zbb       | scalar      |
| ALU             | ROR                    | Zbb       | scalar      |
| ALU             | RORI                   | Zbb       | scalar      |
| ALU             | RORIW                  | Zbb       | scalar      |
| ALU             | RORW                   | Zbb       | scalar      |
| ALU             | ORC.B                  | Zbb       | scalar      |
| ALU             | REV8                   | Zbb       | scalar      |
| ALU             | BCLR                   | Zbs       | scalar      |
| ALU             | BCLRI                  | Zbs       | scalar      |
| ALU             | BEXT                   | Zbs       | scalar      |
| ALU             | BEXTI                  | Zbs       | scalar      |
| ALU             | BINV                   | Zbs       | scalar      |
| ALU             | BINVI                  | Zbs       | scalar      |
| ALU             | BSET                   | Zbs       | scalar      |
| ALU             | BSETI                  | Zbs       | scalar      |
| ALU             | PACk                   | Zbkb      | scalar      |
| ALU             | PACKH                  | Zbkb      | scalar      |
| ALU             | PACKW                  | Zbkb      | scalar      |
| ALU             | BREV8                  | Zbkb      | scalar      |
| ALU             | CZERO.EQZ              | Zicond    | scalar      |
| ALU             | CZERO.NEZ              | Zicond    | scalar      |
| ALU             | MOP.R                  | Zimop     | scalar      |
| ALU             | MOP.RR                 | Zimop     | scalar      |
| ALU             | TRAP                   | I         | scalar      |

## mul

table: mul fu supported instructions

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| mul             | MUL                    | M         | scalar      |
| mul             | MULH                   | M         | scalar      |
| mul             | MULHU                  | M         | scalar      |
| mul             | MULHSU                 | M         | scalar      |
| mul             | MULW                   | M         | scalar      |

## div

table: div fu supported instructions

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| div             | DIV                    | M         | scalar      |
| div             | DIVU                   | M         | scalar      |
| div             | REM                    | M         | scalar      |
| div             | REMU                   | M         | scalar      |
| div             | DIVW                   | M         | scalar      |
| div             | DIVUW                  | M         | scalar      |
| div             | REMW                   | M         | scalar      |
| div             | REMUW                  | M         | scalar      |

## fence

table: fence fu supported instructions

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| fence           | SFENCE.VMA             |           | scalar      |
| fence           | SFENCE.I               |           | scalar      |
| fence           | FENCE                  |           | scalar      |
| fence           | PAUSE                  |           | scalar      |
| fence           | SINVAL.VMA             | Svinval   | scalar      |
| fence           | SFENCE.W.INVAL         | Svinval   | scalar      |
| fence           | SFENCE.INVAL.IR        | Svinval   | scalar      |
| fence           | HFENCE.GVMA            |           | scalar      |
| fence           | HFENCE.VVMA            |           | scalar      |
| fence           | HINVAL.GVMA            |           | scalar      |
| fence           | HINVAL.VVMA            |           | scalar      |

## bku

table: bku fu supported instructions

| Functional Unit | Supported Instructions | Extension | Description |
| --------------- | ---------------------- | --------- | ----------- |
| bku             | CLZ                    | Zbb       | scalar      |
| bku             | CLZW                   | Zbb       | scalar      |
| bku             | CTZ                    | Zbb       | scalar      |
| bku             | CTZW                   | Zbb       | scalar      |
| bku             | CPOP                   | Zbb       | scalar      |
| bku             | CPOPW                  | Zbb       | scalar      |
| bku             | CLMUL                  | Zbc       | scalar      |
| bku             | CLMULH                 | Zbc       | scalar      |
| bku             | CLMULH                 | Zbc       | scalar      |
| bku             | XPERM4                 | Zbkx      | scalar      |
| bku             | XPERM8                 | Zbkx      | scalar      |
| bku             | AES64DS                | Zknd      | scalar      |
| bku             | AES64DSM               | Zknd      | scalar      |
| bku             | AES64IM                | Zknd      | scalar      |
| bku             | AES64KS1I              | Zknd      | scalar      |
| bku             | AES64KS2               | Zknd      | scalar      |
| bku             | AES64ES                | Zkne      | scalar      |
| bku             | AES64ESM               | Zkne      | scalar      |
| bku             | SHA256SIG0             | Zknh      | scalar      |
| bku             | SHA256SIG1             | Zknh      | scalar      |
| bku             | SHA256SUM0             | Zknh      | scalar      |
| bku             | SHA256SUM1             | Zknh      | scalar      |
| bku             | SHA512SIG0             | Zknh      | scalar      |
| bku             | SHA512SIG1             | Zknh      | scalar      |
| bku             | SHA512SUM0             | Zknh      | scalar      |
| bku             | SHA512SUM1             | Zknh      | scalar      |
| bku             | SM4ED0                 | Zksed     | scalar      |
| bku             | SM4ED1                 | Zksed     | scalar      |
| bku             | SM4ED2                 | Zksed     | scalar      |
| bku             | SM4ED3                 | Zksed     | scalar      |
| bku             | SM4KS0                 | Zksed     | scalar      |
| bku             | SM4KS1                 | Zksed     | scalar      |
| bku             | SM4KS2                 | Zksed     | scalar      |
| bku             | SM4KS3                 | Zksed     | scalar      |
| bku             | SM3P0                  | Zksh      | scalar      |
| bku             | SM3P1                  | Zksh      | scalar      |
