# Kunming Lake PrunedAddr Documentation

## Background Introduction

In the RISC-V manual, the descriptions for B-Type and J-Type instructions are as
follows:

> The only difference between the S and B formats is that the 12-bit immediate
> field is used to encode branch offsets in multiples of 2 in the B format.
> Instead of shifting all bits in the instruction-encoded immediate left by one
> in hardware as is conventionally done, the middle bits (imm[10:1]) and sign
> bit stay in fixed positions, while the lowest bit in S format (inst[7])
> encodes a high-order bit in B format.
> 
> Similarly, the only difference between the U and J formats is that the 20-bit
> immediate is shifted left by 12 bits to form U immediates and by 1 bit to form
> J immediates. The location of instruction bits in the U and J format
> immediates is chosen to maximize overlap with the other formats and with each
> other.

This means that for branch instructions other than `jalr`, the least significant
bit of the jump target must be 0. For the `jalr` instruction, the manual
describes the calculation of the jump target as follows:

> The target address is obtained by adding the sign-extended 12-bit I-immediate
> to the register rs1, then setting the least-significant bit of the result to
> zero.

This implies that the least significant bit of the jump target for `jalr` is
also 0.

Combining these two parts, we can observe that all PCs must have their least
significant bit as 0. Consequently, the frontend does not need to store the
least significant bit for any PC-related operations, which saves area.

In practice, when the C extension is disabled, the lower 2 bits of the PC must
be 0; otherwise, an instruction misalignment exception will be raised.

## Usage Guide

The design goal of `PrunedAddr` is to make its usage as similar as possible to
`UInt`. However, due to Chisel limitations, this goal cannot be fully achieved.
In areas where it differs from `UInt`, it can be analogized to `Reg` or `Wire`.
Specific usage guidelines are as follows:

- Use `PrunedAddrInit` to convert from `UInt` to `PrunedAddr`, e.g., `val addr1
  = PrunedAddrInit(addr2)`, where `addr2` is of type `UInt`
- Use `toUInt` to convert from `PrunedAddr` to `UInt`, e.g., `addr.toUInt`.
- The method `def +(offset: UInt)` should only be used when `offset` is an
  immediate. For other cases, `def +(offset: PrunedAddr)` should be used. If
  `offset` is `UInt` and not an immediate, `offset` should be converted to
  `PrunedAddr`.

## Outstanding Issues

- Currently, the use of `PrunedAddr` is limited to the frontend internals, while
  the frontend-backend interface still employs `UInt`. Ideally, the backend
  should also fully adopt `PrunedAddr`. In this case, the `toUInt` method should
  only be used when outputting debug information.
- The method `def &gt;&gt;(offset: Int)` should be removed to reduce confusion.
  The corresponding functionality can be achieved by directly selecting the
  relevant bits.
- For the number of pruned bits, the current implementation uses the parameter
  `instOffset`. Theoretically, this parameter should change with the
  enable/disable state of the C extension. However, Xiangshan currently does not
  support disabling the C extension, and the correctness of disabling the C
  extension has not been verified.
