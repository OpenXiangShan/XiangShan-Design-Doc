# FallThrough Predictor

这是一个 always-not-taken 的 S1 预测器，用于在其余所有预测器都不命中/预测为不跳转时提供预测结果。

如果不考虑 V3 的各种特性，它只需要将输入的当前预测块的起始地址加上预测块大小（默认为 64 字节，下面讨论时为了方便直接使用 64 这个数字）即可作为预测的目标地址（即下一个预测块的起始地址）。

然而实际上，V3 的 S3 预测器组和 Ifu/ICache 对 S1 预测器组存在一些要求，这些要求可以通过 FallThrough 实现，避免给 ubtb 和 abtb 引入额外的复杂度。

## Half-align

Half-align 的细节请参考 mbtb 文档，由于 S1 预测器组直接使用起始地址作为索引（即 not-align 的），所以若不做任何限制，S1 预测器组可以预测 64B 内的任意分支，而对于那些（64B 内，但跨越了两个 32B 边界）的分支，S3 预测器组无法进行预测或校验。

为方便描述，我们定义 aligned 函数伪代码如下，将地址对齐到 32B 边界，即清除地址的低 5 位：

```text
define aligned(addr):
    return addr & ~0x1F // 对齐到 32B
```

```text
        start = 0x0a
0x00    |        0x20             0x40             0x60             0x80
        |----------------------------------| S1 预测器极限范围 [0x0a, 0x4a]
        |-------------------------| S3 预测器极限范围 [0x0a, aligned(0x4a)=0x40]
```

如果分别在 ubtb 和 abtb 内对超范围的分支进行过滤，实现复杂度会比较高。考虑到所有训练进 ubtb/abtb 的分支都一定包含在曾经某次 fallThrough 预测的范围内，所以我们直接禁止 FallThrough 预测跨越两个 32B 边界的范围就可以避免 ubtb/abtb 预测超范围。

伪代码类似于：

```text
target = aligned(start + 0x40)
```

另外考虑 cfiPosition，具体描述见 Bpu 整体设计文档，简单重复其定义：被预测为分支指令的地址相对于取指块起始地址对齐到 32B 后的偏移量，以指令为单位，即：

```text
cfiPosition = (cfiAddr - aligned(start))[5:1]
```

在不考虑 half-align 的限制时，计算 cfiPosition 需要计算上述减法，进行限制以后反而简单了很多：fallThrough 预测的 cfi 为下一个 32B 对齐地址前的最后一条指令，其相对于取指块起始地址对齐到 32B 后的偏移量显然是个常数：

```text
cfiPosition = (cfiAddr - aligned(start))[5:1]
            = ((target - 2) - aligned(start))[5:1]
            = (aligned(start) + 0x40 - 2 - aligned(start))[5:1]
            = 31
```

从语义上，fallThrough 预测的 cfiPosition 似乎没有什么用，因为它不跳转、甚至不是一个真的 cfi，但目前 ICache/Ifu 使用它计算需要取指的位置（需要访问的 data SRAM bank），因此它必须给出一个合理的值来最小化需要访问的 bank 数量，从而节省功耗、降低 2-fetch 的 bank 冲突[^1]。

[^1]: 在 V2 的设计中，ICache 假设永远读取 34B，不需要使用 Bpu 预测的 position，而 Ifu 则根据 Bpu 预测的 taken 进行选择，taken 时根据 Bpu 预测的 position 计算预测块大小，而不 taken 时则根据 target 计算。故 V2 的 fallThrough 预测不需要考虑这一点。V3 相当于把“不 taken 时使用 target-start 计算”这部分逻辑从 Ifu 挪到了 Bpu 内部。

## 禁止取指块跨页

在 V3 设计中，为了节省 Itlb 面积，Ifu/ICache 假设单次取指请求不会跨过页边界（4KB），即需要 Bpu 保证预测的 cfiPosition 和 start 在同一页内。

类似 half-align，我们同样可以通过限制 FallThrough 预测来在不给 ubtb/abtb 引入额外的复杂度的情况下满足这一点。

在具体做法上也比较类似 half-align，我们首先比较 start + 64 和 start 的 pfn（物理页号，即地址第 12 位及以上的位）[^2]，若不同，则将对齐到 4KB 的结果作为 target：

```text
define pageAligned(addr):
    return addr & ~0xFFF // 对齐到 4KB
```

```text
if pfn(start + 0x40) != pfn(start):
    target = pageAligned(start + 0x40)
else:
    target = aligned(start + 0x40)
```

[^2]: 事实上，由于 + 64 最多跨越一个页边界，我们只需要比较 pfn 的最低位即可。

接下来考虑 cfiPosition，当跨页时 cfiPosition 不再是个常数，只能根据 target 和 start 计算：

```text
if pfn(start + 0x40) != pfn(start):
    cfiPosition = ((target - 2) - aligned(start))[5:1]
                = (pageAligned(start + 0x40) - 2 - aligned(start))[5:1]
    // 注意到取[5:1]时忽略了高位，因此 - aligned(start) 和 - aligned(start) - 0x40 效果相同
    // 而 aligned 只 mask 低 5 位，因此 - aligned(start) - 0x40 和 - aligned(start + 0x40) 效果相同
                = (pageAligned(start + 0x40) - 2 - aligned(start + 0x40))[5:1]
    // 补码表示时取负数和按位取反再加一效果相同，故
                = ~(aligned(start + 0x40) - pageAligned(start + 0x40))[5:1]
else:
    cfiPosition = 31
```
