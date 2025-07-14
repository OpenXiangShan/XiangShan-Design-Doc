# Rob

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Glossary of Terms

Table: Terminology Explanation

| Abbreviation | Full name          | Description                              |
| ------------ | ------------------ | ---------------------------------------- |
| rob          | Reorder Buffer     | Reorder Buffer                           |
| rab          | Rename Buffer      | Rename buffer                            |
| -            | Redirect           | Redirect information from ctrlblock      |
| -            | Walk               | Rollback process after a redirect occurs |
| snpt         | Snapshot           | Snapshot information from ctrlblock      |
| wfi          | Wait For Interrupt | Wait for interrupt                       |

## Submodule List

Table: Submodule List

| Submodule           | Description                                                                               |
| ------------------- | ----------------------------------------------------------------------------------------- |
| RobEnqPtrWrapper    | Maintains the enqueue pointer of rob                                                      |
| NewRobDeqPtrWrapper | Maintains the dequeue pointer of rob                                                      |
| Rab                 | Maintains the state of each rat during commit or walk, interacting with the rename module |
| VTypeBuffer         | Maintains a Rab-like structure for Vtype, interacting with the decode module              |
| ExceptionGen        | Exception generation module                                                               |
| SnapshotGenerator   | Snapshot generation module                                                                |

## Design specifications

- Supports instruction writeback and commit
- Supports instruction redirection
- Supports interrupt handling
- Supports Rob compression
- Supports snapshot
- Support for exception handling
- Supports vector memory operations that write back before handling exceptions
  and setting vstart
- Rob supports committing/walking up to 8 entries per cycle
- Rab supports committing/walking up to 6 entries per cycle

## Function

The Rob module includes: RobEnqPtrWrapper for managing the enqueue pointer,
NewRobDeqPtrWrapper for managing the dequeue pointer, Rab for maintaining the
state of various rat during commit or walk, VTypeBuffer for maintaining Vtype
state, ExceptionGen for generating exceptions, and SnapshotGenerator for
creating snapshots.

The Rob module body is a circular queue with 160 entries. The pointers consist
of a 1-bit flag and an 8-bit value. When the value increments from its maximum,
the flag flips to distinguish instruction order. When the queue is empty, enqptr
=== deqptr, with both flag and value equal. When the queue is full, enqptr.value
=== deqptr.value, but enqptr.flag =/= deqptr.flag, meaning the values are equal
while the flags differ. The signals contained in each RobEntry are listed in the
table below.

Table: RobEntry Signal List

| Signal Name      | Description                                                     |
| ---------------- | --------------------------------------------------------------- |
| isVset           | Whether it is a Vset instruction                                |
| commitType       | Instruction commit type                                         |
| isHls            | Is it a virtualization load/store instruction                   |
| wflags           | Whether to write fcsr's fflags                                  |
| ftqIdx           | Pointer of ftq, used to read pcMem                              |
| ftqOffset        | Offset of ftq, used to calculate the PC                         |
| traceBlockInPipe | Trace data in the pipeline, including iretire, ilastsize, itype |
| instrSize        | Number of compressed instructions in Rob                        |
| fpWen            | FS for updating csr                                             |
| isRVC            | Is it a compressed instruction                                  |
| dirtyVs          | VS for updating csr                                             |
| realDestSize     | Number of destination registers written by the instruction      |
| stdWritebacked   | Whether the store instruction has been written back             |
| uopNum           | Number of uops requiring writeback                              |

The Rob employs a design with 8 read Banks, where the lower 3 bits of robidx
determine the bank. For example, robBanks0 contains robidx (in decimal): 0, 8,
16, 24, 32, etc., and robBanks1 contains robidx (in decimal): 1, 9, 17, 25, 33,
etc. Every 8 entries form a Line (0-7, 8-15, 16-23, ...). Each Bank has 20
Entries, totaling 20 Lines. The Bank partitioning is illustrated below.

![rob_entries](./figure/rob_entries.png)

Uses a one-hot Line pointer (20-bit) to read RobEntry data, fetching the current
Line and next Line data (totaling 16 Entries) from 8 Banks. After updating with
the current cycle's writeback information, one Line is selected from the two
Lines to write into the 8 robDeqGroup registers (the second Line is chosen if
all instructions in the first Line are committed in the current cycle). During
instruction commit, data is read from the 8 robDeqGroup registers for
committing. hasCommitted (8-bit) indicates whether each instruction in the
current Line has been committed, serving as one of the conditions for other
instructions to commit. allCommitted indicates that all instructions in the
current Line have been committed and is the control signal for switching the
Line pointer. When allCommitted is 1, the second Line of read data (the latter 8
entries) is selected, updated, and written into robDeqGroup.

