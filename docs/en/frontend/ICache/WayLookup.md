# WayLookup 子模块文档

WayLookup 为 FIFO 结构，暂存 IPrefetchPipe 查询 MetaArray 和 ITLB 得到的元数据，以备 MainPipe
使用。同时监听 MSHR 写入 SRAM 的 cacheline，对命中信息进行更新。更新逻辑与 IPrefetchPipe 中相同，见
[IPrefetchPipe
子模块文档中的“命中信息的更新”](IPrefetchPipe.md#sec:IPrefetchPipe-hit-update)一节。

![WayLookup 队列结构](../figure/ICache/WayLookup/waylookup_structure_rw.png)

![WayLookup 命中信息更新](../figure/ICache/WayLookup/waylookup_structure_update.png)

允许 bypass（即，当 WayLookup 为空时，直接将入队请求出队），为了不将更新逻辑的延迟引入到 DataArray 的访问路径上，在 MSHR
有新的写入时禁止出队，MainPipe 的 S0 流水级也需要访问 DataArray，当 MSHR 有新的写入时无法向下走，所以该措施并不会带来额外影响。

## GPaddr 省面积机制

由于 `gpaddr` 仅在 guest page fault 发生时有用，并且每次发生 gpf 后前端实际上工作在错误路径上，后端保证会送一个
redirect（WayLookup flush）到前端（无论是发生 gpf 前就已经预测错误/发生异常中断导致的；还是 gpf 本身导致的），因此在
WayLookup 中只需存储 reset/flush 后第一个 gpf 有效时的 gpaddr。对双行请求，只需存储第一个有 gpf 的行的
`gpaddr。`

在实现上，把 gpf 相关信号（目前只有 `gpaddr`）与其它信号（`paddr`，etc.）拆成两个 bundle，其它信号实例化
nWayLookupSize 个，gpf 相关只实例化一个寄存器。同时另用一个 `gpfPtr`
指针。总计可以节省$(\text{nWayLookupSize}*2-1)* \text{GPAddrBits} -
\log_2{(\text{nWayLookupSize})} - 1$bit 的寄存器。 当 prefetch 向 WayLookup 写入时，若有 gpf
发生，且 WayLookup 中没有已经存在的 gpf，则将 gpf/gpaddr 写入 `gpf_entry` 寄存器，同时将 `gpfPtr` 设置为此时的
`writePtr。` 当 MainPipe 从 WayLookup 读取时，若 bypass，则仍然直接将 prefetch 入队的数据出队；否则，若
`readPtr === gpfPtr`，则读出 gpf_entry；否则读出全 0。 需要指出：

1. 考虑双行请求，`gpaddr` 只需要存一份（若第一行发生 gpf，则第二行肯定也在错误路径上，不必存储），但 gpf 信号本身仍然需要存两份，因为
   ifu 需要判断是否是跨行异常。
2. `readPtr===gpfPtr` 这一条件可能导致 flush 来的比较慢时 `readPtr` 转了一圈再次与 `gpfPtr`
   相等，从而错误地再次读出 gpf，但如前所述，此时工作在错误路径上，因此即使再次读出 gpf 也无所谓。
3. 需要注意一个特殊情况：一个跨页的取指块，其 32B 在前一页且无异常，后 2B 在后一页且发生 gpf，若前 32B 正好是 16 条 RVC
   压缩指令，则 IFU 会将后 2B 及对应的异常信息丢弃，此时可能导致下一个取指块的 `gpaddr` 丢失。需要在 WayLookup 中已有一个未被
   MainPipe 取走的 gpf 及相关信息时阻塞 WayLookup 的入队（即 IPrefetchPipe s1 流水级），见 PR#3719。
