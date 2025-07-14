# DataPath

- Version: V2R2
- Status: OK
- Date: 2025/01/15
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Glossary of Terms

Table: Terminology Explanation

| Abbreviation | Full name                  | Description                     |
| ------------ | -------------------------- | ------------------------------- |
| og           | Operand generation         | Source operand generation stage |
| v0           | Vector register #0         | Vector logical register 0       |
| vl           | Vector length CSR register | Vector length csr register      |
| rc/reg cache | Register file cache        | Register file cache             |


## Overall design

### Overall Block Diagram

![Overall Block Diagram](./figure/datapath.svg)

### Submodule List

Table: Submodule List

| Submodule             | Description                                             |
| --------------------- | ------------------------------------------------------- |
| IntRFWBCollideChecker | Integer register file write port arbiter                |
| FpRFWBCollideChecker  | Floating-point register file write port arbiter         |
| VfRFWBCollideChecker  | Vector general-purpose register file write port arbiter |
| V0RFWBCollideChecker  | Vector v0 register file write port arbiter              |
| VlRFWBCollideChecker  | Integer vl register file write port arbiter             |
| IntRFReadArbiter      | Integer register file read port arbiter                 |
| FpRFReadArbiter       | Floating-point register file read port arbiter          |
| VfRFReadArbiter       | Vector general-purpose register file read port arbiter  |
| V0RFReadArbiter       | Vector v0 Register File Read Port Arbiter               |
| VlRFReadArbiter       | Vector VL register file read port arbiter               |
| IntRegFile            | Integer register file                                   |
| FpRegFile             | Floating-point register file                            |
| VfRegFile             | Vector general-purpose register file                    |
| V0RegFile             | Vector v0 register file                                 |
| VlRegFile             | Vector vl register file                                 |
| RegCache              | Integer register file cache                             |

### Interface list

Refer to the interface documentation.


## Function

### Overall Functionality

The data path is located in the pipeline after dispatch and before entering the
execution units. It receives instructions from the dispatch queues of integer,
floating-point, vector, and memory operations, with each dispatch exit
corresponding one-to-one to an execution unit's ExeUnit. The data path is
responsible for reading the register file for each instruction, constructing
immediate values, and generating the final operands before entering the ExeUnit.
It contains the physical register files and handles arbitration for register
file read and write operations, as well as data reading and writing. Currently,
the data path also includes a cache for the integer register file, responsible
for reading a portion of integer data.

The DataPath module is the core component of the data path, encompassing the
entire OG0 pipeline stage and the first half of the OG1 pipeline stage. In the
OG0 stage, arbitration for read ports among instructions is performed—only
instructions that win arbitration will read from the register file and proceed
to the OG1 stage. Instructions that lose arbitration will flush themselves, send
a dispatch failure response to the previous stage, and issue an og0 cancel
signal. In the OG1 stage, instructions receive data returned from the register
file and send it along with other state information to subsequent modules. Note
that the DataPath does not perform the final generation of instruction operands;
it only retrieves candidate data read from the register file, Reg Cache, and
PcTargetMem. The final data is generated in the external BypassNetwork.

### Read-write arbitration

Since post-issue register file reading is employed, the number of instructions
issued to the data path far exceeds the read and write ports of the register
file. Therefore, arbitration is necessary to allow only those instructions that
succeed in read arbitration to access the registers.

Each register file has a read arbiter that receives the valid signal and read
address (addr) for each operand of all instructions, returning a ready signal as
a flag for successful arbitration. Only when an instruction's operand matches
the corresponding data type (integer, floating-point, vector general-purpose,
v0, vl) and the data source is of type reg will the valid signal be raised to
initiate an arbitration request. If an operand does not need to read the
register file, its valid signal is 0, and the ready signal will always return 1
to allow it to pass the arbiter. For each instruction, only when all its
operands pass arbitration is it considered a successful read arbitration. The
read arbiter also outputs a set of read requests, equal in number to the
register file's read ports, containing the successfully arbitrated read
addresses for each port. These read requests are sent to the register file for
actual data retrieval.

Each register file has a write arbiter that receives the valid signal for each
operand of all instructions, returning a ready signal as a flag for successful
arbitration. Only when the destination register data type matches and a register
write is required will the valid signal be raised to initiate an arbitration
request. Similar to read arbitration, instructions that do not initiate a
request will always receive ready=1 to allow them to pass the arbiter.

The arbitration logic within the read-write arbiter is detailed in the secondary
module.

### Read register file

