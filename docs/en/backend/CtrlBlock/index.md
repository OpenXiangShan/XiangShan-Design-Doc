# CtrlBlock

- Version: V2R2
- Status: OK
- Date: 2025/01/15
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Glossary of Terms

Table: Terminology Explanation

| Abbreviation | Full name                  | Description                   |
| ------------ | -------------------------- | ----------------------------- |
| -            | Decode Unit                | Decode unit                   |
| -            | Fusion Decoder             | Instruction fusion            |
| ROB          | Reorder Buffer             | Reorder Buffer                |
| RAT          | Register Alias Table       | Rename Mapping Table          |
| -            | Rename                     | Rename                        |
| LSQ          | Load Store Queue           | Memory instruction queue      |
| -            | Dispatch                   | Dispatch                      |
| IntDq        | Int Dispatch Queue         | Fixed-point dispatch queue    |
| fpDq         | Float Point Dispatch Queue | Floating-point dispatch queue |
| lsDq         | Load Store Dispatch Queue  | Memory dispatch queue         |
| -            | Redirect                   | Instruction Redirection       |
| pcMem        | PC MEM                     | Instruction address cache     |

## Submodule List

Table: Submodule List

| Submodule     | Description                 |
| ------------- | --------------------------- |
| dispatch      | Instruction dispatch module |
| decode        | Instruction decoding module |
| fusionDecoder | Instruction fusion module   |
| rat           | Rename table                |
| rename        | Rename module               |
| redirectGen   | Redirect generation module  |
| pcMem         | Instruction address cache   |
| rob           | Reorder Buffer              |
| trace         | Instruction trace module    |
| snpt          | Snapshot Module             |

## Design specifications

Decode width: 6

Rename width: 6

Dispatch width: 6

ROB commit width: 8

ROB commit width: 6

ROB size: 160

Snapshot Size: 4 entries

Number of integer physical registers: 224

Floating-point physical register count: 192

Number of vector physical registers: 128

Vector v0 Physical Register Count: 22

Vector VL physical register count: 32

Supports rename snapshots

Supports trace extension

## Function

The CtrlBlock module includes instruction decoding (Decode), instruction fusion
(FusionDecoder), register renaming (Rename, RenameTable), instruction dispatch
(Dispatch), commit components (ROB), redirect handling (RedirectGenerator), and
snapshot renaming recovery (SnapshotGenerator).

The decoding functional unit fetches 6 instructions from the head of the
instruction queue for decoding each clock cycle. The decoding process translates
the instruction code into an internal code that is easier for the functional
unit to process, identifying the instruction type, the register numbers to be
operated on, and any immediate values contained in the instruction code, which
are used in the subsequent register renaming stage. For complex instructions,
they are selected and then split one by one through the complex decoder
DecodeCompunit. For vset instructions, they are stored in Vtype to guide
instruction splitting. Finally, 6 uops are selected each cycle, with complex
instructions first and simple instructions last, and passed to the renaming
stage. The decoding stage also includes issuing RenameTable read requests.

Instruction fusion pairs up to 5 potential fusion instruction pairs from the 6
uops obtained during decoding: (uop0, uop1), (uop1, uop2), (uop2, uop3), (uop3,
uop4), (uop4, uop5). Each pair is then evaluated for fusion compatibility.
Currently, we support two types of instruction fusion: merging into a new
instruction with additional control signals and replacing the operation encoding
of the first instruction with another form. Upon determining fusion is possible,
operands such as logical register numbers are reassigned, and new operands are
selected. However, HINT-type instructions, like fence, are not supported for
fusion.

The rename stage is responsible for managing and maintaining the mapping between
registers and physical registers. By renaming logical registers, it eliminates
dependencies between instructions and enables out-of-order scheduling. The
rename module mainly consists of the Rename and RenameTable modules, which are
responsible for controlling the Rename pipeline stage and maintaining the
(architectural/speculative) rename table, respectively. The Rename module
includes the FreeList and CompressUnit modules, which handle the maintenance of
free registers and Rob compression.

In the dispatch phase, renamed instructions are distributed to four schedulers
based on instruction type: integer, floating-point, vector, and memory. Each
scheduler is further divided into several issue queues based on different
operation types, with each issue queue having an entry size of 2.

