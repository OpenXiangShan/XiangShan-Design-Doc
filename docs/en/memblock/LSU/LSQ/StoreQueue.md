# Store Queue (StoreQueue)

## Functional Description

StoreQueue is a queue that holds all store instructions, with the following
functionalities:

* Tracking the execution status of store instructions

* Stores the store data and tracks its status (whether it has arrived).

* Provides a query interface for loads, allowing loads to forward stores with
  the same address.

* Responsible for executing MMIO stores and NonCacheable stores

* Write stores committed by the ROB into the sbuffer

* Maintain address and data ready pointers for LoadQueueRAW release and
  LoadQueueReplay wake-up

Stores have been optimized with separate address and data dispatch, meaning the
StoreUnit is the pipeline for dispatching store addresses, while the StdExeUnit
is the pipeline for dispatching store data. These are two different reservation
stations. Store data can be dispatched to the StdExeUnit once ready, and store
addresses can be dispatched to the StoreUnit once ready.

* Each entry in the StoreQueue stores the basic information of a store
  instruction:

Table: Basic information stored in StoreQueue

| Field       | Description                      |
| ----------- | -------------------------------- |
| uop         | store instruction uop            |
| dataModule  | 128-bit data and data valid mask |
| paddrModule | Physical address                 |
| vaddrModule | Virtual Address                  |


* Each entry in the StoreQueue has several status bits indicating the state of
  the store.

Table: State information stored in the StoreQueue

| Field         | Description                                                                                                                                 |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| allocated     | Set the allocated state for this entry to begin tracking the lifecycle of this store.                                                       |
|               | When this store instruction is committed to the Sbuffer, the allocated status is cleared.                                                   |
| addrvalid     | Indicates whether the physical address has been obtained through address translation, used for CAM comparison during load forward checking. |
| datavalid     | Indicates whether the store data has been issued and is available.                                                                          |
| committed     | Whether the store has been committed by the ROB.                                                                                            |
| unaligned     | Unaligned Store                                                                                                                             |
| cross16Byte   | Crossing a 16-byte boundary                                                                                                                 |
| pending       | Whether this store is in MMIO space, primarily used to control the state machine of MMIO                                                    |
| nc            | NonCacheable store                                                                                                                          |
| mmio          | mmio store                                                                                                                                  |
| atomic        | Atomic store                                                                                                                                |
| memBackTypeMM | Whether the PMA is of the main memory type                                                                                                  |
| prefetch      | Whether prefetching is required when submitting to Sbuffer                                                                                  |
| isVec         | Vector store                                                                                                                                |
| vecLastFlow   | The last uop of the vector store flow                                                                                                       |
| vecMbCommit   | Vector stores committed from the merge buffer to the ROB.                                                                                   |
| hasException  | Store instruction has an exception                                                                                                          |
| waitStoreS2   | Wait for the mmio and exception results from Store Unit s2.                                                                                 |

### Feature 1: Data forwarding

* A load needs to query the StoreQueue to find the data of the most recent
  dependent store with the same address that precedes it.

    * Compare the query bus (io.forwrd.sqIdx) with StoreQueue's enqPtr pointer
      to identify all StoreQueue entries older than the load instruction.
      Divided into two cases based on whether flags match or differ.

      * If the same flag is set, the range of older stores is [tail, sqIdx - 1],
        as shown in Figure \ref{fig:LSQ-StoreQueue-Forward-Mask} a). Otherwise,
        the range of older stores is [tail, VirtualLoadQueueSize - 1] and [0,
        sqIdx], as shown in Figure \ref{fig:LSQ-StoreQueue-Forward-Mask} b).

      ![StoreQueue forwarding range
      generation](./figure/LSQ-StoreQueue-Forward-Mask.svg){#fig:LSQ-StoreQueue-Forward-Mask
      width=90%}


    * The query bus uses both virtual and physical addresses for lookup. If a
      physical address match is found but the virtual address does not match, or
      vice versa, the corresponding load instruction is marked as replayInst and
      will be re-executed once the load reaches the ROB head.

    * If only one matching entry is found and its data is ready, forward it
      directly.

    * If only one matching entry is found and the data is not ready, the
      reservation station must be responsible for resending

    * If multiple matches are found, forward the oldest store.

    * The StoreQueue operates in 1-byte units, employing a tree-based data
      selection logic, as shown in Figure \ref{fig:LSQ-StoreQueue-Forward}.

  \newpage

  ![StoreQueue Forward Data
  Selection](./figure/LSQ-StoreQueue-Forward.svg){#fig:LSQ-StoreQueue-Forward
  width=80%}


* Stores participating in data forwarding must satisfy:

    * allocated: This store is still within the store queue and has not been
      written to sbuffer yet.

    * datavalid: The data for this store is ready.

    * addrvalid: This store has completed virtual-to-physical address
      translation and obtained the physical address.

    * If the memory dependency predictor is enabled, the SSID (Store-Set-ID)
      marks historical information of previously failed load prediction
      executions. If the current load hits an SSID in the history, it waits for
      all older stores to complete; if there is no hit, it only waits for older
      stores with the same physical address to complete.

