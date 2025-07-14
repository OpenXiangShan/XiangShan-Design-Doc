# Miss Queue: MissQueue

## Functional Description

Responsible for handling miss requests from load, store, and atomic operations,
containing 16 Miss Entries, each managing one request through a set of state
registers that control its processing flow.

* Miss load request: The MissQueue allocates an empty MissEntry for it and can
  merge or reject the request under certain conditions. After allocation,
  relevant information is recorded in the MissEntry. Requests entering the
  MissQueue send an Acquire request to L2. If it is a full-block overwrite, an
  AcquirePerm is sent (L2 will skip an SRAM read operation); otherwise, an
  AcquireBlock is sent. It waits for L2 to return permission (Grant) or data
  plus permission (GrantData) and sends a GrantAck back to L2 after receiving
  the first beat of Grant/GrantData. Before receiving the response from L2, it
  first receives an L2-upstream hint signal, indicating that the corresponding
  permission and data will arrive on the TileLink D channel in 2 cycles. Upon
  receiving the hint, the MissQueue initiates a refill request to the MainPipe.
  Subsequently, upon receiving Grant/GrantData, it forwards the refill data to
  the MainPipe and waits for the response. After completing the refill, the
  corresponding MissEntry is released.

* Store request for a miss: The process is essentially the same as for a load.
  After the final backfill is completed, the MainPipe sends a response back to
  the StoreBuffer, indicating that the store operation is finished.

* Atomic instruction for a miss: The process is essentially the same as for a
  load. After the final backfill is completed, the MainPipe sends a response
  back to the AtomicsUnit, indicating that the atomic instruction operation is
  finished.

### Feature 1: MissQueue enqueue processing

For newly enqueued requests, the MissQueue's overall operations can be
categorized into response and rejection, with responses further divided into
allocation and merging. The MissQueue supports a certain degree of request
merging to improve the efficiency of miss request processing.

* Allocation of an empty entry: If a new miss request does not meet the
  conditions for merging or rejection, a new MissEntry is allocated for the
  request.

* Request merging condition: When the block address of an allocated MissEntry
  (request A) matches that of a new miss request B, request B can be merged
  under the following two scenarios:
  * The Acquire request to L2 has not yet been acknowledged, and A is a load
    request while B is a load or store request. This means B can be merged with
    A before A successfully initiates a read request to L2, allowing them to
    send the Acquire request together.
  * The Acquire to L2 has been sent out, but Grant/GrantData has not yet been
    received, and A is a load or store request, while B is a load request. This
    means a new load request can be merged before refill, whereas a store
    request can only be merged before the Acquire handshake.

* Request rejection conditions: In the following cases, the new miss request
  will be rejected and will be reissued after a certain period:
  * The new miss request shares the same block address as a request in an
    existing MissEntry but does not meet the request merging conditions.
  * Miss Queue is full.

### Feature 2: MSHR data forwarding to LoadUnit

The MissQueue supports data forwarding. If the lsq replay signal is active (the
replay logic is detailed in the LoadQueueReplay section, selecting the oldest
suitable instruction), in stage1 of the LoadUnit, the specified mshrid and
address are forwarded. Upon receiving the forwarding information, the MissQueue
performs a match. If a match is found, the refill data is directly forwarded to
the LoadUnit in stage2, enabling faster access to previously requested data and
reducing load instruction wait times.

### Feature 3: MissQueue Prefetch Handling

For prefetch requests entering the MissQueue, the source of the prefetch request
is marked within the MissEntry, while the remaining operations are consistent
with a regular load instruction, sending an Acquire request to L2 and waiting
for Grant/GrantData to complete the refill.

### Feature 4: Backfill requests issued by the MissQueue

To improve the efficiency of data backfilling, it is beneficial to immediately
write to the DCache upon receiving the backfill data. Therefore, a backfill
request is sent to the MainPipe in advance to complete metadata reading and
replacement way selection. Upon receiving the hint signal from L2, the MissEntry
corresponding to the request initiates a backfill request to the MainPipe. At
this stage, the backfill request does not carry the specific data to be written
back. While the MainPipe performs metadata reading and replacement way
selection, it continues to wait for the backfill data to arrive. Upon receiving
Grant/GrantData, the backfill data block is forwarded directly to stage2 of the
MainPipe, matching the pre-sent backfill request to complete the write-back
operation. After the write-back operation is completed, the release signal from
the MainPipe is received, releasing the corresponding MissEntry and finalizing
the request.

