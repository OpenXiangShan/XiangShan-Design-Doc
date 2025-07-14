# WbDataPath

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Glossary of Terms

Table: Terminology Explanation

| Abbreviation | Full name              | Description            |
| ------------ | ---------------------- | ---------------------- |
| v0           | Vector mask register   | Vector Mask Register   |
| vl           | Vector length register | Vector Length Register |
| ROB          | Reorder Buffer         | Reorder Buffer         |

## Submodule List

Table: Submodule List

| Submodule            | Description                 |
| -------------------- | --------------------------- |
| VldMergeUnit         | Vector Load Data Merge Unit |
| RealWBCollideChecker | Writeback Arbiter           |

## Function

The wbDataPath module includes a vector load merge unit (VldMergeUnit) and a
write-back arbiter (RealWBCollideChecker). Its primary function is to receive
output signals from various execution units, perform merge processing on the
output signals from execution units with vector load capabilities, and
ultimately output the processed signals.

### Data Processing

The wbDataPath receives output signals from different execution units (integer
execution unit, floating-point execution unit, vector execution unit, memory
access unit) and uses these signals as input signals fromExuPre. It filters out
signals related to vector load operations (VLoad) from the input signals
fromExuPre and combines these elements into a new sequence.

Instantiate multiple vector load merge unit modules based on the index of the
element sequence, and assign the redirection signals, vector load
operation-related signals, and values from the vstart register to the vector
load merge unit module for processing.

Note: Since XiangShan flushes the pipeline, when vstart is not 0 and a vector
memory instruction is executed, the vstart value in CSR will serve as the first
element of that vector instruction. When an exception occurs, the vstart in the
write-back data is the new value, so this vstart cannot be used as the starting
value for vector memory operations.

Filter out indices from the input signal fromExuPre that share the same
parameters as the vector load merge unit module. Use these indices to update the
old vector load operation data in the input signal fromExuPre with the results
processed by the vector load merge unit module, obtaining the processed data
from the execution unit, fromExu.

### Arbiter

Since we have set up register files for the vector v0 and vl registers, write
arbitration must also be performed for v0 and vl.

If the input signal's valid is active and the integer register file write enable
is active, the integer write arbiter's input is valid. If the input signal's
valid is active and the floating-point register file write enable is active, the
floating-point write arbiter's input is valid. If the input signal's valid is
active and the vector register file write enable is active, the vector write
arbiter's input is valid. If the input signal's valid is active and the v0
register file write enable is active, the v0 write arbiter's input is valid. If
the input signal's valid is active and the vl register file write enable is
active, the vl write arbiter's input is valid.

If the vector execution unit writes back to the integer register file, the input
to the integer write arbiter is delayed by one cycle. Only execution units with
uncertain delays need the arbiter's result, and the result data can be retained
until the arbiter succeeds. For execution units with deterministic delays, if
the request fails in the arbiter, the result data is permanently lost. Ports
that do not write back to the physical register file are always ready, and the
highest priority port is always set to ready.

### Output

If the input to the integer write arbiter is valid and the integer write arbiter
is ready, the data is output through the integer write arbiter. If the input to
the floating-point write arbiter is valid and the floating-point write arbiter
is ready, the data is output through the floating-point write arbiter. If the
input to the vector write arbiter is valid and the vector write arbiter is
ready, the data is output through the vector write arbiter. If the input to the
v0 write arbiter is valid and the v0 write arbiter is ready, the data is output
through the v0 write arbiter. If the input to the vl write arbiter is valid and
the vl write arbiter is ready, the data is output through the vl write arbiter.

The output data is sent to the DataPath to be written into the register file in
the next cycle; the output data is sent to the dispatch module to set the
physical register file's state as ready for instruction dispatch; the output
data is sent to the scheduler for write-back wake-up.

### Write back to ROB

Only functional units with successful output handshakes can write back data to
the ROB. In the CtrlBlock, the data is registered for one cycle, and it is
determined whether the write-back data flushes the pipeline, triggers an
exception, fires a trigger, or requires replay. The data is then sent to the ROB
for write-back.

### Overall Block Diagram

![Overall block diagram of WbDataPath](./figure/wbDatapath.svg)

### Interface list

Refer to the interface documentation.

### Secondary Module VldMergeUnit

#### Function

The VldMergeUnit module is primarily used to handle the merging logic for vector
load operations. It receives write-back data from the execution unit, processes
it through the VldMgu module for merging, and finally outputs the merged
write-back data. This module uses the wbReg register to store intermediate data
and selects whether to directly use the write-back data or the merged data based
on the vlWen signal.

For uops where vl is modified by first-only-fault instructions, the write-back
data can be directly used.

#### Overall Block Diagram

![Vector Load Functional Unit Merge Module](./figure/VldMergeUnit.svg)

### Secondary module RealWBCollideChecker

#### Function

The main function of the RealWBCollideChecker module is to perform conflict
checking and arbitration on the write ports of write-back operations. By
grouping the input ports, instantiating an arbiter for each output port, and
connecting the input and output ports to the arbiters, it achieves arbitration
of the write ports.

##### Input-Output Mapping

First, group the input elements by port, then sort the elements within each
group by priority, and finally return the grouped and sorted mapping inGroup.

##### Arbiter Instantiation

Each arbiter is responsible for handling arbitration for one output port. If the
mapping includes the current output port number x, instantiate a RealWBArbiter
module; otherwise, there is no corresponding arbiter for that output port.

##### Arbiter Input

For each arbiter, if the arbiter is not empty, connect the arbiter's input port
to the corresponding mapped input group.

##### Arbiter

A priority arbiter that selects the highest-priority request from multiple input
requests to respond to.

1. By default, the lowest priority request is selected. When all requests are
   invalid, the last input (index n-1) is chosen as the default output.
2. Traverse input ports from the second-lowest priority (n-2) to the highest
   priority (0). When the valid signal of a request i is active, update chosen
   to i and set the output data to the data of that request. Priority rule: the
   smaller the index (0 being the highest priority), the higher the priority.
   The first valid request will override subsequent request assignments.
3. Generate control signals grant based on the valid signal sequence of all
   requests, indicating whether each request is granted. If the length of the
   valid signal sequence is 0, there are no requests. If the length is 1, there
   is only one request, which is directly granted. If the length is greater than
   1, the first element uses the original value, indicating the highest priority
   request does not require precondition checking. Subsequent elements have
   control signals set to !(OR of all preceding requests), meaning the current
   request is granted only if all higher-priority requests are invalid.
4. If the request is granted, the ready signal is determined by the out.ready of
   the downstream module; if the request is invalid, the ready signal is always
   active.
5. If the lowest priority request is granted, the output is valid only when the
   last request is valid; otherwise, the output is directly valid (higher
   priority requests have already been granted).

##### Arbiter Output

For each output port, if the arbiter is not empty, connect the arbiter's output
port to the corresponding output port, and the arbiter's output port is always
ready; if the arbiter is empty, the output port is set to 0.
