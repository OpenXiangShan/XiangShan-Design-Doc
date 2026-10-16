# Architecture Overview {#sec:overview}

XiangShan AI (XSAI) builds on the Kunminghu V2 high-performance general-purpose processor, integrates the CUTE matrix compute unit, and extends the control core's matrix configuration, command commit, memory access, and synchronization mechanisms. The control core executes general-purpose programs and scalar and vector operations, while CUTE executes asynchronous matrix tasks. They work together through command interfaces, the memory system, and synchronization interfaces.

This chapter uses `DefaultMatrixConfig` to introduce the main XSAI modules and their relationships. The overall architecture is shown in [@fig:xsai-overview].

![XSAI overall architecture and matrix data path](figure/xsai-architecture.svg){#fig:xsai-overview}

[View the full architecture diagram](figure/xsai-architecture.svg)

In [@fig:xsai-overview-comparison], components retained from Kunminghu V2 appear at 50% opacity to highlight XSAI additions and modifications.

![Architecture comparison between XSAI and Kunminghu V2](figure/xsai-architecture-comparison.svg){#fig:xsai-overview-comparison}

[View the full architecture comparison diagram](figure/xsai-architecture-comparison.svg)

## Control Core {#sec:overview-core}

The control core retains the instruction-fetch and out-of-order execution structure of Kunminghu V2. Its frontend comprises the branch prediction unit, fetch target queue, instruction cache, instruction fetch unit, and instruction buffer, supplying the backend with instructions. The backend handles decode, rename, dispatch, scheduling, execution, and retirement. Integer, floating-point, and vector execution resources each have issue queues and physical register files.

XSAI adds rename, scheduling, and execution paths for the Mx matrix dimension registers to the backend. Mx holds the matrix dimensions M, N, and K, while MCfgGen maintains matrix register data type configuration. MSET0/MSET1 handle matrix dimension writes and reads; MMA and MZERO generate compute or zeroing commands from the configuration and operands. For matrix memory instructions, MLSU translates and checks the starting address before generating a memory command for CUTE.

Matrix commands are held in AmuCtrlBuffer within the ROB. After the corresponding instructions commit, the commands pass through AMU Arbiter to CUTE. The control core's vector execution resources also support BF16 format conversion, widening multiply-accumulate, base-2 exponentiation, and other operations, providing element-wise computation for inference programs alongside matrix multiply-accumulate.

See [Backend Overview](backend/index.md), [Matrix Function Units](backend/FunctionUnit/MatrixFunctionUnit.md), and [Vector Floating-Point Unit](backend/VFPU.md) for the control-core pipeline and function units.

## CUTE Matrix Compute Unit {#sec:overview-cute}

CUTE comprises TaskController, matrix registers, MTE, load and store units, and memory interfaces. TaskController buffers commands from the control core, maintains matrix register dependencies and execution resource occupancy in the Issue Window, dispatches tasks to ready execution resources, and tracks task completion and retirement.

AB MatrixReg holds A and B operands in four shared tr registers. C MatrixReg holds accumulator values and results in four acc registers. The control core's Mx registers hold matrix dimensions, while CUTE's tr/acc registers hold matrix elements.

MTE is the matrix compute execution resource scheduled by TaskController. It includes operand supply, the MatrixTE compute array, and result writeback. The default array comprises 8×8 PEs. It reads A and B operands from tr and accumulator values from acc, performs `C ← A × B + C`, and writes the result back to acc.

AML and BML load external A and B data into tr, respectively. CML loads the initial accumulator matrix into acc or stores results from acc to external memory. TaskController schedules these load, compute, and store tasks according to their dependencies, allowing independent tasks to overlap.

The execution resources access HBL2 through LocalMMU and Cute2TL. LocalMMU handles request arbitration, transaction identifier management, and response routing, while Cute2TL converts TileLink requests and adapts responses. See [CUTE Matrix Compute Unit](cute/index.md) for the implementation of each submodule.

## Memory System {#sec:overview-memory}

The control core's LSU/LSQ handles scalar and vector memory accesses through DCache, the TLB hierarchy, and page-table walkers. The matrix memory path adds MLSU, DTLB/PMP, and matrix memory queues to supply translated physical base addresses to CUTE commands and maintain memory instruction exception and replay state.

Each core's HBL2 connects both the control core and CUTE. Matrix requests use the cache directory, MSHRs, and coherence mechanisms. A dedicated matrix read-data interface returns complete cache lines to CUTE. In the default matrix configuration, each core's HBL2 holds 2 MiB across 8 banks. The multicore system connects to the shared L3 and system interconnect through CHI.

See [MLSU](memblock/LSU/MLSU.md) for address translation and the matrix access flow, and [HBL2](cache/l2cache/HBL2.md) for the matrix cache interface.

## System Support and Debug {#sec:overview-system}

CSRs and privileged control logic maintain processor state. CLINT provides timers and software interrupts, while IMSIC receives message-signaled interrupts. The Debug module provides external debug access, and performance monitoring records events from the control core, CUTE, and memory system for software tuning and diagnosis.

See [CSRs](backend/CSR.md), [Performance Monitoring](backend/HPM.md), [Debug Module](backend/DebugModule/DM.md), and [CUTE Performance Events and Debug](cute/Performance.md) for the relevant designs.

## Control-Core and CUTE Cooperation {#sec:overview-paths}

### Command Path {#sec:overview-command}

Matrix instructions pass through decode, register rename, scheduling, and execution in the control core, obtaining dimensions, data types, and required operands. The execution units write the generated commands to AmuCtrlBuffer. After the ROB commits the corresponding instructions, AMU Arbiter sends the commands to CUTE through `AmuCtrlIO`. TaskController receives the commands and schedules the actual data operations according to matrix register dependencies.

### Matrix Data Path {#sec:overview-data}

Matrix data passes through HBL2, Cute2TL, and LocalMMU to AML/BML/CML, which write the selected tr or acc registers. MTE reads operands from tr/acc and writes results back to acc. CML stores the results to external memory through the same memory interfaces. The control core supplies command parameters, while matrix data moves among CUTE's registers and load, compute, and store resources.

### Synchronization Path {#sec:overview-sync}

Software uses `mrelease` and `macquire` to coordinate the control core and matrix tasks. After the write acknowledgments for the older Stores required by Release have arrived, CUTE returns a synchronization notification to the control core through `AmuRelease`. The Fence unit updates the corresponding msync counter, and `macquire` waits for the counter to reach the software-specified target. Software uses this protocol to schedule subsequent operations that depend on matrix results and to reuse buffers.

See [Memory Interfaces and System Integration](cute/Integration.md) for the interfaces, address handling, and synchronization semantics of these three paths.

## Reading Guide {#sec:overview-reading}

Table: Main modules and subsequent chapters {#tbl:overview-reading}

| Topic | Subsequent chapters |
| --- | --- |
| Instruction supply | [Branch Prediction](frontend/BPU/index.md), [Instruction Fetch Unit](frontend/IFU/index.md), and [Instruction Cache](frontend/ICache/index.md) |
| Matrix configuration, execution, and commit | [MCfgGen](backend/CtrlBlock/MCfgGen.md), [Matrix Function Units](backend/FunctionUnit/MatrixFunctionUnit.md), and [AmuCtrlBuffer](backend/CtrlBlock/AMUCtrlBuffer.md) |
| Matrix tasks, computation, and data storage | [TaskController](cute/TaskController.md), [Matrix Registers](cute/MatrixReg.md), and [Compute Data Path](cute/Compute.md) |
| Matrix data transfer | [MLSU](memblock/LSU/MLSU.md), [Loads and Stores](cute/MemoryLoader.md), and [HBL2](cache/l2cache/HBL2.md) |
| Control-core and matrix-task synchronization | [Integer Function Units](backend/FunctionUnit/IntFunctionUnit.md) and [System Integration](cute/Integration.md) |