Each register file's read arbiter outputs a set of read requests, equal in
number to the register file's read ports, containing the last successfully
arbitrated read address for each port. These addresses are sent to the register
file in the OG0 stage to initiate read requests. In the OG1 stage, the
corresponding data is output from the register file's read data channels. Each
instruction's operands select their data from the register file's read data
based on their data type and the read port number used.

### Read Reg Cache

A Reg Cache is implemented within DataPath to buffer recently written-back data
from integer ExeUnits and Load ExeUnits. The Reg Cache does not require
read/write arbitration, with its port count matching one-to-one with the number
of operands needing read/write access. If an instruction operand's data source
is of the regcache type, a read request is sent to the Reg Cache. In the OG0
stage, the valid signal and the RC address signal carried by the instruction
itself are sent to the Reg Cache, and in the OG1 stage, data can be retrieved
from the corresponding data channel.

### Read PC

Some instructions require reading the PC as a source operand, with the PC stored
in the external PcTargetMem of the DataPath. During the OG stage, the DataPath
first filters out instructions that need the PC and issues read requests for
their ftq information through the io.fromPcTargetMem interface to the external.
In the OG1 stage, the external returns the read PC information via this
interface.

### Write register file

The write-back results from execution units are aggregated by the external
module WbDataPath, packaged into write request format, and sent to DataPath.
DataPath receives write-back information from five interfaces: io.fromIntWb,
io.fromFpWb, io.fromVfWb, io.fromV0Wb, and io.fromVlWb, each corresponding to
its respective register file. The number of channels per interface matches the
write ports of the register file, containing write enable, write address, and
write data. For timing considerations, these signals are registered within
DataPath for one cycle before being directly forwarded to the register file
write ports.

### Write Reg Cache

The write-back data for the Reg Cache does not come from the execution units but
from the bypass network two cycles after the execution units write back. The Reg
Cache only accepts data from integer ExeUnits and Load ExeUnits, which are
passed through the io.fromBypassNetwork interface and directly sent to the Reg
Cache.

### Handling og0 cancel

In the OG0 stage, instructions can be canceled for various reasons, with
self-induced cancellations referred to as og0 cancel. An instruction is
determined to be og0 canceled under two circumstances: one is failing
arbitration for reading or writing the register file, and the other is the
propagation of og0 cancel. The DataPath retains information about the previous
og0 cancel, represented as a vector with the same width as the issue width,
where each bit indicates whether the corresponding instruction was canceled. If
an instruction has 0 execution delay and is canceled, a 1 is written to its
corresponding position in the vector. In the next cycle, instructions will
compare their operand wake-up source vectors with the cancel information vector.
If they find that the source instruction was canceled in the previous cycle,
they themselves will also be canceled.

Instructions that experience an og0 cancel will flush themselves and not enter
the OG1 stage. In addition to og0 cancel, instructions that experience redirect
flushes or load cancels will also flush themselves and not join the OG1 stage.
However, only instructions that experience og0 cancel will emit the og0 cancel
signal externally. This signal, identical to the internally stored og0 cancel
information mentioned earlier, is transmitted externally via the io.og0Cancel
interface to cancel the instruction's consumer instructions.

### Send a response to the issue queue

DataPath sends response information to the issue queue, indicating whether
instructions were successfully issued to execution units. During the OG stage,
if an instruction experiences og0 cancel, its issue fails, requiring DataPath to
respond with a block status to the issue queue, signaling the need for re-issue.
If it passes the OG0 stage smoothly, no response is sent. In the OG1 stage,
instructions cannot be canceled due to their own issues; it only depends on
whether the subsequent stage can accept them. If not, the instruction cannot
enter the execution unit, and a block status must be sent to the issue queue. If
acceptable, scalar computation instructions are guaranteed to execute
successfully, prompting a success response to the issue queue to clear the
corresponding entry. For vector computation instructions, an uncertain status is
returned before the OG2 stage, as execution is not yet confirmed, keeping the
issue queue unchanged. For memory access instructions, their success can only be
determined after entering the memory execution unit, so the clear response is
issued by the memory unit, while DataPath only returns an uncertain status here.


## Module Design

### Secondary module RFWBCollideChecker

#### Function

Each register file has a write port arbiter responsible for arbitrating write
requests. The arbiter collects valid signals from all instructions requesting to
write to that register file and returns ready signals indicating arbitration
success.

Inside the arbiter, it is divided into multiple port arbiters based on port
numbers. Each port arbiter collects instruction requests for writing to that
port. For example, if an instruction uses the i-th port to write back to the
stack, its request will be sent to the i-th port arbiter.

