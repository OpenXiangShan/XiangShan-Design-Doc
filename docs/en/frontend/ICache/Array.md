# MetaArray and DataArray {#sec:icache-array}

## MetaArray Interleave {#sec:icache-metaarray-interleave}

MetaArray uses set-index interleave: sets with different `setIdx % NumInterleaveBanks` are stored in different physical SRAMs to reduce access conflicts. We require `NumInterleaveBanks` to be at least 2, so one fetch block can always be handled within one cycle (if not cross-line, access one `setIdx`; if cross-line, access `setIdx` and `setIdx + 1`, which fall into two different physical SRAMs).

The case with `NumInterleaveBanks = 2` is shown in [@fig:icache-metaarray-interleave]:

![MetaArray interleave](../figure/ICache/metaArray_interleave.png){#fig:icache-metaarray-interleave}

## DataArray Banking {#sec:icache-dataarray-bank}

DataArray splits one cacheline into multiple banks. Each bank stores part of one cacheline, and each access activates only the required banks, reducing power. The example below uses the default configuration where one 64B cacheline is split into eight 8B banks.

In V2R2, one fetch block had a fixed size of 34B, so each access always activated 5 banks. In V3, fetch-block size is determined by `takenCfiPosition` provided by BPU (that is, fetch-block range is from start address to the address of the first taken branch instruction predicted by BPU). BPU guarantees this value is conflict-free for ICache accesses. Therefore, ICache does not need to check `takenCfiPosition`; it can directly activate corresponding banks.

[@fig:icache-dataarray-bank] shows the DataArray banking design.

![Bank activation example](../figure/ICache/dataArray_bank.png){#fig:icache-dataarray-bank}

In [@fig:icache-dataarray-large-fb], the fetch block size is smaller than 64B and appears legal. Because its start position has an offset inside the bank, the head and tail of this fetch block fall into the same bank of different sets, which may look like an SRAM conflict.

But BPU design guarantees this case will not happen. In short, BPU-predictable `takenCfiPosition` must be before `startVAddr + 64B` aligned to a 32B boundary. In this example, it can be at most at the end of `bank3` in `set x+1`, and cannot reach `bank4` or later banks. For more details, see BPU design documentation.

![Potential conflict example](../figure/ICache/dataArray_large_fb.png){#fig:icache-dataarray-large-fb}