The instruction flow in CtrlBlock proceeds as follows: CtrlBlock reads the
ctrlflow corresponding to the 6 instructions from the Frontend. After decoding,
it adds decoded logical registers and operation codes. Complex instructions are
supplemented with instruction splitting information via DecodeComp. Each cycle,
up to six uops are output, and RAT read requests are issued. For uops that can
undergo instruction fusion, fusion and clearing occur during renaming. After
renaming, physical register information and ROB compression details are added
before being passed to dispatch. Finally, through dispatch, entries are
allocated in ROB/RAB/VTYPE, and instructions are output to the issue queue based
on their type. Among these modules, only the issue queue operates in-order for
input and out-of-order for output; all other modules are in-order for both input
and output.

![CtrlBlock Overview](./figure/CtrlBlock-Overview.svg)

# Decode

The decoding process for scalar instructions is the same as in Nanhu.

For vector instructions, first decode using the same structure as scalar
instructions' decode table, simultaneously obtaining the instruction split type.
Subsequently, the instruction is split based on this type, which involves
modifying source register numbers, source register types, destination register
numbers, destination register types, and updating the uop count to control the
number of writebacks required by the ROB. The decode ready signal can only be
set to 1 after all split uops complete the rename process.

Since scalar floating-point instructions, except i2f, now utilize the vector
floating-point module, only 4 decode signals from fpdecoder are used
(typeTagOut, wflags, typ, rm), with usage identical to Nanhu. Floating-point
instructions running on the vector module require obtaining futype and fuoptype
from the vector decode unit, distinguished by a 1-bit isFpToVecInst signal to
differentiate between floating-point and vector floating-point instructions when
sharing the vector arithmetic unit.

## Decode stage input

In the decode stage, in addition to receiving the instruction stream from the
frontend, it also needs to accept Vtype-related information from the rob: walk,
commit, and vsetvl, to guide the decoding of complex vector instructions.

## Decode output

With fusionDecode: Outputs the instruction stream and controls whether
instruction fusion is enabled.

Regarding rename: the pipeline outputs 6 uops; if a redirect occurs, it blocks
until the redirect in CtrlBlock is sent to the frontend, and the frontend issues
the correct instruction stream.

With RAT: Decode issues speculative rename read requests.

# FusionDecoder

The instruction fusion module identifies whether there are certain relationships
among the uops decoded by the decode module, allowing multiple uops (currently
supporting fusion of only two instructions) to be combined into a single uop
capable of completing the required tasks.

Instruction fusion combines the six uops obtained from instruction decoding into
up to five candidate instruction pairs in the form of (uop0, uop1), (uop1,
uop2), (uop2, uop3), (uop3, uop4), (uop4, uop5). Each pair is then evaluated for
fusion feasibility. Currently, we support two types of instruction fusion:
merging into a single instruction with new control signals and replacing the
operation encoding of the first instruction with another form. After determining
fusion feasibility, we reassign uop operands, such as logical register numbers,
to select new operands. Additionally, HINT-type instructions, such as fence
instructions, cannot be fused.

For example, "slli r1, r0, 32" followed by "srli r1, r1, 32" shifts the value in
r0 left by 32 bits, stores it in r1, then shifts it right by 32 bits. This is
equivalent to "add.uw r1, r0, zero" (pseudo-instruction "zext.w r1, r0"), which
extends and moves the value in r0 to r1.

The input consists of up to 6 decoded uops along with their original instruction
encodings and corresponding valid signals. Here, the inready input has only 5
bits (i.e., the decode width minus one) because we need to pair the uops in
pairs for up to 5 fusion candidates. inReady[i] indicates that it is ready to
accept in(i+1).

The output width is one less than the decode width, including instruction fusion
replacements. This requires updating fuType, fuOpType, lsrc2 (logical register
number of the second operand, if applicable), src2Type (type of the second
operand), and selImm (immediate type). Additionally, instruction fusion
information, such as whether rs2 is derived from rs1/rs2/zero, must be output. A
Boolean vector clear of decode width is also needed to indicate whether each uop
should be cleared due to instruction fusion. Currently, it is envisioned that
the second uop in a fused pair will be cleared. The clear flag for uop 0 will
never be true, as we default to fusing subsequent instructions into the
preceding one, ensuring uop 0 is never eliminated by fusion.

Output Validity Requirements: The instruction pair must be valid (uop pair from
the decode module is valid), cannot be cleared by instruction fusion, must have
a feasible fusion result, and must not be a HINT-type instruction. Additionally,
assign information such as fuType, src2Type, rs2FromZero, etc.

![Fusion Decoder Overview](./figure/Fusion-Decoder-Overview.svg)

