# Rename renaming

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

The Rename module receives instruction decode information from the Decode module
and allocates robIdx and physical registers based on the decode information,
querying the corresponding physical registers for operands. Simultaneously, the
module maintains the state of the freeList according to the instruction decode
information, instruction commit information, and register release information
from RenameTable. It also sends write requests to RenameTable to update the
register mapping state during speculative execution, based on the instruction
decode and commit information. Additionally, the module handles redirect
requests from the ROB, updating the freeList state according to the redirect
information. After renaming, Rename sends the renamed instruction information to
the Dispatch module.

## Basic functionality

Mapping logical registers to physical registers, assigning a physical register
to each logical register in the instruction.

Register renaming maintains rename-related tables or pointers. It manages the
mapping table from logical registers to physical registers, recording the most
recently allocated physical register number for each logical register.

For integer, floating-point, and vector registers, separate physical register
state tables are maintained with 224, 192, and 128 entries, respectively. These
tables record the allocation status of physical registers and track unallocated
physical registers using free physical register allocation pointers.

Maintains a committed logical-to-physical register mapping table (RenameTable,
RAT) recording the mapping relationship between logical and physical registers
in committed state.

Maintains a commit-state pointer for free physical register allocation. Register
renaming technology eliminates write-after-read (WAR) and write-after-write
(WAW) dependencies between instructions, ensuring precise state recovery when
instructions are canceled due to exceptions or mispredicted branch instructions.

## Rename Input

- Input from the decode stage (the FusionDecoder modifies the instructions
  output by the DecodeStage for macro-op fusion, adjusting valid, uop, and other
  information based on adjacent instruction combinations. It also modifies the
  commit type CommitType of the fused instruction based on the ftqptr and
  ftqoffset combinations of adjacent instructions.)
- Accepts speculative rename data feedback from RAT
- Instruction fusion information, and modifying decoded instruction stream based
  on fusion conditions.
- SSIT, waittable information
- Ctrlblock snapshot control information and enqueue/dequeue pointers
- RAB commit information

## Rename Output

- Interact with RAT: Write rename information.
- Interact with dispatch: Pipeline output of renamed uop information when
  dispatch recv is valid.
- With snapshot: enqdata, allowing snapshot generation.

## Allocating integer physical registers {#sec:alloc-int-prf}

Upon receiving valid integer instruction decoding information from the Decode
module, the Rename module determines whether a new integer physical register
needs to be allocated based on the signals io\_in\_[0-5]\_bits\_rfWen and
io\_in\_[0-5]\_bits\_ldest. If rfWen is high and ldest is not 0, a new integer
physical register is allocated. If allocation is required, a request is sent to
intFreeList, and the allocation result is obtained in the same cycle; otherwise,
no request is sent. Additionally, the Rename module supports integer Move
instruction elimination. If a decoded instruction is identified as an integer
Move instruction, no new integer physical register is allocated.

## Allocating floating-point or vector physical registers {#sec:alloc-fp-vec-prf}

Upon receiving valid vector floating-point instruction decode information from
the Decode module, the Rename module determines whether to allocate new vector
floating-point physical registers based on the io_in_[0-5]_bits_fpWen and
io_in_[0-5]_bits_vecWen signals. If the fpWen or vecWen signal is high, a new
floating-point or vector physical register needs to be allocated. If allocation
is required, a request is sent to the fpFreeList or vecFreeList, and the
allocation result is obtained in the same cycle; otherwise, no allocation
request is sent.

## Setting the Physical Register for Source Operands (psrc)

If the instruction decode information from the Decode module includes integer
register or vector floating-point register-type source operands, under normal
circumstances, the Decode module will query the RenameTable one cycle in advance
to obtain the physical register corresponding to the logical register. The
result is obtained in the Rename module one cycle later and transmitted to the
Dispatch module via io_out_[0-5]_bits_psrc_[0-4]. As an exception, if the
destination operand of the previous instruction is the same as the source
operand of the current instruction, the psrc of the current instruction should
be set to the pdest of the previous instruction.

## Set the physical register (pdest) for the destination operand

If the instruction decode information from the Decode module indicates the
presence of a destination operand (see [@sec:alloc-int-prf] and
[@sec:alloc-fp-vec-prf]), the Rename module typically assigns a new physical
register to the Dispatch module via `io_out_[0-5]_bits_pdest`. As an exception,
if the instruction is an integer Move instruction, its `pdest` should be set to
its `psrc`.

## Integer Instruction Commit {#sec:commit-int-inst}

When integer instructions commit, Rename sends free signals to intFreeList based
on io_int_need_free_[0-5] and io_int_old_pdest_[0-5] from RenameTableWrapper,
releasing the corresponding integer physical registers for reuse. If
io_int_need_free_[0-5] is high, the integer physical register in
io_int_old_pdest_[0-5] must be freed. Rename also forwards commit signals from
RAB to intFreeList for maintaining architectural state rename pointers.

## Commit of Floating-Point or Vector Instructions {#sec:commit-fp-vec-inst}

