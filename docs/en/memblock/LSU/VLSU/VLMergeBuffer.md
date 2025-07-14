# Vector Load Merge Unit VLMergeBuffer

## Functional Description

A freelist-based queue that receives requests from the VLSplit module, allocates
an entry for each uop dispatched to the backend to store uop-related
information, collects data returned from the Load pipeline, and writes back to
the backend and Load Queue after all memory access requests split from the uop
are received.

### Feature 1: Maintains split memory requests for uops.

In the second stage of the VLSplit module's pipeline, initiate an entry request
to the VLMergeBuffer. In the same cycle, the VLMergeBuffer returns an entry
index to the VLSplit, with the corresponding entry's allocated flag set to true.
During enqueue, the counter for the corresponding entry is written with the
number of memory access requests split by the current uop. Each uop is allocated
one entry, with each entry maintaining the number of flows that need to be
collected. Once all are collected, it is marked as uopfinish and written back at
the uop granularity. Among the entries marked as uopfinish, select one to write
back to the backend. When multiple entries are ready for writeback, the one with
the smaller index is written back first, and the corresponding flags are
cleared.

### Feature 2: Data Merging

Based on the Load pipeline output information, merge data at the uop
granularity. Merging considers factors such as exceptions, element positions,
and masks.

### Feature 3: Exception Handling

Based on the pipeline output information, correctly sets ExceptionVec, vstart,
and other relevant data when exceptions occur.

### Feature 4: Threshold Backpressure {#sec:VLM-THRESHOLD}

To prevent deadlock, when the number of free entries in the VLMergeBuffer is
less than or equal to 6, a threshold reaction signal is generated and sent to
the VLSplit, backpressuring the VLSplit Pipe. Refer to [@sec:VLS-THRESHOLD]
[Backpressure based on the VLMergeBuffer's Threshold signal](VLSplit.md).

## Overall Block Diagram

Single module without a block diagram

## Main ports

|                | Direction | Description                                                                                          |
| -------------: | --------- | ---------------------------------------------------------------------------------------------------- |
|   frompipeline | In        | Receive read data returns from the Load pipeline                                                     |
|  fromSplit.req | In        | Receives entry requests from the VLSplit module                                                      |
| fromSplit.resp | Out       | Feedback to the VLSplit module, indicating whether allocation was successful and the allocated entry |
|   uopWriteback | Out       | Write back the completed uop to the backend.                                                         |
|          toLsq | Out       | Updates the entry status in the Load queue when completed uops are written back to the backend       |
|       redirect | In        | Redirect port                                                                                        |
|       feedback | Out       | Feedback to the backend Issue Queue, currently the backend does not perform any processing           |
|        toSplit | Out       | Feedback to the VLSplit module indicating the VLMergeBuffer is approaching its threshold             |

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

