# CUTE Matrix Compute Unit

## Terminology

Table: CUTE terminology {#tbl:cute-terms}

| Term            | Description                                                                                                                                    |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| CUTE            | A compute unit that accepts asynchronous matrix commands from the control core and performs matrix loads, multiply-accumulates, and stores     |
| TaskController  | The module responsible for matrix task decoding, dependency tracking, issue, and retirement                                                    |
| MatrixReg       | SRAM-based matrix registers inside CUTE, divided into shared AB registers and C accumulator registers                                          |
| MemoryLoader    | The data transfer modules between external memory and MatrixReg; AML and BML handle A and B loads, while CML handles C loads and result stores |
| DataController  | The modules that supply and collect data and control addresses between MatrixReg and the compute array, denoted ADC, BDC, and CDC              |
| MTE             | MatrixTE, a compute array composed of multiple FReducePE reduction multiply-accumulate units                                                   |
| Reduction block | The A and B vectors supplied to each PE in one operation, each 32 B by default; the element count depends on the data type                     |
| Task completion | The completion handshake of the corresponding MemoryLoader or DataController, or Release/NopLike completion within the scheduler               |
| Task retirement | TaskController releases a completed task from the head of the issue window; this is maintained separately from control-core ROB commit         |

## Functionality

CUTE performs matrix data transfers and matrix multiply-accumulates outside the control core. Through `AmuCtrlIO`, the control core sends commands whose operands, matrix register numbers, shapes, and data types have been determined. CUTE tracks matrix register dependencies between these commands and issues ready tasks to the execution modules. Matrix data remains in CUTE's MatrixReg; compute inputs and outputs do not pass through the control core's scalar register file.

The basic matrix multiply-accumulate operation is `C ← A × B + C`. A and B share four AB MatrixReg registers, while C uses four separate C MatrixReg registers. Each compute command reads two AB registers with different numbers and one C register, then writes the accumulated result back to the same C register. ADC and BDC use the read ports of the selected AB registers; see [Matrix Registers](MatrixReg.md) for the port constraints. Software organizes independent load, compute, and store commands around matrix tiles, and TaskController schedules these commands.

TaskController allows tasks with no dependencies and different execution resources to overlap. Reads and writes to the same matrix register are ordered by task age. Once the compute array has consumed the AB operands, subsequent loads may overwrite them early, allowing the next operands to load while the previous computation drains its pipeline.

## Overall Design

![CUTE modules, control paths, and data paths](./figure/cute-overview.svg){#fig:cute-overview}

In [@fig:cute-overview], control commands enter TaskController, and external data accesses HBL2 through LocalMMU and Cute2TL. AML/BML write A and B data to the selected AB MatrixReg; CML loads the initial accumulator matrix into C MatrixReg or stores results to external memory. ADC and BDC supply A and B vectors to MTE; CDC supplies C blocks and receives result D. The modules cooperate through task configuration interfaces and completion handshakes.

Table: CUTE submodules {#tbl:cute-submodules}

| Submodule                       | Function                                                                                                                                     |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| TaskController                  | Command buffering, issue window, matrix register dependencies, execution resource ownership, completion aggregation, and in-order retirement |
| ABMatrixReg                     | Four shared A/B storage arrays, with per-bank writes and reads of a complete vector group                                                    |
| CMatrixReg                      | Four C storage arrays supporting compute read-modify-write, initial-value loading, and result reads                                          |
| AMemoryLoader/BMemoryLoader     | Default ordinary A/B loads; the AML wrapper also hosts the shared A/B transpose-load engine and AB zeroing                                   |
| TransposeLoadEngine             | Collects source rows by response tag and writes them to AB registers through a two-slot buffer and transpose writeback pipeline              |
| CMemoryLoader                   | Default ordinary/transpose C loads, C zeroing, ordinary/transpose stores, and write acknowledgement tracking                                 |
| ADataController/BDataController | Generate AB read addresses, hold SRAM responses under backpressure, and supply the array                                                     |
| CDataController                 | Generates C read addresses, supplies accumulator values to the array, receives D, and writes it back to C                                    |
| MatrixTE/FReducePE              | An 8×8 PE array by default; A is broadcast along each row and B along each column, and each PE computes a vector dot product plus C          |
| LocalMMU                        | Access-stream arbitration, transaction ID allocation and source-tag encoding, and response routing                                           |
| Cute2TL                         | Converts internal memory requests to TileLink requests and merges matrix read data with ordinary acknowledgements                            |

LocalMMU forwards request addresses directly to Cute2TL and handles request arbitration and transaction IDs. The control-core MLSU translates the command base address; the loader uses it to generate each row's request addresses. Cute2TL uses a separate `matrix_data_in` channel for matrix read data, and request IDs pass through HBL2 extension fields. See [Memory Interface and System Integration](Integration.md) for interface details.

## Default Parameters

XSAI `DefaultMatrixConfig` uses the array and storage geometry of `CUTE_8Tops_128SCP` and sets CUTE's instruction capability switches through the control-core `MatrixExtension`. The following parameters determine the static hardware size; actual throughput also depends on clock frequency, task shape, and data supply.

Table: Default CUTE parameters {#tbl:cute-default-params}

| Parameter or resource       | Default value | Meaning                                                                                               |
| --------------------------- | ------------- | ----------------------------------------------------------------------------------------------------- |
| `Tensor_MN`                 | 128           | The AB outer dimension and the M and N storage capacities of C                                        |
| `Tensor_K`                  | 64 B          | Reduction-dimension storage capacity of each logical AB row: 64 INT8/FP8 elements or 32 BF16 elements |
| `Matrix_MN`                 | 8             | PE count in each of the M and N array dimensions, also the logical bank count of MatrixReg            |
| `ReduceWidthByte`           | 32 B          | Width of each A and B vector accepted by a PE per operation                                           |
| `ResultWidthByte`           | 4 B           | Width of each C and D element                                                                         |
| `outsideDataWidth`          | 512 bit       | Each external data transfer is 64 B                                                                   |
| AB MatrixReg                | 4×8 KiB       | Four shared A/B registers, 32 KiB in total                                                            |
| C MatrixReg                 | 4×64 KiB      | Four accumulator registers, 256 KiB in total                                                          |
| `TaskCtrlIssueWindowDepth`  | 8             | Issue-window depth; the preceding decoded FIFO has the same depth                                     |
| `MsyncRegs`                 | 32            | Number of control-core synchronization registers                                                      |
| `LoaderBridgeChannelConfig` | `ALBLCLLCSL`  | A load, B load, C load, and C store all use the default legacy implementations                        |
| `EnableMatrixPrefetch`      | false         | Matrix-guided prefetch interfaces and tags are not generated by default                               |

See [Matrix Registers](MatrixReg.md) for AB and C capacities, bank layouts, and single-port SRAM constraints. Ordinary loads using the legacy implementation issue external requests through internal channel 0; multichannel requests are used by the transpose engine or parameterized loaders.

## Data Types

Table: Default matrix multiply-accumulate types {#tbl:cute-default-types}

| A and B inputs                                             | Accumulator and result | Default configuration |
| ---------------------------------------------------------- | ---------------------- | --------------------- |
| Four signedness combinations of INT8/UINT8                 | INT32                  | Enabled               |
| FP8 E4M3×E4M3                                              | FP32                   | Enabled               |
| FP8 E5M2×E5M2                                              | FP32                   | Enabled               |
| BF16                                                       | FP32                   | Enabled               |
| FP16                                                       | FP32                   | Disabled              |
| TF32                                                       | FP32                   | Disabled              |
| 16-bit accumulation, INT4, FP32×FP32, block-scaled formats | —                      | Not enabled           |

TaskController dispatches these types to FPE. Default MMA sets the AfterOps control bits to disabled and writes results directly back to C; task valid for the Scale loader/controller remains false. Arith commands zero matrix registers; other Arith operations complete as `NopLike`. See [Compute Data Path](Compute.md) for FPE numerical behavior.

## Shape and Access Boundaries

Default computation uses `8 <= M <= 128` with M aligned to 8, `N = 128`, and a 64 B reduction dimension per A/B row: `K = 64` for INT8/FP8 or `K = 32` for BF16. CDC requires N to equal `Tensor_MN`; the controller rounds M up to the PE width. Bytes not covered by loads retain their old values, so the padded region must contain valid data before computation.

The AB loader writes with a fixed spacing of two entries per logical row, while DataController calculates row-group addresses from the number of reduction blocks in the task's K dimension. The two paths use the same layout for the default 64 B reduction dimension; addresses and tail data for short K must additionally satisfy the controller's access range. See [Compute Shape Constraints](Compute.md#sec:cute-compute-shape) and [Store Boundaries](MemoryLoader.md#sec:cute-store-boundary) for details.

## Chapter Organization

- [Task Control: TaskController](TaskController.md): command input, dependency masks, issue, completion, and Release.
- [Matrix Registers: MatrixReg](MatrixReg.md): AB/C capacities, address mapping, SRAM ports, and read/write timing.
- [Matrix Loads and Stores: MemoryLoader](MemoryLoader.md): ordinary loads, transposition, zeroing, result rearrangement, and parameterized channels.
- [Compute Data Path](Compute.md): controller traversal, broadcast array, FPE pipeline, and numerical behavior.
- [Memory Interface and System Integration](Integration.md): request IDs, TileLink extensions, return paths, and synchronization boundaries.
- [Performance Events and Debugging](Performance.md): hardware event meanings, counting semantics, and task tracing.

## Implementation References

This chapter corresponds to [XSAI DefaultMatrixConfig](https://github.com/OpenXiangShan/XSAI/blob/ee268923b717/src/main/scala/top/Configs.scala), [CUTE parameter definitions](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTEParameters.scala), and [CUTE top-level connections](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTETOP.scala).
