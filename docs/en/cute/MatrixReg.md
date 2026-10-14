# Matrix Registers: MatrixReg

## Design Specifications

CUTE uses four shared AB MatrixReg registers and four C MatrixReg registers. A and B are roles in matrix operations, and both roles select inputs from the same set of AB registers; C stores initial accumulator values and results. TaskController tracks task dependencies directly by matrix register number.

Table: Default matrix register organization {#tbl:cute-matrixreg-geometry}

| Property               | AB MatrixReg                | C MatrixReg                                                  |
| ---------------------- | --------------------------- | ------------------------------------------------------------ |
| Register count         | 4                           | 4                                                            |
| Capacity per register  | 128×64 B = 8 KiB            | 128×128×4 B = 64 KiB                                         |
| Logical bank count     | 8                           | 8                                                            |
| Bank entry width       | 32 B                        | 32 B, containing eight 32-bit elements                       |
| Depth per logical bank | 32                          | 256                                                          |
| SRAM per logical bank  | One 32-row single-port SRAM | One 128-row single-port SRAM each for odd and even addresses |
| Read latency           | 1 cycle                     | 1 cycle                                                      |
| Loader write mask      | Per byte                    | Per byte                                                     |

![Bank and SRAM organization of AB and C matrix registers](./figure/cute-matrixreg.svg){#fig:cute-matrixreg}

Each logical bank's 32 B data in [@fig:cute-matrixreg] is composed of byte-wide ways, with the SRAM waymask serving as byte write enables. Partial writes update only the masked bytes; other bytes retain the previous register contents. Zeroing is performed by separate ZeroTr or ZeroAcc tasks.

## AB Address Mapping

Let `P = Matrix_MN`, `P = 8`; each logical row has a capacity of `Tensor_K = 64 B`, and each bank entry has a width of `R = ReduceWidthByte`, `R = 32 B`. Each logical row therefore occupies two entries. A stores M reduction vectors in its register; B stores N reduction vectors for column-wise broadcast. The load path performs any required B transposition; BDC reads reduction vectors that have already been arranged.

For outer index `r` and byte offset `q` within that row, the default physical address is:

```text
bank       = r % 8
entry      = floor(r / 8) * 2 + floor(q / 32)
byteInEntry = q % 32
```

Bank 0 thus stores logical rows 0, 8, 16, and so on, with each row occupying two adjacent entries. Bank 1 stores logical rows 1, 9, 17, and so on, and the remaining banks follow the same pattern. A complete group read takes one 32 B entry from each of the eight banks, yielding eight reduction vectors totaling 256 B.

Table: Default AB layout examples {#tbl:cute-ab-layout}

| Logical row | bank | Entry for the first 32 B | Entry for the second 32 B |
| ----------- | ---- | ------------------------ | ------------------------- |
| 0–7         | 0–7  | 0                        | 1                         |
| 8–15        | 0–7  | 2                        | 3                         |
| 120–127     | 0–7  | 30                       | 31                        |

ADC selects one AB register, and BDC selects another. The top level does not allow both DataControllers to select the same AB register in the same cycle or both loaders to write the same AB register in the same cycle. TaskController dependencies and FU selection must satisfy these port constraints together.

## AB Read/Write Control

MemoryLoader supplies per-bank addresses, data, and byte masks; DataController supplies read addresses for all eight banks. ABMatrixReg gives writes priority: when a loader write address or write operation is present, the entire DataController group read is blocked. Even if only one bank is written that cycle, the other banks cannot complete that group read.

When no write request is present and DataController requests a read, `BankAddr.ready` permits the read. SRAM returns data in the next cycle, and `Data.valid` is the read-enable signal delayed by one cycle. ABMatrixReg does not retain read data rejected by downstream logic; ADC/BDC hold registers provide this storage.

For example, a read address accepted in cycle t returns data from all eight banks in cycle t+1. If MTE cannot accept it in t+1, DataController holds the group until a later input handshake. Data supply intervals are affected by both loader write priority and MTE backpressure.

## C Address Mapping

Each C bank entry contains eight adjacent N elements from one matrix row. For matrix coordinates `(m,n)`, the default mapping is:

```text
bank  = m % 8
entry = floor(m / 8) * 16 + floor(n / 8)
lane  = n % 8
```

Here 16 is `Tensor_MN / Matrix_MN`. Lanes 0–7 of an entry hold eight elements along N; the same entry across eight banks forms an 8×8 C matrix block. MTE results are concatenated in row-major order, and CDC writes each output row to its corresponding bank.

Table: Default C layout examples {#tbl:cute-c-layout}

| Matrix coordinate range | bank  | entry | lane  |
| ----------------------- | ----- | ----- | ----- |
| m=0–7, n=0–7            | m     | 0     | n     |
| m=0–7, n=8–15           | m     | 1     | n−8   |
| m=8–15, n=0–7           | m−8   | 16    | n     |
| m=120–127, n=120–127    | m−120 | 255   | n−120 |

M row groups have a fixed physical spacing of 16 entries, which CML store also uses for reads. Loads and stores with smaller logical N still use this fixed layout; the compute path requires N to equal 128, as described in [Compute Shape Constraints](Compute.md#sec:cute-compute-shape).

## Even/Odd Single-Port Organization of C

Each logical C bank is split into even and odd physical SRAMs by the least significant bit of the entry address:

```text
physicalBank = entry % 2
physicalRow  = floor(entry / 2)
```

A read of an even entry and a write of an odd entry in the same cycle, or the reverse, can use two different SRAMs. Each physical SRAM has only one access port; a same-cycle read and write to the same even or odd SRAM trigger a conflict assertion, so access timing must satisfy this port constraint.

CMatrixReg accepts request classes from CDC, CML load, and CML store. CDC reads initial C and writes D; CML load writes C; CML store reads C. The module asserts that two read sources or two write sources cannot be present in the same cycle. TaskController guarantees task ordering for the same C register; load, compute, and store on different C registers may overlap using their separate storage arrays.

The request class is delayed by one cycle to select the receiver of the next-cycle SRAM response. CDC compute writeback uses a full-entry mask; CML load may use a partial byte mask, particularly for transpose loads that update one 32-bit lane at a time.

## Zeroing and Partial Updates

`ZeroTr` uses AML to write zeros to all banks of the selected AB register entry by entry; `ZeroAcc` uses CML load to do the same for the selected C register. Neither task issues external memory requests, but both occupy the corresponding loader and complete after the final internal write.

Ordinary and transpose loads write only bytes covered by valid data; the remaining region retains its previous contents. Computation reads complete reduction blocks and row groups, so valid values must also be prepared in tail padding regions. MatrixReg updates bytes individually, while C store writes complete external beats; see [Matrix Loads and Stores](MemoryLoader.md).

## Implementation References

This section corresponds to [ABMatrixReg](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/ABMatrixReg.scala), [CMatrixReg](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CMatrixReg.scala), [register parameters](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTEParameters.scala), and [top-level register port selection](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CUTETOP.scala).
