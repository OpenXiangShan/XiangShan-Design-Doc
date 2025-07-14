# Load Misalign Memory Access Unit: LoadMisalignBuffer

## Functional Description

The LoadMisalignBuffer stores 1 unaligned Load instruction that crosses a
16-byte boundary. The execution logic is a state machine with 7 states. When an
instruction is detected as unaligned and crossing a 16-byte boundary in the
LoadUnit, it requests entry into the LoadMisalignBuffer. The LoadMisalignBuffer
latches this Load and splits it into two separate Load memory operations (flows)
that re-enter the LoadUnit.

The LoadMisalignBuffer collects load memory accesses issued by itself. After
both load memory accesses complete execution, it performs data concatenation and
then sends another wake-up operation to the LoadUnit. This operation does not
actually enter the LoadUnit pipeline for execution but merely triggers the
wake-up signal and delays it by three cycles. After three cycles, the
LoadMisalignBuffer receives the writeback request from the LoadUnit again,
marked as originating from the wake-up operation. At this point, the
LoadMisalignBuffer dequeues and truly writes back to the backend, including
bypassing.

Scalar misaligned writeback to the backend must occur when LoadUnit 1 does not
enable scalar writeback. If this condition is not met, the LoadMisalignBuffer
writeback to the backend is blocked. Vector misaligned writeback to the
VLMergeBuffer must occur when LoadUnit 1 does not enable vector scalar
writeback. If this condition is not met, the LoadMisalignBuffer writeback to the
VLMergeBuffer is blocked.

### Feature 1: Supports splitting memory accesses for misaligned Loads that cross 16-byte boundaries.

Changes occur based on the already executed flow. The state machine transitions
to the s_req state after the first flow writes back, then sends the second flow.
If the first flow carries an exception when writing back to the
LoadMisalignBuffer, it directly writes back the exception information to the
backend without executing the second flow. Any writeback from either flow may
trigger a replay for any reason, and the LoadMisalignBuffer chooses to resend
that flow to the LoadUnit, regardless of the replay cause.

- lb instructions can never be unaligned.

- lh is split into two corresponding lb operations:

![alt text](./figure/LoadMisalign-lh.png)

- lw has different splitting methods based on address:

![alt text](./figure/LoadMisalign-lw.png)

- ld is split differently based on address:

![alt text](./figure/LoadMisalign-ld.png)

### Feature 2: Supports vector unaligned operations

The handling of vector unaligned flows is consistent with scalar unaligned
processing, with the difference being that vectors are written back to the
VLMergeBuffer, while scalars are directly written back to the backend.


### Feature 3: Does not support unaligned Loads outside of Memory space

Misaligned Loads in non-Memory spaces are not supported. When a Load in a
non-Memory space is misaligned, it generates a LoadAddrMisalign exception.


## Overall Block Diagram

![alt text](./figure/LoadMisalign-FSM.svg)

**Status Introduction**

|            Status | Description                                                               |
| ----------------: | ------------------------------------------------------------------------- |
|            s_idle | Waiting for misaligned Load uop to enter                                  |
|           s_split | Split misaligned Load                                                     |
|             s_req | Dispatch split unaligned Load operations to LoadUnit                      |
|            s_resp | LoadUnit writeback                                                        |
| s_comb_wakeup_rep | Merge the results of two unaligned Load operations and issue a wakeup uop |
|              s_wb | Write back to the backend or VLMergeBuffer                                |



## Main ports

|                  | Direction | Description                                                                          |
| ---------------: | --------- | ------------------------------------------------------------------------------------ |
|         redirect | In        | Redirect port                                                                        |
|              req | In        | Receive enqueue requests from LoadUnit                                               |
|              rob | In        | Internally suspended                                                                 |
|     splitLoadReq | Out       | Memory access requests for split flows sent to LoadUnit                              |
|    splitLoadResp | In        | Receives the memory response of the split flow written back by the LoadUnit          |
|        writeBack | out       | Scalar misaligned write-back to the backend.                                         |
|     vecWriteBack | Out       | Vector misaligned writeback to VLMergeBuffer                                         |
|     loadOutValid | In        | The Load Unit has a Load instruction about to write back to the backend              |
|  loadVecOutValid | In        | The Load Unit has Vector Load instructions that will write back to the VLMergeBuffer |
|  overwriteExpBuf | Out       | Dangling                                                                             |
| loadMisalignFull | Out       | LoadMisalignBuffer full flag                                                         |


## Interface timing

The interface timing is relatively simple, described only in text.

|                  | Description                                                                                                                   |
| ---------------: | ----------------------------------------------------------------------------------------------------------------------------- |
|         redirect | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|              req | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|              rob | Internally suspended                                                                                                          |
|     splitLoadReq | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|    splitLoadResp | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|        writeBack | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|     vecWriteBack | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|     loadOutValid | No Valid signal; data is always considered valid, and responses are generated as soon as the corresponding signal is present. |
|  loadVecOutValid | No Valid signal; data is always considered valid, and responses are generated as soon as the corresponding signal is present. |
|  overwriteExpBuf | Dangling                                                                                                                      |
| loadMisalignFull | No Valid signal; data is always considered valid, and responses are generated as soon as the corresponding signal is present. |