## Overall Block Diagram

The overall architecture of the MissQueue is shown in [@fig:DCache-MissQueue].

![MissQueue Flowchart](./figure/DCache-MissQueue.svg){#fig:DCache-MissQueue}

## Interface timing

### Request Interface Timing Example

[@fig:DCache-MissQueue-Timing] illustrates the interface timing after a load
miss request enters the MissQueue. Upon arrival, the request allocates a
MissEntry, and in the next cycle, an Acquire request is sent to L2 to await hint
and data responses. After receiving the l2_hint signal, a backfill request is
initiated to the MainPipe in the following cycle. Upon receiving the first beat
of Grant data, a mem_finish response is returned to L2. After receiving the last
beat of Grant data, the backfill data is forwarded to stage2 of the MainPipe via
refill_info in the next cycle, completing the data write.

![MissQueue
Timing](./figure/DCache-MissQueue-Timing.svg){#fig:DCache-MissQueue-Timing}

## MissEntry Module
### Feature 1: Miss Entry allocation, merging, and rejection

  * Empty entry allocation: If a new miss request does not meet the merge or
    rejection conditions, a new Miss Entry is allocated for the request.
  * Request merging condition: When the block address of an allocated Miss Entry
    (request A) matches that of a new miss request B, request B can be merged
    under the following two scenarios:
    * The Acquire request to L2 has not yet been acknowledged, and A is a load
      request while B is a load or store request. This means B can be merged
      with A before A successfully initiates a read request to L2, allowing them
      to send the Acquire request together.
    * The Acquire to L2 has been sent out, but Grant/GrantData has not yet been
      received, and A is a load or store request, while B is a load request.
      This means a new load request can be merged before refill, whereas a store
      request can only be merged before the Acquire handshake.
  * Request rejection conditions: In the following cases, the new miss request
    will be rejected and will be reissued after a certain period:
    * The new miss request shares the same block address as a request in an
      existing Miss Entry but does not meet the request merging conditions.
    * Miss Queue is full.

### Feature 2: MissEntry State Design:

Miss Entry is controlled by a series of state registers that manage the
execution of operations and their sequence. The s_* register indicates whether
the request to be scheduled has been sent, and the w_* register indicates
whether the expected response has been received. These registers are initially
set to true.B. When allocating a Miss Entry for a request, the corresponding s_*
and w_* registers are set to false.B, indicating that the request has not been
sent and the expected handshake response has not been received.
[@tbl:MissEntry-state] and [@fig:DCache-MissEntry] illustrate the descriptions
of each register and the execution sequence:

Table: MissEntry State List {#tbl:MissEntry-state}

| Status          | Descrption                                                                                                                                   |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| s_acquire       | Send an AcquireBlock / AcquirePerm request to L2.                                                                                            |
| w_grantfirst    | Waiting to receive the first beat of GrantData; a high signal indicates reception.                                                           |
| w_grantlast     | Waiting to receive the last beat of GrantData; a high signal indicates reception.                                                            |
| s_grantack      | After receiving data from L2, send a response back to L2. A GrantAck can be returned upon receiving the first beat of the Grant.             |
| s_mainpipe_req  | Send a backfill request to the Main Pipe to backfill the data into the DCache.                                                               |
| w_mainpipe_resp | Indicates that after sending the atomic request to the Main Pipe for backfilling into the DCache, a response from the Main Pipe is received. |
| w_l2hint        | Indicates that the current miss request has received the l2_hint signal and can be awakened, initiating a proposal request to the MainPipe.  |
| w_refill_resp   | Indicates that the refill request for non-atomic operations is completed, and the MissEntry can be released.                                 |

![MissEntry Flowchart](./figure/DCache-MissEntry.svg){#fig:DCache-MissEntry}

### Feature 3: MissEntry Alias Handling

The L1 DCache supports handling cache alias issues in coordination with L2. When
sending an Acquire request to L2, the MissEntry includes the alias bits
(vaddr[13:12]) of the request address for L2 to store and determine if alias
issues need resolution. The detailed alias resolution process is described in
the ProbeQueue section.