The port arbiter adopts a priority-based arbitration strategy with a fallback
mechanism. When configuring functional units, each unit's configuration for the
register file write port includes not only the port number but also a priority
level. If multiple instructions issue write requests simultaneously, the port
arbiter grants arbitration success to the instruction with the higher priority.

The port arbiter ensures that if an instruction does not issue a request, its
ready=1, indicating arbitration success; if multiple instructions issue requests
simultaneously, only one among them will have ready=1, signifying arbitration
success.

The port arbiter is configured with a fallback strategy, assigning a counter to
each instruction. Each time an instruction issues a request but fails
arbitration, the counter is incremented; each time it succeeds, the counter is
cleared. When the counter accumulates to its maximum value of 7, the fallback
state is triggered. In this state, all non-fallback instruction requests are
masked, and priority arbitration is performed. Once the fallback succeeds and
the instruction wins arbitration, the counter is cleared, exiting the fallback
state.

#### Overall Block Diagram

Taking the floating-point register file write port arbiter as an example, its
internal structure is shown in the figure below.

![Overall Block Diagram](./figure/fpWArbiter.svg)

#### Interface list

Refer to the interface documentation.

### Secondary module RFReadArbiter

#### Function

Each register file has a read port arbiter responsible for arbitrating read
ports. Similar to the write port arbiter, the read port arbiter collects all
requests for operands that can read the register file and returns a flag
indicating whether arbitration was successful. The difference is that the
requests collected by the read port arbiter also carry the read address, and it
ultimately outputs the successfully arbitrated address for each read port, which
is then sent to the register file for the read operation.

Within the arbiter, it is similarly divided into multiple port arbiters for
arbitration based on port numbers. Similar to write arbitration, each port
arbiter also adopts a priority arbitration strategy with a fallback mechanism.
The final output address for each port is provided by the operand that issues a
request and wins arbitration. If there is no read request at a certain moment,
the final address defaults to that of the operand with the lowest priority.

#### Overall Block Diagram

The structure of the read port arbiter is essentially the same as that of the
write port arbiter, so it won't be elaborated here. The main difference is that
each read request carries a read address, and each internal port arbiter also
outputs a final address.

#### Interface list

Refer to the interface documentation.

### Secondary module RegFile

#### Function

The DataPath is equipped with five physical register files: integer and
floating-point each have a single file, while the vector register file is split
into three to reduce port count and area overhead. Among these, VfRegFile is the
general-purpose vector register file, storing values for logical registers
#1-#31 and some temporary registers. V0RegFile is dedicated to the vector #0
logical register, and VlRegFile exclusively holds the value of the vector vl CSR
register.

The register file employs a partitioned design, divided into S=1, 2, or 4 blocks
depending on specific conditions. The partitioning is vertical, meaning a
register file with a capacity of N and element size of M-bit is divided into S
register files of size N * (M / S). Each element is distributed across the
blocks, and both reading and writing operations access all partitioned register
files simultaneously.

The register file has R read ports, each with two signals: raddr (address) and
rdata (data), without a read enable signal. At a given moment, the read address
is provided, and the register file latches the address for one cycle. In the
next cycle, it uses the address to read the corresponding data and sends it to
the data interface.

The register file has W write ports, each with three signals: write enable
(wen), write address (waddr), and write data (wdata). At any given moment, if
wen is asserted, the corresponding address will be written with the provided
data, and the written data will be visible in the next cycle. The integer
register file has a special location: address 0 is never actually written to and
always retains a value of 0.

#### Specifications

Table: Register File Specifications

| Register File | Capacity | Bit Width | Number of read ports | Number of write ports | Number of blocks |
| ------------- | -------- | --------- | -------------------- | --------------------- | ---------------- |
| IntRegFile    | 224      | 64-bit    | 11                   | 8                     | 4                |
| FpRegFile     | 192      | 64-bit    | 11                   | 6                     | 4                |
| VfRegFile     | 128      | 128-bit   | 12                   | 6                     | 4                |
| V0RegFile     | 22       | 128-bit   | 4                    | 6                     | 2                |
| VlRegFile     | 32       | 8-bit     | 4                    | 4                     | 1                |


### Secondary module RegCache

#### Overall Block Diagram

![RegCache Overall Block Diagram](./figure/regcache.png)

#### Function

The Reg Cache, as a subset of the Reg File, stores the most recent write-back
results from some EXUs and handles part of the read requests originally sourced
from reg-type data, thereby reducing the number of read ports required for the
Reg File.

