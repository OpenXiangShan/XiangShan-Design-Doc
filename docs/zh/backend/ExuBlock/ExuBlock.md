# ExuBlock

- 版本：V2R2
- 状态：OK
- 日期：2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## 输入输出

`flush` 是一个带 valid 信号的 Redirect 输入

`in` 是按 issueBlock 和 每个 issueBlock 包含的 exu 对应的 ExuInput 输入。即 in(i)(j) 表示输入来源于第 i 个issueBlock 中的第 j 个exu。

`out` 是按 issueBlock 和 每个 issueBlock 包含的 exu 对应的 ExuOutput 输出。即 out(i)(j) 表示对应第 i 个issueBlock 中的第 j 个exu 的输出。

`csrio` 、 `csrin` 和 `csrToDecode` 只有当该 ExuBlock 中存在 `CSR` 时才存在。

类似地， `fenceio` 只有当该 ExuBlock 中存在 `fence` 时才存在。`frm` 只有当该 ExuBlock 中需要 `frm` 作为 src 时才存在。`vxrm` 只有当该 ExuBlock 中需要 `vxrm` 作为 src 时才存在。

`vtype` 、 `vlIsZero` 和 `vlIsVlmax` 只有当该 ExuBlock 中需要写 Vconfig 时才存在。

## 功能

ExuBlock 主要负责将外部模块传入的信号按照配置需求连接到各个 exu，并将 exu 的输出整理作为 ExuBlock 的输出。

![ExuBlock 总览](./figure/ExuBlock-Overview.svg)

## 设计规格

在 Backend 中一共有 3 个ExuBlock：intExuBlock，fpExuBlock 和 vfExuBlock，分别是整数、浮点、向量的执行模块。每个 ExuBlock 中包含若干个 ExeUnit 单元。

intExuBlock 中包含了 8 个ExeUnit，IO 包括了 flush, in, out, csrio, csrin, csrToDecode, fenceio, frm, vtype, vlIsZero 和 vlIsVlmax，不包括 vxrm。

fpExuBlock 中包含了 5 个ExeUnit，IO 包括了 flush, in, out 和 frm，不包括 csrio, csrin, csrToDecode, fenceio, vxrm, vtype, vlIsZero 和 vlIsVlmax。

vfExuBlock 中包含了 5 个ExeUnit，IO 包括了 flush, in, out, frm, vxrm, vtype, vlIsZero 和 vlIsVlmax，不包括 csrio, csrin, csrToDecode 和 fenceio。
