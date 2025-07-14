# Scheduler

- Version: V2R2
- Status: OK
- Date: 2025/01/15
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

Descriptions of different types of Schedulers and their strategies.

The primary function of the Scheduler module is to encapsulate the IQ
(Instruction Queue) and connect the Dispatch module with the DataPath module.
There are four types: intScheduler, fpScheduler, vfScheduler, and memScheduler,
corresponding to integer, floating-point, vector, and memory operations
(including both scalar and vector memory accesses). Notably, within the
memScheduler, the ready signals of the sta and std IQs are ANDed before being
passed to the Dispatch module. The Dispatch module then responds with a valid
signal based on the IQ's ready status. If the IQ is not ready, the valid signal
for IQ enqueue from Dispatch will be deasserted.
