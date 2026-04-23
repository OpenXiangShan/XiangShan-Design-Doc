# XiangShan ICache Design Document

- Version: V3
- Status: draft
- Date: 2026/04/22
- commit: TODO

## Glossary

| Abbreviation | Full Name | Description |
| --- | --------- | ------------ |
| ICache/I$ | Instruction Cache | L1 instruction cache |
| L2 Cache/L2$ | Level Two Cache | L2 cache |
| FTQ | Fetch Target Queue | Fetch target queue, see [FTQ design doc](../FTQ/index.md) |
| IFU | Instruction Fetch Unit | Fetch unit, see [IFU design doc](../IFU/index.md) |
| ITLB | Instruction Translation Lookaside Buffer | Address translation buffer |
| PMP | Physical Memory Protection | Physical memory protection module |
| PMA | Physical Memory Attribute | Physical memory attribute module (part of PMP) |
| BEU | Bus Error Unit | Bus error unit |
| FDIP | Fetch-directed Instruction Prefetch | Fetch-directed instruction prefetch |
| MSHR | Miss Status Holding Register | Miss status holding register |
| af | Instruction Access Fault | Access fault, exception code 1 in RISC-V |
| (g)pf | Instruction (Guest) Page Fault | Instruction (guest) page fault, exception code 12 (20) in RISC-V |
| hwe | Hardware Error | Hardware error, exception code 19 in RISC-V |
| vaddr | Virtual Address | Virtual address |
| (g)paddr | (Guest) Physical Address | (Guest) physical address |
| PBMT | Page-Based Memory Types | Page-based memory types, see the Svpbmt extension |
| fb | Fetch Block | Fetch block |

## Submodules

| Submodule | Description |
| --- | --------- |
| [PrefetchPipe](PrefetchPipe.md) | Prefetch pipeline |
| [MainPipe](MainPipe.md) | Main pipeline |
| [WayLookup](WayLookup.md) | Metadata buffer queue |
| [MetaArray](Array.md) | Metadata array |
| [DataArray](Array.md) | Data array |
| [MissUnit](MissUnit.md) | Miss handling unit |
| [Replacer](Replacer.md) | Replacement policy unit |
| [CtrlUnit](CtrlUnit.md) | Control unit, currently only for ECC check/error injection control |

## Design Specifications

- Cache instruction data.
- Request data from L2 through TileLink on miss.
- Software maintains L1 I/D cache coherence (`fence.i`).
- Support cross-cacheline (pre)fetch requests.
- Support flush (BPU redirect, backend redirect, `fence.i`).
- Support prefetch requests.
  - Hardware prefetch uses the FDIP algorithm.
  - Software prefetch uses the Zicbop `prefetch.i` instruction.
- Support configurable replacement policy.
- Support configurable number of miss status registers.
- Support translation/protection checks.
- Support error checking and error injection[^ecc].
  - Parity code is used by default.
  - Error injection control registers are software-visible through MMIO.
