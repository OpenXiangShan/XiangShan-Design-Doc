# Backend overview

The Backend is the back-end of the Xiangshan processor, which includes multiple
components such as instruction decode (Decode), rename (Rename), dispatch
(Dispatch), schedule (Schedule), issue (Issue), execute (Execute), writeback
(Writeback), and retire (Retire), as shown in [@fig:backend-overall].

![Overall Backend Architecture](figure/backend.svg){#fig:backend-overall}

## Basic technical specifications

- 6-wide decode, rename, and dispatch
  - 224-entry integer register file, 192-entry floating-point register file,
    128-entry vector register file
  - Move instruction elimination
  - Instruction fusion
- 160-entry ROB
  - Supports ROB compression (up to 6 uops per entry)
  - Up to 8 entries retired per cycle
  - Snapshot recovery
- Rename Buffer
  - 256-entry RAB
  - Instruction commit and register writeback
- Integer, floating-point, and vector computation
