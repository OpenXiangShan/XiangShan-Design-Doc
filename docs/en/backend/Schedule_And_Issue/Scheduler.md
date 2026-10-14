# Scheduler

- Version: V2R2A
- Status: OK
- Date: 2026/10/13
- commit: [XSAI e8fb1a14](https://github.com/OpenXiangShan/XSAI/tree/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f)

## Function

Scheduler wraps the IQs and connects Dispatch to DataPath. With the matrix extension enabled, XSAI has five scheduler classes: intScheduler, fpScheduler, vfScheduler, mfScheduler, and memScheduler. Like the integer, floating-point, and vector schedulers, mfScheduler reuses SchedulerArithImp and its existing enqueue, age selection, wake-up, cancellation, and dequeue-feedback mechanisms.

Table: Scheduler responsibilities

| Scheduler | Main instructions                                     |
| --------- | ----------------------------------------------------- |
| Int       | Integer, CSR, Fence, dimension writes, mrelease, mcfg |
| Fp        | Scalar floating-point                                 |
| Vf        | Vector computation and vector configuration           |
| Mf        | Dimension reads, MMA, mzero control requests          |
| Mem       | Scalar, vector, and matrix memory operations          |

MemScheduler ANDs the ready signals of the sta and std IQs before passing them to Dispatch. Dispatch returns valid according to the IQ ready state. It does not assert enqueue valid when the IQ is not ready.

## Matrix scheduling resources

The default MfScheduler has two IQs, each with 16 entries, 2 enqueue ports, and 12 complex entries. The first IQ contains MSET1, which reads mx dimensions and writes an integer destination. The second contains MEX0 and MEX1, which generate MMA and matrix arithmetic requests, respectively. MSET0 and MRELEASE are in IntScheduler; MLSU0 is in MemScheduler.

MfScheduler listens to integer and mx writeback according to its configuration. MMA waits for three dimension sources to become ready. Ordinary MLS in MemScheduler waits for the address, stride, and two dimension sources. mx writeback has current-cycle and delayed wake-up interfaces for the corresponding issue-queue stages. The raw Mcfg configuration is stored in the queue as instruction metadata.

CtrlBlock flushes, DataPath OG0/OG1 cancellation, and scalar load-dependency cancellation all connect to MfScheduler. LdExuCnt counts memory execution resources including MLSU. LdWakeupCnt and LdPfTrainCnt count scalar load and hybrid memory units that produce scalar load results.

The implementation is in [Scheduler.scala](https://github.com/OpenXiangShan/XSAI/blob/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f/src/main/scala/xiangshan/backend/issue/Scheduler.scala).
