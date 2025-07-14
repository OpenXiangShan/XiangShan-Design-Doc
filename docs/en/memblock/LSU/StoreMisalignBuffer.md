# Store Misalign Memory Access Unit StoreMisalignBuffer

## Functional Description

The StoreMisalignBuffer stores 1 misaligned Store instruction that crosses a
16-byte boundary. The execution logic is a state machine with 7 states. When an
instruction in the StoreUnit is detected as misaligned and crossing a 16-byte
boundary, it requests entry into the StoreMisalignBuffer. The
StoreMisalignBuffer latches this Store and splits it into two Store memory
flows, which are then re-entered into the StoreUnit.

StoreMisalignBuffer collects Store accesses initiated by itself. After both
Store accesses complete, if it is a non-page-crossing misalignment, it writes
back. Scalar misaligned writeback to the backend must occur when StoreUnit 1
does not enable scalar writeback. If not satisfied, StoreMisalignBuffer
writeback to the backend is blocked. Vector misaligned writeback to
VSMergeBuffer must occur when StoreUnit 1 does not enable vector scalar
writeback. If not satisfied, StoreMisalignBuffer writeback to VSMergeBuffer is
blocked.

For Stores that cross 4K pages, we require that the instruction can only execute
when it reaches the head of the Rob. If an older Store enters the
StoreMisalignBuffer during this time, it will evict the current cross-4K-page
Store and set the needFlushPipe flag to true. When a Store finally writes back,
we generate a redirect.

For vectors, when a vector Store flow is evicted, it notifies VSMergeBuffer to
mark the corresponding entry as needRsReplay, causing the uop to be resent.

### Feature 1: Supports split memory access for unaligned Stores crossing 16Byte boundaries

Different transitions occur based on the executed flow. The state machine will
enter the s_req state after the first flow is written back, then send the second
flow. If the first flow carries an exception written back to
StoreMisalignBuffer, it directly sends the exception information to the backend
without executing the second flow. Any flow writeback may trigger a replay for
any reason, and StoreMisalignBuffer will resend that flow to StoreUnit
regardless of the replay cause.

- The sb instruction can never cause misalignment.

- An sh operation is split into two corresponding sb operations:

![alt text](./figure/StoreMisalign-sh.png)

- sw varies based on address splitting methods:

![alt text](./figure/StoreMisalign-sw.png)

- sd varies based on address splitting methods:

![alt text](./figure/StoreMisalign-sd.png)

### Feature 2: Supports vector unaligned operations

The vector misaligned flow is handled similarly to the scalar misaligned flow,
with the difference being that the vector writes back to the VSMergeBuffer,
while the scalar writes back directly to the backend.


### Feature 3: Does not support unaligned Store to non-Memory space

Misaligned Stores in non-Memory spaces are not supported. A StoreAddrMisalign
exception is raised if a Store in a non-Memory space is misaligned.

### Feature 4: Supports Cross-Page Store

Since Store operations need to write to the Sbuffer, in cases of cross-page
access, two physical addresses are generated. The physical address of the lower
page can reside in the StoreQueue, while the physical address of the higher page
requires separate storage. We opt to store it in the StoreMisalignBuffer.
Consequently, for cross-page Store operations, we must wait until the
instruction is committed from the Store Queue to the Sbuffer before clearing the
corresponding entry in the StoreMisalignBuffer. Therefore, we provide the
StoreQueue with the metadata and address currently latched in the
StoreMisalignBuffer for write-back purposes. Specifically, we determine whether
to latch and retain the current Store metadata based on signals received from
the rob and StoreQueue.

## Overall Block Diagram

![alt text](./figure/StoreMisalign-FSM.svg)


**Status Introduction**

|  Status | Description                                                                                 |
| ------: | ------------------------------------------------------------------------------------------- |
|  s_idle | Waiting for unaligned Store uop to enter                                                    |
| s_split | Split unaligned Store                                                                       |
|   s_req | Dispatch the split misaligned Store operations to the StoreUnit.                            |
|  s_resp | StoreUnit Writeback                                                                         |
|    s_wb | Write back to backend or VSMergeBuffer                                                      |
| s_block | Block the instruction from dequeuing until the Store Queue writes the entry to the Sbuffer. |

## Main ports

|                       | Direction | Description                                                                          |
| --------------------: | --------- | ------------------------------------------------------------------------------------ |
|              redirect | In        | Redirect port                                                                        |
|                   req | In        | Receives enqueue requests from StoreUnit                                             |
|                   rob | In        | Receive relevant metadata information from Rob                                       |
|         splitStoreReq | Out       | Memory access requests of split flows sent to StoreUnit                              |
|        splitStoreResp | In        | Receives the memory response of the split flows written back by the StoreUnit.       |
|             writeBack | out       | Scalar misaligned write-back to the backend.                                         |
|          vecWriteBack | Out       | Vector misaligned writeback to VSMergeBuffer                                         |
|         StoreOutValid | In        | The Store Unit has a Store instruction that is about to write back to the backend.   |
|      StoreVecOutValid | In        | The Store Unit has Vector Store instructions pending write-back to the VSMergeBuffer |
|       overwriteExpBuf | Out       | Dangling                                                                             |
|             sqControl | In/Out    | Interface for interaction with Store Queue                                           |
| toVecStoreMergeBuffer | Out       | Send flush-related information to VSMergeBuffer                                      |


## Interface timing

The interface timing is relatively simple, described only in text.

|                       | Description                                                                                                                   |
| --------------------: | ----------------------------------------------------------------------------------------------------------------------------- |
|              redirect | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|                   req | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|                   rob | No Valid signal; data is always considered valid, and responses are generated as soon as the corresponding signal is present. |
|         splitStoreReq | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|        splitStoreResp | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|             writeBack | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|          vecWriteBack | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|         StoreOutValid | No Valid signal; data is always considered valid, and responses are generated as soon as the corresponding signal is present. |
|      StoreVecOutValid | No Valid signal; data is always considered valid, and responses are generated as soon as the corresponding signal is present. |
|       overwriteExpBuf | Dangling                                                                                                                      |
|             sqControl | No Valid signal; data is always considered valid, and responses are generated as soon as the corresponding signal is present. |
| toVecStoreMergeBuffer | No Valid signal; data is always considered valid, and responses are generated as soon as the corresponding signal is present. |