After receiving floating-point instruction commit information from the RAB,
Rename combines this with commit information from `RenameTableWrapper` to send
free signals to `fpFreeList`, releasing unused vector/floating-point physical
registers for new instructions. If the delayed
`io_rabCommits_info_[0-5]_fp/vecWen` signal, along with the delayed
`io_rabCommits_isCommit` and `io_rabCommits_commitValid_[0-5]` signals (which
indicate the current cycle is in the commit phase and the commit signal for that
channel is valid, as detailed in [@sec:w-arch-rat]), are all high, then the
corresponding `io_fp/vec_old_pdest_[0-5]` floating-point or vector register
needs to be released. Additionally, Rename forwards the commit signal from the
RAB to `fpFreeList` for maintaining the architectural state rename pointer.

## Redirect

When a redirect signal is received via the io\_redirect port, freeList suspends
physical register allocation and resets the allocation pointer to the
architectural state or a snapshot state. Additionally, the Rename module stops
sending write request signals to the RenameTable.

## Re-rename {#sec:rename-re-rename}

One cycle after the redirect signal is received, the Rename module enters the
re-renaming process. The re-renaming signal is passed to Rename from the RAB via
the `io_rabCommits` port. During re-renaming, the Rename module will no longer
output valid instruction signals to Dispatch or send write request signals to
`RenameTable`.

The Rename module sends re-renaming signals to intFreeList, fpFreeList, and
vecFreeList through their respective io\_walkReq\_[0-5] ports. These re-renaming
signals originate from the RAB module's io\_rabCommits\_walkValid\_[0-5],
io\_rabCommits\_info\_[0-5]\_isMove, io\_rabCommits\_info\_[0-5]\_ldest, and
io\_rabCommits\_info\_[0-5]\_rf/fp/vecWen signals. The signals on
io\_walkReq\_[0-5] are only valid when io\_rabCommits\_isWalk is high.

For intFreeList, when io_rabCommits_walkValid_[0-5] is high, and the
corresponding channel's io_rabCommits_info_[0-5]_rfWen is high,
io_rabCommits_info_[0-5]_ldest is not 0, and io_rabCommits_info_[0-5]_isMove is
low, the corresponding io_walkReq_[0-5] port will send a valid signal,
indicating that re-rename is required.

For `fpFreeList` and `vecFreeList`, when `io_rabCommits_walkValid_[0-5]` is high
and the corresponding channel's `io_rabCommits_info_[0-5]_fp/vecWen` signal is
high, the `io_walkReq_[0-5]` port will receive a valid signal, indicating that
re-renaming is required.

## robIdx Allocation

The Rename module is responsible for assigning robIdx to each micro-instruction.
It internally maintains a robIdxHead. Under normal circumstances, the Rename
module sequentially assigns consecutive robIdx to the decoded instructions from
the Decode module and increments the robIdxHead. However, if the corresponding
channel's io_in_[0-5]_bits_lastUop is low, or the compressUnit's corresponding
channel's io_out_needRobFlags_[0-5] is low, the next channel's micro-instruction
will not be assigned a robIdx.

In the cycle when a redirect occurs, the module resets robIdxHead to the
redirected robIdx. In the next cycle, it decides whether to increment robIdxHead
based on the value of io_redirect_bits_level.

## Determining rename snapshot generation {#sec:decide-snpt-gen}

The Rename module is also responsible for deciding whether to generate rename
snapshots. Rename snapshots aim to reduce the time required for re-renaming
after a redirect occurs. Rename snapshots are distributed across multiple
modules, including `RenameTable`, `RenameTable_1`, `RenameTable_2`,
`intFreeList`, `fpFreeList`, `vecFreeList`, `Rob`, `Rab`, and `CtrlBlock`, with
each storing different snapshot contents. Therefore, a module is needed to
coordinate snapshot generation across these modules, and this module is Rename.
Externally, Rename transmits the snapshot generation signal to other modules via
`io_out_*_bits_snapshot`. Internally, Rename also forwards the snapshot
generation signal to `intFreeList`, `fpFreeList`, and `vecFreeList`.

There are several constraints on the generation of rename snapshots. First, the
Rename module internally maintains a snapshot counter, `snapshotCtr`, and a
snapshot can only be generated when this counter is 0. Second, if another
snapshot already exists, the `robIdx` assigned to the first micro-op renamed in
the current cycle must differ by 6 from the `robIdx` of the most recently
generated snapshot, which is greater than the ROB commit width. Finally, the
first micro-op renamed in the current cycle must be the first micro-op of its
corresponding instruction, meaning `io_in_0_bits_firstUop` must be high. Only
when these three conditions are met, and there is a branch/jump instruction
among the six micro-ops being renamed, will a snapshot be generated. At this
point, the `io_out_*_bits_snapshot` signals for the channels containing
branch/jump instructions will be pulled high, and Rename will also notify its
internal submodules of the snapshot generation signal.

