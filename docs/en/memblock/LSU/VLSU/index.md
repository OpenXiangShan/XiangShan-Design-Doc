# Vector Memory Access

## Submodule List

| Submodule                         | Descrption                                                                                      |
| --------------------------------- | ----------------------------------------------------------------------------------------------- |
| [VLSplit](VLSplit.md)             | Vector Load uop splitting module                                                                |
| [VSSplit](VSSplit.md)             | Vector Store uop splitting module                                                               |
| [VLMergeBuffer](VLMergeBuffer.md) | Vector Load flow merge module                                                                   |
| [VSMergeBuffer](VSMergeBuffer.md) | Vector Load flow merge module                                                                   |
| [VSegmentUnit](VSegmentUnit.md)   | Vector Segment execution module                                                                 |
| [VfofBuffer](VfofBuffer.md)       | Vector fault-only-first instruction write-back VL register uop collection and write-back module |


## Functional Description

- Supports all memory access instructions in RVV 1.0
- Supports out-of-order scheduling for Vector Load/Store instructions
- Supports out-of-order execution of Uops split from Vector Load/Store
  instructions
- Supports vector out-of-order violation checking and recovery
- Supports unaligned vector memory access
- Vector memory access to non-Memory space is not supported

### Parameter configuration

|   Parameters   | Configuration (number of entries) |
| :------------: | :-------------------------------: |
|      VLEN      |                128                |
| VLMergeBuffer  |                16                 |
| VSMergeBuffer  |                16                 |
| VSegmentBuffer |                 8                 |
|   VFOFBuffer   |                 1                 |

### Functional Overview

Before entering the VLSIssueQueue, the Dispatch stage allocates indices for the
Load Queue or Store Queue. After vector memory access instructions are split
into uops in the backend, they are first decoded in the Vsplit module to
calculate masks and address offsets, while also requesting Mergebuffer entries.
In the new vector memory access architecture, the scalar LoadUnit & StoreUnit,
as well as Load Queue & Store Queue, are reused.

Vector Load and Store share two Issue Queues. For vector Load, the two Issue
Queues connect to two VLSplits. For vector Store, the two Issue Queues connect
to two VSSplits. The two VLSplits correspond to LoadUnit0 and LoadUnit1
respectively. The two VSSplits correspond to StoreUnit0 and StoreUnit1
respectively. When a vector Load requires replay via the Replay Queue, it may be
resent to a different load unit. After vector memory access completes execution
in the pipeline, the results are aggregated by the merge buffer and written
back.


## Overall Block Diagram

Overall block diagram pending update
<!-- 请使用 svg -->
