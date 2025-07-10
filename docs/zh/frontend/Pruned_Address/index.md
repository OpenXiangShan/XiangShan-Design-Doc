# 昆明湖 PrunedAddr 文档

## 背景介绍

在 RISC-V 手册中，对于 B-Type 和 J-Type 的指令描述如下：

> The only difference between the S and B formats is that the 12-bit immediate field is used to encode  branch offsets in multiples of 2 in the B format. Instead of shifting all bits in the instruction-encoded immediate left by one in hardware as is conventionally done, the middle bits (imm[10:1]) and sign bit stay in fixed positions, while the lowest bit in S format (inst[7]) encodes a high-order bit in B format.
>
> Similarly, the only difference between the U and J formats is that the 20-bit immediate is shifted left by 12 bits to form U immediates and by 1 bit to form J immediates. The location of instruction bits in the U and J format immediates is chosen to maximize overlap with the other formats and with each other.

这意味着对于除了`jalr`以外的分支指令，跳转目标的最低为一定为 0。而对于`jalr`指令，手册中对计算跳转目标的描述如下：

> The target address is obtained by adding the sign-extended 12-bit I-immediate to the register rs1, then setting the least-significant bit of the result to zero.

这意味着`jalr`的跳转目标最低位也为 0。

综合这两部分，我们可以发现所有的 PC 最低为一定为 0。于是，前端所有涉及到 PC 的部分均不用存储最低位，这可以节省面积。

实际上，当 C 扩展关闭时，PC 的低 2 位一定为 0，否则会报指令非对齐异常。

## 使用指南

`PrunedAddr`的设计目标是使用起来和`UInt`尽可能相同。但是，出于 Chisel 的限制，这一目标并不能全部实现。在那些和`UInt`不同的地方，可以类比`Reg`或`Wire`。具体的使用指南如下：

- 使用`PrunedAddrInit`进行从`UInt`到`PrunedAddr`的转换，例如`val addr1 = PrunedAddrInit(addr2)`，其中`addr2`的类型是`UInt`
- 使用`toUInt`进行从`PrunedAddr`到`UInt`的转换，例如`addr.toUInt`
- `def +(offset: UInt)`这一方法仅当`offset`为立即数时才应被使用。对于其他情况，应当使用`def +(offset: PrunedAddr)`。如果`offset`是`UInt`且不是立即数，应当将`offset`转换为`PrunedAddr`

## 遗留问题

- 目前，对于`PrunedAddr`的使用仅限于前端内部，前端给后端的接口仍然使用`UInt`。理想情况下，后端也应当全部使用`PrunedAddr`。此时`toUInt`这一方法应当只在输出调试信息时使用
- `def >>(offset: Int)`这一方法应当删除以减少混乱。对应的功能可以由直接选择对应位来实现
- 对于裁剪的位数，目前的实现中使用了`instOffset`这一参数。理论上来说，这一参数应当会随着 C 扩展的开关发生变化。但现在香山实际上不支持关闭 C 扩展，关闭 C 扩展的正确性还未经过验证