### Feature 2: Misaligned store instructions

The StoreQueue supports handling unaligned store instructions. Each unaligned
store instruction occupies one entry and is written after aligning the address
and data in the dataBuffer.

### Feature 3: Vector Store Instructions

As shown in Figure \ref{fig:LSQ-StoreQueue-Vector}, StoreQueue pre-allocates
entries for vector store instructions. StoreQueue controls the commit of vector
stores via vecMbCommit:

  * For each store, retrieve the corresponding information from the feedback
    vector fbk.

    Determines if the store meets the commit conditions (valid and marked as
    commit or flush) and checks if the store matches the instruction
    corresponding to uop(i) (via robIdx and uopIdx). The store is marked as
    committed only when all conditions are met. Checks if any instruction within
    VecStorePipelineWidth meets the conditions; if so, the vector store is
    considered committed; otherwise, it is not.

  * Special case handling (Store crossing page boundaries):

    Under special circumstances (when a store crosses page boundaries and
    storeMisalignBuffer contains the same uop), if the store meets the condition
    io.maControl.toStoreQueue.withSameUop, vecMbCommit is forcibly set to true,
    indicating that the store is committed regardless of other factors.

![Vector store
instruction](./figure/LSQ-StoreQueue-Vector.svg){#fig:LSQ-StoreQueue-Vector
width=25%}


### Feature 4: CMO

StoreQueue supports CMO instructions, which share the MMIO state machine
control:

  * s_idle: Idle state, transitions to s_req upon receiving a CMO store request.

  * s_req: Refresh the Sbuffer, wait for the line flush to complete, then send a
    CMO operation request via CMOReq, and enter the s_resp state

  * s_resp: Upon receiving the response from CMOResp, transitions to s_wb state.

  * s_wb: Waits for the ROB to commit the CMO instruction, then transitions to
    the s_idle state.

### Feature 5: CBO

StoreQueue supports CBO.zero instruction:

  * The data portion of the CBO.zero instruction writes 0 to the dataModule.

  * When CBO.zero is written to Sbuffer: flush the Sbuffer, wait for the flush
    to complete, and then write back via cboZeroStout.

### Feature 6: MMIO and NonCacheable Store Instructions

* Execution of MMIO Store instructions

  * Stores to MMIO space can only be executed when they reach the head of the
    ROB, but they differ slightly from loads. When a store reaches the head of
    the ROB, it may not necessarily be at the tail of the store queue. Some
    stores may have already been committed but are still in the store queue and
    have not been written to the sbuffer. These stores must first be written to
    the sbuffer before the MMIO store can proceed.

  * Use a state machine to control the execution of MMIO stores.

    * s_idle: Idle state, transitions to s_req upon receiving an MMIO store
      request;

    * s_req: Send a request to the MMIO channel. Once the request is accepted by
      the MMIO channel, it transitions to the s_resp state.

    * s_resp: The MMIO channel returns a response. After receiving it, record
      whether an exception is generated and transition to the s_wb state.

    * s_wb: Convert the result into internal signals and write back to ROB. Upon
      success, if there is an exception, transition to s_idle; otherwise,
      proceed to the s_wait state.

    * s_wait: Wait for the ROB to commit this store instruction. After commit,
      return to the s_idle state.

* NonCacheable Store instruction execution

  * For store instructions in NonCacheable space, they must wait until after
    commit before being sent out in order from the StoreQueue

  * Use a state machine to control NonCacheable store execution.

    * nc_idle: Idle state, transitions to nc_req upon receiving a NonCacheable
      store request.

    * nc_req: Sends a request to the NonCacheable channel. After the request is
      accepted by the NonCacheable channel, if the uncacheOutstanding feature is
      enabled, it transitions to nc_idle; otherwise, it enters the nc_resp
      state.

    * nc_resp: Accepts the response from the NonCacheable channel and
      transitions to the nc_idle state

### Feature 7: Store instruction commit and write to SBuffer

The StoreQueue adopts an early commit approach.
* Early Commit Rules:

  * Check the conditions for entering the commit phase.

    * Instruction valid.

    * The ROB head pointer of the instruction does not exceed the pending commit
      pointer.

    * Instruction does not need to be canceled.

    * The instruction does not wait for the Store operation to complete, or it
      is a vector instruction

  * If it is the first instruction in the CommitGroup, then

    * Check MMIO status: No MMIO operation or an MMIO operation exists and the
      MMIO store has been committed.

    * For vector instructions, otherwise the vecMbCommit condition must be
      satisfied.

  * If it is not the first instruction in the CommitGroup, then:

    * The commit state depends on the commit state of the previous instruction.

    * For vector instructions, the vecMbCommit condition must be satisfied.