# Redirect

The ctrlblock is primarily responsible for generating redirects and sending them
to various modules.

## RedirectGenerator

The RedirectGenerator module manages redirect signals from different sources
(such as execution units and load) and decides whether a redirect occurs and how
to flush related information. It ensures the correctness of the data flow
through multi-stage registers and synchronization mechanisms, and guarantees the
correctness of instruction execution through address translation and error
detection.

Concatenate the fullTarget of the oldest executing redirect with
cfiUpdate.target to obtain the fullTarget field. Additionally, if the oldest
executing redirect does not originate from a CSR, it is necessary to check the
validity of addresses such as IAF, IPF, and IGPF based on the translation type
of the instruction address.

Then, the oldest execution redirect and load redirect are selected, ensuring
that this oldest redirect won't be flushed by robFlush or previous redirects.

![redirect overview](./figure/Redirect-Overview.svg)

## generation of redirect

The Redirects generated in Ctrlblock mainly originate from two sources:

* Errors occurring during processor execution (including branch prediction and
  memory violations) aggregated by redirectgen (referred to as exuredirect in
  the following).
* And robflush generated by rob exceptiongen: interrupts (CSR)/exceptions/flush
  pipeline (CSR + fence + load + store + varith + vload + vstore) + front-end
  exceptions. The redirect handling for exceptions/interrupts/flushes from the
  ROB is similar.

For redirects aggregated by redirectgen:

* Functional unit writeback redirects (jump, brh) are input to the redirectgen
  module after being delayed by one cycle, provided they are not canceled by
  older, already processed redirects.
* The violation (memory access violation) from Memblock writeback is input to
  redirectgen after one cycle delay, provided it hasn't been canceled by an
  older processed redirect.

Redirectgen selects the oldest redirect, waits for one cycle after input, and
then outputs it along with the data read back from pcMem.

For the robflush signal, upon receiving it, it is also necessary to wait for one
cycle plus the data read back from pcMem.

When generating Redirect, CtrlBlock prioritizes redirecting the robflush signal.
Only when robflush is absent will it handle exuredirect.

The overall block diagram of the above components is as follows:

![Generation of redirect](./figure/Redirect-Gen.svg)

## redirect distribution

After generating the Redirect signal, Ctrlblock distributes the redirect signal
to various pipeline stages.

* For decode, send the current redirect or redirectpending (i.e., decode waits
  until the redirect from Ctrlblock to the frontend is ready, ensuring the
  correct instruction stream reaches the frontend before the pipeline can
  proceed);
* For rename, rat, rob, dispatch, snpt, and mem, the current redirect is sent.
* For issueblock, datapath, and exublock, send the redirected signal after a
  one-cycle delay.

Among these, the redirect sent to the frontend is particularly special. The
redirect sent to the frontend and its resulting impact consist of three parts:
rob_commit, redirect, and ftqIdx (readAhead, seloh).

![Redirect sent to the frontend](./figure/Redirect-ToFrontend.svg)

### For rob commit

Since the flush signal sent to the frontend may be delayed by several cycles,
and if commits continue before the flush, it may lead to errors where commits
are followed by flushes. Therefore, we treat all flushes as exceptions to ensure
consistent handling behavior at the frontend. When the ROB commits an
instruction with a flush signal, we need to directly flush the commit with
robflush in ctrlblock, informing the frontend to perform a flush without
committing.

As for exuredirect, the corresponding instruction must wait for the walk to
complete after being written back to the ROB before it can be committed.
Therefore, these two types of redirects do not require special handling, as
their commit will always occur after their write-back.

### For redirect:

The redirect signal sent to the frontend includes an additional CFIupdate, while
the ftq information is updated through additional readAhead and seloh.

For exuredirect, their CFIupdate and ftqidx information are already included
when passed back from the functional unit, so no special processing is required.

For flushes issued by the ROB, the destination address for CFI updates due to
exceptions must wait for retrieval from the CSR: first, the ROB issues a flush
signal, generating an exception, sends a redirect to the CSR indicating the
exception, receives the Trap Target from the CSR back to the ctrlblock, and
finally issues a redirect to the front-end.

For other pipeline flushes that result in destination address updates, the base
PC is obtained through previous interactions with pcmem. In CtrlBlock, the
destination address is generated by adding an offset based on whether it flushes
itself.

