# Vector Store Merge Unit VSMergeBuffer

## Functional Description

A freelist-based queue that receives requests from the VSSplit module, allocates
an entry for each uop issued by the backend to store related uop information,
collects data returned from the Store pipeline, and writes back to the backend
and Store Queue after receiving all memory access requests split from the uop.

### Feature 1: Maintains split memory requests for uops.

In the second stage of the VSSplit module's pipeline, it requests an entry from
VSMergeBuffer. In the same cycle, VSMergeBuffer returns an entry index to
VSSplit and sets the corresponding entry's allocated flag to true. Upon
enqueueing, the counter for the corresponding entry is written with the number
of split memory requests for the current uop. Each uop is allocated one entry,
and each entry tracks the number of flows that need to be collected. Once all
are collected, it is marked as uopfinish and written back at the granularity of
the uop. Among the entries marked as uopfinish, one is selected to write back to
the backend, with lower-index entries prioritized when multiple are available.
The relevant flags are then cleared.

### Feature 2: Handles exceptions.

Based on the pipeline output information, correctly sets ExceptionVec, vstart,
and other relevant data when exceptions occur.

### Feature 3: Marks whether a uop needs to be flushed based on the flush signal from StoreMisalignBuffer.

For unaligned vector store accesses, there is a special case. When
StoreMisalignBuffer generates a flush signal for vector stores, it is sent to
VSMergeBuffer. VSMergeBuffer will mark the corresponding entry as needRSReplay,
ultimately notifying the Issue Queue to resend.


## Overall block diagram
No block diagram for a single module.

## Main ports

|                    | Direction | Description                                                                                           |
| -----------------: | --------- | ----------------------------------------------------------------------------------------------------- |
|       frompipeline | In        | Receives read data returns from the Store pipeline.                                                   |
|      fromSplit.req | In        | Receives entry requests from the VSSplit module.                                                      |
|     fromSplit.resp | Out       | Feedback to the VSSplit module, whether the allocation was successful and the allocated entry         |
|       uopWriteback | Out       | Write back the completed uop to the backend.                                                          |
|              toLsq | Out       | When a completed uop writes back to the backend, it updates the status of entries in the Store queue. |
|           redirect | In        | Redirect port                                                                                         |
|           feedback | Out       | Feedback to the backend Issue Queue on whether resending is required.                                 |
| fromMisalignBuffer | In        | Receives flush signals from StoreMisalignBuffer.                                                      |

## Interface timing

The interface timing is relatively simple, described only in text.

|                    | Description                                                                                                                   |
| -----------------: | ----------------------------------------------------------------------------------------------------------------------------- |
|       frompipeline | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|      fromSplit.req | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|     fromSplit.resp | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|       uopWriteback | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|              toLsq | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|           redirect | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|           feedback | Has Valid status. Data is valid when Valid is asserted.                                                                       |
| fromMisalignBuffer | No Valid signal; data is always considered valid, and responses are generated as soon as the corresponding signal is present. |

