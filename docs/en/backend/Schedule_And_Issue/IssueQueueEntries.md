# IssueQueueEntries

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Glossary of Terms

Table: Terminology Explanation

| Abbreviation | Full name  | Descrption  |
| ------------ | ---------- | ----------- |
| IQ           | IssueQueue | Issue Queue |


## Design specifications

- Supports three types of issue queue entries: EnqEntry, SimpleEntry, and
  ComplexEntry.
- Supports dual-port read/write.
- Supports writeback wakeup and speculative wakeup.
- Supports direct dequeue of EnqEntry.
- Supports instruction transfer between entries.
- Supports Wake-up, Cancellation, and Feedback

## Function

### Overall Functionality

Entries is the module within the issue queue that stores uops. It contains
multiple entry modules, each capable of holding one uop. These entries are
divided into two main categories: EnqEntry, which corresponds to the enqueue
port of the issue queue, and OthersEntry, which are more numerous. \
\
Entries consolidates the issue and status information from all entries and
passes it to the issue queue control logic. It also receives selection results
from the control logic and outputs the complete information of the uop to be
issued. \
\
Entries accepts wake-up signals from the IQ (either its own IQ or fast wake-ups
from other IQs) and WriteBack (write-back wake-ups), cancellation signals from
the datapath (e.g., og0Cancel, og1Cancel), and feedback signals post-issue,
which are aggregated and forwarded to each entry. \
\
Entries also manages the transfer logic between entries. EnqEntry receives uops
from the IQ input. If OthersEntry is ready, the uop is transferred to
OthersEntry according to certain rules. EnqEntry supports transferring out the
previous uop and enqueuing the next uop in the same cycle, enabling seamless
transitions. \
\
In advanced issue queue configurations, OthersEntry is further divided into
SimpleEntry and ComplexEntry. Entries also controls the transfer strategy from
SimpleEntry to ComplexEntry.

### Transfer Strategy
ComplexEntry is the final entry type and cannot be transferred. SimpleEntry can
transfer to ComplexEntry, while EnqEntry can transfer to either ComplexEntry or
SimpleEntry. Only entries that have not been issued can be transferred. If an
issued entry fails, its issued flag is cleared, making it transferable again. If
an issued entry succeeds, it becomes invalid and no longer needs transfer.
EnqEntry-to-OthersEntry transfer logic: EnqEntry prioritizes transfer to
ComplexEntry, then to SimpleEntry. Transfers are all-or-nothing—either fully to
ComplexEntry, fully to SimpleEntry, or no transfer. EnqEntry transfers to
ComplexEntry only if there are enough free ComplexEntries and all SimpleEntries
are empty; otherwise, it transfers to SimpleEntry. SimpleEntry-to-ComplexEntry
transfer logic: Each cycle, up to num_enq (equivalent to the number of
EnqEntries) SimpleEntries can transfer to ComplexEntry, with one transfer per
free ComplexEntry slot. SimpleEntry transfers take priority over EnqEntry.
Transfer order for SimpleEntries is strictly age-based, with older entries
prioritized, determined by querying the age matrix in IQ.

![Schematic diagram](./figure/Entires_trans.svg)

### Issue and Dequeue
Entries collect the valid and canIssue signals from each entry and pass them to
the IQ. The IQ returns the deqSelOH signal, which selects the entry positions to
dequeue, and the deqReady signals indicating whether each exit can accept the
dequeue (currently, deqReady is a constant high signal). When both are valid,
the entry is considered dequeued, and the deqSel signal is sent to that entry. \
\
After receiving deqSel, the entry is not immediately cleared but is marked as
issued, recording the issue port and the cycles elapsed since issue. It must
then wait for the subsequent resp signal indicating successful issue before
being cleared. \
\
Entries are responsible for aggregating all resp signals and forwarding the
corresponding resp to the entry. For non-memory IQ entries, the resp signals are
only og0resp and og1resp, selected based on the entry's dequeue port and the
cycles elapsed since issue. The entry and robIdx must match the resp's robIdx
for the resp to be forwarded. \
\
Memory IQs have more resp signals, varying by IQ type, and require comparing
lqidx and sqidx to select the correct resp. \
\
During issue, the selected entry's uop information is also sent to the IQ. Due
to timing constraints, deqSelOH is not used directly for selection. Instead, the
IQ provides staged selection results, including enqEntryOldest, simpEntryOldest,
and compEntryOldest. These signals are used to select the corresponding dequeued
uops, which are then prioritized (comp > simp > enq) to determine the final
dequeued uop.

### Wakeup and Cancellation
Entries do not handle wakeup logic; they only pass wakeup and cancellation
signals to all entries. Due to timing constraints, Entries also manage
same-cycle cancellation logic. Cancellation sources have long latency, and if
wakeup and cancellation were processed normally before IQ dequeues, timing would
suffer. Thus, IQ dequeues based on same-cycle wakeup results, while Entries
separately compute same-cycle cancellations before finally determining which
uops to cancel among the dequeued candidates.

## Overall Block Diagram

![Schematic diagram](./figure/Entires_top.svg)

## Interface timing

![Schematic diagram](./figure/Entires_signal.png)

The io_* signal group is for IQ instruction enqueue, with a maximum of two
instructions per cycle, accompanied by potential wakeup signals. Due to timing
considerations, handling cases where enqueued instructions are simultaneously
woken is addressed by delaying wakeup by one cycle (see enqDelay_wakeup in the
diagram). To align timing, this portion of wakeup follows a bypass timing
similar to speculative wakeup, affecting srcStateNext—thus impacting
canIssueBypass—akin to ComplexEntry's same-cycle wakeup and issue.

## Secondary Modules: EnqEntry & OthersEntry