A special case is the XRet issued by CSR to flush the pipeline. In this
scenario, the destination address update also needs to be obtained from CSR.
However, the path generating Xret in CSR no longer relies on the exception
feedback from rob and can directly interact with Ctrlblock via csrio.

### For ftqIdx:

Ctrlblock primarily sends two sets of data: ftqIdxAhead and ftqIdxSelOH.

Here, ftqIdxAhead is used by the frontend to read the ftqidx related to the
redirect one cycle ahead. ftqIdxAhead is a vector of FtqPtr with a size of 3,
where the first is the executed redirect (jmp/brh), the second is the load
redirect, and the third is robflush.

ftqIdxSelOH selects valid ftqidx: the first two are chosen via one-hot codes
from redirectgen output, while the third is determined by whether the redirect
sent to the frontend is valid.

## Ensure the order of redirect issuance

To ensure correct execution, newer redirects cannot be dispatched before older
ones. The following four scenarios are explained:

(1) New exuredirect issued after old robflush:

During writeback, exuredirect checks forward to see if there is an older
redirect.

Upon robflush arrival, later-generated exuredirects are directly flushed in
exublock; for earlier-generated exuredirects not yet flushed by robflush, they
are checked against older redirects and flushed if any exist.

(2) The new exuredirect follows the old exuredirect:

During writeback, exuredirect checks forward to see if there is an older
redirect.

When a redirect occurs, newly generated exuredirects will also be directly
flushed in the exublock; for earlier generated exuredirects that haven't been
flushed by the current redirect yet, it checks if there are older redirects, and
if so, they will also be canceled.

(3) The new robflush occurs after the old redirect.

In this scenario, the ROB ensures that such a situation will not occur. The
robflush output indicates that the current robdeq instruction carries an
exception/interrupt flag, while robdeq (the oldest ROB index) must be older than
any existing redirect.

(4) The new robflush occurs after the old robflush.

This is primarily ensured within the ROB. The exceptionGen obtains the oldest
robflush, and when robflush is issued, it checks the previous flushout. Newer
robflushes will be canceled.

# Snapshot recovery

For rename recovery, Kunming Lake currently adopts a snapshot recovery phase:
during redirection, it may not revert to the arch state but could restore to a
certain snapshot state. Snapshots are speculative states saved during the rename
phase according to specific rules, including ROB enqptr, Vtypebuffer enqptr, RAT
spec table, freelist Headptr (dequeue pointer), and ctrlblock for overall
control of robidx. Currently, each of these modules maintains four snapshots.

## SnapshotGenerator

The SnapshotGenerator module is primarily used for generating and maintaining
snapshots. It essentially functions as a circular queue, maintaining up to four
snapshots.

Enqueue: When the circular queue is not full and the enqueue signal is not
canceled by a redirect, the next cycle enqueues at enqptr and updates enqptr.

Dequeue: If the dequeue signal is not canceled by redirect, the next cycle
dequeues at deqptr and updates deqptr.

Flush: The corresponding snapshot is flushed in the next cycle based on the
flush vector.

Update enqptr: If there is an empty snapshot, select the one closest to deqptr
as the new enq pointer.

Snapshots: The snapshots queue register outputs directly.

![Snapshots Overview](./figure/Snapshot-Overview.svg)

## Snapshot creation

Regarding the timing of snapshot creation, it is currently managed during
rename. Since it is observed that the primary performance impact of redirects
still stems from branch mispredictions, snapshots are created at branch jump
instructions. Additionally, to ensure that other redirects can also utilize
snapshot recovery in the absence of branch jumps, a snapshot is taken every
commitwidth*4=32 uops.

The Rename module tags all six output uops with a snapshot flag, indicating
whether a uop requires snapshotting. In the Ctrlblock, the snapshot flags from
all six uops are aggregated onto the first uop. This operation ensures
correctness of the snapshot mechanism under blockBackward scenarios: if a
blockbackward occurs among the six uops and a snapshot is required after it, the
snapshot would fail to be recorded in the ROB due to blockbackward.
Consolidating all snapshots onto the first uop resolves this issue.

The creation of snapshots for Rat, freelist, and ctrlblock is controlled by the
snapshot flag output from the rename module. The storage data is managed by each
module itself.

For Rob and vtype snapshot creation, in addition to the snapshot flag from the
rename output stream to rob, considerations must also include non-blockbackward,
as well as ensuring that rab, rob, and vtypebuffer are not full. The snapshot
creation for rob and vtype and the snapshot writing in the aforementioned
modules may not occur in the same cycle, but by having the snapshot flag follow
the rename output stream to rob, we can ensure synchronization by writing the
same robidx.

