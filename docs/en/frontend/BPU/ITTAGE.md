# BPU Submodule ITTAGE

## Function

ITTAGE 接收来自 BPU 内部的预测请求，其内部由一个基预测表和多个历史表组成，每个表项中都有一个用于存储间接跳转指令目标地址的字段。基预测表用 PC
索引，而历史表用 PC 和一定长度的分支历史折叠后的结果异或索引，不同历史表使用的分支历史长度不同。在预测时，还会用 PC
和每个历史表对应的分支历史的另一种折叠结果异或计算 tag，与表中读出的 tag
进行匹配，如果匹配成功则该表命中。最终的结果取决于命中的历史长度最长的预测表的结果。最终，ITTAGE 将预测结果输出至 composer。

### Prediction of indirect jump instructions

ITTAGE is used to predict indirect jump instructions. The jump targets of
ordinary branch instructions and unconditional jump instructions are directly
encoded in the instructions, making them easy to predict. In contrast, the jump
addresses of indirect jump instructions come from runtime-variable registers,
offering multiple possible choices that require prediction based on branch
history.

为此，ITTAGE 的每个表项在 TAGE 表项的基础上加入了所预测的跳转地址项，最后输出结果为选出的命中预测跳转地址而非选出的跳转方向。

Since each FTB entry stores information for at most one indirect jump
instruction, the ITTAGE predictor can predict the target address of only one
indirect jump instruction per cycle.

香山昆明湖 V2R2 架构中的 ITTAGE 提供了 5 个带 tag 的预测表 T1-T5，基准预测器和带 tag 的预测表的基本信息见下表。

| **predictor**           | ** with tag** | ** function **                                                                                            | ** entry composition **                                                                                                                           | **item count**              |
| ----------------------- | ------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| Baseline Predictor T0   | No            | Used to provide prediction results when none of the tags in the tagged prediction table match.            | ITTAGE does not implement T0, but directly uses the prediction result from ftb as the baseline prediction result                                  |                             |
| Prediction tables T1-T5 | Yes           | When there is a tag match, the one with the longest history is selected to provide the prediction result. | valid: 1bit; tag: 9bit; sctr: 2bits（表示要不要输出这个预测结果）; useful: 1bit（usefulness 计数器）; target_offset: 20 bits（target 共 50 bits，出于面积考虑，高位 30 bits 分开存储） | T1-T2 各 256 项，T3-T5 各 512 项 |

The BPU module maintains a 256-bit global branch history ghv and separately
manages folded branch histories for each of ITTAGE's 5 tagged prediction tables,
with the folding algorithm identical to TAGE. The specific configurations for
folded histories are detailed in the table below, where ghv is a circular queue,
and the "lower" n bits refer to the low-order bits starting from the position
indicated by ptr:

| ** history**                                | **index folded branch history length** | **tag folded branch history 1 length** | ** tag folded branch history 2 length** | ** Design principle **                                                |
| ------------------------------------------- | -------------------------------------- | -------------------------------------- | --------------------------------------- | --------------------------------------------------------------------- |
| Global branch history ghv                   | 256 bits                               | 无                                      | 无                                       | Each bit represents whether the corresponding branch is taken or not. |
| T1 corresponds to folded branch history     | 4 比特                                   | 4 比特                                   | 4 比特                                    | ghv takes the lower 4 bits of ptr for folded XOR                      |
| T2 corresponds to folded branch history     | 8 比特                                   | 8 比特                                   | 8 比特                                    | ghv takes the lower 8 bits of ptr for folded XOR                      |
| T3 corresponds to folded branch history.    | 9 比特                                   | 9 比特                                   | 8 比特                                    | ghv takes the lower 13 bits from ptr, folds, and XORs them.           |
| T4 corresponds to folded branch history     | 9 比特                                   | 9 比特                                   | 8 比特                                    | ghv takes the lower 16 bits of ptr for folded XOR                     |
| T5 corresponds to the folded branch history | 9 比特                                   | 9 比特                                   | 8 比特                                    | ghv takes the lower 32 bits of ptr for folded XOR                     |