### Function

The functionalities of EnqEntry and OthersEntry are essentially the same.
EnqEntry, being directly connected to the enqueue port, includes an additional
layer of enqueue wake-up handling, while the rest of the features are identical.
Hence, they are described together. The most critical functions of an Entry
include: valid, canIssue, issued, and status. \
\
**Valid** indicates whether the entry is active. When a uop enters the entry,
the uop information from the enqueue is written into the registers, and valid is
set to active. The entry is cleared and valid is set to inactive under any of
the following conditions: flush, tranSel being active, or issueResp indicating a
successful issue. \
\
**Issued** records whether the uop has been issued. It is marked as issued when
deqSel is active; it is marked as unissued if issueResp fails or if an operand
is canceled and is no longer ready. \
\
When all source operands are ready and the state is unissued, **canIssue** is
output as active. \
\
**Status** is a series of information describing the state of the source
operands, including operand type (srcType), state (srcState), data sources
(dataSources), load information for waking the operand (srcLoadDependency), EXU
information for waking the operand (srcWakeUpL1ExuOH), and the post-wake-up
cycle counter (srcTimer). \
\
wakeUpFromWB and wakeUpFromIQ transmit the pdest and register types (xp, fp, vp)
to be woken. If the pdest number matches the register number of the entry's
operand and the register types also match, the operand is woken and marked as
ready. \
\
og0Cancel and og1Cancel transmit the EXU numbers to be canceled. For og*Cancel,
if the EXU to be canceled matches the EXU that woke the operand and the srcTimer
corresponds to the issued pipeline delay, the operand is canceled. For ldCancel,
if the load pipeline stage to be canceled matches srcLoadDependency, the operand
is canceled. \
\
When wake-up and cancellation for the same operand arrive simultaneously,
cancellation takes higher priority. \
\
The source operand status information output by the Entry comes in two forms:
immediate and delayed, corresponding to fast and slow wake-ups. Immediate means
the source operand status information is obtained from the registers and output
immediately in the same cycle after the wake-up and cancellation updates.
Delayed means the source operand status information is written back to the
registers after wake-up and cancellation updates and is output from the
registers in the next cycle. \
\
WB wake-ups are always slow, while IQ wake-ups can be configured as fast or
slow. Entries configured for fast wake-ups are called ComplexEntry, while those
configured for slow wake-ups are called SimpleEntry. EnqEntry could
theoretically be configured, but in practice, it is always fast. \
\
The difference between EnqEntry and OthersEntry lies in the additional enqueue
wake-up. Due to timing constraints, wake-up and cancellation during enqueue
cannot be performed before writing to EnqEntry, so they are delayed to the
beginning of the next cycle after writing to EnqEntry. First, the delayed
wake-up and cancellation signals (enqDelay*) are used to update the
register-direct output state, followed by normal wake-up and cancellation. Note
that enqueue wake-up only occurs in the first cycle after the uop enters
EnqEntry; thereafter, the register-direct output state is used directly.

Summary:
1. An Entry is a structure within IssueQueue that stores critical uop
   information, analogous to RS.
2. The standard design specification for Kunming Lake's integer IssueQueue
   includes 24 Entry items.
3. Entries are logically categorized into three types: EnqEntry, SimpleEntry,
   and ComplexEntry.
4. 2 EnqEntries serve as enqueue ports. Each cycle, the two instructions
   entering the IQ can only be stored here.
5. 6 SimpleEntries + 16 ComplexEntries.

### Overall Block Diagram

![Schematic diagram](./figure/Entires_valid.svg)

![Schematic diagram](./figure/Entires_entryReg.svg)

imm stores immediate values, while payload holds the original instruction
information, which the entry does not process.

![Schematic diagram](./figure/Entires_status.svg)

srcStatus indicates the status of each source operand for uops. issued marks the
issue state of a uop, as issuance may succeed or fail. Only successful issuance
can modify validReg, so issued is used to track whether the uop is mid-issuance.

![Schematic diagram](./figure/Entires_issueTimer.svg)

The issueTimer and deqPortIdx exist to accommodate the entry transfer mechanism.
After an instruction is issued, it passes through OG0 and OG1 stages. Only uops
that successfully pass OG1 and enter the EXU are considered issued. If a failure
occurs midway, the IQ must be notified to reissue. Without the transfer
mechanism, uops can be located via entryIdx. With the transfer mechanism, a uop
may move to another location immediately after being issued, making it difficult
for OG0/1 resp signals to locate it. Hence, issueTimer and deqPortIdx signals
are added. Once a uop is issued, issueTimer is modified and increments each
cycle, while deqPortIdx records the dequeue port it was issued from. Based on
the timing relationship shown in the diagram, OG0 and OG1 resp signals only need
to recognize these two signal values within each Entry to locate the uop.

![Schematic diagram](./figure/Entires_srcStatus.svg)

Wake-up --> Modify srcState srcWakeupL1ExuOH --> Mark speculative wake-up
signals indicating which EXU they originated from.

![Schematic diagram](./figure/Entires_WBwakeup.svg)

Writeback wakeup is issued in the final cycle of uop execution; entries woken by
writeback cannot be woken and issued in the same cycle.

![Schematic diagram](./figure/Entires_wakeup.svg)

dataSource is used for speculative wakeup scenarios. Writeback wakeup directly
sets to reg. Speculative wakeup in the same cycle → forward. Each additional
cycle of stay modifies it once, finally maintaining reg → forward → bypass → reg
→ reg.

![Schematic diagram](./figure/Entires_ldcancel.svg)

srcLoadDependency 3-bit, used to record the Load dependency relationships of
each uop. When ldCancel occurs, all uops on the wake-up chain are flushed.

