# 错误处理

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
| CHI | Coherent Hub Interface | CHI 总线协议 | 

## 设计规格

- 支持 ECC 校验
- 支持 CHI DataCheck
- 支持 CHI Poison

## Cached 访存请求错误处理

基本的错误处理逻辑：由检测到错误的 Cache Level 进行错误上报；保存/传播地址对应错误状态

    1. L2 Cache 将本地 Directory/DataStorage 检错结果上报至 BEU；来自下级 CHI 的 DataCheck 错误并入 denied/corrupt 传播，当前本地上报条件未直接包含该外来检查结果
    2. 对于来自 L1/L3 Cache 的请求，L2 Cache 会根据检测到的错误类型在通信中通知 L1/L3 Cache
    3. 对于来自 L1/L3 Cache 的错误数据，L2 Cache 会将错误类型记录在 meta 中


### ECC

#### ECC 校验码

L2 Cache 默认的 ECC 校验码为 SECDED。同时，L2 Cache 支持 parity、SEC 等校验码，可在 Configs 中修改，编译时进行配置。相关[校验算法参考](https://github.com/OpenXiangShan/Utility/blob/master/src/main/scala/utility/ECC.scala)

SECDED 要求对于一个 $n$ 位的数据，先取 Hamming 校验位数 $h$，使其满足 $2^h \geq n + h + 1$；完整 SECDED 还需要 1 bit 总奇偶位，因此校验位数为 $h + 1$。

#### ECC 处理流程

L2 Cache 支持 ECC 功能。当 MainPipe 在 s3 向 Directory 和 DataStorage 重填数据时，会计算 tag 和 data 的校验码，前者与 tag 一起存入 Directory 中的 tagArray（SRAM），后者与 data 一起存入 DataStorage 中的 array（SRAM）

1. 对于 tag，直接以 tag 为单元进行 ECC 编码/解码。
2. 对于 data，基于物理设计以及便于检错的需求，将 data 划分成 dataBankBits（128 bits）的单元进行 ECC 编码/解码。在 SECDED 算法下，每个 128 bit 单元使用 9 bit 校验，编码后为 137 bit；对于 1 个 512 bit 的 cache line，总计使用 4 × 9 = 36 bit 校验位
    

当访存请求读取 SRAM 时，会同步读取出对应的校验码。MainPipe 会在 s2 和 s5 分别获得 tag 和 data 的校验结果。当 MainPipe 检测到本地 ECC 错误后，会在 s5 收集错误信息，CoupledL2 仲裁各个 Slice 的错误信号，并上报至 BEU。数据读路径返回原始数据并使用 `decode.error` 检错，没有将 `decode.corrected` 接回输出。

### 总线端口

#### TL 总线

当 L2 Cache 接收来自 L1/L3 Cache 的数据时，若检测到错误（denied/corrupt = 1），则 MainPipe 在 s3 写 Directory 时，将对应 meta 中 tagErr/dataErr 置为 1

当 L2 Cache 向 L1/L3 传输数据时，若 L2 Cache 检测到 ECC 错误或者对应 meta 中 tagErr/dataErr = 1，则将对应通道（如 D 通道 GrantBuffer）信号中 denied/corrupt 置为 1；否则均置为 0

- 特别的，对于 TL D 通道返回数据时，若 denied = 1，则需要将对应 corrupt 也置为 1；在当前设计下，L2 Cache 不应认为 L1 Cache 持有对应数据 copy（L1 Cache 在后续 Release 时，会直接丢弃对应 copy）

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
    - DataCheck 校验错误并入 corrupt 继续传播

当 L2 Cache 接收来自 L3 Cache 的数据时，若检测到错误：

1. respErr = NDERR，则不会将对应数据写入 L2 Cache，但会完成其余流水线处理（例如，对于来自 L1 Cache 的 Acquire 请求，L2 Cache 将会返回数据并将 denied 和 corrupt 置 1
2. respErr = NDERR/DERR 或者 poison 域中任意一位为 1 或者 dataCheck 奇校验检验出错误时，则 MainPipe 在 s3 写 Directory 时，将对应 meta 中 dataErr 置为 1
3. DataCheck 校验出错后并入 corrupt 传播

当 L2 Cache 向 L3 Cache 传输数据时，Tag 错误和 Data 错误分别影响请求可用性与数据可信度。通用的 CHI 错误语义可映射为 NDERR 或 DERR，但不同通道和事务允许发送的响应并不相同。对有数据的 Write/Snoop 事务，当前 `TXDAT` 只发送 DERR 或 OK：

1. 当 `task.corrupt = 1` 时，respErr 为 DERR，poison 域置为全 1
2. 当 `task.corrupt = 0` 时，respErr 为 OK，poison 域置为全 0
3. dataCheck 域填充对 data 进行奇校验的校验码

因此，不能把通用的 Tag/Data 错误组合直接视为当前 `TXDAT` 实际可发送的全部响应；无数据 `TXRSP` 及其他事务需要通过各自的发送路径判断。

一致性状态处理（RN 接收到包含 NDERR 请求）：

1. 对于分配事务，L2 将正常处理流水线，但是不回将包含 NDERR 请求的相关数据写回 Directory 或者 DataStorage，缓存状态不变 （具体相关事务类型为 ReadClean, ReadNotSharedDirty, ReadShared, ReadUnique, CleanUnique, MakeUnique）
2. 对于释放事务，L2 正常处理 （具体相关事务类型为 WriteBack, WriteEvictFull, Evict, WriteEvictOrEvict）
3. 对于 Snoop，L2 probe L1（ToN），回复 SnpResp_I 以及 NDERR，一律不 forward（不回复 CompData），暂不将 L2 对应缓存行置为 Invalid
4. 对于其他事务，L2 保证相应数据缓存状态不升级


## Uncached 访存请求错误处理

CoupledL2 中 MMIOBridge 会将 TL 与 CHI 之间的错误处理相关域进行转换，但自身不直接上报错误。后级 Uncache Store 会将返回的 denied/corrupt 形成 U_ECC 事件。

CHI to TL（RXDAT/RXRSP）
    
1. 若 respErr = NDERR，则置 denied 为 1
2. 若 respErr = NDERR/DERR 或者 poison 域中任意一位为 1 或者 dataCheck 奇校验检验出错误时，则置 corrupt 为 1
3. 否则，denied 与 corrupt 均置为 0

- 特别的，对于 RXRSP（如 Comp），由于 TL-SPEC 要求部分类型响应（如 AccessAck）中 corrupt 必须为 0，故当 respErr = NDERR/DERR 时，均置 denied 为 1
- 出现错误后，应根据请求类型选择同步异常：NC/MMIO Load 的 denied 产生 Load Access Fault，仅 corrupt 产生 Hardware Error；MMIO Store 写完成响应的 DERR/NDERR 均转成 denied，产生 Store Access Fault；取指路径的错误产生 Instruction Access Fault。Uncache Store 的错误还会形成 U_ECC 事件。


TL to CHI（TXDAT）

1. 当 corrupt = 1 时，则置 respErr 为 DERR，置 poison 为全 1
2. 当 corrupt = 0 时，则置 respErr 为 OK，置 poison 为全 0
3. dataCheck 域填充对 data 进行奇校验的校验码
