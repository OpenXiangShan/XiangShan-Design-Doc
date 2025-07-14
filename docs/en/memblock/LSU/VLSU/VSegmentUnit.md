# Vector Segment Memory Access Instruction Processing Unit VSegmentUnit

## Functional Description

The main structure is an 8-entry queue, where each entry has a 128-bit address
register, a 128-bit data register, an index/stride register, and registers for
storing the physical register numbers, write enables, uopidx, and other
information of different uops. Additionally, there is a register for storing the
decoding information of the entire instruction. Internally, a state machine
controls the splitting process according to the segment order.

In VSegmentUnit.scala, there are comments integrated with the code. You can read
the following text in conjunction with these comments and the code to understand
the relevant logic of the SegmentUnit.

During the execution of Segment instructions, the out-of-order backend of the
pipeline must ensure that all preceding instructions have completed execution,
and no subsequent instructions can enter the pipeline (similar to the waiting
mechanism of atomic instructions). Additionally, it must guarantee that the uops
of the instructions enter the SegmentUnit in the order they were split. Only
then can the SegmentUnit ensure the sequence of Segment instructions.

### Feature 1: Splitting Segment Instructions

![alt text](./figure/VSegment-split.png)

- segmentIdx: The sequence number of the segment, where segmentIdx <= vl. It
  indicates the current segment being processed and is also used for data
  selection and merging.
- fieldIdx: Index of the field, used to identify whether the current segment
  transmission has ended. fieldIdx < nfields.
- fieldOffset: The relative offset of elements within the same segment,
  implemented as an accumulator with a step of 1.
- segmentOffset: Used to record the offset between different Segments. For
  stride instructions, it is an accumulator with stride granularity; for
  unit-stride, it is an accumulator with nfield*eew granularity; for index, it
  is the index register element corresponding to segmentIdx.
- vaddr = baseaddr + (fieldIdx << eew) + segmentOffset

The above diagram shows an example of queue pointer jumps under the
configuration of lmul=1, nf=2, vl=16. segmentIdx points to the current split
segment, while SplitPtr points to the split field register. In the diagram,
segmentIdx is 0 and splitPtr is 0. After splitting and accessing the first
element of the first uop, SplitPtr increments by nf to access the field1 element
of segment0. After accessing field2, the current segment's element access is
complete, segmentIdx increments by 1, and SplitPtr jumps to the field0 register
of the next segment. When segmentIdx reaches 8, it corresponds to the first
element of the next uop in the field0 register group (the second element in each
field register in the diagram). When segmentIdx=16 and the field2 element access
is completed, the instruction execution ends. For segment Index, there is
another pointer used to select the index register, implemented similarly to
selecting different registers of the same field as described above.

### Feature 2: fault only first modifies the VL register's uop to be written back separately

For fault-only-first instructions, VSegmentUnit does not use VfofBuffer to write
back additional uops. Instead, it transitions to s_fof_fix_vl to write back uops
modifying the VL register.

### Feature 3: Supporting Segment's Misaligned Memory Access

The VSegmentUnit instruction independently executes unaligned memory accesses
without relying on MisalignBuffer. The VSegmentUnit itself handles the splitting
of unaligned instructions and the merging of data.

## State transition diagram

![alt text](./figure/VSegmentUnit-FSM.svg)

**Status Introduction**

|                    Status | Description                                                                                       |
| ------------------------: | ------------------------------------------------------------------------------------------------- |
|                    s_idle | Waiting for SegmentUnit uop to enter                                                              |
|       s_flush_sbuffer_req | flush sbuffer                                                                                     |
| s_wait_flush_sbuffer_resp | Wait for Sbuffer and StoreQueue to be empty.                                                      |
|                 s_tlb_req | Query DTLB                                                                                        |
|           s_wait_tlb_resp | Wait for DTLB response.                                                                           |
|                      s_pm | Check execution permissions.                                                                      |
|               s_cache_req | Request to read DCache                                                                            |
|              s_cache_resp | DCache response                                                                                   |
|     s_misalign_merge_data | Merge unaligned Load Data.                                                                        |
|    s_latch_and_merge_data | Merge the Data of each element into complete uop-granularity Data                                 |
|               s_send_data | Send Data to Sbuffer                                                                              |
|         s_wait_to_sbuffer | Wait for the pipeline stage sending to Sbuffer to clear, i.e., actually sent to Sbuffer           |
|                  s_finish | The instruction execution is completed, and starts writing back to the backend in uop granularity |
|              s_fof_fix_vl | Fault-only-first instruction data uop has been written back, write-back uop modifying VL register |

