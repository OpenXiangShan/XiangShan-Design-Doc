# ExuUnit

- 版本：V2R2
- 状态：OK
- 日期：2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## 术语说明

Table: fu 术语说明

| fu         | 描述                     |
| ---------- | ------------------------ |
| alu        | 算术逻辑单元             |
| mul        | 乘法单元                 |
| bku        | B 扩展位运算和密码学单元 |
| brh        | 条件跳转单元             |
| jmp        | 直接跳转单元             |
| i2f        | 整数转浮点单元           |
| i2v        | 整数移动到向量单元       |
| VSetRiWi   | 读整数写整数的 vset 单元 |
| VSetRiWvf  | 读整数写向量的 vset 单元 |
| csr        | 控制状态寄存器单元       |
| fence      | 内存同步指令单元         |
| div        | 除法单元                 |
| falu       | 浮点算数逻辑单元         |
| fcvt       | 浮点转换单元             |
| f2v        | 浮点移动到向量单元       |
| fmac       | 浮点融合乘加             |
| fdiv       | 浮点除法单元             |
| vfma       | 向量浮点融合乘加单元     |
| vialu      | 向量整数算术逻辑单元     |
| vimac      | 向量整数乘加单元         |
| vppu       | 向量排列处理单元         |
| vfalu      | 向量浮点算数逻辑单元     |
| vfcvt      | 向量浮点转换单元         |
| vipu       | 向量整数处理单元         |
| VSetRvfWvf | 读向量写向量的 vset 单元 |
| vfdiv      | 向量浮点除法单元         |
| vidiv      | 向量整数除法单元         |

## 输入输出

`flush` 是一个带 valid 信号的 Redirect 输入

`in` 是按具体 ExeUnit 参数配置生成的 ExuInput

`out` 是按具体 ExeUnit 参数配置生成的 ExuOutput

`csrio` 、 `csrin` 和 `csrToDecode` 只有当该 ExeUnit 中存在 `CSR` 时才存在。

类似地， `fenceio` 只有当该 ExeUnit 中存在 `fence` 时才存在。`frm` 只有当该 ExeUnit 中需要 `frm` 作为 src 时才存在。`vxrm` 只有当该 ExeUnit 中需要 `vxrm` 作为 src 时才存在。

`vtype` 、 `vlIsZero` 和 `vlIsVlmax` 只有当该 ExeUnit 中需要写 Vconfig 时才存在。

另外，对于 ExeUnit 中存在 JmpFu 或者 BrhFu 的情况，还需要输入指令地址翻译类型 `instrAddrTransType`

## 功能

每个 ExuUnit 会根据其配置参数生成一系列对应的 FU 模块。

busy 用于表示当前 ExeUnit 是否处于繁忙状态。对于延迟确定的 ExeUnit，功能单元永远不会被标记为繁忙，因为延迟是固定的，所有的任务都会按顺序完成。在这种情况下，busy 被直接设置为 false，表示功能单元始终是空闲的。而对于非确定延迟的 ExeUnit，当有输入 fire 时将 busy 拉高，在输出 fire 时拉低。另外，如果正在输入的 uop 或者正在计算的 uop 需要被 redirect flush，则也将 busy 拉低。

另外，ExeUnit 中会检查混合延迟类型，即检查是否存在同一端口的功能单元具有不同的延迟类型（确定和不确定的）。如果存在这种混合情况，对于不确定延迟的功能单元，确保其优先级是最大值。这种设计逻辑确保了在处理不同类型延迟的功能单元时。写回端口的优先级得到适当的配置，避免优先级的冲突或不一致。

每个 ExuUnit 中除了拥有各个 FU 外，还有一个子模块 in1ToN，其是一个 Dispatcher，其作用是将输入到 ExuUnit 的一个 ExuInput 进一步派遣到不同的 FU，这里需要保证同一个 ExuInput 必须进入 1 个 FU，且不能进入多于 1 个的 FU 中。

另外还有一组寄存器 inPipe，是大小为 latencyMax+ 1 的 （valid，input）对，其记录了输入，以及输入处于什么哪一周期的计算。对于需要控制流水线的 FU，可以通过 inPipe 获得原始的数据。

最后，还需要将不同 FU 的输出结果进行汇总，选出一个 FU 的输出结果作为 ExeUnit 的输出。

![ExuUnit 总览](./figure/ExuUnit-Overview.svg)

## 设计规格

在 Backend 中一共有 3 个ExuBlock：intExuBlock，fpExuBlock 和 vfExuBlock，分别是整数、浮点、向量的执行模块。每个 ExuBlock 中包含若干个 ExeUnit 单元。

intExuBlock 中包含了 8 个 ExeUnit，每个 ExeUnit 对应的功能如下：

Table: intExuBlock 中 各个ExeUnit 包含的 Fu

| ExeUnit | 功能                                    |
| ------- | --------------------------------------- |
| exus0   | alu，mul，bku                           |
| exus1   | brh，jmp                                |
| exus2   | alu，mul，bku                           |
| exus3   | brh，jmp                                |
| exus4   | alu                                     |
| exus5   | brh，jmp，i2f，i2v，VSetRiWi，VSetRiWvf |
| exus6   | alu                                     |
| exus7   | csr，fence，div                         |

fpExuBlock 中包含了 5 个 ExeUnit，每个 ExuUnit 对应的功能如下：

Table: fpExuBlock 中 各个ExeUnit 包含的 Fu

| ExeUnit | 功能                  |
| ------- | --------------------- |
| exus0   | falu，fcvt，f2v，fmac |
| exus1   | fdiv                  |
| exus2   | falu，fmac            |
| exus3   | fdiv                  |
| exus4   | falu，fmac            |

vfExuBlock 中包含了 5 个 ExeUnit，每个 ExuUnit 对应的功能如下：

Table: vfExuBlock 中 各个ExeUnit 包含的 Fu

| ExeUnit | 功能                           |
| ------- | ------------------------------ |
| exus0   | vfma，vialu，vimac，vppu       |
| exus1   | vfalu，vfcvt，vipu，VSetRvfWvf |
| exus2   | vfma，vialu                    |
| exus3   | vfalu                          |
| exus4   | vfdiv，vidiv                   |

## 门控

ExuUnit 还支持功能单元 FU 的时钟门控（Clock Gating）。通过控制每个功能单元 FU 的时钟使能信号 clk_en 来降低功耗。只有在功能单元需要时，时钟才会被启用，并且根据功能单元的延迟设置和是否启用不确定延迟，动态计算时钟门控的使能信号，从而实现功耗优化。

简单来说，对于固定延迟且延迟周期数大于 0 的 FU，使用两个 latReal + 1 长度的向量 fuVldVec 和 fuRdyVec，在 FU 输入有效时， fuVldVec(0) 为 1，在每个周期将 1 向后移动。另外对于 fuRdyVec(i)，其值取决于 fuRdyVec(i+1) 和 fuVldVec(i+1)。这样当 fuVldVec 中有 1 时就说明当前有有效的计算。

对于不确定延迟的 FU，使用 uncer_en_reg 在 FU 输入 fire 时记录，并在 FU 输出 fire 时清空。

于是对于可以使用门控的 FU来说，其 clk_en 拉高的条件就是：零延迟的 FU 且 FU 输入 fire；多周期延迟的 FU 且输入 fire，或当前 FU 中有有效计算；不确定延迟的 FU 且 FU 输入 fire，或当前 FU 中有有效的计算。通过这样的条件进行时钟门控。
