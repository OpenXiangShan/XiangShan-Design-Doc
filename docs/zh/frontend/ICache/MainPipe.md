# MainPipe 子模块文档

MainPipe 为 ICache 的主流水，为 2 级流水设计，负责从 DataArray 中读取数据、ECC 检查、缺失处理，并且将结果返回给 IFU。

## S0 流水级

1. 接收来自 FTQ 的取指请求。
2. 从 wayLookup 队头项获取元数据。
3. 若命中，根据取指请求和元数据向 dataArray 发送读请求。

## S1 流水级

1. metaArray ECC 校验。
2. 根据命中结果、异常信息、metaArray 校验结果判断是否需要取指。
3. 若命中，接收 dataArray 的响应。
4. 若缺失且无异常，通过 Arbiter 将依次将至多两个 cacheline 的缺失请求发送至 missUnit。并等待直到重填完成。
5. 将数据发送到 IFU。

### MetaArray ECC 校验

prefetchPipe 读出 metaArray 的元数据和校验码后，并不对其进行校验，而是直接存入 wayLookup，在 mainPipe 中进行校验。

除了校验码本身的校验之外，metaArray ECC 校验还会检查是否存在多路命中（即同一个 setIdx 存在多个 way 的 tag 都命中）。如果存在多路命中，即使校验码通过了检查，也会认为 metaArray 出现了错误。

## S2 流水级

1. dataArray ECC 校验。
2. metaArray 或 dataArray ECC 校验出错时，向 BEU 发送错误信息。
3. 将校验结果发送到 IFU。

V3 早期设计中，试图将 mainPipe 缩短到一个流水级，即 dataArray ECC 校验也在 S1 中完成，但由于 dataArray 本身 SRAM 较大，校验逻辑是位宽很大的组合逻辑，时序无法收敛，因此改为现在的两级设计。故 ICache 到 IFU 的存在 S1 和 S2 流水级上的两个端口，分别进行握手。
