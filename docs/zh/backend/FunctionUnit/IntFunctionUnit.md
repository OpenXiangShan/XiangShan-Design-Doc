# IntFunctionUnit

- 版本：V2R2A
- 状态：OK
- 日期：2026/10/13
- commit：[XSAI e8fb1a14](https://github.com/OpenXiangShan/XSAI/tree/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f)

整数功能单元包括 jmp, brh, i2f, i2v, f2v, csr, alu, mul, div, fence, bku，以及矩阵扩展增加的规模设置、类型配置和 release 请求生成单元。矩阵乘加与置零请求在 Mf 执行块中生成，见 [MatrixFunctionUnit](./MatrixFunctionUnit.md)。每个功能单元支持的指令如下表：

## jmp

table: jmp fu 支持的指令

| 功能单元 | 支持指令 | 扩展 | 描述   |
| -------- | -------- | ---- | ------ |
| jmp      | AUIPC    | I    | scalar |
| jmp      | JAL      | I    | scalar |
| jmp      | JALR     | I    | scalar |

## brh

table: brh fu 支持的指令

| 功能单元 | 支持指令 | 扩展 | 描述   |
| -------- | -------- | ---- | ------ |
| brh      | BEQ      | I    | scalar |
| brh      | BNE      | I    | scalar |
| brh      | BGE      | I    | scalar |
| brh      | BGEU     | I    | scalar |
| brh      | BLT      | I    | scalar |
| brh      | BLTU     | I    | scalar |

## i2f

table: i2f fu 支持的指令

| 功能单元 | 支持指令  | 扩展 | 描述   |
| -------- | --------- | ---- | ------ |
| i2f      | FCVT.S.W  | F    | scalar |
| i2f      | FCVT.S.WU | F    | scalar |
| i2f      | FCVT.S.L  | F    | scalar |
| i2f      | FCVT.S.LU | F    | scalar |
| i2f      | FCVT.D.W  | D    | scalar |
| i2f      | FCVT.D.WU | D    | scalar |
| i2f      | FCVT.D.L  | D    | scalar |
| i2f      | FCVT.D.LU | D    | scalar |
| i2f      | FCVT.H.W  | Zfh  | scalar |
| i2f      | FCVT.H.WU | Zfh  | scalar |
| i2f      | FCVT.H.L  | Zfh  | scalar |
| i2f      | FCVT.H.LU | Zfh  | scalar |

## i2v

table: i2v fu 支持的指令

| 功能单元 | 支持指令 | 扩展 | 描述   |
| -------- | -------- | ---- | ------ |
| i2v      | FMV.D.X  | D    | scalar |
| i2v      | FMV.W.X  | F    | scalar |
| i2v      | FMV.H.X  | Zfh  | scalar |

另外作为向量指令拆分的 uop（具体拆分方式请参考 decode），支持的 UopSplitType 为 VSET，VEC_0XV，VEC_VXV， VEC_VXW，VEC_WXW， VEC_WXV，VEC_VXM，VEC_SLIDE1UP， VEC_SLIDE1DOWN， VEC_SLIDEUP， VEC_SLIDEDOWN， VEC_RGATHER_VX， VEC_US_LDST， VEC_US_FF_LD，VEC_S_LDST，VEC_I_LDST。支持：

* 整数到向量的 move

## f2v

table: f2v fu 支持的指令

| 功能单元 | 支持指令 | 扩展 | 描述 |
| -------- | -------- | ---- | ---- |
| f2v      | FLI.H    | I    | zfa  |
| f2v      | FLI.S    | I    | zfa  |
| f2v      | FLI.D    | I    | zfa  |

另外作为向量指令拆分的uop（具体拆分方式请参考 decode），支持的 UopSplitType 为 VEC_VFV, VEC_0XV, VEC_VFW, VEC_WFW, VEC_VFM, VEC_FSLIDE1UP, VEC_FSLIDE1DOWN。支持：

* 浮点到向量的 move

## csr

table: csr fu 支持的指令

| 功能单元 | 支持指令 | 扩展  | 描述   |
| -------- | -------- | ----- | ------ |
| csr      | csrrw    | I     | scalar |
| csr      | csrrs    | I     | scalar |
| csr      | csrrc    | I     | scalar |
| csr      | csrrwi   | I     | scalar |
| csr      | csrrsi   | I     | scalar |
| csr      | csrrci   | I     | scalar |
| csr      | ebreak   | I     | scalar |
| csr      | ecall    | I     | scalar |
| csr      | sret     | I     | scalar |
| csr      | mret     | I     | scalar |
| csr      | mnret    | smdt  | scalar |
| csr      | dret     | debug | scalar |
| csr      | wfi      |       | scalar |
| csr      | wrs.nto  | zawrs | scalar |
| csr      | wrs.sto  | zawrs | scalar |

`minit` 由 csr 单元执行，将 mstatus.MS 置为 Initial，矩阵数据、mcfg 表和同步计数器保持原值。矩阵上下文状态的更新路径见 [CSR](../CSR.md#sec:matrix-context)。

## 矩阵配置与 release

Table: 整数执行资源中的矩阵功能单元

| 功能单元 | 指令 | 输入与结果 | 默认执行资源 |
| -------- | ---- | ---------- | ------------ |
| MSetMtilexRiWmf | msettilem/n/k、msettilemi/msettileni/msettileki | 整数或 10 位无符号立即数写对应 mx 物理寄存器 | MSET0 |
| Mcfg | msetcfg | 检查整数源中的 type_code、table_sel，将原始配置写回 ROB | BJU3 |
| Mcfg | mgetcfg | 译码阶段取得的 mcfg 原始值快照写整数 rd | BJU3 |
| Mrelease | mrelease | 将同步计数器索引封装为 AMU release 请求 | MRELEASE |

规模设置原样写入 XLEN 位状态，规模合法性由使用 M/N/K 的功能单元检查。`msetcfg` 的新值通过 ROB 中的 MCfgBuffer 提交，提交后刷新流水线，使后继指令重新取得配置；配置表的推测状态与恢复见 [MCfgGen](../CtrlBlock/MCfgGen.md)。

Mrelease 的 FU 延迟配置为 CertainLatency(0)。生成的请求写回 [AmuCtrlBuffer](../CtrlBlock/AMUCtrlBuffer.md)，在 ROB 提交后送往 CUTE；CUTE 完成返回时，Fence 更新对应的同步计数器。

## alu

table: alu fu 支持的指令

| 功能单元 | 支持指令  | 扩展   | 描述   |
| -------- | --------- | ------ | ------ |
| alu      | LUI       | I      | scalar |
| alu      | ADDI      | I      | scalar |
| alu      | ANDI      | I      | scalar |
| alu      | ORI       | I      | scalar |
| alu      | XORI      | I      | scalar |
| alu      | SLTI      | I      | scalar |
| alu      | SLTIU     | I      | scalar |
| alu      | SLL       | I      | scalar |
| alu      | SUB       | I      | scalar |
| alu      | SLT       | I      | scalar |
| alu      | SLTU      | I      | scalar |
| alu      | AND       | I      | scalar |
| alu      | OR        | I      | scalar |
| alu      | XOR       | I      | scalar |
| alu      | SRA       | I      | scalar |
| alu      | SRL       | I      | scalar |
| alu      | SLLI      | I      | scalar |
| alu      | SRLI      | I      | scalar |
| alu      | SRAI      | I      | scalar |
| alu      | ADDIW     | I      | scalar |
| alu      | SLLIW     | I      | scalar |
| alu      | SRAIW     | I      | scalar |
| alu      | SRLIW     | I      | scalar |
| alu      | ADDW      | I      | scalar |
| alu      | SUBW      | I      | scalar |
| alu      | SLLW      | I      | scalar |
| alu      | SRAW      | I      | scalar |
| alu      | SRLW      | I      | scalar |
| alu      | ADD.UW    | Zba    | scalar |
| alu      | SH1ADD    | Zba    | scalar |
| alu      | SH1ADD.UW | Zba    | scalar |
| alu      | SH2ADD    | Zba    | scalar |
| alu      | SH2ADD.UW | Zba    | scalar |
| alu      | SH3ADD    | Zba    | scalar |
| alu      | SH3ADD.UW | Zba    | scalar |
| alu      | SLLI.UW   | Zba    | scalar |
| alu      | ANDN      | Zbb    | scalar |
| alu      | ORN       | Zbb    | scalar |
| alu      | XORN      | Zbb    | scalar |
| alu      | MAX       | Zbb    | scalar |
| alu      | MAXU      | Zbb    | scalar |
| alu      | MIN       | Zbb    | scalar |
| alu      | MINU      | Zbb    | scalar |
| alu      | SEXT.B    | Zbb    | scalar |
| alu      | SEXT.H    | Zbb    | scalar |
| alu      | ROL       | Zbb    | scalar |
| alu      | ROLW      | Zbb    | scalar |
| alu      | ROR       | Zbb    | scalar |
| alu      | RORI      | Zbb    | scalar |
| alu      | RORIW     | Zbb    | scalar |
| alu      | RORW      | Zbb    | scalar |
| alu      | ORC.B     | Zbb    | scalar |
| alu      | REV8      | Zbb    | scalar |
| alu      | BCLR      | Zbs    | scalar |
| alu      | BCLRI     | Zbs    | scalar |
| alu      | BEXT      | Zbs    | scalar |
| alu      | BEXTI     | Zbs    | scalar |
| alu      | BINV      | Zbs    | scalar |
| alu      | BINVI     | Zbs    | scalar |
| alu      | BSET      | Zbs    | scalar |
| alu      | BSETI     | Zbs    | scalar |
| alu      | PACk      | Zbkb   | scalar |
| alu      | PACKH     | Zbkb   | scalar |
| alu      | PACKW     | Zbkb   | scalar |
| alu      | BREV8     | Zbkb   | scalar |
| alu      | CZERO.EQZ | Zicond | scalar |
| alu      | CZERO.NEZ | Zicond | scalar |
| alu      | MOP.R     | Zimop  | scalar |
| alu      | MOP.RR    | Zimop  | scalar |
| alu      | TRAP      | I      | scalar |

## mul

table: mul fu 支持的指令

| 功能单元 | 支持指令 | 扩展 | 描述   |
| -------- | -------- | ---- | ------ |
| mul      | MUL      | M    | scalar |
| mul      | MULH     | M    | scalar |
| mul      | MULHU    | M    | scalar |
| mul      | MULHSU   | M    | scalar |
| mul      | MULW     | M    | scalar |

## div

table: div fu 支持的指令

| 功能单元 | 支持指令 | 扩展 | 描述   |
| -------- | -------- | ---- | ------ |
| div      | DIV      | M    | scalar |
| div      | DIVU     | M    | scalar |
| div      | REM      | M    | scalar |
| div      | REMU     | M    | scalar |
| div      | DIVW     | M    | scalar |
| div      | DIVUW    | M    | scalar |
| div      | REMW     | M    | scalar |
| div      | REMUW    | M    | scalar |

## fence

table: fence fu 支持的指令

| 功能单元 | 支持指令        | 扩展    | 描述   |
| -------- | --------------- | ------- | ------ |
| fence    | SFENCE.VMA      |         | scalar |
| fence    | SFENCE.I        |         | scalar |
| fence    | FENCE           |         | scalar |
| fence    | PAUSE           |         | scalar |
| fence    | SINVAL.VMA      | Svinval | scalar |
| fence    | SFENCE.W.INVAL  | Svinval | scalar |
| fence    | SFENCE.INVAL.IR | Svinval | scalar |
| fence    | HFENCE.GVMA     |         | scalar |
| fence    | HFENCE.VVMA     |         | scalar |
| fence    | HINVAL.GVMA     |         | scalar |
| fence    | HINVAL.VVMA     |         | scalar |

### 矩阵同步 {#sec:matrix-sync}

Fence 增加 macquire、msyncregreset（译码常量 MSYNCRESET）和 mfence。默认配置有 32 个 64 位同步计数器，复位为 0。正向 mrelease 请求携带一个计数器索引，CUTE 的反向完成接口携带 32 位完成向量；一次有效返回可同时标记多个计数器。

Table: Fence 矩阵同步行为

| 指令 | 行为 | 状态转换 |
| ---- | ---- | -------- |
| macquire | 锁存整数源中的目标值和同步索引，等待计数器值大于等于目标值 | idle → wait_macquire → macquire → idle |
| msyncregreset | 将指定同步计数器清零 | idle → msyncregreset → idle |
| mfence | 请求清空标量 SBuffer，等待 sbIsEmpty 后完成 | idle → wait → fence → idle |

`macquire` 和 `mfence` 在译码中同时设置 noSpec 与 blockBack，等待前序指令并阻塞后继指令进入 ROB。msyncregreset 设置 noSpec。Fence 在等待 macquire 时继续接收 CUTE 的完成返回，返回向量中每个置位项使对应计数器加 1，直到等待条件满足。

若 msyncregreset 清零的索引与同周期返回向量中的置位项冲突，当前实现执行清零，并抑制该次返回向量的全部加一操作，包括其他索引。若没有这个冲突，则对所有置位项分别加一。

`mfence` 以标量 SBuffer 排空作为完成条件，CUTE 任务可以继续在途。mrelease/macquire 等待此前 Store 及其依赖链完成，无关 Load 或 Compute 可以继续执行，详见 [Release 的同步语义](../../cute/TaskController.md#sec:cute-release)。实现见 [Fence.scala](https://github.com/OpenXiangShan/XSAI/blob/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f/src/main/scala/xiangshan/backend/fu/Fence.scala)。

## bku

table: bku fu 支持的指令

| 功能单元 | 支持指令   | 扩展  | 描述   |
| -------- | ---------- | ----- | ------ |
| bku      | CLZ        | Zbb   | scalar |
| bku      | CLZW       | Zbb   | scalar |
| bku      | CTZ        | Zbb   | scalar |
| bku      | CTZW       | Zbb   | scalar |
| bku      | CPOP       | Zbb   | scalar |
| bku      | CPOPW      | Zbb   | scalar |
| bku      | CLMUL      | Zbc   | scalar |
| bku      | CLMULH     | Zbc   | scalar |
| bku      | CLMULH     | Zbc   | scalar |
| bku      | XPERM4     | Zbkx  | scalar |
| bku      | XPERM8     | Zbkx  | scalar |
| bku      | AES64DS    | Zknd  | scalar |
| bku      | AES64DSM   | Zknd  | scalar |
| bku      | AES64IM    | Zknd  | scalar |
| bku      | AES64KS1I  | Zknd  | scalar |
| bku      | AES64KS2   | Zknd  | scalar |
| bku      | AES64ES    | Zkne  | scalar |
| bku      | AES64ESM   | Zkne  | scalar |
| bku      | SHA256SIG0 | Zknh  | scalar |
| bku      | SHA256SIG1 | Zknh  | scalar |
| bku      | SHA256SUM0 | Zknh  | scalar |
| bku      | SHA256SUM1 | Zknh  | scalar |
| bku      | SHA512SIG0 | Zknh  | scalar |
| bku      | SHA512SIG1 | Zknh  | scalar |
| bku      | SHA512SUM0 | Zknh  | scalar |
| bku      | SHA512SUM1 | Zknh  | scalar |
| bku      | SM4ED0     | Zksed | scalar |
| bku      | SM4ED1     | Zksed | scalar |
| bku      | SM4ED2     | Zksed | scalar |
| bku      | SM4ED3     | Zksed | scalar |
| bku      | SM4KS0     | Zksed | scalar |
| bku      | SM4KS1     | Zksed | scalar |
| bku      | SM4KS2     | Zksed | scalar |
| bku      | SM4KS3     | Zksed | scalar |
| bku      | SM3P0      | Zksh  | scalar |
| bku      | SM3P1      | Zksh  | scalar |