ITTAGE requires a 3-cycle delay:

* Index generation takes 0 cycles.
* 1-cycle data readout
* 2-cycle selection of hit result
* 3-cycle output

### 写缓存（WriteBuffer）

每个 IttageTable 使用 WriteBuffer 模块实现写缓存，用于在 SRAM 写操作与读操作冲突时，暂存写请求以保证数据一致性。 每次
ITTAGE 更新时都会写进这个 WriteBuffer；当 SRAM 读端口空闲时，WriteBuffer 会将数据写入 SRAM。


### Predictor training

First, define the provider as the prediction table with the longest required
history length among all those producing tag matches, while the other matching
prediction tables (if any) are called altpred. When the provider's ctr is 0, the
altpred's result is chosen as the prediction.

ITTAGE 表项中包含一个 usefulness 域，当 provider 预测正确而 altpred 预测错误时 provider 的 usefulness
置 1，表示该项是一个有用的项，便不会被训练时的分配算法当作空项分配出去。当 provider 产生的预测被证实为一个正确的预测，且此时的 provider 与
altpred 的预测结果不同，则 provider 的 usefulness 域被置 1。

若预测地址与实际一致，则将对应 provider 表项的 ctr 计数器自增 1；若预测地址与实际不一致，则将对应 provider 表项的 ctr 计数器自减
1。ITTAGE 中，会根据 ctr 判断是否采取这个预测的跳转目标结果。当 ctr 为 0 时，会选择 altpred 的结果。

接下来，若该 provider 所源自的预测表并非所需历史长度最高的预测表，则此时执行如下的表项增添操作。表项增添操作会首先读取所有历史长度长于
provider 的预测表的 usefulness 域。若此时有某表的 usefulness 域值为 0，则在该表中分配一对应的表项；若没有找到满足
usefulness 域值为 0 的表，则分配失败。当有多个预测表（如 Tj,Tk 两项）的 usefulness 域均为 0
时，表项的分配概率是随机的，分配的时候随机把某些 table 给 mask 掉，让它不会每次都分配同一个。这里的表项分配的随机性是通过 chisel 的
util 包里的 64 位线性反馈移位寄存器原语 LFSR64 生成伪随机数来实现的，在 verilog 代码中对应 allocLFSR_lfsr
寄存器。在训练时，用 8 位饱和计数器 tickCtr 统计分配失败次数-成功次数，当分配失败的次数足够多，tickCtr 计数器计数到满达到饱和时，触发全局
useful bit reset，把所有的 usefulness 域清零。

Note: The saturating counter for clearing the usefulness field in ITTAGE is
named tickCtr, with a length of 8 bits. Both the name and length differ from
TAGE.

最后，在 ITTAGE 表分配新项时，新表项中的 ctr 计数器均被设置为 2，usefulness 域被设置为 0。

## Storage structure

* 5 张历史表，项数分别为 256、256、512、512、512，每张表没有分 bank。
* 每个表项含有 1bit valid，9bit tag，2bit ctr，20bit target_offset，1bit useful，都使用 SRAM
  统一存储。
* 以 FTB 结果作为 base table。
* 每个历史表有 4 项的写缓存（WriteBuffer）。

## Prediction flow

* s0 performs index calculation, and the address is sent to the SRAM.
* s1 reads the entries, performs bank selection, and determines hits, with the
  results registered to s2.
* s2 calculates the longest history match and the second-longest history match:
  * When there is a history table hit and ctr!=0, the target address from the
    longest history result is attempted.
  * When the provider has low confidence (ctr==0), if the second-longest history
    matches, the target address from the second-longest history result is
    attempted.
  * When no history table hits, the FTB result is used.
* s3 uses the target address and compares it with the s2 result within the BPU
  to determine whether the pipeline needs to be flushed.

## Training process

基本和 TAGE 相同，对于 target 字段，仅当分配新表项或者原 ctr 为最小值 0 时，才会替换新值，否则保持原样。