After submission, stores can be written sequentially to the sbuffer. These
stores are first written to the dataBuffer, which is a two-entry buffer
(channels 0 and 1) used to handle read latency from the larger store queue. Only
channel 0 can handle unaligned instructions. To simplify the design, even if
exceptions occur on both ports, only one unaligned dequeue is allowed.

* Write valid signal generation:

  * When a 0-channel instruction is misaligned and crosses a 16-byte boundary:

    * Instructions in Channel 0 have been allocated and committed

    * Channels 0 and 1 of the dataBuffer can simultaneously accept instructions.

    * Channel 0 instruction is not a vector instruction and the address and data
      are valid; or it is a vector instruction with vsMergeBuffer and committed.

    * Does not cross a 4K page table; or crosses a 4K page table but can be
      dequeued, and 1) if it is channel 0: allows writing data with exceptions;
      2) if it is channel 1: does not allow writing data with exceptions.

    * The previous instruction was not a NonCacheable instruction. If it is the
      first instruction, it cannot itself be a Noncacheable instruction.

  * Otherwise, the following conditions must be met

    * Instructions have been allocated and committed.

    * Not a vector and the address and data are valid, or it is a vector and
      vsMergeBuffer is submitted.

    * Previous instructions were neither NonCacheable nor MMIO instructions. If
      it is the first instruction, it cannot itself be a Noncacheable or MMIO
      instruction.

    * For unaligned stores, they must not cross a 16-byte boundary, and the
      address and data must be valid or an exception will occur.

* Address and data generation:

  * Address is split into high and low parts:

    * Low-order address: 8-byte aligned address

    * High address: Low address plus an 8-byte offset

  * Data is split into high and low parts:

    * Crossing 16-byte boundary data: The original data is left-shifted by the
      number of bytes contained in the lower 4-bit offset of the address.

    * Lower data: The lower 128 bits of data crossing a 16-byte boundary;

    * High-order data: The upper 128 bits of data crossing a 16-byte boundary.

  * Write selection logic:

    * If dataBuffer can accept misaligned instruction writes, and the
      instruction in channel 0 is misaligned and crosses a 16-byte boundary,
      then

      * Check if it crosses a 4K page table and can be dequeued while crossing:
        Channel 0 uses the low address and low data to write to dataBuffer;
        Channel 1 uses the physical address from StoreMisaligBuffer and high
        data to write to dataBuffer.

      * Otherwise: Channel 0 uses the lower address and lower data to write to
        dataBuffer; Channel 1 uses the higher address and higher data to write
        to dataBuffer.

    * If the channel instruction does not cross a 16-byte boundary and is
      unaligned, use a 16-byte aligned address and aligned data to write to the
      dataBuffer.

    * Otherwise, pass the original data and address to dataBuffer.

### Feature 7: Force flush Sbuffer

StoreQueue employs a dual-threshold method to control forced Sbuffer flushing:
upper threshold and lower threshold. When the number of valid entries in
StoreQueue exceeds the upper threshold, StoreQueue forces Sbuffer flushing until
the number of valid entries falls below the lower threshold, at which point
Sbuffer flushing stops.

\newpage

## Overall Block Diagram

![StoreQueue overall framework](./figure/LSQ-StoreQueue.svg){#fig:LSQ-StoreQueue
width=90%}

## Interface timing

### Enqueue interface timing example

![StoreQueue Overall
Framework](./figure/LSQ-StoreQueue-Enq-Timing.svg){#fig:LSQ-StoreQueue-Enq-Timing
width=90%}

\newpage

### Data update interface timing.

![Data Update Interface
Timing](./figure/LSQ-StoreQueue-Data-Timing.svg){#fig:LSQ-StoreQueue-Data-Timing
width=90%}

### Address Update Interface Timing

StoreQueue address updates are similar to data updates. The StoreUnit updates
the address via io_lsq in the s1 stage and updates exceptions via
io_lsq_replenish in the s2 stage. Unlike data updates, address updates only
require one cycle instead of two.

### MMIO interface timing example

![MMIO Interface Timing
Example](./figure/LSQ-StoreQueue-MMIO-Timing.svg){#fig:LSQ-StoreQueue-MMIO-Timing
width=90%}

\newpage
### NonCacheable Interface Timing Example

![NonCacheable Interface Timing
Example](./figure/LSQ-StoreQueue-NC-Timing.svg){#fig:LSQ-StoreQueue-NC-Timing
width=90%}

### CBO interface timing example

![CBO interface timing
example](./figure/LSQ-StoreQueue-CBO-Timing.svg){#fig:LSQ-StoreQueue-CBO-Timing
width=90%}

\newpage
### CMO Interface Timing Example

![CMO interface timing
example](./figure/LSQ-StoreQueue-CMO-Timing.svg){#fig:LSQ-StoreQueue-CMO-Timing
width=90%}
