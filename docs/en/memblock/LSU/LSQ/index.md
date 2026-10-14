# Load Store Queue: LSQ

## Submodule List

| Submodule                                   | Description                                                             |
| ------------------------------------------- | ----------------------------------------------------------------------- |
| [VirtualLoadQueue](VirtualLoadQueue.md)     | TODO                                                                    |
| [LoadQueueRAR](LoadQueueRAR.md)             | TODO                                                                    |
| [LoadQueueRAW](LoadQueueRAW.md)             | TODO                                                                    |
| [LoadQueueReplay](LoadQueueReplay.md)       | DONE                                                                    |
| [LoadQueueUncache](LoadQueueUncache.md)     | TODO                                                                    |
| [LoadExceptionBuffer](LqExceptionBuffer.md) | TODO                                                                    |
| [StoreQueue](StoreQueue.md)                 | DONE                                                                    |
| [MlsQueue](MLSQ.md)                         | Address preparation and TLB-miss replay for XSAI matrix memory accesses |


## Functional Description

LSQ includes LoadQueue and StoreQueue and connects the pipelines through LsqWrapper. XSAI adds a separate MlsQueue that manages matrix memory instructions using `mlsqIdx` and reclaims queue entries after MLSU completes address preparation. CUTE tracks data transfers after instruction commit; see [Matrix load/store queue MLSQ](MLSQ.md).

  * LoadQueue

    * LoadQueueRAR: RAR violation check queue

    * LoadQueueRAW: RAW violation check queue

    * LoadQueueUncache: MMIO/Noncacheable load instruction processing queue

    * LoadQueueReplay: Load instruction scheduling replay queue

    * LoadExceptionBuffer: Exception handling queue for Load instructions

    * VirtualLoadQueue: Sequential maintenance queue for Load instructions

  * StoreQueue

#### Feature 1: Update LqPtr for Load instructions and SqPtr for Store instructions

* Due to timing considerations, the allocation of LqPtr and SqPtr is split into two parts, as shown in the figure

  ![LSQ allocation](./figure/LSQ-LsqEnqCtrl.svg){#fig:LSQ-LsqEnqCtrl width=60%}

  * Dispatch stage

    * Count the number of LoadFlow or StoreFlow for each instruction and calculate the LqPtr or SqPtr in a cumulative manner

  * LSQ enqueue phase

    * Accurately calculate LqPtr or SqPtr by accumulating based on the enqPtr maintained by LoadQueue or StoreQueue

  * LsqEnqCtrl update logic

    * If a pipeline flush occurs, update based on the number of flushed Load or Store instructions and the commit count

    * If no pipeline flush occurs but there is an allocation request, update based on the enqueue and commit counts

    * Otherwise, update based on the commit count

## Overall Block Diagram

![Overall LSQ Framework](./figure/LSQ.svg){#fig:LSQ width=40%}


\newpage

## Interface timing

### Timing example of Load and Store instruction enqueue interface

![Enqueue Update](./figure/LSQ-LsqEnqCtrl-Timing.svg){#fig:LSQ-LsqEnqCtrl-Timing width=90%}
