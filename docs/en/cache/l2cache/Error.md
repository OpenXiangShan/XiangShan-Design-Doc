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
| CHI.         | Coherent Hub Interface                   | CHI bus protocol                                         |

## Design specifications

- Supports ECC Check
- Support CHI DataCheck
- Support CHI Poison

## Cached access request error handling

Basic error handling logic: the Cache Level that detects the error reports it;
the error status corresponding to the address is saved/propagated.

    1. L2 Cache 将在 L2 Cache 检测到的 ECC/DataCheck Error 上报至 BEU，由 BEU 触发中断向软件报告错误
    2. 对于来自 L1/L3 Cache 的请求，L2 Cache 会根据检测到的错误类型在通信中通知 L1/L3 Cache
    3. 对于来自 L1/L3 Cache 的错误数据，L2 Cache 会将错误类型记录在 meta 中


### ECC

#### ECC Check Code

The default ECC code for L2 Cache is currently SECDED. Meanwhile, L2 Cache also
supports parity, SEC, and other error-correcting codes, which can be modified in
Configs and configured at compile time. Related [Error Correction Code
Reference](https://github.com/OpenXiangShan/Utility/blob/master/src/main/scala/utility/ECC.scala).

For SECDED, for an $n$-bit data, the required number of check bits $r$ must
satisfy: $2^r \geq n + r + 1$

#### ECC processing flow

The L2 Cache supports ECC functionality. When MainPipe refills data to Directory
and DataStorage in s3, it calculates the check codes for tag and data. The
former is stored together with the tag in the tagArray (SRAM) of the Directory,
and the latter is stored together with the data in the array (SRAM) of the
DataStorage.

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

#### TL bus

When the L2 Cache receives data from L1/L3 Cache and detects an error
(denied/corrupt = 1), the MainPipe sets the tagErr/dataErr in the corresponding
meta to 1 when writing to the Directory in s3.

When the L2 Cache transmits data to L1/L3, if the L2 Cache detects an ECC error
or the corresponding meta has tagErr/dataErr = 1, the denied/corrupt signals in
the corresponding channel (e.g., D channel GrantBuffer) are set to 1; otherwise,
they are set to 0.

- Specifically, when data is returned on the TL D channel, if denied = 1, the
  corresponding corrupt must also be set to 1; in the current design, L2 Cache
  should not assume that L1 Cache holds a corresponding data copy (L1 Cache will
  directly discard the corresponding copy upon subsequent Release).

- Specifically, since the TL C channel only has a corrupt field and no denied
  field, the opcode field is used to assist in distinguishing denied/corrupt.
  For example, in
  [SinkC](https://github.com/OpenXiangShan/CoupledL2/blob/master/src/main/scala/coupledL2/SinkC.scala).
```
task.corrupt := c.corrupt && (c.opcode === ProbeAckData || c.opcode === ReleaseData)
task.denied := c.corrupt && (c.opcode === ProbeAck || c.opcode === Release)
```

#### CHI Bus

L2 Cache supports configurable Poison/DataCheck:
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

1. If respErr = NDERR, the corresponding data will not be written to L2 Cache,
   but the remaining pipeline processing will be completed (for example, for
   Acquire requests from L1 Cache, L2 Cache will return data and set denied and
   corrupt to 1).
2. When respErr = NDERR/DERR, or any bit in the poison field is 1, or the
   dataCheck parity check detects an error, then MainPipe, when writing to
   Directory in s3, will set dataErr in the corresponding meta to 1.
3. If dataCheck detects an error, it reuses the ECC error reporting process.
   MainPipe collects the error information in s5 and reports it to BEU

When the L2 Cache transfers data to the L3 Cache:

1. If the L2 Cache detects a tag ECC error or the corresponding meta has tagErr
   = 1, it sets respErr to NDERR and poison to all 0s.
2. If the L2 Cache detects a data ECC error or the corresponding meta has
   dataErr = 1, it sets respErr to DERR and the poison field to all 1s.
3. If L2 Cache detects a data ECC error, or the corresponding meta has tagErr =
   1 and dataErr = 1, then it will set respErr to NDERR and set poison to all
   1s.
4. If no errors are detected in the L2 Cache, respErr is set to OK and poison is
   set to all 0s.
5. The dataCheck field fills in the check code for odd parity check on the data.

* In the current version, the L2-supported Write/Snoop transactions do not allow
  respErr to be NDERR in the relevant data packet transmissions (thus, respErr
  in TXDAT can only be DERR or OK in practice).

Coherence State Handling (RN receives a request containing NDERR):

1. For allocation transactions, L2 will process the pipeline normally, but will
   not write the data related to the NDERR request back to Directory or
   DataStorage; the cache state remains unchanged (the specific related
   transaction types are ReadClean, ReadNotSharedDirty, ReadShared, ReadUnique,
   CleanUnique, MakeUnique).
2. For release transactions, the L2 processes them normally (specific related
   transaction types include WriteBack, WriteEvictFull, Evict,
   WriteEvictOrEvict).
3. For Snoop, L2 probes L1 (ToN), replies with SnpResp_I and NDERR, and does not
   forward (does not reply with CompData) in any case; it temporarily does not
   set the corresponding L2 cache line to Invalid.
4. For other transactions, L2 ensures the corresponding data cache state is not
   upgraded (in the current version, this is guaranteed by 1)

## Uncached memory access request error handling.

In CoupledL2, the MMIOBridge converts error-related fields between TL and CHI
but does not report any errors.

CHI to TL (RXDAT/RXRSP).

1. If respErr = NDERR, set denied to 1.
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
3. The dataCheck field fills in the check code for odd parity check on the data.
