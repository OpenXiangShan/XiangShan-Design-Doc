# FallThrough {#sec:bpu-fallthrough}

This is an always-not-taken S1 predictor that provides a prediction result when all other predictors miss or predict not-taken.

If we ignore the various V3 features, it only needs to add the current prediction block start address to the prediction block size (64 bytes by default; for convenience we use 64 directly in the discussion below) to obtain the predicted target address, that is, the start address of the next prediction block.

However, in practice, the V3 S3 predictor group and Ifu/ICache impose some requirements on the S1 predictor group. These requirements can be satisfied by fallThrough, avoiding extra complexity in ubtb and abtb.

## Half-align {#sec:bpu-fallthrough-half-align}

For the details of half-align, please refer to the mbtb documentation. Since the S1 predictor group uses the start address directly as the index, i.e. it is not aligned, the S1 predictor group can predict any branch within 64 bytes if no restriction is applied. For branches that are within 64 bytes but cross two 32-byte boundaries, however, the S3 predictor group cannot predict or validate them.

For convenience, we define the aligned function as pseudo code below, which aligns an address to a 32-byte boundary by clearing the low 5 bits:

```text
define aligned(addr):
    return addr & ~0x1F // align to 32B
```

```text
        start = 0x0a
0x00    |        0x20             0x40             0x60             0x80
        |----------------------------------| S1 predictor limit range [0x0a, 0x4a]
        |-------------------------| S3 predictor limit range [0x0a, aligned(0x4a)=0x40]
```

Filtering out-of-range branches separately inside each predictor would be relatively complex to implement. Considering that all branches trained into the other predictors must have been included in some previous fallThrough prediction range (during cold start, the branch predictors are empty and can only make fallThrough predictions), we can simply forbid ranges that cross two 32-byte boundaries inside the fallThrough predictor to avoid out-of-range predictions [^bpu-fallthrough-32b-limit].

[^bpu-fallthrough-32b-limit]: Ideally this would be the case, but the actual mbtb implementation is not ideal, so mbtb still has special handling. See the mbtb documentation.

The pseudo code is roughly:

```text
target = aligned(start + 0x40)
```

Next, consider cfiPosition. For the detailed definition, see the overall Bpu design document. To restate it briefly, cfiPosition is the offset, in instructions, of the address predicted as a branch instruction relative to the 32-byte aligned prediction block start address:

```text
cfiPosition = (cfiAddr - aligned(start))[5:1]
```

Without the half-align restriction, calculating cfiPosition requires the subtraction above. After applying the restriction, it becomes much simpler: the cfi predicted by fallThrough is the last instruction before the next 32-byte aligned address, so its offset relative to the 32-byte aligned prediction block start address is obviously a constant:

```text
cfiPosition = (cfiAddr - aligned(start))[5:1]
            = ((target - 2) - aligned(start))[5:1]
            = (aligned(start) + 0x40 - 2 - aligned(start))[5:1]
            = 31
```

Semantically, fallThrough's cfiPosition may seem useless, because it does not actually jump and is not even a real cfi. However, ICache/Ifu currently use it to calculate the fetch position (that is, the data SRAM bank to access), so it must provide a reasonable value to minimize the number of banks accessed, thereby saving power and reducing bank conflicts in 2-fetch mode [^bpu-fallthrough-icache-conflict].

[^bpu-fallthrough-icache-conflict]: In the V2 design, ICache always assumed a 34-byte read and did not need to use the Bpu-predicted position, while Ifu chose based on the Bpu-predicted taken result: when taken, it computed the predicted block size from the Bpu-predicted position; when not taken, it computed it from the target. Therefore, the V2 fallThrough prediction did not need to consider this. V3 is roughly moving the logic of “use target-start when not taken” from Ifu into the Bpu itself.

## Forbid Fetch Blocks from Crossing Pages {#sec:bpu-fallthrough-no-cross-page}

In the V3 design, to save Itlb area, Ifu/ICache assume that a single fetch request will not cross a page boundary (4 KB), which means the Bpu must guarantee that the predicted cfiPosition and start are within the same page.

Similar to half-align, we can satisfy this requirement by restricting fallThrough predictions without introducing extra complexity into ubtb/abtb.

The concrete method is similar to half-align as well. We first compare the PFN (physical page number, i.e. bits above address bit 11) of start + 64 and start [^bpu-fallthrough-pfn-compare]. If they differ, we use the 4 KB aligned result as the target:

```text
define pageAligned(addr):
    return addr & ~0xFFF // align to 4KB
```

```text
if pfn(start + 0x40) != pfn(start):
    target = pageAligned(start + 0x40)
else:
    target = aligned(start + 0x40)
```

[^bpu-fallthrough-pfn-compare]: In fact, since +64 can cross at most one page boundary, we only need to compare the least significant bit of the PFN.

Next, consider cfiPosition. When crossing a page boundary, cfiPosition is no longer a constant and must be calculated from target and start:

```text
if pfn(start + 0x40) != pfn(start):
    cfiPosition = ((target - 2) - aligned(start))[5:1]
                = (pageAligned(start + 0x40) - 2 - aligned(start))[5:1]
    // Note that when taking [5:1], the high bits are ignored, so - aligned(start) and - aligned(start) - 0x40 have the same effect.
    // Since aligned only masks the low 5 bits, - aligned(start) - 0x40 and - aligned(start + 0x40) have the same effect.
                = (pageAligned(start + 0x40) - 2 - aligned(start + 0x40))[5:1]
    // In two's complement representation, taking the negative is equivalent to bitwise not plus one, so
                = ~(aligned(start + 0x40) - pageAligned(start + 0x40))[5:1]
else:
    cfiPosition = 31
```
