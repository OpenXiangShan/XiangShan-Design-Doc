# MainPipe {#sec:icache-mainpipe}

MainPipe 为 ICache 的主流水，为 2 级流水设计，负责从 DataArray 中读取数据、ECC 检查、缺失处理，并且将结果返回给 IFU。

## S0 流水级 {#sec:icache-mainpipe-s0}

1. 接收来自 FTQ 的取指请求。
2. 从 wayLookup 队头项获取元数据。
3. 若命中，根据取指请求和元数据向 dataArray 发送读请求。

## S1 流水级 {#sec:icache-mainpipe-s1}

1. 根据命中结果、异常信息判断是否需要取指。
2. 若命中，接收 dataArray 的响应。
3. 若缺失且无异常，通过 Arbiter 将依次将至多两个取指块共四个 cacheline 的缺失请求发送至 missUnit。并等待直到重填完成。
4. 将数据发送到 IFU。

## S2 流水级 {#sec:icache-mainpipe-s2}

1. metaArray 和 dataArray ECC 校验。
2. metaArray 或 dataArray ECC 校验出错时，向 BEU 发送错误信息。
3. 将校验结果发送到 IFU。

V3 早期设计中，试图将 mainPipe 缩短到一个流水级，即 dataArray ECC 校验也在 S1 中完成，但由于 dataArray 本身 SRAM 较大，校验逻辑是位宽很大的组合逻辑，时序无法收敛，因此改为现在的两级设计。ICache 和 Ifu 约定在 s1 级的端口握手成功的下一拍中，ICache s2 提供的校验结果有效。直到下一次 s1 级握手成功 s2 流水级才会更新。因此，mainPipe s2 级不需要用传统的 ready-valid 信号控制，s2 与 Ifu 的端口也不需要握手，简化设计。

### MetaArray ECC 校验 {#sec:icache-mainpipe-s2-meta-ecc}

prefetchPipe 读出 metaArray 的元数据和校验码后，并不对其进行校验，而是直接存入 wayLookup，在 mainPipe 中进行校验。

除了校验码本身的校验之外，metaArray ECC 校验还会检查是否存在多路命中（即同一个 setIdx 存在多个 way 的 tag 都命中）。如果存在多路命中，即使校验码通过了检查，也会认为 metaArray 出现了错误。
