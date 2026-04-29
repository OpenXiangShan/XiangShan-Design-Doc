# WayLookup {#sec:icache-waylookup}

wayLookup 为环形队列结构，暂存 prefetchPipe 查询 metaArray 和 ITLB 得到的元数据，以备 mainPipe 使用。同时监听 missUnit 的重填广播，对命中信息进行更新。更新逻辑与 PrefetchPipe 中相同，见 [@sec:icache-hit-update] [PrefetchPipe “命中信息的更新” 一节](PrefetchPipe.md#sec:icache-hit-update)。

## 指针更新 {#sec:icache-waylookup-pointer-update}

当 prefetchPipe 向 wayLookup 写入时，`writePtr++`；当 mainPipe 从 wayLookup 读取时，`readPtr++`。当队列满时（`writePtr.flag =/= readPtr.flag && writePtr.value === readPtr.value`），不再接收新的入队请求。

wayLookup 支持 bypass，即当 wayLook 空（`writePtr === readPtr`）时，将 prefetchPipe 本拍即将写入的数据立即出队到 mainPipe。为了简化指针更新逻辑，bypass 时 `writePtr` 和 `readPtr` 同时更新（`writePtr++` 和 `readPtr++`），因此在 bypass 后队列仍然是空的。

## BPU 冲刷 {#sec:icache-waylookup-bpu-flush}

由于 BPU/FTQ 流水上的一些减拍，相比 V2R2，FTQ 向 ICache 发送预取请求的实际更早了一拍，这导致一个取指块被 BPU s3 override 时，该取指块可能已经入队 wayLookup，因此 wayLookup 也需要处理 BPU 冲刷请求。好在，需要被冲刷的请求一定刚刚入队 wayLookup（最快的情况下，BPU s1 = prefetchPipe s0，BPU s2 = prefetchPipe s1 = wayLookup.io.write，BPU s3 = wayLookup `entries[writePtr - 1]`），因此只需要考虑队尾一项是否需要冲刷。

具体来说，wayLookup 记录队尾项对应的 `ftqIdx`，当收到 BPU s3 override 请求时，若 `ftqIdx` 匹配，且 `writePtr` > `readPtr`（即队尾项还没有被 mainPipe 读走），则冲刷队尾项（`writePtr--`）

## 异常处理 {#sec:icache-waylookup-exception}

由于 `gpaddr` 等信号仅在相应异常发生时有用，并且每次发生异常后前端实际上工作在错误路径上，后端保证会送一个重定向到前端（无论是发生异常前就已经预测错误/发生异常中断导致的；还是异常本身导致的），因此在 wayLookup 中只需存储 reset/flush 后第一个异常有效时的相关信号，节省存储面积。

在实现上，把这些信号（`itlbException`，`gpaddr`，etc.）与其它信号（`waymask`，etc.）拆成两个 Bundle，其它信号实例化 nWayLookupSize 个，异常相关只实例化一个寄存器。用一个 `exceptionPtr` 指示异常对应的项。

当 prefetchPipe 向 wayLookup 写入时，若有异常发生，则将相关信号写入 `exceptionEntry` 寄存器，同时将 `exceptionPtr` 设置为此时的 `writePtr`。

当 mainPipe 从 wayLookup 读取时，若 bypass，则仍然直接将 prefetchPipe 入队的数据出队；否则，若 `readPtr === exceptionPtr`，则读出 exceptionEntry；否则读出全 0。

另外，同样是由于发生过异常以后处理器已经工作在错误路径上，因此在 `exceptionEntry` 有效时，wayLookup 不再接收新的入队请求，从而反压 prefetchPipe、FTQ 和 BPU，节省功耗。直到后端重定向将前端带回正确路径，冲刷掉 `exceptionEntry`。