![rob_enq](./figure/rob_enq.svg)

Rob enqueue: When Rob can accept instructions, io_enq_canAccept is asserted,
allowing Dispatch to send up to 6 instructions. Upon receiving instructions, Rob
updates enqptr by calculating dispatchNum based on enqueue requests and
allocating enqptr. If no redirect occurs, enqptr is updated to enqptr +
dispatchNum; if a redirect signal occurs, enqptr is set based on the robidx of
the redirect instruction (depending on the redirect level). During enqueue, if
an instruction requires move elimination, the writebackd signal is directly
asserted, allowing commit without writeback. If an instruction generates an
exception during decode, numWB is set to 0 in the rename stage, and the
instruction is not dispatched to IQ but marked as written back upon entering
Rob. Note that vector memory instructions must wait for all uops to write back
before handling exceptions. allocatePtrVec allocates 6 enqPtrs, with allocation
conditions being instruction validity and being the first uop (firstUop signal
from decode or Rob compression). canEnqueue (6 bits) indicates whether each
instruction can enter Rob: instruction is valid, is the first uop, and Rob can
accept it. uopNum records how many instructions (for Rob compression) or uops
(for vector instruction splitting) are compressed. uopNum is updated during
enqueue and decremented for each uop writeback (multiple uops can write back in
the same cycle). For store instructions, uopNum is set to 1, stdWritebacked is
deasserted, and std uops are not counted in uopNum. When std uops write back,
stdWritebacked is asserted.

Rob writeback, Exu writeback control signals to the rob will be registered in
ctrlBlock for one cycle. Due to Rob compression, multiple Exus may write back
the same robidx. While registering in ctrlBlock, Rob compression calculation is
performed. Each Exu counts the number of Exus (among those that can potentially
be compressed together, as some Exus cannot have compression relationships to
avoid wasting area and timing) that write back the same robidx as itself, and
transmits this count to Rob via writebackNums in the io interface.

![rob_commit](./figure/rob_commit.svg)

Rob commits instructions at the dequeue pointer position when the Rob state
machine is idle, the instruction is valid, all uops have been written back, and
blockCommit is low. If the instruction at the dequeue position has an exception,
blockCommit is raised to prevent instruction commit until the exception is
resolved. commitValidThisLine indicates whether the 8 entries in the line
containing deqptr can be committed. The criteria are: the entry is valid, all
its uops have been written back, no interrupts are enabled, no exceptions exist
in the dequeue instructions, no instructions require reply, no older
instructions block commit, and the instruction itself has not been committed
before. Note the allowOnlyOneCommit scenario: when an exception occurs in any of
the 8 dequeue Entries or interrupts are enabled, Rob allows only one instruction
to be committed per cycle.

Rob dequeue: Rob dequeues committed instructions, counts the number of committed
entries, increments the deqptr value by the number of committed entries, updates
the dequeue pointer, and sets the valid bit of dequeued entries to low.

Rob state machine, with two states: s_idle and s_walk. State updates are
primarily related to redirect. s_idle: Normal state where instructions can be
committed. After a redirect, at least two cycles in walk state are required
before returning to idle. s_walk: Walk state where instructions cannot be
committed, waiting for all modules to complete the walk and return to s_idle.
The state machine transition code is as follows.

```
  /**
   * state changes
   * (1) redirect: switch to s_walk
   * (2) walk: when walking comes to the end, switch to s_idle
   */
  state_next := Mux(
    io.redirect.valid || RegNext(io.redirect.valid), s_walk,
    Mux(
      state === s_walk && walkFinished && rab.io.status.walkEnd && vtypeBuffer.io.status.walkEnd, s_idle,
      state
    )
  )
```

Rob redirection and snapshot. Rob does not commit instructions in the same cycle
as redirect valid. The read pointer of Rob is switched based on the walk start
address, which comes from two sources: snapshot and deqptr. The walk start
address is selected from the older and most recent position relative to the
issued redirect instruction. The snapshot in Rob stores a set of robidx values,
which are based on the robidx of the first instruction enqueued, incremented by
0, 1, 2, 3, 4, 5, 6, and 7, totaling 8 robidx values. The Rob snapshot is
controlled by the snapshot in ctrlblock. The following diagram illustrates the
selection of walkPtr.

![rob_walkPtr](./figure/rob_walkPtr.svg)

