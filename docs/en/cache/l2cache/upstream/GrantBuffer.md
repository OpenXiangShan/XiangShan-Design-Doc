# GrantBuffer

## Basic Functions

GrantBuffer receives response tasks and full-line data from MainPipe and selects the response path according to the response type:

- HintAck: when a response to the prefetcher is required, it enters the 10-entry pftRespQueue and returns in FIFO order.
- Grant, GrantData, AccessAck, AccessAckData, ReleaseAck, and CBOAck: enter grantQueue. The task queue and two data-beat queues enqueue together; each has 16 entries by default.
- Matrix AccessAckData: shares grantQueue with other upstream responses and returns full-line data through the separate MatrixDataOut interface when it reaches the queue head.
- Merged requests (`mergeA`): process both the original prefetch response and the merged Acquire response.

Grant / GrantData also allocates an inflightGrant entry to record the cache-line address whose response has been scheduled but whose channel E GrantAck has not yet arrived. The entry is cleared on the corresponding GrantAck. Get / Put AccessAckData / AccessAck does not wait for GrantAck.

### Feature 1: Pipeline Entry Backpressure

GrantBuffer provides entry-blocking signals to RequestArb based on tasks in the main pipeline that may produce responses, grantQueue occupancy, inflightGrant occupancy, and pftRespQueue occupancy. Tasks already in the main pipeline cannot wait for queue space at the output, so resources must be reserved at the entry.

Let `N = mshrsAll` denote the number of response-task queue and inflightGrant entries; the default N is 16. Capacity checks use the following resource counts:

Table: GrantBuffer resource counts

| Resource                    | Current occupancy           | Pipeline tasks counted    | Regular request blocking threshold | MSHR task blocking threshold |
| --------------------------- | --------------------------- | ------------------------- | ---------------------------------- | ---------------------------- |
| Response-task queue         | grantQueue entries          | Tasks from channels A / C | Total ≥ N                          | Total ≥ N − 1                |
| Resources awaiting GrantAck | Valid inflightGrant entries | Tasks from channel A      | Total ≥ N                          | Total ≥ N − 1                |
| Prefetch response queue     | pftRespQueue entries        | Tasks from channel A      | Total ≥ 10                         | Total ≥ 9                    |

The pipeline count includes valid tasks in s2–s5. The MSHR threshold reserves an additional entry for s1. Checks of resources awaiting GrantAck count all channel A tasks in the pipeline to reserve inflightGrant entries that may be allocated.

Channel A is blocked when any resource is insufficient; channel C is blocked when response-task queue resources are insufficient; MSHR tasks are blocked when any corresponding resource is insufficient. Channel B must wait for GrantAck whenever an inflightGrant entry has the same address, preventing a Probe from overtaking an unfinished Grant.

Matrix responses occupy the response queue and return data through a separate interface. If the matrix interface remains unready, queue occupancy backpressures later requests through the entry checks above.

### Feature 2: Regular Channel D Data Width

Grant, AccessAck, ReleaseAck, and CBOAck carry no data and send only one channel D beat. Regular GrantData / AccessAckData contains two 32 B beats: the first is sent when grantQueue dequeues, and the second is buffered in grantBuf and sent with priority afterward. The next response can be taken only after the buffered beat completes its handshake.

When critical-word-first delivery is required, the task's `isKeyword` flag selects the beat to send first; the other beat is stored in grantBuf. The task queue and the two data queues always dequeue in the same order.

### Feature 3: Matrix Data Responses

When the head task satisfies `matrixTask && opcode == AccessAckData`, GrantBuffer returns a full cache line through MatrixDataOut:

Table: MatrixDataOut fields

| Field    | Width    | Content                                                                     |
| -------- | -------- | --------------------------------------------------------------------------- |
| sourceId | 64 bits  | The task's ameIndex, used by the matrix side to match the request           |
| channel  | 3 bits   | Matrix data channel number from the low three bits of the task's ameChannel |
| data     | 512 bits | DSBlock formed from two 32 B beats in the original order within the line    |

The matrix interface uses a Decoupled handshake. When ready is 0, the response remains at the queue head. On a successful handshake, the task queue and both data queues dequeue together. If grantBuf still holds the second beat of a regular channel D response, that beat takes priority and the matrix response waits for it to complete.

AccessAck for a matrix Put still returns through regular channel D. source retains the TileLink transaction source, and AmeIndex in user carries the matrix index.

### Feature 4: Hint and Response Pairing

CustomL1Hint in MainPipe records early-wakeup information in response order. Hints for regular channel D responses are sent through l1Hint to wake L1D Loads waiting for refill.

Matrix AccessAckData sets `isMatrixData` in the Hint queue and sends no regular l1Hint. Slice ANDs GrantBuffer's matrix-data valid with the condition that the Hint queue head is a matrix response; it also returns the matrix interface ready ANDed with that condition to GrantBuffer. A MatrixDataOut handshake pops the corresponding Hint entry at the same time.

A matrix response can be sent when its task is at the head of grantQueue, grantBuf has no pending regular channel D beat, and the matching matrix entry is at the head of the Hint queue. One matrix interface handshake pops the response task, both data queue entries, and the matching Hint entry together.

## Overall Block Diagram

![GrantBuffer](./figure/GrantBuf.svg)

See the overall block diagram in [Matrix memory access path HBL2](../HBL2.md) for matrix response and Hint pairing.
