# Error Handling

- Version: V2R2
- Status: OK
- Date: 2025/04/24

## Glossary of Terms

| Abbreviation | Full name                                | Descrption                                               |
| ------------ | ---------------------------------------- | -------------------------------------------------------- |
| ICache/I$    | Instruction Cache                        | L1 instruction cache                                     |
| DCache/D$    | Data Cache                               | L1 Data Cache                                            |
| L1 Cache/L1$ | Level One Cache                          | L1 Cache                                                 |
| L2 Cache/L2$ | Level Two Cache                          | L2 cache                                                 |
| L3 Cache/L3$ | Level Three Cache                        | L3 Cache                                                 |
| BEU          | Bus Error Unit                           | Bus error unit                                           |
| MMIOBridge   | Memory-Mapped I/O Bridge                 | Memory-mapped I/O bridge.                                |
| ECC          | Error Correction Code                    | Error Check Code                                         |
| SECDED.      | Single Error Correct Double Error Detect | Single-bit error correction, double-bit error detection. |
| TL           | Tile Link.                               | Tile Link Bus Protocol                                   |
| CHI.         | Coherent Hub Interface                   | CHI 总线协议                                                 |

## Design specifications

- Supports ECC Check
- 支持 CHI DataCheck
- 支持 CHI Poison

## Cached 访存请求错误处理

Basic error handling logic: the Cache Level that detects the error reports it;
the error status corresponding to the address is saved/propagated.

    1. L2 Cache 将在 L2 Cache 检测到的 ECC/DataCheck Error 上报至 BEU，由 BEU 触发中断向软件报告错误
    2. 对于来自 L1/L3 Cache 的请求，L2 Cache 会根据检测到的错误类型在通信中通知 L1/L3 Cache
    3. 对于来自 L1/L3 Cache 的错误数据，L2 Cache 会将错误类型记录在 meta 中


### ECC

#### ECC Check Code

