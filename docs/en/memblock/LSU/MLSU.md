# Matrix Load/Store Instruction Execution Unit: MLSU

## Functional Description

The matrix load/store instruction execution unit `MlsUnit` receives matrix Load / Store instructions from the memory issue queue, translates the base address, checks permissions, generates memory-access descriptors, and writes the control result back to the backend. After the instruction commits, CUTE's load and store units transfer matrix data through L2 according to the descriptor.

A matrix memory access proceeds through descriptor preparation, instruction commit, and data transfer. MLSU writeback means that the address-preparation result has reached the backend. After ROB commit, AmuCtrlBuffer sends the descriptor to CUTE; CUTE reports task completion after the data transfer finishes. See [CUTE matrix unit](../../cute/index.md) for matrix task execution and completion.

## Design Specifications

- Supports Load / Store control requests for A, B, and C matrix registers, including the transpose and whole-register memory-access forms defined in the decode table.
- Receives the base address and stride from integer registers, matrix dimensions from mx dimension registers, and matrix type configuration saved during decoding.
- Uses MemBlock's Load DTLB request port and the corresponding PMP check port; Load / Store permissions are distinguished by the TLB command.
- Supports MLSQ replay after TLB misses and pipeline cancellation after redirects.
- The default configuration instantiates 1 MLSU pipeline; VirtualMlsQueue and MlsQueueReplay each have 8 entries.

MLSU translates and checks permissions for the starting base address. The address-alignment condition `s0_addr_aligned` is fixed at true, and misaligned-exception detection for matrix memory accesses is not implemented. Load / Store triggers are not connected. Matrix data accesses use the path between CUTE and L2 and do not enter the scalar MisalignBuffer or Uncache processing flows.

The control-core decode table includes A / B Store, and MLSU can generate their descriptors. CUTE routes all Store tasks to CML, selecting a C register with the low two bits of the matrix number. Actual write data comes from a C register; the data-store path for A / B registers is not implemented.

## Overall Design

MLSU has four pipeline stages, s0–s3, whose functions are shown in [@fig:MLSU-pipeline].

