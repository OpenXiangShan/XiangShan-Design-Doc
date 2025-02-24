# 错误处理

- 版本：V2R2
- 状态：OK
- 日期：2025/02/24
- commit：[fdbc42a4e4f502385c1ad2f4dea697e3857cd2b7](https://github.com/OpenXiangShan/CoupledL2/tree/fdbc42a4e4f502385c1ad2f4dea697e3857cd2b7)

## 术语说明

| 缩写 | 全称 | 描述 |
| --- | --- | --- |
| ICache/I$ | Instruction Cache | L1 指令缓存 |
| DCache/D$ | Data Cache | L1 数据缓存 |
| L1 Cache/L1$ | Level One Cache | L1 缓存 |
| L2 Cache/L2$ | Level Two Cache | L2 缓存 |
| L3 Cache/L3$ | Level Three Cache | L3 缓存 |
| BEU | Bus Error Unit | 总线错误单元 |
| MMIOBridge | Memory-Mapped I/O Bridge | 内存映射 I/O 转接桥 |
| ECC | Error Correction Code | 错误校验码 |
| SECDED | Single Error Correct Double Error Detect | 单比特纠错双比特校验 |
| TL | Tile Link | Tile Link 总线协议 |
| CHI | | CHI 总线协议 | 

## 设计规格

- 支持 ECC 校验
- 支持 CHI DataCheck
- 支持 CHI Poison

## Cached 访存请求错误处理

基本的错误处理逻辑：由检测到错误的 Cache Level 进行错误上报；保存/传播地址对应错误状态

    1. L2 Cache 将在 L2 Cache 检测到的 ECC/DataCheck Error 上报至 BEU，由 BEU 触发中断向软件报告错误
    2. 对于来自 L1/L3 Cache 的请求，L2 Cache 会根据检测到的错误类型在通信中通知 L1/L3 Cache
    3. 对于来自 L1/L3 Cache 的错误数据，L2 Cache 会将错误类型记录在 meta 中


### ECC

#### ECC 校验码

L2 Cache 目前默认的 ECC 校验码为 SECDED。同时，L2 Cache 支持 parity、SEC 等校验码，可在 Configs 中修改，编译时进行配置。相关[校验算法参考](https://github.com/OpenXiangShan/Utility/blob/master/src/main/scala/utility/ECC.scala)。

SECDED 要求对于一个 𝑛 位的数据，所需的校验位数 r 需要满足：$ 2^r \geq n + r + 1 $

#### ECC 处理流程

L2 Cache 支持 ECC 功能。在 MainPipe 在 s3 向 Directory 和 DataStorage 重填数据时，会计算 tag 和 data 的校验码，前者与 tag 一起存入 Directory 中的 tagArray（SRAM），后者与 data 一起存入 DataStorage 中的 array（SRAM）。

    1. 对于 tag，直接以 tag 为单元进行 ECC 编码/解码。
    2. 对于 data，基于物理设计以及更好检测错误的需求，目前将 data 划分成 dataBankBits（128 bits）的单元进行 ECC 编码/解码。因而在 SECDED 算法要求下，对于 1 个 512 bits 的 cache line，应该有 4 * 8 = 32 bits 校验位。
    

当访存请求读取 SRAM 时，会同步读取出对应的校验码。MainPipe 会在 s2 和 s5 分别获得 tag 和 data 的校验结果。当 MainPipe 检验到错误后，会在 s5 收集错误信息，CoupledL2 仲裁各个 Slice 错误信号，并上报至 BEU。

### 总线端口

#### TL 总线

当 L2 Cache 接收来自 L1/L3 Cache 的数据时，若检测到错误（denied/corrupt = 1），则 MainPipe 在 s3 写 Directory 时，将对应 meta 中 tagErr/dataErr 置为 1。

当 L2 Cache 向 L1/L3 传输数据时，若 L2 Cache 检测到 ECC 错误或者对应 meta 中 tagErr/dataErr = 1，则将对应通道（如 D 通道 GrantBuffer）信号中 denied/corrupt 置为 1；否则均置为 0。

- 特别的，由于 TL C 通道中只有 corrupt 域而不存在 denied 域。故使用 opcode 域用于辅助区分 denied/corrupt。如 [SinkC](https://github.com/OpenXiangShan/CoupledL2/blob/master/src/main/scala/coupledL2/SinkC.scala) 中
```
task.corrupt := c.corrupt && (c.opcode === ProbeAckData || c.opcode === ReleaseData)
task.denied := c.corrupt && (c.opcode === ProbeAck || c.opcode === Release)
```

#### CHI 总线

L2 Cache 支持可配置的 Poison/DataCheck：
 - Poison 域：
    - DAT 中每 8 bytes 设置 1 bit Poison 位
    - L2 Cache 中 Poison 采用 over poison 策略
    - Poison 错误 L2 Cache 不进行上报
 - DataCheck 域：
    - DAT 中每 8 bits 设置 1 bit DataCheck 位
    - L2 Cache 中 DataCheck 默认采用奇校验
    - L2 Cache 中 DataCheck 仅对 data 进行校验，不对 packet 整体进行校验
    - DataCheck 校验错误由 L2 Cache 进行上报

当 L2 Cache 接收来自 L3 Cache 的数据时，若检测到错误：

    1. respErr = NDERR，则 MainPipe 在 s3 写 Directory 时，将对应 meta 中 tagErr 置为 1
    2. respErr = NDERR/DERR 或者 poison 域中任意一位为 1 或者 dataCheck 奇校验检验出错误时，则 MainPipe 在 s3 写 Directory 时，将对应 meta 中 dataErr 置为 1
    3. dataCheck 检验出错误，则复用 ECC 错误上报流程，MainPipe 在 s5 收集错误信息后，上报 BEU

当 L2 Cache 向 L3 Cache 传输数据时，

    1. 若 L2 Cache 检测到 tag ECC 错误或者对应 meta 中 tagErr = 1，则将 respErr 置为 NDERR，将 poison 置为全 0
    2. 若 L2 Cache 检测到 data ECC 错误或者对应 meta 中 dataErr = 1，则将 respErr 置为 DERR，并将 poison 域置为全 1
    3. 若 L2 Cache 未检测到任何错误，则将 respErr 置为 OK，将 poison 置为全 0
    4. dataCheck 域填充对 data 进行奇校验的校验码


## Uncached 访存请求错误处理

CoupledL2 中 MMIOBridge 会将 TL 与 CHI 之间的错误处理相关域进行转换，但不会进行任何错误上报。

CHI to TL（RXDAT）
    
    1. 若 respErr = NDERR，则置 denied 为 1
    2. 若 respErr = NDERR/DERR 或者 poison 域中任意一位为 1 或者 dataCheck 奇校验检验出错误时，则置 corrupt 为 1
    3. 否则，denied 与 corrupt 均置为 0
- 当出现错误时，后续由 ICache 或 DCache 触发 access fault，上报软件处理


TL to CHI（TXDAT）

    1. 当 corrupt = 1 时，若 opcode = Release，则置 respErr 为 NDERR，否则置 respErr 为 DERR
    2. 当 corrupt = 0 时，则置 respErr 为 OK
    3. dataCheck 域填充对 data 进行奇校验的校验码