walkPtr update: When redirect is valid, if io_snpt_useSnpt is 1, select the
corresponding snapshot based on io_snpt_snptSelect; if io_snpt_useSnpt is 0,
select deqPtr. Note that walkptr must align to the address of bank0. If redirect
is invalid and rob is in walk state without walk completion, walkptr increments
by 8 each cycle. Under other conditions, walkptr does not update. lastWalkPtr is
the endpoint of the walk, determined by whether the redirect instruction flushes
itself: if it flushes itself, lastWalkPtr is redirect's robidx - 1; otherwise,
it is redirect's robidx. The donotNeedWalk mechanism: in the first cycle of
walk, among the 8 entries, instructions older than the redirect's robidx do not
need to be walked. Walk completion is judged when walkPtrTrue > lastWalkPtr,
where walkPtrTrue is walkPtr without considering bank address alignment. When
walkFinished is 1, the walk completion information is sent to rab and
vtypeBuffer. shouldWalkVec indicates whether the 8 entries should be walked,
determined by whether they are older than lastWalkPtr, combined with
donotNeedWalk to ultimately decide if walking is necessary.

When Redirect is valid, Rob cannot commit instructions in that cycle. The walk
pointer updates to the walk start point (snapshot recovery or dequeue position).
Note that the walk start address must correspond to a robidx in Bank0. The walk
end position lastWalkPtr is recorded. In the next cycle, the state machine
transitions to walk state, updates the read Bank pointer to the walk pointer's
position, and sets the valid bit of robEntry instructions after the redirect to
0. In the following cycle, information needed for walking is fetched from the 8
robDeqGroups and passed to rab (realDestSize) and VTypeBuffer (isVset). During
walk state, 8 Rob entries are walked per cycle: realDestSize is accumulated and
passed to rab, and isVset is accumulated and passed to VTypeBuffer. Rob stops
its own walk upon reaching lastWalkPtr but remains in walk state until both rab
and VTypeBuffer complete their walks. Rab can walk up to 6 Entries per cycle,
while VTypeBuffer can walk up to 8 Entries per cycle.

Rob exception handling: Since instructions following an exception-generating
instruction are not executed, Rob only needs to preserve the oldest exception,
implemented via the Rob exception generation module. Internally, Rob only checks
for exceptions in instructions being committed. In the Rob exception generation
module, the enq signal (aligned with Rob enqueue signals) is responsible for
passing exception information from the frontend and decode, corresponding to up
to 6 instructions. The wb signal passes exception information written back by
functional units (csr + fence + load + store + vload + vstore), and the oldest
instruction's exception information must be output. The current signal holds the
current exception information. Enqueued instructions are ordered, so priorityMux
suffices to select the oldest exception. Writeback instructions are
out-of-order, requiring robidx comparison to determine the oldest exception. The
exception handling module groups and selects the oldest instruction: the first
cycle selects the oldest within each group, and the second cycle selects the
oldest from the first cycle's results. The oldest exception from the second
cycle is compared with current; if current is younger, it is updated to the
oldest exception. For vector memory access exceptions with the same robidx but
multiple uops, both the oldest robidx and the vstart to be set by the exception
are compared, retaining the exception with the smaller vstart.

Rob interrupt handling: Interrupts are processed similarly to exceptions.
Interrupts come from the CSR module. Instructions requiring flushPipe or
replayInst are currently also handled in exceptionGen. Rob handles them by first
sending a flushOut to ctrlBlock, which responds with a redirect to flush the
pipeline. The difference is that branch mispredictions and memory violations
generate redirects with faster target acquisition, directly reading a pc from
pcMem and combining it with ftqOffset to calculate the target for the frontend.
For interrupts and exceptions, information is first sent to CSR, which returns
the corresponding target to the frontend. Currently, interrupts are only
responded to when deqPtr points to non-load, non-store, non-fence, non-csr, and
non-vset instructions.

When the wfi_enable signal is asserted (from the CSR register,
*wait-for-interrupt enable*), the hasWFI flag is set to 1 when a wfi instruction
is enqueued into Rob. hasWFI will then set blockCommit to 1, blocking Rob
commits and thereby pausing the pipeline to wait for an interrupt. When the CSR
receives an interrupt, it asserts io_csr_wfiEvent, and hasWFI is set to 0 (or if
a timeout of 1M cycles occurs without an interrupt, it is also set to 0),
allowing Rob to resume normal instruction commits.

## Overall design

### Overall Block Diagram

### Interface list

Refer to the interface documentation.

## Module Design

### Secondary module

#### Function

#### Overall Block Diagram

#### Interface list

Refer to the interface documentation.