The snapshot counter snapshotCtr controls the interval between snapshot
generations. Since snapshots taken too close together are meaningless and waste
snapshot resources, this counter is implemented. snapshotCtr is initially set to
4 times the RAB commit width, i.e., 4×8=32. If no valid rename snapshot
currently exists, snapshotCtr is set to 0; otherwise, it decrements by n for
every n microinstructions renamed, until it reaches 0. Once snapshotCtr is 0, if
a rename snapshot is generated at any point, snapshotCtr is reset to the maximum
value minus the number of microinstructions renamed in that cycle, i.e., 32 -
PopCount(io_out_*_valid && io_out_*_ready).

## Overall Block Diagram

![Overall Rename block diagram](./figure/Rename-Overall.svg)

## Interface timing

### Timing Diagram of Decode Input Interface

![Timing Diagram of Decode Input
Interface](./figure/Rename-Input.svg){#fig:rename-input}

[@fig:rename-input] shows three input examples from decode. When both ready and
valid signals are high, the corresponding bits are received by the Rename
module.

### Timing diagram of Rename output interface

![Timing diagram of Rename output
interface](./figure/Rename-Output.svg){#fig:rename-output}

[@fig:rename-output] illustrates three rename result examples. When both ready
and valid signals are high, the corresponding bits are sent by Rename module to
Dispatch.

### Timing diagram of instruction commit logic

![Timing diagram of instruction commit
logic](./figure/Rename-Commit-IO.svg){#fig:rename-commit-io}

[@fig:rename-commit-io] illustrates the five instruction commit inputs from the
ROB. When io_rabCommits_isCommit is high and io_rabCommits_isWalk is low,
io_rabCommits_info_*_* represents the instruction commit information. When
io_rabCommits_commitValid_* is high, the corresponding io_rabCommits_info_*_*
transmits valid instruction commit information to the Rename module. Meanwhile,
io_*_old_pdest_* will send the old physical register number to be released to
the Rename module after a one-cycle delay, and after another cycle delay, it
will transmit the signal indicating whether an integer physical register needs
to be released via the io_int_need_free_* port to the Rename module.

### Timing Diagram of Redirect and Rename Recovery

![Timing diagram of redirect and
re-rename](./figure/Rename-Redirect-IO.svg){#fig:rename-redirect-io}

[@fig:rename-redirect-io] illustrates the signals before and after a redirect
occurs. In the first two cycles, io_redirect_valid is low, and Rename operates
normally, as shown in [@fig:rename-commit-io]. Subsequently, the
io_redirect_valid signal is pulled high for one cycle, indicating the arrival of
a redirect. The redirect information is sent via io_redirect_bits_*, and Rename
will enter the re-rename state starting from the next cycle. In the following
three cycles, io_rabCommits_isCommit is low, and io_rabCommits_info_*_* no
longer sends commit information. Conversely, io_rabCommits_isWalk is high,
indicating that io_rabCommits_info_*_* is sending re-rename information, and
Rename needs to perform re-rename operations. When io_rabCommits_walkValid_* is
high, the corresponding io_rabCommits_info_*_* sends valid re-rename
information.

# RenameTableWrapper

The RenameTableWrapper is a wrapper module that internally contains the integer
rename table module RenameTable, the floating-point rename table module
RenameTable_1, and the vector rename table module RenameTable_2. Beyond simply
bundling these three rename tables, this wrapper module also handles logic
related to commit and re-rename internally. The RenameTableWrapper serves as a
bridge between the internal rename tables and external modules.

## Read speculative rename table

RenameTableWrapper has 12 integer register read ports, 18 floating-point
register read ports, and 30 vector floating-point register read ports. The
integer read ports are grouped in pairs, the floating-point read ports in
triplets, and the vector read ports in sets of five, with six groups of read
ports each. The integer read ports retrieve speculative mappings from integer
logical registers to integer physical registers, the floating-point read ports
retrieve mappings from floating-point logical registers to vector floating-point
physical registers, and the vector read ports retrieve mappings from vector
logical registers to vector floating-point physical registers.

RenameTableWrapper's read operations are synchronous. This means a read request
sent via io_(int/fp/vec)ReadPorts_*_*_addr in cycle `T` will return the logical
register's corresponding physical register in cycle T+1 through
io_(int/fp/vec)ReadPorts_*_*_data.

Reads from RenameTableWrapper are forwarded. If a read request is sent to an
address in clock cycle `T` while a write request is also sent to the same
address, the value read in cycle `T+1` will be the value written to that address
in cycle `T`.

The read operation of RenameTableWrapper has a hold function. If at the `T`
clock cycle, a read port's io_(int/fp/vec)ReadPorts_*_*_hold is high, then at
the `T+1` clock cycle, the read value will be the same as that at the `T` clock
cycle.

## Writing to the Speculative Rename Table During Rename Phase

RenameTableWrapper has 6 integer register write ports, 6 floating-point register
write ports, and 6 vector register write ports, used to update speculative
rename tables during the rename phase. The integer register write ports update
the speculative mapping from logical integer registers to physical integer
registers, the floating-point write ports update the mapping from logical
floating-point registers to vector floating-point physical registers, and the
vector write ports update the mapping from logical vector registers to vector
floating-point physical registers.

Writes to RenameTableWrapper are synchronous. This means that write requests
sent via io_(int/fp/vec)RenamePorts_*_addr and io_(int/fp/vec)RenamePorts_*_data
in clock cycle `T` will not be readable until cycle `T+1`.

The writes to RenameTableWrapper are enabled. Only write requests with
io\_(int/fp/vec)RenamePorts\_\*\_wen asserted are valid.

RenameTableWrapper's write operations are prioritized. Higher-numbered write
channels have higher priority, meaning if two channels write to the same
address, the result from the higher-numbered channel prevails.

## Writing architectural rename table during commit phase {#sec:w-arch-rat}

The RenameTableWrapper updates the architectural rename table by monitoring
commit information from RAB. When the io_rabCommits_isCommit signal is high in a
cycle, it indicates a commit is occurring. If any io_rabCommits_commitValid_*
signal is high, the commit signal for that port is valid. Further examination is
then required for io_rabCommits_info_*_rfWen, io_rabCommits_info_*_fpWen, and
io_rabCommits_info_*_vecWen. If io_rabCommits_info_*_rfWen is high, the integer
register needs architectural rename table update; if io_rabCommits_info_*_fpWen
is high, the floating-point register requires update; if
io_rabCommits_info_*_vecWen is high, the vector register needs update. In these
cases, RenameTableWrapper will modify the entry at address
io_rabCommits_info_*_ldest in the integer/floating-point/vector architectural
rename table to io_rabCommits_info_*_pdest.

## Providing Physical Register Release Information During Commit Phase

The `RenameTableWrapper` provides physical register release information based on
writes to the architectural rename table during the commit phase. This
information includes the integer physical register numbers to be released
(`io_int_old_pdest_*`) and their corresponding valid signals
(`io_int_need_free_*`), as well as the vector/floating-point physical register
numbers to be released (`io_(fp/vec)_old_pdest_*`). These signals come directly
from the submodules of `RenameTableWrapper` and are used by the Rename module to
release physical registers based on instruction commit status.

## Writing to the Speculative Rename Table During Re-Rename Phase

RenameTableWrapper listens to commit information from RAB to perform
re-renaming. If the io\_rabCommits\_isWalk signal is high in a cycle, it
indicates re-renaming is occurring. If a specific io\_rabCommits\_walkValid\_\*
signal is high, it means the re-renaming signal for that port is valid. Further
checks are required for io\_rabCommits\_info\_\*\_rfWen,
io\_rabCommits\_info\_\*\_fpWen, and io\_rabCommits\_info\_\*\_vecWen. If
io\_rabCommits\_info\_\*\_rfWen is high, it indicates integer registers need
re-renaming; if io\_rabCommits\_info\_\*\_fpWen is high, it indicates
floating-point registers need re-renaming; if io\_rabCommits\_info\_\*\_vecWen
is high, it indicates vector registers need re-renaming. In these cases,
RenameTableWrapper will modify the entry at io\_rabCommits\_info\_\*\_ldest in
the integer, floating-point, or vector speculative rename tables to
io\_rabCommits\_info\_\*\_pdest.

## Maintenance of rename snapshots

The RenameTableWrapper forwards external rename snapshot signals io\_snpt\_\* to
each submodule for generating, releasing, flushing, and using rename snapshots.

## Overall Block Diagram

![Overall block diagram of RenameTableWrapper](./figure/RenameTableWrapper.svg)

## Interface timing

### Timing Diagram for Integer Read/Write Interface (Floating-Point Vector Similar)

![Integer read/write interface timing
diagram](./figure/RAT-Wrapper-RW-IO.svg){#fig:rat-wrapper-rw-io}

[@fig:rat-wrapper-rw-io] illustrates the timing of integer read/write
interfaces.

At time 2, io_intRenamePorts_0 writes 73 to address 14. Simultaneously,
io_intReadPorts_0_0 issues a read request to address 14, thus reading the value
73 written at time 2 during time 3.

At time 4, io\_intRenamePorts\_0 writes 74 to address 4, and
io\_intRenamePorts\_1 also writes 75 to address 4. Consequently, when
io\_intReadPorts\_0\_0 issues a read request to address 4 at time 5, it reads
the value 75 written by io\_intRenamePorts\_1 at time 6.

At times 3 and 7, io_intReadPorts_0_0_hold is high, so the values read at times
4 and 8 match those read at times 3 and 7 (73 and 76, respectively), rather than
the values at address 5 or the newly written value 77 at time 7.

### Timing Diagram of Rename Recovery and Commit Interface

![Timing Diagram of Re-Rename and Commit
Interfaces](./figure/RAT-Wrapper-Re-Rename-IO.svg){#fig:rat-wrapper-re-rename-io}

[@fig:rat-wrapper-re-rename-io] illustrates the timing of two re-rename and
commit interfaces.

From time 1 to time 4, io_rabCommits_isWalk is high, and io_rabCommits_ioCommit
is low, indicating a re-renaming state. At time 2, io_rabCommits_walkValid_0 is
high, io_rabCommits_info_0_rfWen is low, and io_rabCommits_info_0_fpWen is high.
Thus, re-rename interface 0 writes 37 to address 0 of the floating-point
speculative rename table. At time 3, both re-rename interfaces write to logical
integer register 12. Here, interface 1 has higher priority than interface 0, so
57 is written to address 12 of the integer speculative rename table.

From time 5 to time 9, io_rabCommits_isWalk is low and io_rabCommits_ioCommit is
high, indicating the commit state. At time 7, io_rabCommits_commitValid_0 is
high, io_rabCommits_info_0_rfWen is low, and io_rabCommits_info_0_fpWen is high,
so commit interface 0 writes 92 to address 18 in the floating-point
architectural rename table.

# RenameTable supporting move elimination {#sec:me-rat}

The `RenameTable` supporting move elimination is used for integer register
renaming. The module, named ``RenameTable``, maintains the mapping between
logical and physical integer registers. It has 12 speculative rename table read
ports, 6 speculative rename table write ports, and 6 architectural rename table
write ports. Internally, it uses 32 registers with a width of 8 to manage the
mappings. The behavior of the read and write ports is identical to that
described in `RenameTableWrapper`. Note that for timing considerations,
speculative rename table write requests at ``T0`` are processed at ``T1``, and
speculative rename table write data at ``T0`` is bypassed to speculative rename
table read results at ``T1``.

Additionally, the module internally maintains 4 speculative rename table
snapshots for quick recovery during redirection and re-renaming. These snapshots
are stored in the submodule SnapShotGenerator_3, named
_snapshots_snapshotGen_io_snapshots_0/1/2/3_[0-31] in RenameTable. The
generation, release, usage, and flushing of snapshots are entirely controlled by
external signals io_redirect and io_snpt_*.

The externally provided redirect signal `io_redirect` and snapshot control
signal `io_snpt_*` are delayed by one cycle to become `t1_redirect` and
`t1_snap_*`. When `t1_redirect` is high, the `t1_snap_useSnpt` signal is
checked. If `t1_snap_useSnpt` is low, the speculative rename table is set to the
architectural rename table. If `t1_snap_useSnpt` is high, the speculative rename
table is set to
`_snapshots_snapshotGen_io_snapshots_[t1_snap_snptSelect]_[0-31]`.

Additionally, the module generates physical register release signals based on
the write ports to the architectural rename table and the internal architectural
rename table outputs. If the write enable signal io_archWritePorts_n_wen for a
write port is low, the next cycle's io_old_pdest_n will be 0. If the write
enable signal is high, the next cycle's io_old_pdest_n will be the current
cycle's arch_table[io_archWritePorts_n_addr]. Note that io_old_pdest_n is
bypassed. For n > 0, if a lower-indexed channel (j < n) writes to the same
logical register in the architectural rename table, the next cycle's
io_old_pdest_n should reflect the value written by the lower-indexed channel
(io_archWritePorts_j_data) instead of arch_table[io_archWritePorts_n_addr].
Furthermore, for n > 1, if multiple lower-indexed channels write to the same
logical register, the next cycle's io_old_pdest_n should reflect the value
written by the highest-indexed channel among them (e.g.,
io_archWritePorts_k_data for j < k < n).

The physical register release signals also include io_need_free_*. If the
current cycle's io_old_pdest_n signal does not match any entry in arch_table_*,
the next cycle's io_need_free_n signal for that channel will be set high. Note
that for n > 0, if a lower-indexed channel's io_old_pdest_j matches
io_old_pdest_n, the next cycle's io_need_free_n signal will not be set high.

## Overall Block Diagram

![Overall Block Diagram of RenameTable](./figure/RenameTable.svg)

## Interface timing

### Timing diagram of read/write interfaces

![Timing diagram of RenameTable read/write interface supporting move
elimination](./figure/RAT-RW-IO.svg)

# RenameTable without move elimination support

The RenameTable without move elimination support is fundamentally similar to
[@sec:me-rat] but excludes io_need_free_* signals. The floating-point rename
table `RenameTable_1` and vector rename table `RenameTable_2` use this type.

The floating-point register rename table `RenameTable_1` maintains the mapping
between logical floating-point registers and physical vector floating-point
registers. It has 18 read speculative rename table ports, 6 write speculative
rename table ports, and 6 write architectural rename table ports. Internally, it
uses 34 registers with a width of 8 to maintain the mapping relationships.

The floating-point register rename table ``RenameTable_2`` maintains the mapping
between logical vector registers and physical vector/floating-point registers.
It has 30 speculative rename table read ports, 6 speculative rename table write
ports, and 6 architectural rename table write ports. Internally, it uses 48
registers with a width of 8 to manage the mappings.

## Interface timing

### Timing diagram of read/write interfaces

![Timing diagram of RenameTable read/write interfaces without move elimination
support](./figure/RAT-NO-ME-RW-IO.svg)

# StdFreeList

Within the Rename module, StdFreeList is instantiated as fpFreeList and
vecFreeList. As mentioned in [@sec:alloc-fp-vec-prf], [@sec:commit-fp-vec-inst],
and [@sec:rename-re-rename], fpFreeList is responsible for receiving allocation
requests for vector floating-point physical registers during rename, returning
allocated free vector floating-point physical registers. During re-rename, it
handles reallocation of vector floating-point physical registers based on
re-rename requests from the RAB. During commit, it releases vector
floating-point physical registers that are no longer in use and updates the
architectural dequeue pointer.

## Overall Block Diagram

![Overall block diagram of StdFreeList](./figure/StdFreeList.svg)

## Interface timing

### Timing diagram of free register allocation

![Timing Diagram of StdFreeList Physical Register
Allocation](./figure/StdFreeList-Alloc-IO.svg){#fig:stdfreelist-alloc-io}

[@fig:stdfreelist-alloc-io] illustrates the timing for free physical register
allocation. At times 3, 5, and 6, io_redirect and io_walk are low, while
io_doAllocate and io_canAllocate are high, enabling the allocation of free
physical registers. At time 3, io_allocateReq_[2-4] is high, and StdFreeList
returns the allocated free physical register numbers 151, 112, and 143 via
io_allocatePhyReg_[2-4]. At time 5, io_allocatePhyReg_[0-2|5] returns the
allocated free physical register numbers 127, 162, 163, and 144. At time 6, it
returns 174, 182, and 179. For every successful allocation of `n` free physical
registers, the internal headPtr increments by `n`.

### Instruction Commit Timing Diagram

![Timing diagram of StdFreeList instruction
commit](./figure/StdFreeList-Commit-IO.svg){#fig:stdfreelist-commit-io}

[@fig:stdfreelist-commit-io] illustrates the timing of instruction commit, where
io_freeReq_* represents the io_freeReq signal for a specific path, and
io_freePhyReg_* represents the io_freePhyReg signal corresponding to
io_freeReq_* for a specific path. When both io_redirect and io_walk are low, if
io_freeReq is high, StdFreeList will add the corresponding io_freePhyReg to the
free queue.

Furthermore, one cycle before io\_freeReq\_\*, the Rename module also passes the
RAB commit information to update the architectural dequeue pointer archHeadPtr.
When io\_commit\_isCommit and the corresponding channel's
io\_commit\_commitValid\_\* signal are high, it indicates that the update signal
for that channel is valid. In this case, if the corresponding channel's
io\_commit\_info\_\*\_fpWen or io\_commit\_info\_\*\_vecWen is high, it means
the channel will increment archHeadPtr by one. If `k` channels meet the above
conditions, archHeadPtr will be incremented by `k`.

### Timing Diagram of Instruction Rename Recovery

![Timing diagram of StdFreeList instruction
re-rename](./figure/StdFreeList-Re-Rename-IO.svg){#fig:stdfreelist-re-rename-io}

[@fig:stdfreelist-re-rename-io] illustrates the timing of instruction
re-renaming. When `io_redirect` is asserted high for one cycle at time 1,
`io_walk` will be held high for several cycles, indicating the module has
entered the re-renaming phase. At time 1, since `io_snpt_useSnpt` is low,
`headPtr` is restored to the value of `archHeadPtr`. This restoration is not
immediate; instead, at time 2, the count of high `io_walkReq_*` signals (2) is
added to obtain `headPtrAllocate` (5), which is written to `headPtr` at time 3.
Subsequently, while `io_walk` is high, `headPtrAllocate` is set to `headPtr +
PopCount(io_walkReq_*)` and written to `headPtr` in the next cycle.

The rename recovery process aims to eliminate rename states on mispredicted
execution paths. This is achieved by first restoring headPtr to the
architectural state archHeadPtr (or to the snapshot state when io_snpt_useSnpt
is high), then renaming back to the state before entering the incorrect path.

## Key circuit: Circular queue

Free physical registers are maintained by a circular queue. This queue consists
of the register group freeList (i.e., freeList_* in the code, with a size of
size), a head pointer headPtr (i.e., headPtr_* in the code), and a tail pointer
tailPtr (i.e., tailPtr_* in the code). Here, headPtr is the dequeue pointer, and
tailPtr is the enqueue pointer.

For clarity, consider a standard queue where both headPtr and tailPtr are
pointers to elements in the freeList. During normal operation, tailPtr is always
greater than or equal to headPtr, and the queue elements are {headPtr, headPtr +
1, ..., tailPtr - 1}. When an element is enqueued, it is placed in
freeList[tailPtr], and tailPtr is incremented by one. When an element is
dequeued, freeList[headPtr] is retrieved, and headPtr is incremented by one. If
tailPtr equals headPtr, the queue is empty; if tailPtr is greater than headPtr,
the queue is non-empty.

![Regular queue](./figure/Queue-Normal.svg)

However, since freeList cannot be infinitely long, we designed a circular queue
- essentially connecting a finite regular queue end-to-end. Here, tailPtr and
headPtr can no longer simply point to freeList elements: under original design,
when tailPtr equals headPtr, the circular queue could be either empty or full.

To address this issue, we added a flag field to tailPtr and headPtr. This field
is initially false and toggles each time the pointer wraps around from
freeList[size - 1] to freeList[0]. Thus, when the value is the same, if the
flags are identical, it indicates the circular queue is empty; if the flags
differ, it indicates the queue is full.

Timing for updating canAllocate: In the current cycle, freeRegCnt is calculated
based on headPtr, tailPtr, freeReq, and allocateReq. This value is then
registered in the next cycle as freeRegCntReg (which represents the actual
size). If freeRegCntReg exceeds the decode width, canAllocate is set high and
propagated in the same cycle.

![Circular queue](./figure/Queue-Circle.svg)

# MEFreeList

MEFreeList is instantiated as intFreeList in the Rename module. As mentioned in
[@sec:alloc-int-prf], [@sec:commit-int-inst], and [@sec:rename-re-rename],
intFreeList handles allocation requests for integer physical registers during
rename, returns allocated free integer physical registers, reallocates integer
physical registers based on re-rename requests from RAB during re-rename, and
releases unused integer physical registers during commit. Unlike StdFreeList,
MEFreeList supports move instruction elimination. If an instruction is a move
instruction, Rename does not assert io\_allocateReq\_\*\_valid, so MEFreeList
does not allocate a free physical register for it.

## Overall Block Diagram

![Overall block diagram of MEFreeList](./figure/MEFreeList.svg)

## Interface timing

### Timing diagram of free register allocation

![Timing Diagram of MEFreeList Physical Register
Allocation](./figure/MEFreeList-Alloc-IO.svg){#fig:mefreelist-alloc-io}

[@fig:mefreelist-alloc-io] illustrates the timing of free physical register
allocation. At times 3, 5, and 6, io\_redirect and io\_walk are low, while
io\_doAllocate and io\_canAllocate are high, enabling free physical register
allocation. At time 3, io\_allocateReq\_[2-4] is high, and MEFreeList returns
allocated free physical register numbers 151, 112, and 143 via
io\_allocatePhyReg\_[2-4]. At time 5, io\_allocatePhyReg\_[0-2|5] returns
allocated free physical register numbers 127, 162, 163, and 144. At time 6, it
returns 174, 182, and 179.

### Instruction Commit Timing Diagram

![MEFreeList instruction commit timing
diagram](./figure/MEFreeList-Commit-IO.svg){#fig:mefreelist-commit-io}

[@fig:mefreelist-commit-io] illustrates the timing of instruction commits. Here,
`io_freeReq_*` represents the `io_freeReq` signal for a specific lane, and
`io_freePhyReg_*` represents the `io_freePhyReg` signal corresponding to
`io_freeReq_*` for that lane. When both `io_redirect` and `io_walk` are low, if
`io_freeReq` is high, `StdFreeList` will add the corresponding `io_freePhyReg`
to the free queue.

Additionally, two cycles before io_freeReq_*, the Rename module passes commit
information from the RAB to update the architectural dequeue pointer
archHeadPtr. When io_commit_isCommit and the corresponding channel's
io_commit_commitValid_* are high, the update signal for that channel is valid.
If the channel's io_commit_info_*_rfWen is high, io_commit_info_*_ldest is
non-zero, and io_commit_info_*_isMove is low, it indicates that the channel will
increment archHeadPtr by one. If `k` channels meet these conditions, archHeadPtr
will be incremented by `k`.

When io\_commit\_commitValid\_\* is high in a cycle, the io\_freeReq\_\* signal
may not always be high two cycles later. This phenomenon is caused by move
elimination. The io\_freeReq\_\* signal here comes from the RenameTable's output
signal io\_need\_free. As mentioned in the RenameTable module, RenameTable's
io\_need\_free signal may not be asserted when the arch\_table contains the same
physical register. This occurs because move elimination causes different logical
registers to share the same physical register, resulting in identical physical
registers across different entries in RenameTable.

### Timing Diagram of Instruction Rename Recovery

![MEFreeList instruction re-rename timing
diagram](./figure/MEFreeList-Re-Rename-IO.svg){#fig:mefreelist-re-rename-io}

[@fig:mefreelist-re-rename-io] illustrates the timing of instruction re-rename.
When io_redirect is asserted high for one cycle at time 1, io_walk is
subsequently asserted high for several cycles, indicating the module has entered
the re-rename phase. At time 1, since io_snpt_useSnpt is low, headPtr is
restored to the value of archHeadPtr. This restoration does not occur
immediately but is calculated at time 2 by adding the count of high io_walkReq_*
signals (2) to obtain headPtrAllocate (5), which is then written to headPtr at
time 3. Thereafter, when io_walk is high, headPtrAllocate is set to headPtr +
PopCount(io_walkReq_*) and written to headPtr in the next cycle.

The re-rename process aims to eliminate rename states on incorrectly speculated
execution paths. This is achieved by first restoring the headPtr to the
architectural archHeadPtr state (or to the snapshot state when io_snpt_useSnpt
is high), then re-renaming to the state before entering the incorrect path.

# CompressUnit

The CompressUnit determines which instructions can share the same ROB entry,
i.e., be compressed into a single ROB entry. This module receives outputs from
the decode unit and generates ROB compression information based on the decode
results.

A channel is marked as compressible by the ROB (`canCompress_[0-5]`) if and only
if the decoded information for that channel meets the following conditions: the
channel's decoded information is valid (`io_in_[0-5]_valid`), the channel does
not involve instruction fusion (`!io_in_[0-5]_bits_commitType[2]`), the channel
does not involve instruction splitting or is the last micro-op of a split
instruction (`io_in_[0-5]_bits_lastUop`), the channel has no exceptions
(`io_in_[0-5]_bits_exceptionVec_*` are all low), and the channel is marked as
compressible by the ROB (`io_in_[0-5]_bits_canRobCompress`).

The `CompressUnit` outputs a flag for each channel indicating whether a ROB
entry needs to be allocated (`io_out_needRobFlags_[0-5]`). The
`io_out_needRobFlags_[0-5]` signal for a channel is set high if and only if
`canCompress_[0-5]` for that channel is 0, or if the channel is the one with the
highest index in its contiguous group of `canCompress_[0-5]` set to 1.

The `CompressUnit` outputs the number of instructions in the ROB entry for each
channel via `io_out_instrSizes_[0-5]`. When `canCompress_[0-5]` for a channel is
0, `io_out_instrSizes_[0-5]` for that channel is 1. When `canCompress_[0-5]` for
a channel is 1, `io_out_instrSizes_[0-5]` for that channel is the count of
elements in the contiguous group of `canCompress_[0-5]` where it belongs.

CompressUnit outputs a channel mask io\_out\_masks\_[0-5] for each channel,
indicating which channels share the same ROB entry. This signal is 6 bits wide,
matching the number of channels. When canCompress\_n is 0 for a channel,
io\_out\_masks\_n[n] is 1, and all other bits are 0. When canCompress\_n is 1,
the bits set to 1 in io\_out\_masks\_n correspond to the indices of channels in
the "continuous group of canCompress\_[0-5] set to 1" that includes the current
channel.

For example, if {canCompress_5, canCompress_4, canCompress_3, canCompress_2,
canCompress_1, canCompress_0} == {1, 0, 0, 1, 1, 0}, then
{io_out_needRobFlags_5, io_out_needRobFlags_4, io_out_needRobFlags_3,
io_out_needRobFlags_2, io_out_needRobFlags_1, io_out_needRobFlags_0} == {1, 1,
1, 1, 0, 1}, {io_out_instrSizes_5, io_out_instrSizes_4, io_out_instrSizes_3,
io_out_instrSizes_2, io_out_instrSizes_1, io_out_instrSizes_0} == {1, 1, 1, 2,
2, 1}, {io_out_masks_5, io_out_masks_4, io_out_masks_3, io_out_masks_2,
io_out_masks_1, io_out_masks_0} == {{1, 0, 0, 0, 0, 0}, {0, 1, 0, 0, 0, 0}, {0,
0, 1, 0, 0, 0}, {0, 0, 0, 1, 1, 0}, {0, 0, 0, 1, 1, 0}, {0, 0, 0, 0, 0, 1}}.

## Overall Block Diagram

![Overall block diagram of CompressUnit](./figure/CompressUnit.svg)

## Interface timing

This module is purely combinational logic with signals processed within the same
cycle.

# SnapshotGenerator

As mentioned in [@sec:decide-snpt-gen], rename snapshots are distributed across
modules requiring error path elimination after redirection to accelerate
re-renaming. For rename-related modules, this submodule exists in RenameTable,
RenameTable_1, RenameTable_2, StdFreeList, and MEFreeList.

The snapshot data stored in different submodules varies. For RenameTable(\_\*),
each stores four spec\_tables; for StdFreeList and MEFreeList, each stores four
headPtrs.

The module internally maintains a pair of circular pointers, `snptEnqPtr` and
`snptDeqPtr`. When `io_redirect` is low, if the snapshot storage is not full and
`io_enq` is high, the module records the data from `io_enqData_*` into
`snapshots_[snptEnqPtr_value]`, sets `snptValids[snptEnqPtr_value]` to 1, and
increments `snptEnqPtr`.

Conversely, when io\_redirect is low, if io\_deq is high, it indicates that the
snapshot module needs to dequeue a snapshot. At this point,
snptValids\_[snptDeqPtr\_value] will be set low, and snptDrqPtr will be
incremented by one.

During redirection, the snapshot module flushes internal snapshots based on
io_flushVec_* signals. First, if io_flushVec_* is high, the corresponding
channel's snptValids_* will be deasserted; second, snptEnqPtr rolls back to the
first position where snptValids_* becomes low after deassertion.

The data stored in snapshots is transmitted externally via the
io\_snapshots\_[0-3]\_\* interface for recovery during redirection. Whether and
which snapshot to use during redirection is determined by CtrlBlock, which
generates the unified control signals. This module only provides the snapshot
data.