L2 Cache 目前默认的 ECC 校验码为 SECDED。同时，L2 Cache 支持 parity、SEC 等校验码，可在 Configs
中修改，编译时进行配置。相关[校验算法参考](https://github.com/OpenXiangShan/Utility/blob/master/src/main/scala/utility/ECC.scala)

SECDED 要求对于一个 $n$ 位的数据，所需的校验位数 $r$ 需要满足： $ 2^r \geq n + r + 1 $

#### ECC processing flow

L2 Cache 支持 ECC 功能。当 MainPipe 在 s3 向 Directory 和 DataStorage 重填数据时，会计算 tag 和
data 的校验码，前者与 tag 一起存入 Directory 中的 tagArray（SRAM），后者与 data 一起存入 DataStorage 中的
array（SRAM）

1. For tags, ECC encoding/decoding is performed directly on the tag as a unit.
2. For data, based on physical design and the need for better error detection,
   the data is currently divided into dataBankBits (128 bits) units for ECC
   encoding/decoding. Therefore, under the SECDED algorithm requirements, for a
   512-bit cache line, there should be 4 * 8 = 32 bits of check bits.

When a memory access request reads from SRAM, the corresponding check code is
synchronously read out. The MainPipe obtains the check results for the tag and
data at stages s2 and s5, respectively. Upon detecting an error, the MainPipe
collects error information at s5, the CoupledL2 arbitrates error signals from
various Slices, and reports them to the BEU.

### Bus port

#### TL 总线

When the L2 Cache receives data from L1/L3 Cache and detects an error
(denied/corrupt = 1), the MainPipe sets the tagErr/dataErr in the corresponding
meta to 1 when writing to the Directory in s3.

When the L2 Cache transmits data to L1/L3, if the L2 Cache detects an ECC error
or the corresponding meta has tagErr/dataErr = 1, the denied/corrupt signals in
the corresponding channel (e.g., D channel GrantBuffer) are set to 1; otherwise,
they are set to 0.

- 特别的，对于 TL D 通道返回数据时，若 denied = 1，则需要将对应 corrupt 也置为 1；在当前设计下，L2 Cache 不应认为 L1
  Cache 持有对应数据 copy（L1 Cache 在后续 Release 时，会直接丢弃对应 copy）

- 特别的，由于 TL C 通道中只有 corrupt 域而不存在 denied 域。故使用 opcode 域用于辅助区分 denied/corrupt。如
  [SinkC](https://github.com/OpenXiangShan/CoupledL2/blob/master/src/main/scala/coupledL2/SinkC.scala)
  中
```
task.corrupt := c.corrupt && (c.opcode === ProbeAckData || c.opcode === ReleaseData)
task.denied := c.corrupt && (c.opcode === ProbeAck || c.opcode === Release)
```

#### CHI Bus

L2 Cache 支持可配置的 Poison/DataCheck：
- Poison Field:
    - In DAT, 1 Poison bit is set for every 8 bytes.
    - The L2 Cache adopts an over-poison strategy for Poison.
    - Poison errors are not reported by the L2 Cache.

- DataCheck field:
    - In DAT, 1 DataCheck bit is set for every 8 bits.
    - In L2 Cache, DataCheck defaults to odd parity
    - In the L2 Cache, DataCheck only verifies the data and does not check the
      entire packet.
    - DataCheck errors are reported by the L2 Cache.

When the L2 Cache receives data from the L3 Cache and detects an error:

1. respErr = NDERR，则不会将对应数据写入 L2 Cache，但会完成其余流水线处理（例如，对于来自 L1 Cache 的 Acquire
   请求，L2 Cache 将会返回数据并将 denied 和 corrupt 置 1
2. respErr = NDERR/DERR 或者 poison 域中任意一位为 1 或者 dataCheck 奇校验检验出错误时，则 MainPipe 在
   s3 写 Directory 时，将对应 meta 中 dataErr 置为 1
3. If dataCheck detects an error, it reuses the ECC error reporting process.
   MainPipe collects the error information in s5 and reports it to BEU

When the L2 Cache transfers data to the L3 Cache:

1. If the L2 Cache detects a tag ECC error or the corresponding meta has tagErr
   = 1, it sets respErr to NDERR and poison to all 0s.
2. If the L2 Cache detects a data ECC error or the corresponding meta has
   dataErr = 1, it sets respErr to DERR and the poison field to all 1s.
3. 若 L2 Cache 检测到 data ECC 错误或者对应 meta 中 tagErr = 1 且 dataErr = 1， 则将 respErr 置为
   NDERR，将 poison 置为全 1
4. If no errors are detected in the L2 Cache, respErr is set to OK and poison is
   set to all 0s.
5. dataCheck 域填充对 data 进行奇校验的校验码

* In the current version, the L2-supported Write/Snoop transactions do not allow
  respErr to be NDERR in the relevant data packet transmissions (thus, respErr
  in TXDAT can only be DERR or OK in practice).

Coherence State Handling (RN receives a request containing NDERR):

1. 对于分配事务，L2 将正常处理流水线，但是不回将包含 NDERR 请求的相关数据写回 Directory 或者 DataStorage，缓存状态不变
   （具体相关事务类型为 ReadClean, ReadNotSharedDirty, ReadShared, ReadUnique,
   CleanUnique, MakeUnique）
2. For release transactions, the L2 processes them normally (specific related
   transaction types include WriteBack, WriteEvictFull, Evict,
   WriteEvictOrEvict).
3. 对于 Snoop，L2 probe L1（ToN），回复 SnpResp_I 以及 NDERR，一律不 forward（不回复 CompData），暂不将
   L2 对应缓存行置为 Invalid
4. For other transactions, L2 ensures the corresponding data cache state is not
   upgraded (in the current version, this is guaranteed by 1)

## Uncached memory access request error handling.

In CoupledL2, the MMIOBridge converts error-related fields between TL and CHI
but does not report any errors.

CHI to TL (RXDAT/RXRSP).

1. 若 respErr = NDERR，则置 denied 为 1
2. If respErr = NDERR/DERR or any bit in the poison field is 1 or dataCheck odd
   parity detects an error, then set corrupt to 1
3. Otherwise, both denied and corrupt are set to 0.

- Specifically, for RXRSP (e.g., Comp), since TL-SPEC requires certain response
  types (e.g., AccessAck) to have corrupt = 0, when respErr = NDERR/DERR, denied
  is set to 1.
- When an error occurs, the ICache or DCache subsequently triggers a Hardware
  Error, which is reported to the software for handling.

TL to CHI (TXDAT).

1. When corrupt = 1, set respErr to DERR and poison to all 1s
2. When corrupt = 0, set respErr to OK and poison to all 0s
3. dataCheck 域填充对 data 进行奇校验的校验码
