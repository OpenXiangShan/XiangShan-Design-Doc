# Load Store Unit: LSU

## Submodule List

| Submodule                                     | Descrption                        |
| --------------------------------------------- | --------------------------------- |
| [LoadUnit](LoadUnit.md)                       | Load instruction execution unit   |
| [StoreUnit](StoreUnit.md)                     | Store Address Execution Unit      |
| [StdExeUnit](StdExeUnit.md)                   | Store Data Execution Unit         |
| [AtomicsUnit](AtomicsUnit.md)                 | Atomic instruction execution unit |
| [VLSU](VLSU/index.md)                         | Vector Memory Access              |
| [LSQ](LSQ/index.md)                           | Memory access queue               |
| [Uncache](Uncache.md)                         | Uncache processing unit           |
| [SBuffer](SBuffer.md)                         | Store commit buffer               |
| [LoadMisalignBuffer](LoadMisalignBuffer.md)   | Load unaligned buffer             |
| [StoreMisalignBuffer](StoreMisalignBuffer.md) | Store unaligned buffer            |

## Design specifications

### Instruction set specification

- Support for the execution and writeback of Load/Store instructions in the RVI
  instruction set
- Support for RVA atomic instruction extension
- Supports RVH virtualization extension
- Supports RVV vector extension
- Supports Load/Store/Atomic accesses to Cacheable address spaces
- Supports Load/Store accesses to MMIO and Uncache address spaces (excluding
  vector memory access instructions and unaligned memory access instructions).
- Support for cache operation instructions such as Zicbom and Zicboz, and
  support for Zicbop software prefetch instructions
- Supports unaligned memory access (Zicclsm) and guarantees atomicity for
  unaligned accesses within 16B-aligned ranges (Zama16b).
- Supports Sv39 and Sv48 paging mechanisms
- Support for contiguous page address translation (Svnapot)
- Support for page-based memory attributes (Svpbmt)
- Supports Pointer masking (Supm, Ssnpm, Sspm)
- Supports Compare-and-Swap atomic instructions (Zacas)
- Support for RVWMO memory consistency model
- Supports custom fault injection instructions

### Microarchitecture Features

- Supports out-of-order scheduling of Load/Store instructions, including
  accesses to Cacheable and Uncache (non-MMIO) address spaces
- Supports out-of-order scheduling of vector memory accesses based on the scalar
  pipeline
- Supports element-merged access for Unit-stride vector memory operations.
- Supports the dispatch and execution of Store instructions with separate
  address and data
- Supports Load instruction resend mechanism based on LoadQueue
- Supports non-speculative execution of atomic instructions
- Support for SBuffer optimization to enhance Store instruction performance
- Supports data forwarding mechanisms based on StoreQueue and SBuffer.
- Supports detection and recovery of RAR/RAW memory access violations
- Supports the MESI cache coherence protocol
- Support for multi-level cache access based on TileLink bus
- Support for DCache SECDED error checking
- Supports software-configurable hardware prefetchers such as Stream, Stride,
  and SMS

### Parameter configuration

|      Parameters      |       Configuration        |
| :------------------: | :------------------------: |
|      VAddr Bits      |    (Sv39) 39, (Sv48) 48    |
|     GPAddr Bits      |  (Sv39x4) 41, (Sv48x4) 50  |
|       LoadUnit       |         3 x 8B/16B         |
|      StoreUnit       |         2 x 8B/16B         |
|     StoreExeUnit     |             2              |
|      LoadQueue       |             72             |
|     LoadQueueRAR     |             72             |
|     LoadQueueRAW     |             32             |
|   LoadQueueReplay    |             72             |
|  LoadUncacheBuffer   |             4              |
|      StoreQueue      |             56             |
|     StoreBuffer      |          16 x 64B          |
|    VLMergeBuffer     |             16             |
|    VSMergeBuffer     |             16             |
|    VSegmentBuffer    |             8              |
|      VFOFBuffer      |             1              |
|       Load TLB       | 48-entry fully associative |
|      Store TLB       | 48-entry fully associative |
|   L1 Prefetch TLB    | 48-entry fully associative |
|   L2 Prefetch TLB    | 48-entry fully associative |
|        DCache        | 64KB 4-way set associative |
|     DCache MSHR      |             16             |
|  DCache Probe Queue  |             8              |
| DCache Way Predictor |            Off             |


## Functional Description