## Decoding Instance

### Segment Unit-Stride/Stride

Unit-stride instructions are processed with a stride of eew * nf. The offset
registers used in this type of instruction are scalar registers, and the number
of uops depends on the number of data registers. Therefore, the number of uop
splits = emul * nf. For example, if emul = 2 and nf = 4, the uop numbering is as
follows: uopIdx = 0, base address rs1, stride rs2, destination register vd;
uopIdx = 1, base address rs1, stride rs2, destination register vd+1; uopIdx = 2,
base address rs1, stride rs2, destination register vd+2; ...... uopIdx = 7, base
address rs1, stride rs2, destination register vd+7.

### Segment Index

- The split count is: Max(lmul*nf, emul), ensuring sequential splitting starts
  from the first field's register group.

- For example: emul=4, lmul=2, nf=2, uop splitting is as follows:
    - uopidx=0, base address src, offset vs2, destination register vd
    - uopidx=1, base address (dontCare), offset vs2+1, destination register vd+1
    - uopidx=2, base address (dontCare), offset vs2+2, destination register vd+2
    - uopidx=3, base address (dontCare), offset vs2+3, destination register vd+3

- Another example: emul=2, lmul=1, nf=3, uop splitting is as follows:
    - uopidx=0, base address src, offset vs2, destination register vd
    - uopidx=1, base address (dontCare), offset vs2+1, destination register vd+1
    - uopidx=2, base address (dontCare), offset (dontCare), destination register
      vd+2

- For example: emul=8, lmul=1, nf=8, uop splitting is as follows:
    - uopidx=0, base address src, offset vs2, destination register vd
    - uopidx=1, base address (dontCare), offset vs2+1, destination register vd+1
    - uopidx=2, base address (dontCare), offset vs2+2, destination register vd+2
    - uopidx=3, base address (dontCare), offset vs2+3, destination register vd+3
    - uopidx=4, base address (dontCare), offset vs2+4, destination register vd+4
    - uopidx=5, base address (dontCare), offset vs2+5, destination register vd+5
    - uopidx=6, base address (dontCare), offset vs2+6, destination register vd+6
    - uopidx=7, base address (dontCare), offset vs2+7, destination register vd+7

## Main ports

|                 | Direction | Description                                                                                                      |
| --------------: | --------- | ---------------------------------------------------------------------------------------------------------------- |
|              in | In        | Receive uop dispatch from the Issue Queue.                                                                       |
|    uopwriteback | In        | Write back the completed uop to the backend.                                                                     |
|         rdcache | In/Out    | DCache Request/Response                                                                                          |
|         sbuffer | Out       | Write Sbuffer request.                                                                                           |
| vecDifftestInfo | Out       | Information required for DifftestStoreEvent in sbuffer                                                           |
|            dtlb | In/out    | Read/Write DTLB Request/Response                                                                                 |
|         pmpResp | In        | Receive access permission information from PMP.                                                                  |
|   flush_sbuffer | Out       | Flush sbuffer request                                                                                            |
|        feedback | Out       | Feedback to the Issue Queue module                                                                               |
|        redirect | In        | Redirect port                                                                                                    |
|   exceptionInfo | Out       | Output Exception information, participating in the arbitration of writing back exception information in MemBlock |
|  fromCsrTrigger | In        | Receives Trigger-related data from CSR                                                                           |

## Interface timing

The interface timing is relatively simple, described only in text.
|                 | Description                                                                                                                   |
| --------------: | ----------------------------------------------------------------------------------------------------------------------------- |
|              in | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|    uopwriteback | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|         rdcache | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|         sbuffer | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
| vecDifftestInfo | Valid simultaneously with the sbuffer port                                                                                    |
|            dtlb | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|         pmpResp | Has Valid and Ready. Data is valid when ready.                                                                                |
|   flush_sbuffer | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|        feedback | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|        redirect | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|   exceptionInfo | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|  fromCsrTrigger | No Valid signal; data is always considered valid, and responses are generated as soon as the corresponding signal is present. |