Currently, Reg Cache is only set for the integer register file, storing the
write-back results of 4 ALU-equipped EXUs and 3 LDUs.

##### Data Section (RC Data Module)

The pipeline stage for the data portion is the same as the Reg File, with read
requests issued in the OG0 stage and data retrieved in the OG1 stage.

The data section is divided into two parts: RC_INT is responsible for storing
results from the 4 ALUs in the EXUs, and RC_LS is responsible for storing
results from the 3 LDUs.

Each section internally adopts a fully associative structure, while the entire
Reg Cache employs unified addressing using 5 bits, where the most significant
bit being 0 represents RC_INT and 1 represents RC_LS.

The specific parameter configuration of the Reg Cache is shown in the table
below.

Table: Reg Cache Specifications

| Reg Cache | Capacity | Bit Width | Number of read ports | Number of write ports |
| --------- | -------- | --------- | -------------------- | --------------------- |
| RC_INT    | 16       | 64-bit    | 23                   | 4                     |
| RC_LS     | 12       | 64-bit    | 23                   | 3                     |

(1) Reading RC data

Instruction reading RC data is similar to reading the register file. In the OG0
stage of the data path, the data source is an RC-type operand initiating a read
request to RC, sending out the corresponding RC address.

In the OG1 stage of the data path, the RC data result is obtained and
transmitted to the BypassNetwork, where the final data is selected through
multiplexing based on the data source type.

No arbitration is set for reading RC; each operand capable of reading the
integer register file is assigned an exclusive read port.

(2) Writing RC Data

RC data is written using the bypassed data from the BypassNetwork stage, with
the write address being the RC address carried when the wake-up signal is
issued.

Due to the 3-cycle interval between wake-up issuance and data write-back
reaching the bypass stage, the selected replacement item addresses in the RC
must be delayed by 3 cycles before being used for data writing.

##### Age component (RC Age Timer)

The age component consists of two modules: the age counter and the age matrix.
The age counter module assigns a 2-bit age counter to each RC entry, which is
updated based on the read and write operations of the RC entries.

Maintain separate age matrices for RC_INT and RC_LS, each cycle selecting 4 and
3 entries respectively for replacement, and transmitting their RC_Idx to the
WakeUpQueue of 4 ALUs and 3 LDUs. Each WakeUpQueue carries the corresponding
RC_Idx when issuing a fast wake-up signal, informing its consumers to fetch data
from that location.

For an N-entry RC, its age matrix is an N x N square matrix. Each entry
Age[i][j] indicates the relative age order between entry i and entry j. A value
of 1 means entry i is older than entry j, and entry i should be evicted first.

Clearly, Age[i][j] = ~Age[j][i] (if i != j), and we stipulate that if i == j,
Age[i][j] = 1. Thus, the portion that actually needs to be stored is the upper
triangular matrix, consisting of N * (N - 1) / 2 bits.

(1) Replacement algorithm

The age matrix is maintained as follows:

 - 在 T0 时刻根据各项的状态，通过一个年龄比较函数得到两两之间的年龄次序，写入年龄矩阵
 - At time T1, based on the count of 1s in each row, entries exceeding the
   threshold are considered selected for replacement.

If M items are to be selected for replacement, then items with a count of 1s >=
N - M + 1 are chosen. Based on the count of 1s ranging from N - M + 1 to N, the
positions of these M items are determined, thereby obtaining RC_Idx.

(2) Age Update

Each RC entry maintains an AgeTimer, with update rules as follows:

 - When an entry is updated, the counter is cleared
 - Currently has a read request, remains unchanged (including cases where a read
   request was issued but the instruction was canceled)
 - 计数器已达到最大值，维持不变
 - In all other cases, the counter increments by 1.

``` c
if (wen):
    AgeTimerNext = 0
else if (hasReadReq):
    AgeTimerNext = AgeTimer
else if (AgeTimer == 3):
    AgeTimerNext = 3
else:
    AgeTimerNext = AgeTimer + 1
```

(3) Age comparison

The age comparison function compares based on AgeTimerNext—the larger the
counter value, the older the entry is considered. If two counters have the same
value, the entry with the smaller index is considered older.

``` c
for(i = 0; i < N ; i++)
    for(j = 0; j < N; j++)
        if (i == j)
            AgeNext[i][j] = 1
        else if (i < j)
            if (AgeTimerNext[i] >= AgeTimerNext[j])
                AgeNext[i][j] = 1
            else
                AgeNext[i][j] = 0
        else
            AgeNext[i][j] = ~AgeNext[j][i]
```

#### Interface list

Refer to the interface documentation.
