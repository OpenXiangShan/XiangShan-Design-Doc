# Compute Data Path

## Design Specifications

- Default MatrixTE contains 8×8 FReducePEs.
- Each PE accepts 256-bit A and B inputs and one 32-bit C, and produces one 32-bit D.
- A vectors are broadcast along array rows, and B vectors along array columns.
- ADC, BDC, and CDC supply data in the same traversal order, with lockstep MTE input handshakes.
- FReducePE contains an input-decode register stage and MACPipe0 through MACPipe4, totaling six valid register stages with per-stage backpressure.
- Accumulation state across reduction blocks resides in C SRAM and advances through block-by-block read-modify-write.

## Overall Design

![MatrixTE broadcast array, FReducePE pipeline, and C read-modify-write](./figure/cute-compute.svg){#fig:cute-compute}

In [@fig:cute-compute], ADC reads eight A reduction vectors at a time, and BDC reads eight B reduction vectors. PE `(i,j)` computes the dot product of the i-th A vector and j-th B vector and adds element `(i,j)` of the C block. The 64 outputs are concatenated in row-major order into a 256 B D block, which CDC writes back to the C register.

A is broadcast along array rows, and B along array columns. Each PE independently receives a complete pair of reduction vectors, computes the dot product and accumulator value in its own pipeline, and produces the corresponding D element.

## Compute Shape Constraints {#sec:cute-compute-shape}

Let `P = Matrix_MN = 8` and `R = ReduceWidthByte = 32 B`. TaskController converts the K element count to bytes according to the input format, then divides by R to obtain `Kreduce`. ADC/BDC round M up, while CDC first pads M to a multiple of P; CDC requires N to equal `Tensor_MN = 128`.

The default full shape uses `N=128`, M aligned to 8 and no greater than 128, and 64 bytes along K per A/B row. K is 64 for INT8/FP8 and 32 for BF16; both correspond to two 32 B reduction blocks.

A and B must select different AB matrix register numbers, namely `ms1 != ms2`. The control-core Mma does not check this condition, but CUTE's shared AB read ports assert a conflict if ADC and BDC select the same register; see [Matrix Registers](MatrixReg.md).

Dimension counting and memory access behavior are as follows:

- If M is not aligned to 8, the controllers still read and compute a complete final group of 8 rows; padded row contents depend on previous MatrixReg values and preceding loads or zeroing.
- N is fixed at 128, and CDC checks this condition with an assertion.
- K bytes divided by 32 gives an integer reduction-block count; every counted block participates in computation as a complete 32 B block, with no valid-element mask within the block.
- The AB loader writes with a fixed spacing of two entries per logical row, while ADC/BDC compute row-group addresses from task `Kreduce`. The two agree when `Kreduce=2`; short K changes compute read addresses but retains loader write spacing.
- The byte mask controls bytes updated by a load; uncovered bytes retain old data and may fall within subsequent compute read ranges.

The control core checks instruction shape upper bounds, and CUTE traversal and address generation follow these rules. Software tiling must satisfy dimension checks, MatrixReg layout, and full-block access ranges together, and prepare data in padded regions read by computation.

## DataController Traversal and Data Supply

### Addresses and Loop Order

Let `Mb=ceil(M/8)` and `Nb=N/8=16`, with `kr` the 32 B reduction-block index. M is the instruction's row count; the final group is processed as a complete row group even if it contains fewer than 8 rows. The three controllers traverse N blocks fastest, then M blocks, then K reduction blocks:

```text
for kr in 0 .. Kreduce-1:
    for mb in 0 .. Mb-1:
        for nb in 0 .. Nb-1:
            Aentry = mb * Kreduce + kr
            Bentry = nb * Kreduce + kr
            Centry = mb * Nb + nb
            Dblock = dot(Ablock, Bblock) + Cblock
            C[Centry] = Dblock
```

The same group of eight A row reduction vectors is reused across N blocks, and the same group of eight B column vectors is reused across M blocks. Each reduction block reads C, computes, and writes C once for all M and N blocks before the next reduction block begins. The next accumulation reads the previous result from C SRAM again.

A complete task supplies `Mb × Nb × Kreduce` input groups to the array and writes back the same number of D blocks. Execution time depends on input handshake intervals together with configuration, SRAM latency, and pipeline fill and drain.

### ready, valid, and hold

MTE combines the A, B, and C input ready signals of PE(0,0) into `ComputeGo` and sends that ready to all three input paths. All PEs execute in lockstep with the same configuration; CDC broadcasts D ready, and D valid is taken from PE(0,0). A and B inputs must handshake in the same cycle.

`ComputeGo` indicates that the array can currently accept the next input group. ADC/BDC/CDC use it to coordinate SRAM reads. If the array applies backpressure when MatrixReg returns data one cycle later, DataController stores the return in a single-entry hold register. Hold data takes priority on subsequent sends, and the consumed-input count advances only on actual `fire`.

ADC and BDC complete independently after supplying all their input vectors to the array, allowing TaskController to release the corresponding AB read dependencies. CDC reports overall Compute completion after receiving and writing back the final D; TaskController then releases the Compute resource and C access dependencies.

### C Writeback

MTE produces row-major 8×8 D. CDC writes each row's eight elements as a 32 B entry into one C bank; all banks use the same entry address and an all-ones write mask. Write-address traversal advances through N blocks and M blocks, then returns to the start and advances the K reduction-block count after a complete pass.

Default MMA sets post-processing controls such as `Is_AfterOps_Tile` to false and writes compute results in the ordinary C layout. Subsequent transpose stores execute as separate CML store tasks.

## FReducePE Pipeline

### Interface and Input Decoding

FReducePE has a 4-bit `opcode`; `AVector`, `BVector`, and `CAdd` inputs use ready/valid. Input decoding converts different formats to a common sign, 10-bit exponent, and significand representation; integers distinguish signed/unsigned, while BF16 and FP8 extend to the internal significand width. TaskController generates E4M3×E4M3 and E5M2×E5M2 compute types for FP8, with A and B using the same format in each type.

Within the default 256-bit vector, INT8/FP8 contain 32 elements and BF16 contains 16. A PE's vector byte width is fixed, while its reduction element count depends on the input format.

Table: FReducePE register stages {#tbl:cute-fpe-pipeline}

| Register stage | Main operation                                                                                                                                                               |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Input decoding | Converts A, B, and C to internal types and stores the group's opcode and exception properties                                                                                |
| MACPipe0       | Forms products and product exponents; INT8/FP8 use two product paths and begin maximum-exponent comparison                                                                   |
| MACPipe1       | Completes maximum-exponent comparison, generates per-term alignment shifts, and combines NaN, Inf, zero, and other properties                                                |
| MACPipe2       | Extends floating-point products to 26 bits and right-shifts for alignment; integers bypass floating-point alignment; sums each group of four terms into a partial sum        |
| MACPipe3       | Combines partial sums and C into the reduction result; retains the second group's result for merging in the next stage                                                       |
| MACPipe4       | Merges the two INT8/FP8 groups; outputs 32-bit integer results or performs floating-point leading-zero counting, normalization, mantissa truncation, and exception selection |

Each register stage holds valid and propagates backpressure through per-stage AllowIn. It accepts the next data group only when empty or when the next stage can accept it; a blocked stage retains its data. One data group passes through six register stages in sequence; a matrix task processes multiple input groups continuously and completes after final result writeback.

### Integer Computation

Integer inputs are sign- or zero-extended according to opcode and undergo reduction multiply-accumulate, producing a 32-bit result. TaskController ignores `sat` in the MMA Bundle; FPE uses a fixed integer data path and truncates results exceeding the output width to that width.

### Floating-Point Computation

The floating-point path first compares product and C exponents, then aligns to a common exponent for grouped reduction. The main alignment data width is 26 bits, with low bits truncated on right shifts. Normalization uses leading-zero counting and shifts to extract the FP32 mantissa; output uses the truncated result directly, without G/R/S-driven RNE rounding correction. The MMA Bundle's `rm` field does not control computation in TaskController or FPE; results follow the fixed grouping, alignment, and normalization order.

An exponent above 127 after normalization produces Inf with the corresponding sign; below −126, the significand is shifted further right to form a subnormal result; below −149, the significand is set to zero. These shifts also truncate.

Exception selection uses fixed outputs: NaN is `0x7fc00000`, and positive and negative Inf are `0x7f800000` and `0xff800000`, respectively. E4M3 decoding follows its finite-number and NaN format rules, and the all-negative-zero path ultimately produces positive zero. The FPE output interface carries 32-bit D data; floating-point exception properties are used internally in the pipeline for result selection.

## Compute Type Configuration

DefaultMatrixConfig enables INT8→INT32, FP8→FP32, and BF16→FP32. Static configuration switches determine whether FPE paths such as FP16, TF32, MXFP8, MXFP4, and NVFP4 are instantiated; they are disabled in this configuration.

Block-scaled inputs are supplied by Scale MatrixReg, Scale loaders, and Scale controllers. Current TaskController holds task valid for ASL, BSL, ASC, and BSC false, and the default configuration disables these data-supply paths.

The default top level performs multiply-accumulate through MatrixTE, and CDC writes directly back to C SRAM; AfterOps, FakeVPU, and VectorStreamInterface are not instantiated. The mzero operation in Arith commands zeros matrix registers through loaders; other Arith commands complete as `NopLike` within the scheduler.

## Implementation References

This section corresponds to [MatrixTE](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/MatrixTE.scala), [ADataController](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/ADataController.scala), [BDataController](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/BDataController.scala), [CDataController](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/CDataController.scala), [FReducePE](https://github.com/OpenXiangShan/CUTEFPE/blob/7b40bf01ccfcc17ea7a54a610d9dceab0256c84a/fpe/src/main/scala/top/FReducePE.scala), and [MACPipes](https://github.com/OpenXiangShan/CUTEFPE/blob/7b40bf01ccfcc17ea7a54a610d9dceab0256c84a/fpe/src/main/scala/top/MACPipes.scala).