- DataArray supports banked storage for lower power.
- Support serving two fetch blocks in one cycle when SRAM accesses do not conflict. See [@sec:icache-2fetch] [2-fetch](#2-fetch-secicache-2fetch).

[^ecc]: In this document, error checking and error injection features are also referred to as ECC. See [@sec:icache-ecc] [ECC](#ecc-secicache-ecc).

## Parameters

See `case class ICacheParams` in `Parameters.scala`. Selected parameters are listed below:

| Parameter | Default | Description | Requirement |
| ------ | --- | --------- | ------ |
| nSets | 256 | Number of SRAM sets | Power of 2 |
| nWays | 4 | Number of SRAM ways | |
| rowBits | 64 | Data width of each bank | Factor of `(blockBytes * 8)` |
| blockBytes | 64 | Bytes per cacheline | Fixed 64B for RVA23 profile |
| Replacer | "setplru" | Replacement policy | Supported by rocket-chip ReplacementPolicy, currently including "random", "setlru", "setplru" |
| NumFetchMshr | 4 | Number of fetch MSHRs | |
| NumPrefetchMshr | 10 | Number of prefetch MSHRs | |
| WayLookupSize | 32 | WayLookup depth, also used to backpressure and limit max prefetch distance | |
| MetaEcc | "parity" | ECC type for MetaArray | "parity" or "secded" |
| DataEcc | "parity" | ECC type for DataArray | "parity" or "secded" |
| DataEccUnit | 64 | ECC unit size in bits; one check bit per data unit | Factor of `rowBits` |
| NumInterleavedBank | 2 | Number of interleaved banks in MetaArray | Power of 2 and >= 2 |
| MetaWaySplit | 2 | Number of physical-way splits in MetaArray, for SRAM PPA tuning | Factor of `nWays` |
| MetaDataSplit | 1 | Number of physical-data splits in MetaArray, for SRAM PPA tuning | |
| DataPaddingBits | 1 | Extra padding bits per DataArray entry, for SRAM PPA tuning | |
| EnableCtrlUnit | true | Whether to instantiate CtrlUnit; if false, ECC features are not software-controllable | |
| ctrlUnitParameters | - | CtrlUnit parameters | See [@sec:icache-ctrlunit] [CtrlUnit doc](./CtrlUnit.md) |

## Functional Overview

> Before reading this document, it is recommended to read the FDIP and Decoupled Frontend papers in the references for prerequisite background.

> This document and related code are still under active construction. Some descriptions may reflect intended design behavior and may not be fully implemented yet.

ICache structure is shown in [@fig:icache-structure].

![ICache structure](../figure/ICache/pipeline.png){#fig:icache-structure}

From a structural view, ICache mainly consists of:

- prefetchPipe: prefetch pipeline; interacts with MetaArray and ITLB to obtain metadata and handles prefetch requests.
- mainPipe: main pipeline; reads DataArray, handles fetch requests, performs ECC checks, and sends results to IFU.
- wayLookup: buffer between prefetchPipe and mainPipe; stores metadata query results.
- metaArray: stores cacheline metadata (tag, valid, maybeRvc, etc.) and check bits.
- dataArray: stores cacheline data and check bits.
- missUnit: maintains MSHR state, accepts miss requests, sends requests to L2 cache, and refills SRAM on response.
- ctrlUnit: control unit; software can control ICache behavior through MMIO-mapped CSRs, currently only ECC-check related behavior.

From a pipeline view, to save read ports and power, ICache uses serialized MetaArray/DataArray access and a tightly coupled prefetch+fetch design. This means all fetch blocks must go through prefetchPipe first and then enter mainPipe in the same order, which is guaranteed by FTQ design.

After reset or redirect, the first fetch request is sent to both mainPipe and prefetchPipe. Since wayLookup is empty, mainPipe stalls for one cycle and waits for prefetchPipe to write metadata into wayLookup. At that point, prefetchPipe s0 is shared by prefetch and fetch flows, and prefetchPipe s1 and mainPipe s0 are in the same logical pipeline stage. During steady-state operation, mainPipe may stall because of ICache misses, full IBuffer, and so on, while prefetchPipe can keep running. wayLookup then gets filled, and mainPipe/prefetchPipe run in parallel until the next redirect, with prefetchPipe s0 and mainPipe s0 in the same logical stage.

Both prefetchPipe and mainPipe decide miss/exception status based on metadata from MetaArray and ITLB. If there is no exception and a miss occurs, missUnit sends an L2 cache request. For prefetchPipe, processing can complete after issuing the prefetch miss. For mainPipe, processing completes only after refill and data delivery to IFU.

## Functional Details

### Prefetch Requests

ICache may accept prefetch requests from two sources:

1. Hardware prefetch requests from FTQ, based on FDIP.
2. Software prefetch requests from LoadUnit in MemBlock, which are essentially Zicbop `prefetch.i` instructions (see the RISC-V CMO specification).

However, prefetchPipe can process only one prefetch request per cycle, so arbitration is required. ICache top-level logic buffers software prefetch requests, then chooses one request between software and FTQ hardware prefetch to send into prefetchPipe. Software prefetch has higher priority, as shown in [@fig:icache-prefetch-source].

Logically, each LoadUnit may issue a software prefetch request, so up to `LduCnt` requests (current default `LduCnt=3`) may appear in one cycle. Considering implementation cost and performance benefit, ICache only accepts and processes one per cycle; the rest are dropped, and the smallest port index wins. In addition, if prefetchPipe is blocked and ICache already buffers one software prefetch request, the buffered request may be overwritten.

![ICache prefetch request receive and arbitration](../figure/ICache/prefetch_source.png){#fig:icache-prefetch-source}

The handling flow for hardware prefetch requests is:

1. Query MetaArray and ITLB to get metadata, including wayMask (bitmask indicating which way hits), physical address, exception information, and so on.
2. Write metadata into wayLookup for mainPipe.
3. Decide whether to issue a prefetch request based on wayMask and exception information.
    1. If needed, send to missUnit for miss handling.

Software prefetch follows almost the same flow, but since it does not affect control flow, its metadata is not sent to wayLookup (therefore not sent to mainPipe and later stages).

For pipeline-stage details, see [@sec:icache-prefetchpipe] [PrefetchPipe doc](PrefetchPipe.md).

### Fetch Requests

The handling flow for fetch requests is:

1. Read metadata from wayLookup.
2. Read DataArray by wayMask to get instruction data (if hit).
3. Decide whether to issue a fetch miss request based on wayMask and exception information.
    1. If needed, send to missUnit for miss handling.
4. Send instruction data and metadata to IFU.
5. Perform ECC checks on instruction data/metadata and send check results to IFU (if enabled).

For pipeline-stage details, see [@sec:icache-mainpipe] [MainPipe doc](MainPipe.md).

### Cross-page Fetch Requests {#sec:icache-cross-page}

In V3, to save ITLB ports, ICache does not allow fetch requests crossing page boundaries. That is, the up-to-two fetch blocks and up-to-two cachelines in one fetch request must be in the same page (`vaddr[49:12]` equal). ICache hardware itself does not directly check this; BPU and FTQ guarantee it. Specifically:

- When BPU generates a fetch block, if `startVAddr + 64` falls into the next page (that is, `startVAddr[49:12]` differs from `(startVAddr + 64)[49:12]`), BPU truncates the fetch block at the page boundary by marking `takenCfiPosition` at the last instruction in the current page.
- When FTQ tries to send a 2-(pre)fetch request, it checks whether the two fetch blocks are in the same page. If not, FTQ will not send a 2-(pre)fetch request.

### 2-(pre)fetch {#sec:icache-2fetch}

To improve fetch bandwidth in branch-intensive scenarios, V3 ICache supports 2-(pre)fetch requests, meaning each cycle can accept one (pre)fetch request carrying up to two fetch blocks. 2-prefetch and 2-fetch are decoupled by wayLookup (for example, fb0 and fb1 can be sent to prefetchPipe as one 2-prefetch request and enqueued into wayLookup in one cycle, while mainPipe may process fb0 in one cycle and then process a 2-fetch containing fb1 and fb2 in the next cycle). Considering hardware complexity and performance trade-offs, both 2-prefetch and 2-fetch have constraints.

Constraints for 2-prefetch requests:

1. Software prefetch does not support 2-prefetch. Only FTQ hardware prefetch supports 2-prefetch.
2. As described in [@sec:icache-cross-page], the two fetch blocks in one 2-prefetch request must be in the same page.
3. In FTQ, `bpuPtr - pfPtr` must be >= 4. In other words, flushing of the second fetch block caused by BPU s3 override must complete inside FTQ. Once a 2-prefetch request is sent to prefetchPipe, BPU is not allowed to flush it (backend-redirect-triggered flush still applies).
4. The two fetch blocks must not cause MetaArray read-port conflicts; one of the following must hold:
    1. They are in the same cacheline.
    2. They are in adjacent cachelines, and the later fetch block (larger setIdx) is not cross-line.
    3. They are in interleaved cachelines, and neither fetch block is cross-line.

Some conflict examples are shown in [@fig:icache-2prefetch-conflict]:

![2-prefetch conflict examples](../figure/ICache/2prefetch_conflict.png){#fig:icache-2prefetch-conflict}

Constraints for 2-fetch requests:

1. TODO

### Exception Propagation and Special-case Handling

ICache checks fetch-request permissions through ITLB and PMP and receives L2 responses. Possible exceptions are listed in [@tbl:icache-exception].

Table: ICache exception list {#tbl:icache-exception}

| Source | Exception | Description | Handling |
| --- | --- | --------- | ------------ |
| ITLB | af | Access fault during virtual-address translation | Block fetching, mark block as af, send to backend through IFU |
| ITLB | gpf | Guest page fault | Block fetching, mark block as gpf, send to backend through IFU, and pass valid `gpaddr` plus `isForNonLeafPTE` to backend GPAMem |
| ITLB | pf | Page fault | Block fetching, mark block as pf, send to backend through IFU |
| backend | af/pf/gpf | Same as ITLB af/gpf/pf | Same as ITLB af/gpf/pf |
| PMP/PMA | af | Physical address has no permission | Mark block as af, send to backend through IFU |
| L2 | corrupt | L2 cache response `corrupt` | Mark block as hwe, send to backend through IFU |
| L2 | denied | L2 cache response `denied` | Mark block as af, send to backend through IFU |
| ECC | corrupt | ECC check error | Mark block as hwe, send to backend through IFU |

Additional notes:

1. In normal fetch flow, there is no backend exception item. However, for hardware resource saving, XiangShan frontend only carries 41/50-bit PC (Sv39*4/Sv48*4), while target addresses of instructions like `jr`/`jalr` come from 64-bit registers. According to RISC-V, addresses whose high bits are not all-0 or all-1 are illegal and must raise exceptions. This check can only be done in backend, then sent to FTQ together with backend redirect signals, and then sent to ICache together with fetch requests. It is essentially an ITLB-type exception, so its description/handling is the same as ITLB exceptions.
2. In V2R2, PMP/PMA existed as a standalone module. In V3, for timing reasons, PMP/PMA checks are moved earlier to ITLB refill. At the ICache interface, PMP/PMA results are returned together with ITLB results. Because their meanings differ, they are still listed separately in the table.
3. In V2R2, hwe exceptions (introduced in RISC-V Privileged Spec v1.13) were not supported. Therefore, V2R2 handled the above hwe scenarios as af and did not distinguish L2 `corrupt` (for example, L2 ECC check error) from `denied` (for example, bus permission denied). V3 supports hwe.
4. In V2R2, ECC auto-retry on error was implemented, so ECC errors did not raise exceptions (unless retry hit an L2 exception). V3 removed this feature for design simplification and timing, and now raises hwe for software handling.

These exceptions have priority: backend > ITLB > PMP > L2 = ECC. This is natural:

1. With backend exception, vaddr sent to frontend is incomplete/illegal, so ITLB translation is meaningless and ITLB exception results are invalid.
2. With ITLB exception, translated paddr is invalid, so PMP check is meaningless and PMP exception results are invalid.
3. With PMP exception, paddr has no access permission; fetch request is invalid and no L2 request is sent, so L2/ECC checks are invalid.
4. L2 and ECC checks are inherently mutually exclusive: L2 is on miss path, ECC is on hit path, so relative priority is irrelevant.

For the three backend exception types and three ITLB exception types, backend/ITLB each selects one with internal priority so at most one is asserted at a time.

In addition, some mechanisms trigger special cases. In older docs/code they were also called exceptions, but they do not raise RISC-V-defined `exception`. To avoid confusion, they are referred to as special cases hereafter, as listed in [@tbl:icache-special-case].

Table: ICache special case list {#tbl:icache-special-case}

| Source | Special case | Description | Handling |
| --- | --- | --------- | ------------ |
| PMP | mmio | Physical address is in MMIO space | Block fetching, mark block as mmio, IFU performs **non-speculative** fetch |
| ITLB | pbmt.NC | Page attribute is non-cacheable and idempotent | Block cache fetch, IFU performs **speculative** fetch |
| ITLB | pbmt.IO | Page attribute is non-cacheable and non-idempotent | Same as pmp mmio |

### Flush

When backend/IFU redirect, BPU redirect, or `fence.i` happens, selected storage structures and pipeline stages in ICache must be flushed depending on reason. Possible flush targets/actions include:

1. All pipeline stages in MainPipe and PrefetchPipe
   - During flush, set `s0/1/2_valid` to `false.B`.
2. `valid` in MetaArray
   - During flush, set `valid` to `false.B`.
   - `tag` and `code` do not need flushing because their validity is controlled by `valid`.
   - Data in DataArray does not need flushing because its validity is controlled by MetaArray `valid`.
3. WayLookup
   - Reset read/write pointers.
   - Set `gpf_entry.valid` to `false.B`.
4. All MSHRs in MissUnit
   - If an MSHR has not sent a request to bus yet, simply invalidate it (`valid === false.B`).
   - If an MSHR has already sent a bus request, mark it pending-flush (`flush === true.B` or `fencei === true.B`), and invalidate it when the D-channel grant returns. At that time, grant data is neither replied to MainPipe/PrefetchPipe nor written into SRAM.
   - Note that if D-channel grant and flush (`io.flush === true.B` or `io.fencei === true.B`) arrive in the same cycle, MissUnit still does not write SRAM, but **does** reply data to MainPipe/PrefetchPipe to avoid introducing port latency into response logic. MainPipe/PrefetchPipe also receive the flush in that cycle, so they will discard the data.

Flush targets per flush reason are listed in [@tbl:icache-flush].

Table: ICache flush target list {#tbl:icache-flush}

| Flush reason | 1 | 2 | 3 | 4 |
| ------ | --- | --- | --- | --- |
| backend/IFU redirect | Y | | Y | Y |
| BPU redirect | Y[^redirect_tab_bpu] | Y[^redirect_tab_bpu] | | |
| `fence.i` | Y[^redirect_tab_fencei] | Y | Y[^redirect_tab_fencei] | Y |

[^redirect_tab_bpu]: BPU precise predictor (result from BPU s3) may override simple predictor (result from BPU s0). Its redirect reaches ICache at most 2 cycles after prefetch issue, so only prefetchPipe s0/s1 and tail entries in wayLookup need to be flushed. See related submodule docs.

[^redirect_tab_fencei]: Logically, `fence.i` needs to flush MainPipe and PrefetchPipe (because in-flight data may become invalid). But in current implementation, assertion of `io.fencei` always accompanies backend redirect, so explicit MainPipe/PrefetchPipe flush by `fence.i` is unnecessary.

ICache does not accept fetch/prefetch requests while flushing (`io.req.ready === false.B`).

#### ITLB Flush Notes

ITLB flush is special. Cached PTEs only need flushing on `sfence.vma`, and that path is handled by backend, so frontend/ICache normally does not manage ITLB flush. There is one exception: currently ITLB does not store `gpaddr` to save resources. When `gpf` occurs, ITLB refetches from L2TLB, and the retry state is controlled by a `gpf` cache. This requires ICache, after receiving `ITLB.resp.excp.gpf_instr`, to ensure one of the following:

1. Re-issue the same `ITLB.req.vaddr` until `ITLB.resp.miss` deasserts (then `gpf` and `gpaddr` are both valid and can be normally sent to backend). ITLB will flush its `gpf` cache in this process.
2. Assert `ITLB.flushPipe`, in which case ITLB flushes its `gpf` cache.

If ITLB `gpf` cache is not flushed, and a request with a different `ITLB.req.vaddr` arrives and causes another `gpf`, the core may hang.

Therefore, whenever PrefetchPipe s1 is flushed, regardless of reason, ICache must also flush ITLB `gpf` cache (that is, assert `ITLB.flushPipe`).

### ECC {#sec:icache-ecc}

First, note that with default parameters, ICache uses parity code, which only provides 1-bit error detection and no correction. Strictly speaking, this is not ECC (Error Correction Code). However, secded is configurable, and many code symbols use ECC naming for error detection/recovery features (`ecc_error`, `ecc_inject`, etc.). Therefore this document still uses ECC to refer to error detection, error recovery, and error injection features for consistency with code.

ICache supports error detection, error recovery, and error injection as part of RAS[^ras], and these are controlled by CtrlUnit. Refer to RISC-V RERI[^reri].

[^ras]: This RAS (Reliability, Availability, and Serviceability) is different from RAS (Return Address Stack).

[^reri]: RERI (RAS Error-record Register Interface), see the [RISC-V RERI specification](https://github.com/riscv-non-isa/riscv-ras-eri).

#### Error Detection

When MissUnit refills MetaArray and DataArray, it computes check bits for metadata and data. Metadata check bits are stored together with metadata in Meta SRAM, while data check bits are stored in dedicated Data Code SRAM.

When a fetch request reads SRAM, check bits are read out together. MainPipe checks metadata/data in s1/s2 respectively. Software can enable/disable this feature by writing specific values to CSR fields. In versions around Jun-Dec, this control used custom CSR `sfetchctl`; later it was changed to MMIO-mapped CSR. See [CtrlUnit doc](./CtrlUnit.md).

For check-code design, the code type is parameterized. Default is parity, where check bit is reduction XOR of data: $code = \oplus data$. At check time, reduction XOR is applied on data and code: $error = (\oplus data) \oplus code$. If result is 1, an error is detected; otherwise it is **considered** no error (even-numbered bit errors may still escape detection).

After [#4044](https://github.com/OpenXiangShan/XiangShan/pull/4044), ICache supports error injection, which requires writing incorrect check bits into MetaArray/DataArray. A `poison` bit is introduced: when asserted, it flips the write code, i.e., $code = (\oplus data) \oplus poison$.

To reduce undetected cases, data is currently split into DataCodeUnit chunks (default 64 bits), and parity is computed per chunk. Therefore for each 64B cacheline, $8(data) + 1(meta) = 9$ check bits are generated.

When MainPipe detects an error in s1/s2, it performs:

1. Error handling: raise hwe exception for software handling.
2. Error reporting: report the error to BEU, which then raises interrupt for software.
3. Request canceling: if MetaArray check fails, read ptag is unreliable, so hit/miss judgment is unreliable. Therefore no L2 request is sent regardless of hit/miss result; exception is directly propagated to IFU and then backend.

#### Error Injection

According to RISC-V RERI[^reri], to let software test ECC behavior and better validate hardware functionality, hardware should provide error injection, i.e., proactively trigger ECC errors.

ICache error injection is controlled by CtrlUnit and triggered by writing specific values to fields in MMIO-mapped CSRs. See [CtrlUnit doc](./CtrlUnit.md).

Currently ICache supports:

- Injection by target paddr; injection fails when target paddr misses.
- Injection into MetaArray or DataArray.
- Injection fails when ECC check itself is not enabled.

A simplified software injection flow is:

```asm
inject_target:
  # maybe do something
  ret

test:
  la t0, $BASE_ADDR     # load base address of mmio-mapped CSR
  la t1, inject_target  # load target address for injection
  jalr ra, 0(t1)        # jump to target to ensure it is loaded into ICache
  sd t1, 8(t0)          # write target address to CSR
  la t2, ($TARGET << 2 | 1 << 1 | 1 << 0)  # set target/select + inject enable + check enable
  sd t1, 0(t0)          # write injection request to CSR
loop:
  ld t1, 0(t0)          # read CSR
  andi t1, t1, (0b11 << (4+1)) # read injection status
  beqz t1, loop         # keep waiting if injection not finished

  addi t1, t1, -1
  bnez t1, error        # jump to error handling if injection fails

  jalr ra, 0(t1)        # injection succeeds; jump to target to trigger error
  j    finish           # finish

error:
  # handle error
finish:
  # finish
```

A test case has been implemented in [this repository](https://github.com/OpenXiangShan/nexus-am/pull/48), covering:

1. Normal MetaArray injection.
2. Normal DataArray injection.
3. Invalid target injection.
4. Injection with ECC check disabled.
5. Injection on miss target address.
6. Attempting to write read-only CSR fields.

## References

1. Glenn Reinman, Brad Calder, and Todd Austin. "[Fetch directed instruction prefetching.](https://doi.org/10.1109/MICRO.1999.809439)" 32nd Annual ACM/IEEE International Symposium on Microarchitecture (MICRO). 1999.