![MLSU pipeline and matrix memory-access descriptor path](./figure/xsai-mlsu.svg){#fig:MLSU-pipeline}

Table: MLSU pipeline stage functions {#tbl:MLSU-stages}

| Stage | Main functions                                                                                                                                    | Output                                                    |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| s0    | Arbitrate initial issue and MLSQ replay, select base address, stride, and dimensions, check matrix number and dimensions, and send a DTLB request | Virtual base address and instruction information          |
| s1    | Receive DTLB results, generate the physical base address, and collect page faults, guest-page faults, and access faults                           | Physical base address, TLB-miss and exception information |
| s2    | Combine PMP / PMA results, determine replay, and generate issue-queue feedback                                                                    | Permission-check result and replay cause                  |
| s3    | Update MLSQ, generate AmuLsuIO, and write the instruction control result back to the backend                                                      | Matrix memory-access descriptor and exception information |

### s0: Request Arbitration and Address Translation Request

s0 receives initial issues from the issue queue and replays from MlsQueueReplay. Replay requests normally have priority. If the instruction being issued for the first time is older than the replay instruction, the replay is deferred so the older instruction executes first.

For an initial issue, the base address comes from `src(0)`, the row stride for a regular access comes from `src(1)`, and the two dimensions come from `src(2)` and `src(3)`. Their meanings depend on the target matrix: M and K for A, K and N for B, and M and N for C. Replay retains the original instruction, virtual base address, stride, and two dimensions and re-enters the same translation path.

The two dimensions describe the architectural matrix shape. CUTE determines the source memory layout from the matrix type and transpose flag. A regular B load uses N as the outer dimension and K as the contiguous dimension; a transposed B load reads a source matrix with K rows and N elements per row. `stride` is the byte distance between the start addresses of adjacent source-memory rows.

Table: A / B load descriptors and source memory layouts {#tbl:MLSU-source-layout}

| Load form    | Descriptor `row`, `column` | Source memory row count | Contiguous elements per row |
| ------------ | -------------------------- | ----------------------- | --------------------------- |
| Regular A    | M, K                       | M                       | K                           |
| Transposed A | M, K                       | K                       | M                           |
| Regular B    | K, N                       | N                       | K                           |
| Transposed B | K, N                       | K                       | N                           |

TaskController configures the regular loader or shared transpose engine according to the outer row count and contiguous dimension in the table above. See [Matrix loading and storing](../../cute/MemoryLoader.md) for address generation and bank mapping.

Whole-register memory accesses do not read the regular row stride or mx dimensions. Their stride is determined by register type: A / B uses `TRLEN / 8`, and C uses `ARLEN / 8`. The output descriptor dimensions are generated in s3.

s0 checks whether the matrix register number matches the A / B or C type. For accesses other than whole-register accesses, it also checks dimension bounds according to the element width and `ROWNUM`, `TRLEN`, and `ARLEN`, setting an illegal-instruction exception when a bound is exceeded. See [Matrix loading and storing](../../cute/MemoryLoader.md) and [Matrix computation](../../cute/Compute.md) for CUTE's dimension and tail-block handling conditions.

The virtual address in the DTLB request is the starting base address. Load uses `TlbCmd.read`, and Store uses `TlbCmd.write`. Current matrix requests are not issued as hypervisor-specific memory instructions; `hyperinst` is inactive.

### s1: Receiving DTLB Results

s1 receives the physical address and miss information returned by the DTLB. Load collects `loadPageFault`, `loadGuestPageFault`, and `loadAccessFault`; Store collects the corresponding Store exceptions. The instruction's ROB index travels through the pipeline to cancel affected requests on a redirect.

The MLSU s1 datapath receives DTLB results. CUTE subsequently accesses L2 for matrix data, through a path without StoreQueue / SBuffer data forwarding. For scalar Store visibility, `mfence` waits for SBuffer to drain. CUTE tasks establish dependencies through `mrelease` / `macquire` and synchronization counters; `mrelease` waits for older CUTE Stores.

### s2: Permission Checks and Replay Decision

s2 combines Load / Store access faults returned by PMP with existing exceptions. On a DTLB miss, it clears the exception vector for that cycle and marks the instruction for `C_TM` replay. `C_TM` is currently the only matrix replay cause; CUTE and L2 manage queuing and waiting for subsequent cache accesses.

MLSU also reports to the issue queue whether the replay queue can accept the request, along with other feedback. Instructions that complete translation and permission checks can proceed to writeback. Instructions requiring replay are retained and reissued by [Matrix load/store queue MLSQ](./LSQ/MLSQ.md).

### s3: Descriptor Generation and Writeback

s3 updates the address-preparation state in MLSQ and assembles `AmuLsuIO`. The descriptor contains the read/write direction, target matrix number, element width, physical base address, row stride, transpose flag, matrix type, and two dimensions.

Table: Matrix memory-access control information generated by MLSU {#tbl:MLSU-descriptor}

| Field                   | Meaning                                                                                            |
| ----------------------- | -------------------------------------------------------------------------------------------------- |
| `ls`                    | Whether the instruction is a Store                                                                 |
| `ms`                    | Matrix register number specified by the instruction                                                |
| `widths`                | Derived from the mcfg type for regular accesses; 8 bits for whole-register A / B and 32 bits for C |
| `baseAddr`              | Physical base address returned by the DTLB                                                         |
| `stride`                | Row stride for regular accesses, or the generated stride for whole-register accesses               |
| `transpose`             | Whether the access is transposed                                                                   |
| `isA` / `isB` / `isacc` | A, B, or C matrix selection                                                                        |
| `row` / `column`        | Two dimensions for regular accesses, or fixed dimensions for whole-register accesses               |

For whole-register C accesses, `row` is `ROWNUM`, and `column` is `ARLEN / 32`. Whole-register A dimensions are `ROWNUM × (TRLEN / 8)`; the B descriptor uses `(TRLEN / 8) × ROWNUM`. Whole-register B loads retain the regular B source layout: the default descriptor is 64×128, while source memory has 128 rows of 64 bytes each, with a 64 B row stride.

For regular C accesses, `widths` is generated from mcfg. The default CML store-reordering data is organized as 32-bit elements; result-type conversion and compact storage controlled by `widths` are not implemented. See [C store boundaries](../../cute/MemoryLoader.md#sec:cute-store-boundary) for the range of valid data written back.

MLSU places the descriptor in `amuCtrl` on the backend writeback interface, following the backend exception and commit paths. AmuCtrlBuffer forwards the control request to CUTE after normal instruction retirement. An unretired instruction canceled by an exception or redirect does not initiate data transfer in CUTE.

## Address and Exception Boundaries

MLSU performs one address translation and permission check on the starting base address. CUTE generates requests for each row from this physical base address, stride, and dimensions. LocalMMU arbitrates requests and routes transaction identifiers; it does not implement page-table walks or per-row address translation. Physical addresses of subsequent rows must be directly computable from the physical base address and stride. Later rows in a cross-page access do not pass through control-core translation or permission checks again.

The 512-bit matrix response interface carries data, task index, and channel number, without TileLink `denied` / `corrupt`. The Cute2TL response path also does not convert bus errors into precise control-core matrix exceptions. Matrix memory-access exceptions received by the control core originate from MLSU checks before task dispatch.

## Implementation

- [MlsUnit.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/mem/pipeline/MlsUnit.scala)
- [MemBlock.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/mem/MemBlock.scala)
- [Matrix control interface definitions](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/backend/fu/matrix/Bundles.scala)