The memory access pipeline is responsible for receiving memory access
instructions (including Load/Store instructions for memory, MMIO, and Uncache
address spaces, as well as atomic instructions for memory address spaces) from
the issue queue. It completes the memory access operations based on the
instruction type, obtains the execution results, writes them back to the
register file, and notifies the forwarding bypass network to wake up subsequent
instructions and perform data forwarding.


### Dispatch of memory instructions

Load and Store instructions have complex control mechanisms, such as ordering,
forwarding, and violations, thus requiring a queue to preserve the
first-in-first-out sequence of load and store instructions for related control.
This queue is the LoadQueue and StoreQueue. After operations like instruction
decoding and renaming are completed, Load/Store instructions need to be
dispatched to the ROB and LSQ, with corresponding robIdx, lqIdx, and sqIdx
allocated, then enter the respective issue queues. Once all source operands are
ready, they are issued to the pipeline in the MemBlock. Throughout their
execution lifecycle in the MemBlock, Load/Store instructions carry lqIdx and
sqIdx for ordering in memory violation detection and data forwarding.

For scalar memory access instructions, one instruction allocates one LoadQueue
or StoreQueue entry.

For vector memory access instructions, a single instruction is split into
multiple uops during the decode stage, each containing several elements
equivalent to one memory access operation. During dispatch, a uop allocates
several LSQ entries equal to the number of elements it contains.

### Execution of memory access instructions

The memory unit includes 3 Load pipelines, 2 Store address pipelines, and 2
Store data pipelines. Each pipeline independently receives and executes
instructions dispatched from the corresponding issue queue.

The Load pipeline is a 4-stage pipeline structure:

- **s0**: Calculates memory access addresses, arbitrates requests from different
  sources (unaligned Load, Load replay, MMIO, prefetch, scalar Load, vector
  Load, etc.), accesses TLB, accesses DCache directory, and sends write-back
  wake-up signals.
- **s1**: Receives TLB address translation responses, obtains DCache read
  directory results for way selection, and accesses DCache data SRAM; performs
  RAW hazard detection with store instructions in StoreUnit s1; queries
  StoreQueue / LoadQueueUncache / SBuffer / DCache MSHR for data forwarding.
- **s2**: Query LoadQueueRAR and LoadQueueRAW for subsequent Load/Store
  instruction violation checks; if DCache misses, MSHR needs to be allocated in
  s2; perform RAW violation checks with StoreUnit s1's Store instructions.
- **s3**: Write-back; if no write-back is needed, the wake-up must be canceled;
  if a memory access violation occurs, the pipeline is flushed; if a resend is
  required, it enters LoadQueueReplay.

The Store address pipeline has a 4-stage structure:

- **s0**: Calculates memory access addresses, arbitrates requests from different
  sources (unaligned Store, scalar Store, vector Store, etc.), and accesses TLB
- **s1**: Receives TLB address translation responses; performs RAW hazard
  detection with load instructions in LoadUnit s1 and s2; queries LoadQueueRAW
  for violation checks.
- **s2**: Marked as address ready in the StoreQueue.
- **s3**: Write-back

The Store data pipeline writes the received data back to the StoreQueue and
marks it as ready after receiving it from the issue queue.

### Execution of vector memory instructions

For vector memory access instructions other than Segment, VLSplit and VSSplit
receive uops issued from the vector memory access issue queue, splitting the uop
into several elements. VLSplit and VSSplit then issue these elements to the
LoadUnit/StoreUnit for execution, following the same process as scalar memory
access. After execution, elements are written back to VLMerge/VSMerge, where the
Merge module collects and combines them into uops before writing back to the
vector register file.

Segment instructions are processed by the independent VSegmentUnit module.

### Load instruction replay

Load instructions do not support re-dispatch in the issue queue. Thus, when a
Load instruction encounters the following special cases, it must enter
LoadQueueReplay to await re-execution:

- **C_MA**: The memory access violation prediction algorithm (MDP) predicts that
  a Load has an address dependency with an older Store whose address is not yet
  ready
- **C_TM**: TLB miss
- **C_FF**: The Load has an address dependency with an older Store, but the data
  for this Store is not yet ready.
- **C_DR**: DCache miss and MSHR full, or an existing MSHR for the same address
  cannot accept new Loads
- **C_DM**: DCache miss, current Load successfully received by MSHR.
- **C_WF**: Way predictor misprediction (way predictor is disabled by default)
- **C_BC**: Bank conflict occurred during DCache access
- **C_RAR**: LoadQueueRAR full
- **C_RAW**: LoadQueueRAW full
- **C_NK**: Memory access violation occurred with Store instruction from
  StoreUnit
