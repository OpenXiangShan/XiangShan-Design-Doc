# IssueQueue

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Design specifications

- Supports four different types of issue queue modules to accommodate scalar
  integer, vector floating-point, scalar memory, and vector memory operations
- Supports two enqueue ports and two dequeue ports
- Supports speculative wake-up signal generation
- Support speculative wake-up signal register replication
- Supports early detection of instruction write-back conflicts
- Supports issuing the oldest instruction among ready instructions

## Function

The issue queue module serves as the starting point of the processor's
out-of-order scheduling, connecting the previous Dispatch pipeline stage and the
subsequent DataPath pipeline stage. In a superscalar out-of-order processor, to
achieve correct out-of-order execution of instructions, it is necessary to
correctly handle the dependencies between instructions. The key to determining
whether an instruction can execute correctly is the readiness of its source
operands. A source operand becomes ready only after the preceding instruction it
depends on has completed execution. The IQ receives up to two instructions
dispatched from the Dispatch stage, whose source operands may not yet be ready.
These instructions are temporarily stored inside the IQ, which continuously
monitors wake-up signals that will mark the corresponding source operands as
ready. Each cycle, the IQ internally selects up to two instructions with all
operands ready, following the oldest-first policy, and sends them to the
subsequent DataPath pipeline stage. Through this method, the issue queue ensures
that all inter-instruction dependencies are guaranteed during out-of-order
execution while maximizing the performance of out-of-order scheduling.

### Instruction enqueue

The enqueue logic for the four different types of issue queues is largely the
same, with only minor differences due to variations in certain signals. The
issue queue internally instantiates the Entries module responsible for
instruction storage. Generally, the issue queue supports two enqueue ports,
meaning it can receive up to two valid instructions from the previous pipeline
stage each cycle. Correspondingly, the Entries module also supports two enqueue
ports. The instruction enqueue process involves the instructions entering
through the IQ's input ports, selecting key signals, and sending them to the
Entries' input ports. During this process, signals inherent to the instructions,
such as robIdx and fuType, are directly connected without additional processing.
Signals indicating instruction status, such as srcState, are initialized through
combinational logic before entering the Entries. For detailed signal
information, refer to the Entries interface documentation. This issue queue
supports simultaneous instruction enqueue and wake-up. Due to timing
considerations, the wake-up logic is not implemented directly before the
instructions enter the Entries but instead involves sending the input wake-up
signals to the Entries, synchronously delaying them by one cycle before wake-up.

### Maintenance of instruction age relationships

To implement the oldest-first policy for instruction issue selection, the issue
queue needs to record and process the age of instructions within the entries
every cycle. The issue queue internally instantiates several AgeDetector modules
to achieve this functionality. Corresponding to the three different types of
entries, the issue queue needs to instantiate up to three AgeDetectors. Each age
matrix can simultaneously receive multiple age queries from dequeue ports and
return the oldest entry among the queries. Each cycle, the AgeDetector receives
the enqueue status of the three types of entries from the Entries feedback,
responsible for maintaining the age relationships of all instructions.
Intuitively, when an instruction is enqueued, its age is necessarily the
youngest among all instructions. The issue queue maintains instruction age
relationships through signal transmission from Entries to AgeDetector and
applies the oldest-first policy during the instruction issue selection phase by
reading the AgeDetector.

### Instruction issue selection

The issue queue divides entries into at most three types and supports the
transfer of instruction storage locations between entries. The three types of
entries have strict age relationships, so instruction issue selection is
performed in parallel for each type of entry, followed by a final 3-to-1
selection of the oldest instruction for issue. Due to timing considerations, to
meet the requirement of two dequeue ports, the design prioritizes the needs of
the first dequeue port. The functional implementation is as follows: based on
the three Detectors corresponding to EnqEntry, SimpleEntry, and ComplexEntry,
the three oldest issuable instructions are selected, and then, according to the
strict age relationships among the three types of entries, one instruction is
ultimately selected following the priority order Complex > Simple > Enq and sent
to the first dequeue port. For the second dequeue port, the selection depends on
the configuration of the functional units (fu) at the ports: if the fus of the
two ports are different, the instructions they can dequeue will not overlap, and
the second port selects the oldest instruction using the same method as the
first port. If the fus of the two ports are the same, overlap is possible, so
after masking the selection result of the first port, a "random" valid
instruction is selected. In the current IQ configuration, the fus of the two
ports are different (or there is only one port), so there is no "random"
selection scenario, and the specific "random" process is not elaborated further.

