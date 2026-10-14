# Task Control: TaskController

## Design Specifications

- The command input uses `AmuCtrlIO` with a `ready/valid` handshake.
- The decoded FIFO and circular issue window each contain 8 entries by default; the window can be statically configured with 4, 8, or 16 entries.
- At most one ready task issues per cycle, with the oldest ready task taking priority.
- Execution resource busy state and ownership are tracked separately for AML, BML, CML load, Compute, and CML store.
- Completion dependencies, A-read-completion dependencies, and B-read-completion dependencies maintain matrix register ordering.
- Tasks may issue and complete out of order; at most one task retires from the window head per cycle.

## Overall Design

![TaskController command buffering, issue window, and completion paths](./figure/cute-task-window.svg){#fig:cute-task-window}

The decoded FIFO in [@fig:cute-task-window] holds commands and their static read/write sets; the issue window holds task state and dependencies on older tasks. Once a task issues, the corresponding FU tracker records its window slot in `ownerSlot`. Module completion updates the original slot through its owner; retirement checks `winHead` and releases slots in window-entry order.

Window retirement releases CUTE's task record. The control core separately tracks matrix instruction execution and ROB commit state and updates synchronization registers through Release completion pulses; each side advances through its own control logic.

## Command Input and Decoding

`AmuCtrlIO` contains a 2-bit `op` and 150-bit `data`. `op` distinguishes MMA, MLS, Release, and Arith, and `data` is interpreted as a different Bundle for each operation class. With Difftest enabled, it also carries `pc` and `coreid`. Input `fire` writes a command to the decoded FIFO; upstream backpressure comes from available FIFO space.

MMA stores `ms1`, `ms2`, `md`, `mtilem`, `mtilen`, `mtilek`, and format encodings. MLS stores the register number, load/store selection, A/B/C class, transpose flag, 48-bit base address, 48-bit stride, row and column counts, and element width. Address and stride are in bytes; row and column counts are in elements.

Decoding generates a static set of up to three read registers and one write register for each command. MMA reads two AB registers and the destination C, and writes the destination C; load writes its target register; store reads its target register; mzero writes its target register. Arith currently recognizes only mzero operations; other Arith commands become `NopLike` with empty read/write sets.

Table: Task classes and execution resources {#tbl:cute-task-fu}

| Task               | Function                                                        | Resources required for issue              |
| ------------------ | --------------------------------------------------------------- | ----------------------------------------- |
| `LoadA`            | Ordinary or transpose A load                                    | AML idle and ready                        |
| `LoadB`, ordinary  | Ordinary B load                                                 | BML idle and ready                        |
| `LoadB`, transpose | B load through the shared transpose engine                      | AML idle and ready                        |
| `LoadC`            | Load initial C values                                           | CML load idle and ready                   |
| `Compute`          | Matrix multiply-accumulate                                      | Compute idle; ADC, BDC, and CDC all ready |
| `Store`            | Write results through CML                                       | CML store idle and ready                  |
| `ZeroAcc`          | Zero a C register                                               | CML load idle and ready                   |
| `ZeroTr`           | Zero an AB register                                             | AML idle and ready                        |
| `Release`          | Update completion state for a selected synchronization register | Executes within the scheduler             |
| `NopLike`          | No matrix data operation                                        | Executes within the scheduler             |

The load class bits `isA`, `isB`, and `isacc` must be one-hot. CUTE takes the low two bits of the register number for both AB and C indices; command semantics determine the class. Store issue always configures CML, which reads the selected C register; dependency detection still builds the read set according to the command's register class. See [Store Boundaries](MemoryLoader.md#sec:cute-store-boundary) for store class requirements.

## Issue Window

The window maintains circular age order through `winHead`, `winTail`, and `winCount`. Each slot contains the following main state.

Table: Issue-window slot state {#tbl:cute-window-state}

| Field                            | Meaning                                                                                              |
| -------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `valid`                          | The slot holds a live task                                                                           |
| `issued`                         | The task has been sent to an execution module or executed within the scheduler                       |
| `completed`                      | The task's data operation is complete                                                                |
| `readADone`, `readBDone`         | Compute has supplied all A/B operands to the array and no longer reads the corresponding AB register |
| `waitCompleteMask`               | Older window slots whose completion is required                                                      |
| `waitReadAMask`, `waitReadBMask` | Older Compute slots whose A/B read completion is required                                            |
| `opKind`, `entry`                | Task class, original command, and static read/write sets                                             |
| `seqId`                          | A 16-bit task sequence number used to correlate debug events                                         |
| `fifoIdx`                        | A debug index maintained separately for each task class                                              |

The decoded FIFO head can enter the window when it is not full. If the window is full but its head retires in the same cycle, the newly released slot can be reused. Dependency construction excludes the task retiring in that cycle so that a new task is not associated with a released slot number.

## Dependency Construction and Resolution

When a new task enters the window, its read/write sets are compared only with strictly older live slots. Dependencies are established at entry and subsequently tested against older task state bits; retirement broadcasts the retiring slot number and clears its bit from all wait masks. The window does not rename matrix registers.

Table: Matrix register dependency rules {#tbl:cute-task-dependencies}

| Relationship between the older and new tasks                                  | Wait condition                        |
| ----------------------------------------------------------------------------- | ------------------------------------- |
| The older task writes AB; the new task reads or writes the same AB            | Older task `completed`                |
| The older task reads AB as a Compute A input; the new task writes the same AB | Older task `readADone`                |
| The older task reads AB as a Compute B input; the new task writes the same AB | Older task `readBDone`                |
| The older task otherwise reads AB; the new task writes the same AB            | Older task `completed`                |
| RAW, WAW, or WAR on C                                                         | Older task `completed`                |
| The new task is Release                                                       | `completed` for all older Store tasks |

Compute both reads and writes C, so subsequent tasks reading or overwriting the same C must wait for Compute to complete. A and B read completion are tracked independently: a subsequent load overwriting only the AB register holding A needs only the corresponding A read completion. The dependency graph tracks A and B read completion separately; actual computation still requires the two inputs to select different AB registers, as described in [Matrix Registers](MatrixReg.md).

For example, consider tasks entering the window in the order `LoadA tr0`, `LoadB tr1`, `Compute tr0,tr1,acc0`, `LoadA tr0`, `Store acc0`. Compute waits for the first two loads; the second `LoadA tr0` waits for Compute's `readADone` and may start before C result writeback completes; Store waits for overall Compute completion. Once the array has accepted all A operands, the next load can overwrite tr0 while the PEs continue processing in-flight data and writing C.

## Oldest-Ready Issue

Each unissued slot calculates dependency readiness and resource readiness separately. Dependency readiness requires no unsatisfied bits in any of the three wait masks; resource readiness depends on the module busy and ready conditions in [@tbl:cute-task-fu].

The ready vector is rotated into age order relative to `winHead`; a priority encoder selects the oldest ready entry and maps it back to its actual slot number. An older task waiting for data therefore does not block a younger independent task, although total issue width remains one. Issue selection uses the window state at the start of the cycle: newly entered tasks and tasks whose dependencies are resolved by a completion signal received that cycle have no same-cycle issue bypass.

When issuing Compute, TaskController configures the shape and register numbers for ADC, BDC, and CDC together and configures MTE's compute type. M and N remain element counts; K is converted to bytes and divided by `ReduceWidthByte` to obtain the compute reduction-block count. The loader's external beat count is rounded up in units of 64 B and differs from the compute reduction-block count.

## Completion and Retirement Timing

The five FU trackers each hold `busy` and `ownerSlot`. Issue claims the corresponding tracker; the completion handshake is `MicroTaskEndValid && MicroTaskEndReady`, with EndReady asserted only when a valid owner exists. A completion signal without an owner is an interface error.

AML/BML/CML load/CML store completion sets `completed` in the owner slot and releases the tracker. For Compute, ADC and BDC completion set `readADone` and `readBDone`, respectively; CDC completes after all result writebacks, sets `completed`, and releases the Compute tracker. CDC completion must not precede A and B read completion.

The window head can retire when it is complete. If it completes through a FU handshake in the current cycle, retirement logic may also use that completion directly. Only one entry retires per cycle; completed younger tasks wait for preceding tasks to release in order. Retirement and acceptance of a new task can occur together to maintain window capacity.

## Release Synchronization Semantics {#sec:cute-release}

When Release enters the window, it establishes completion dependencies on all older Store tasks. When Release issues, it generates a Valid pulse on `mrelease`, sets the specified `msyncRd` bit to true, and marks itself complete. The interface has no ready signal; the receiver updates synchronization state from the pulse.

Once all older Store tasks have completed, Release satisfies its dependency readiness condition and participates in oldest-ready issue selection; unrelated older Load or Compute tasks may continue executing. If the window head still holds an incomplete task, Release remains in the window after generating its pulse until it retires in order. If an older Store depends on a preceding Compute, that dependency chain also delays Release.

Release's completion condition includes CML write acknowledgements for preceding Store tasks. The control core's `mrelease` completion return causes Fence to update the corresponding synchronization counter; `macquire` waits for the target counter to reach the specified value. To drain the scalar store buffer, `mfence` separately requests an SBuffer flush and waits for `sbIsEmpty`; its completion condition is separate from CUTE Release. See [Matrix Synchronization](../backend/FunctionUnit/IntFunctionUnit.md#sec:matrix-sync).

## Implementation References

This section corresponds to [TaskController](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/TaskController.scala), [AmuCtrlIO and task interfaces](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/Bundles.scala), and [the YGJKControl completion interface](https://github.com/OpenXiangShan/CUTE/blob/d27b93d61c359478f4202f8f42cbfe82c830912a/src/main/scala/config_ygjk.scala).