## Snapshot deletion

Snapshot deletion mainly includes two scenarios: one is deleting expired
snapshots during commit; the other is deleting snapshots on the wrong path
during redirect.

For snapshot deletion during commit: Ctrlblock deletes snapshots by controlling
the deq signal. If one of the eight uops in robcommit matches the first uop in
the snapshot pointed to by the current deqptr, the expired snapshot is deleted.
Ctrlblock transmits the deq signal to the aforementioned modules to synchronize
the deletion of expired commit snapshots.

During redirect: Ctrlblock removes snapshots on incorrect paths by providing a
flushvec signal—it checks whether the first uop of a snapshot is newer than the
current redirect (accounting for wrap-around cases). If older, the snapshot is
flushed by setting the corresponding flushvec bit. Ctrlblock then propagates
flushvec to synchronize snapshot invalidation across relevant modules.

## Management of snapshots

Ctrlblock maintains a snapshot copy of robidx internally, allowing it to
conveniently inform each module whether a snapshot is hit and the snapshot
number when a redirect arrives. Ctrlblock traverses the snapshots and, if there
is a snapshot older than the current redirect (or equal if not flushing itself),
permits snapshot recovery, records the hit snapshot number, and passes it to the
aforementioned modules.

The recovery of the speculative state through snapshots is controlled by each
module itself.

Overall block diagram of the above sections:

![Snapshot generation, deletion, and management](./figure/Snapshot-Gen.svg)

# pcMem

pcMem is essentially an instantiation of SyncDataModuleTemplate, requiring
multiple read ports and 1 write port. It has 64 entries, each containing only
startAddr.

pcMem reads the base PC, which needs to be combined with Ftq Offset to get the
full PC.

Under the current configuration, 14 read ports are required: one each for
redirect and robFlush, three each for bjuPC and bjuTarget, three for load, and
three for trace.

Inputs include write enable, write address, and write data from the front-end
Ftq, as well as read requests and read addresses from different sources, with
read results output separately.

![PCMem Overview](./figure/PCMem-Overview.svg)

# GPAMem

The GPAMem module is similar to pcMem, instantiating a SyncDataModuleTemplate,
but only requires 1 read port and 1 write port, with a size of 64 entries. Each
entry mainly includes a gpaddr, storing the gpaddr information corresponding to
the frontend's ftq.

Rob issues a gpaddr read request one cycle before exception output to read the
ftq information of the address, and receives the returned gpaddr information in
the second cycle. The final interaction with csr is handled directly through
robio.

Inputs include write enable, write address, and write data from the frontend
IFU, as well as read requests and read addresses from the rob. The output to the
rob is the read result.

![GPAMem Overview](./figure/GPAMem-Overview.svg)

# Trace

The trace submodule in ctrlBlock collects instruction trace information,
receiving data from rob instruction commits. It performs secondary compression
(combining instructions that do not require PC with those that do and storing
them together in the trace buffer) on top of rob compression to reduce read
pressure on pcMem.

![Trace diagram](./figure/trace.svg)

## Feature support

The current implementation of the KMH core's internal trace only supports
instruction tracing. The instruction trace information collected within the core
includes: priv, cause, tval, itype, iretire, ilastsize, and iaddr. The itype
field supports all types.

## Trace pipeline stage functions:

There are three cycles in ctrlBlock:

* Stage 0: Buffer rob commitInfo for one cycle;
* Stage 1: commitInfo compression, blocking commit signal generation;
* Stage 2: Reads the basePc from pcmem based on the compressed ftqptr, and
  retrieves the priv, xcause, and xtval corresponding to the currently committed
  instruction from csr.

memBlock

* Stage 3: Calculate the final iaddr using ftqOffset and the basePc read from
  pcmem;

## Trace buffer compression mechanism

Before each group of commitInfo enters the trace buffer, it must be compressed.
That is, each commitInfo item requiring a PC is combined with its preceding
items into a single entry before being sent to the trace buffer. Before entering
the trace buffer, it is determined whether all entries can be dequeued in the
next cycle. If not, the rob's commit is blocked. This block persists until the
commitInfo that triggered the block signal is fully dequeued from the trace
buffer. The commitInfo that generates the blockCommit signal will
unconditionally enter the trace buffer, but the commitInfo in the next cycle
will definitely be blocked.