### Speculative wake-up signal generation

The issue queue is responsible for managing instructions, not only including the
management of when instructions are issued but also informing other instructions
when they can be issued, the latter of which is achieved through speculative
wake-up. Generally, if an instruction's source operand depends on the write-back
value of a previous instruction, the current instruction's source operand can
only be marked as ready when the previous instruction writes back. To improve
the performance of out-of-order instruction execution, if the previous
instruction has a fixed execution latency, its write-back time can be determined
when it is issued from the issue queue. Accordingly, the issue queue can
generate a speculative wake-up signal at a certain time, as long as it is
ensured that the speculatively woken instruction does not fetch its source
operand earlier than the time the previous instruction obtains its result. This
can accelerate out-of-order execution through forwarding or bypassing. In the
issue queue, for non-memory IQ, the module responsible for generating
speculative wake-up signals is the WakeupQueue. In the same cycle an instruction
is selected for issue, it also enters the WakeupQueue, moving through different
shift pipelines based on its execution latency—0 latency generates a speculative
wake-up after one cycle, 2 latency after three cycles, and so on. This method
enables the generation of speculative wake-up signals. For memory IQ, its
wake-up signal is passed from the memory unit through the loadWakeUp interface
unique to the memory IQ, delayed by one cycle, treated as the IQ's own wake-up
signal, and then broadcast to other IQs through the same interface as the
WakeupQueue.

### Early detection of write-back conflicts

Write-back conflicts are divided into two parts. The first part involves the
write-back conflict at the IQ exit itself. Each dequeue port of the issue queue
corresponds to an EXU, and each EXU may contain a group of FUs with varying
execution latencies. However, each EXU has only one write-back port (referring
to the write-back port to the ROB, distinct from the register file write port,
where one or more EXU write-back ports share a single register file write port).
For example, a combination of ALU and Mul FUs can lead to write-back conflicts
between 0-latency and 2-latency instructions. If a 0-latency instruction is
issued two cycles after a 2-latency instruction, they will complete execution
simultaneously, resulting in an FU write-back conflict. To prevent such
scenarios, the issue queue internally instantiates the fuBusyTable module to
detect FU conflicts. The fuBusyTable operates on a per-dequeue-port basis,
recording each port's dequeued instructions and their respective feedback
signals each cycle to update its records. Subsequent instruction selection and
issuance also reference this module's records to avoid FU write-back conflicts.
The second part involves register file write-back conflicts. Due to the limited
number of register file write ports, multiple EXU write-back ports may share a
single register file write port, leading to potential write port conflicts
between issue queues. Similarly, the issue queue instantiates intWbBusyTable and
vfWbBusyTable. Whenever an instruction is issued, the corresponding write logic
is generated and sent to the external WbFuBusyTable module, where write ports
with the same identifier are processed to obtain the final WbFuBusyTable. During
instruction selection, the WbFuBusyTable is read from the external module based
on the write port and fed into the IQ as a reference for selection.

## Overall Block Diagram

![Schematic diagram](./figure/IssueQueue_top.svg)

## Interface timing

![Schematic diagram](./figure/IssueQueue_io.png)

## Secondary module WakeupQueue

A critical module controlling the issuance of speculative wake-up signals by
each IQ, serving as the wake-up source for speculative wake-up and corresponding
to each non-memory access IQ's dequeue port. The module internally consists of
multiple pipelines, with the number of pipelines directly related to the Fu
Latency of the corresponding dequeue port. The number of pipelines corresponds
to the different Latencies of the Fu associated with the dequeue port.

### Overall Block Diagram

![Schematic diagram](./figure/IssueQueue_wakeupqueue.svg)

### Interface timing

![Schematic diagram](./figure/IssueQueue_wq_io.png)

## Secondary module AgeDetector

This module is the age matrix module, maintaining the order of instruction age
among entries in the issue queue. The entries in the issue queue can be
categorized into at most three types, and for each type, their AgeDetector
modules are independent. This module uses matrix registers to indicate the age
relationships between entries, with the rows and columns of the matrix
corresponding to the number of entries. Below is an example using a 6-entry
SimpleEntry:

![Schematic diagram](./figure/IssueQueue_age.svg)

### Overall Block Diagram

![Schematic diagram](./figure/IssueQueue_age_top.svg)