- **C_MF**: LoadMisalignBuffer full

LoadQueueReplay prioritizes and retries based on the above reasons from highest
to lowest priority.

### Store instruction replay

Store instructions are retransmitted by the issue queue. After a Store
instruction is issued from the issue queue, the queue does not immediately clear
this instruction but waits for feedback from the StoreUnit. The StoreUnit sends
corresponding feedback based on whether the TLB hits. If the TLB misses, the
issue queue is responsible for retransmitting the instruction.

### Detection and recovery of RAR memory access violations

**RAR Memory Access Violation**: According to the RVWMO model, when (1) two read
operations to the same address (including cases with overlapping addresses) are
separated by a write operation to the same address, and (2) the results returned
by these two read operations originate from different write operations, the two
read operations must maintain consistency with the program order. In a
single-core scenario, although the memory unit may execute Load instructions out
of order, it ensures the execution results of two Load instructions to the same
address adhere to the program order through a data forwarding mechanism.
However, in a multi-core scenario, when two out-of-order Load instructions to
the same address are separated by a write operation from another core (note: a
write operation, not a write instruction), the older Load may read the newer
value after the write operation, while the younger Load may read the older value
before the write operation, resulting in an RAR memory access violation.

**Detection of RAR memory access violations**: The LoadQueueRAR module in the
LoadQueue uses a FreeList structure to record all**potentially older Load
instructions that might have the same address but have not yet been executed**.
When a Load instruction reaches stage s2 in the LoadUnit (where address
translation and PMA/PMP checks are completed), a LoadQueueRAR entry is
allocated. A Load instruction in LoadQueueRAR**can be released from LoadQueueRAR
once all older Load instructions in program order have been written back**. If a
Load instruction detects a younger Load with the same address during access to
LoadQueueRAR, and the younger Load might have been accessed by another core (the
address has been replaced or probed), an RAR memory access violation occurs,
requiring a rollback.

**RAR memory access violation recovery**: Upon detecting an RAR violation, the
LoadUnit initiates a rollback, flushing the pipeline starting from the
instruction following the older Load that caused the violation.

### Detection and recovery of RAW memory access violations

**RAW Memory Violation**: The result of a Load instruction executed by the
processor core should come from **the most recent write operation in the global
memory order observed by the current processor core**. Specifically, if the most
recent write operation comes from a Store instruction of the current core, the
Load should retrieve the data written by that Store. To optimize the performance
of Load instructions, superscalar out-of-order processors may speculatively
execute Loads. As a result, a Load instruction might execute before an older
Store to the same address, fetching the old value prior to the Store, which
constitutes a RAW memory violation.

**RAW memory access violation detection**: The LoadQueueRAW module in LoadQueue
uses a FreeList structure to record all**Load instructions that may have the
same address but have not yet executed older Stores**. When a Load instruction
executes to stage s2 in the LoadUnit (where address translation and PMA/PMP
checks are completed), a LoadQueueRAW entry is allocated. When all Store
addresses in the StoreQueue are ready, all Loads in LoadQueueRAW can be
released; or when**all older Stores in program order have their addresses
ready**, the Load can be released from LoadQueueRAW. If a Store instruction
finds a younger Load with the same address when querying LoadQueueRAW, a RAW
memory access violation occurs, requiring a rollback.

**RAW Memory Access Violation Recovery**: When a RAW violation is detected, the
LoadQueueRAW initiates a rollback, flushing the pipeline starting from the
instruction following the violating Store.

### SBuffer optimizes Store instruction performance

According to the RVWMO model, in a multi-core scenario (without FENCE or other
barrier-semantic instructions), a core's Store instruction can become visible to
other cores later than younger Load instructions with different addresses. This
memory model rule primarily optimizes Store instruction performance. Weak
consistency models like RVWMO allow the inclusion of an SBuffer in the processor
core to temporarily hold committed Store write operations, merging these writes
before writing them to DCache, thereby reducing contention for DCache SRAM ports
by Store instructions and improving Load instruction execution bandwidth.

SBuffer is a 16 × 512B fully associative structure. When multiple Store
addresses fall within the same cache block, SBuffer merges these Stores.

The SBuffer can write up to 2 Store instructions per cycle, with each Store
instruction's write data width being 16B (exceptionally, the cbo.zero
instruction operates on one cache block at a time).

