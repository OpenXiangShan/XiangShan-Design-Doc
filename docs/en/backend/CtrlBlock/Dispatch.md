# Dispatch

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Glossary of Terms

Table: Terminology Explanation

| Abbreviation | Full name       | Description                                                                                                 |
| ------------ | --------------- | ----------------------------------------------------------------------------------------------------------- |
| -            | renameIn        | Uop information input to the rename module                                                                  |
| -            | fromRename      | Buffered uop information output from the rename module.                                                     |
| -            | toRenameAllFire | Signal indicating all uops have completed dispatch                                                          |
| -            | enqRob          | Signals sent to the rob are buffered for one cycle in ctrlblock before entering the rob.                    |
| -            | IQValidNumVec   | Number of instructions per Exu in IQ                                                                        |
| -            | toIssueQueues   | Uop information dispatched to all IQs                                                                       |
| -            | XXBusyTable     | Register file status table                                                                                  |
| -            | wbPregsXX       | Write-back register file information, used to update the BusyTable.                                         |
| -            | wakeUpXX        | Fast wake-up information, used for speculative updates to the BusyTable.                                    |
| -            | og0Cancel       | Indicates that the uop is canceled in the og0 stage                                                         |
| -            | ldCancel        | Indicates that the memory access uop has executed up to the s3 stage (s0-s3), and the uop has been canceled |
| -            | fromMem         | Signals from memory operations, including lsq commit and cancel counts.                                     |
| -            | toMem           | Signals sent to memory, including lsqEnqIO.                                                                 |

## Submodule List

Table: Submodule List

| Submodule   | Description                                                                                                                                             |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| XXBusyTable | Register file status tables, comprising five types: Int (integer), Fp (floating-point), Vec (vector, excluding V0), V0 (vector V0), and Vl (vcsr's vl). |
| rcTagTable  | Integer register cache (register file cache) Tag table                                                                                                  |
| lsqEnqCtrl  | Module controlling pointers entering the load/store queue                                                                                               |

## Design specifications

- Supports dispatching uops to all IQs using a load-balancing strategy.
- Supports updating and maintaining the BusyTable and writing to srcState during
  dispatch
- Supports updating and maintaining pointers entering the LSQ and writing them
  to lqidx and sqidx during dispatch
- Supports sequential blocking of uops
- Supports masking instructions with exceptions when dispatching to IQs

## Function

The Dispatch module includes the BusyTable, rcTagTable, and lsqEnqCtrl for each
register file. It updates the BusyTable and rcTagTable based on the write-back
register file, fast wake-up, og0Cancel, and ldCancel. The lsqEnqCtrl module
controls the enqueue pointers lqidx/sqidx for the load/store queue. When the lsq
capacity is insufficient, it pulls down io_enq_CanAccept to block dispatch.

Each clock cycle, the Dispatch module dispatches up to 6 uops that have
undergone renaming to various IQs. Once all pending uops are dispatched, the
handshake signal toRenameAllFire is asserted. Upon receiving this signal, the
rename module updates the next set of uops for the Dispatch module.

Each clock cycle, the Dispatch module counts the number of instructions per Exu
in each IQ. For each fu type, all Exus containing it undergo load comparison
across their respective IQs, strictly following load order to generate dispatch
strategies, which are then stored in registers.

The Dispatch module collects input signals from rename and output signals after
pipelining. Based on the fuType in the input signals, it calculates the number
of preceding uops (with smaller indices) that share the same fu as each uop.
Using these two pieces of information, it looks up a table to determine the
dispatch IQ. The first piece of information is the fu type, and the second is
the count of preceding uops with the same fu type. Dispatch is performed in
ascending order of IQ load: the first uop of a given fu type is assigned to the
least-loaded IQ, the second to the next least-loaded IQ, and so on.

The Dispatch module receives control signals from various modules to block the
dispatching of instructions. The reasons for blocking mainly include: the
targeted IQ is not ready, the number of instructions dispatched to the same IQ
exceeds the IQ's entry capacity, the ROB cannot receive instructions, the LSQ
cannot receive instructions, there are preceding instructions that require
blockBackward, or the instruction itself or preceding instructions require
waitForward. Blocking occurs sequentially; if an instruction is blocked, all
subsequent instructions are also blocked. Once blocking occurs, toRenameAllFire
is pulled low, and the next group of instructions can only be dispatched after
the blocked instructions have been dispatched.

The Dispatch module masks instructions under exceptional conditions (by
deasserting the valid signal sent to the IQ) and does not dispatch them to the
IQ. Examples include instructions with decoding exceptions or those flagged for
singleStep.


## Overall design

### Overall Block Diagram

![Overall Block Diagram](./figure/dispatch.svg)

### Interface list

Refer to the interface documentation.

## Module Design

### Level 2 module BusyTable

#### Function

The BusyTable module is responsible for recording the busy status of the
register file. During dispatch, it reads the BusyTable with psrc to obtain the
ready status of source operands.

Each register file corresponds to a BusyTable module, with the number of entries
matching the register file, initialized to 0 (idle state). When an instruction
is renamed, the corresponding pdest information is input via allocPregs,
changing the corresponding entry from 0 to 1. The BusyTable also receives
speculative wake-up signals wakeUpXX, changing the corresponding entry from 1 to
0 upon wake-up. Speculatively woken instructions may be canceled, in which case
og0Cancel changes the corresponding entry from 0 to 1 (possibly in the same
cycle as wakeup, with higher priority than wakeup). For integer BusyTables,
ldCancel must also be handled.

The number of read ports in the BusyTable module is determined by the number of
register operands required per instruction in the ISA multiplied by the issue
width. For example, with a 6-issue width, the integer BusyTable has 2 * 6 = 12
read ports, while floating-point and vector units have 18 each, and V0 and Vl
have 6 each.

#### Overall Block Diagram

![Overall Block Diagram](./figure/busyTable.svg)

#### Interface list

Refer to the interface documentation.

### Submodule rcTagTable

#### Function

The rcTagTable serves as the tag for the integer register file cache, closely
resembling the integer BusyTable module, and also features 12 read ports.


#### Interface list

Refer to the interface documentation.

### Submodule lsqEnqCtrl

The lsqEnqCtrl module manages the pointers for entries into the lsq and sends
uops to the lsq. It maintains pointers based on each instruction's needAlloc (a
2-bit signal, where the LSB indicates entry into the load queue and the MSB
indicates entry into the store queue) and numLsElem (the number of entries
required). When io_enq_iqAccept is asserted (indicating the uop is accepted by
the IQ), the uop is sent to the lsq.


#### Interface list

Refer to the interface documentation.
