# Vector FOF Instruction Unit VfofBuffer

## Functional Description

Process and write back the uop that modifies the VL register for vector Fault
Only First (fof) instructions. For fof instructions, we additionally split out a
separate uop responsible for modifying the VL register. Currently, we adopt a
non-speculative execution approach for fof instructions.

### Feature 1: Collect write-back information of memory-accessing uops

The VfofBuffer is responsible for collecting write-back information of
memory-accessing uops from fof instructions, with only one entry. If the VL
register needs to be updated, the information maintained in the VfofBuffer is
updated accordingly. When a Fault Only First (fof) instruction is dispatched, in
addition to the normal entry into VLSplit, an entry is also allocated in the
vfofBuffer. This entry monitors the write-back of uops with the same RobIdx from
the VLMergeBuffer, without preventing these uops from writing back to the
backend. Instead, it collects relevant metadata from these uops to update its
own VL. Uops written back to the backend from the VLMergeBuffer carry exception
information and VL, among other details. Based on this write-back information,
we determine whether the uop should cause a change in VL. If a VL change is
required, it is compared with the VL maintained in the VfofBuffer and updated to
the smaller value.

### Feature 2: Write back the uop that modifies the VL register

The VfofBuffer will write back the uop that modifies the VL register only after
all memory-accessing uops of the instruction have been written back. Even if no
modification to the VL register is needed, this uop will still be written back,
but the write signal will not be enabled.

## Overall Block Diagram

No block diagram for a single module.

## Main ports

|                   | Direction | Description                                           |
| ----------------: | --------- | ----------------------------------------------------- |
|          redirect | In        | Redirect port                                         |
|                in | In        | Receive uop dispatch from the Issue Queue.            |
| mergeUopWriteback | In        | Receive data uops written back from the VLMergeBuffer |
|      uopWriteback | Out       | Write back the uop modifying VL to the backend        |


## Interface timing

The interface timing is relatively simple, described only in text.

|                   | Description                                                          |
| ----------------: | -------------------------------------------------------------------- |
|          redirect | Has Valid status. Data is valid when Valid is asserted.              |
|                in | Includes Valid and Ready signals. Data is valid when Valid && Ready. |
| mergeUopWriteback | Includes Valid and Ready signals. Data is valid when Valid && Ready. |
|      uopWriteback | Includes Valid and Ready signals. Data is valid when Valid && Ready. |