**SBuffer eviction**:

- When the capacity of SBuffer exceeds a certain threshold, a swap-out operation
  is performed, and the replacement block is selected according to the PLRU
  replacement algorithm and written to DCache.
- SBuffer supports a passive flush mechanism; instructions like FENCE / atomic /
  vector Segment will clear the SBuffer upon execution.
- SBuffer supports a timeout flush mechanism; data blocks that have not been
  replaced for over $2^{20}$ cycles will be evicted.

### Store-to-Load data forwarding

The presence of SBuffer and speculative execution of Load instructions require
Load instructions to access not only DCache but also SBuffer and StoreQueue.
Therefore, SBuffer and StoreQueue must provide Store-to-Load data forwarding.
When multiple sources hit simultaneously, LoadUnit needs to merge data from
these sources with priority: StoreQueue > SBuffer > DCache.

### Execution of MMIO instructions

The Xiangshan core only allows scalar memory access instructions to access the
MMIO address space. MMIO accesses and any other memory operations are strongly
ordered. Therefore, MMIO instructions must wait until they become the head of
the RoB to execute, meaning all preceding instructions have completed. For MMIO
Load instructions, virtual-to-physical address translation must be completed,
and PMA/PMP physical address checks must pass. For MMIO Store instructions,
virtual-to-physical address translation must be completed, physical address
checks must pass, and write data must be ready. The LSQ then sends the memory
request to the Uncache module, which accesses peripherals via the bus. The
results are returned to the LSQ, which writes them back to the RoB.

Atomic instructions and vector instructions do not support MMIO access. If such
instructions access the MMIO address space, they will trigger the corresponding
AccessFault exception.

### Execution of Uncache instructions.

In addition to supporting access to non-idempotent, strongly ordered MMIO
address spaces, the Xiangshan core also supports access to idempotent, weakly
consistent (RVWMO) Non-cacheable address spaces, referred to as NC. Software
configures the PBMT field in the page table to NC to override the original PMA
attributes. Unlike MMIO accesses, NC accesses allow out-of-order memory
operations. NC Load execution has no side effects and can thus be speculatively
executed.

Memory access instructions identified as NC addresses (PBMT = NC) in the
LoadUnit/StoreUnit pipeline are marked in the LSQ. The LSQ is responsible for
sending NC accesses to the Uncache module. The Uncache supports handling
multiple NC requests simultaneously, supports request merging, and is
responsible for forwarding Stores to NC Loads being executed in the LoadUnit.

Atomic instructions and vector instructions do not support NC access. If such
instructions access the NC address space, they will trigger the corresponding
AccessFault exception.

### Unaligned memory access

The Xiangshan core supports unaligned access to Memory space by scalar and
vector memory instructions.

- Scalar unaligned accesses not crossing 16B boundaries can proceed normally
  without additional handling.
- Scalar unaligned memory accesses that cross 16B boundaries are split into two
  aligned memory operations in the MisalignBuffer. After completion, the
  MisalignBuffer handles the concatenation and write-back.
- Vector non-Segment Unit-stride instructions access a contiguous address space,
  merging elements to access 16B at once, thus requiring no additional handling.
- For non-Segment vector instructions other than Unit-stride, the VSplit module
  completes element splitting and address calculation, sends them to the
  pipeline. If the elements are unaligned, they are sent to MisalignBuffer. The
  remaining process is the same as for unaligned scalars, except that
  MisalignBuffer eventually writes back to VMerge instead of directly to the
  backend.
- The misalignment handling for vector Segment instructions is independently
  completed by the VSegmentUnit, not reusing the scalar memory access path but
  through an independent state machine.

Atomic instructions do not support unaligned access. Neither MMIO nor NC address
spaces support unaligned access, and these cases will trigger an AccessFault
exception.

### Execution of atomic instructions

The Xiangshan core supports the RVA and Zacas instruction sets. In the current
design of Xiangshan, atomic instructions cache the accessed cache block into the
DCache before performing the atomic operation.

The memory access unit monitors the addresses and data issued by the Store issue
queue. If it is an atomic instruction, it enters the AtomicsUnit. The
AtomicsUnit performs a series of operations, including TLB address translation,
clearing the SBuffer, and accessing the DCache.

## Overall design

### Overall block diagram and pipeline stages

![MemBlock Architecture Diagram](./figure/memblock.svg)
