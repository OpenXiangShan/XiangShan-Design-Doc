# Load Replay Queue: LoadQueueReplay

## Functional Description

LoadQueueReplay is used to store load instructions that need to be replayed and
wakes them up based on different conditions, scheduling them into the LoadUnit
for execution. It mainly includes the following states and stored information:

Table: LoadQueueReplay Storage Information

| Field              | Descrption                                                                                                                                                                       |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| allocated          | Whether it has been allocated also indicates whether the entry is valid.                                                                                                         |
| scheduled          | Whether it has been scheduled indicates that the item has already been selected and has been or will be sent to the LoadUnit for replay.                                         |
| uop                | The uop information included in the execution of a Load instruction.                                                                                                             |
| vecReplay          | Vector load instruction related information                                                                                                                                      |
| vaddrModule        | Virtual address of the Load instruction.                                                                                                                                         |
| cause              | Reasons for a load instruction replay in the load replay queue include:                                                                                                          |
|                    | C_MA(bit0): store-load prediction violation                                                                                                                                      |
|                    | C_TM (Bit 1): TLB miss                                                                                                                                                           |
|                    | C_FF(bit2): store-to-load-forwarding store data is ready, causing failure                                                                                                        |
|                    | C_DR (Bit 3): DCache miss occurs, but MSHR cannot be allocated                                                                                                                   |
|                    | C_DM (Bit 4): DCache miss occurred                                                                                                                                               |
|                    | C_WF (Bit 5): Way predictor misprediction.                                                                                                                                       |
|                    | C_BC (Bit 6): Bank conflict                                                                                                                                                      |
|                    | C_RAR (Bit 7): LoadQueueRAR has no space to accept the instruction.                                                                                                              |
|                    | C_RAR (Bit 8): LoadQueueRAW has no space to accept the instruction.                                                                                                              |
|                    | C_NK (Bit 9): LoadUnit detects a store-to-load-forwarding violation                                                                                                              |
|                    | C_MF (Bit 10): LoadMisalignBuffer has no space to accept the instruction.                                                                                                        |
| Blocking           | The Load instruction is currently blocked.                                                                                                                                       |
| strict             | The memory dependency predictor determines whether an instruction needs to wait for all preceding store instructions to complete execution before entering the scheduling phase. |
| blockSqIdx         | StoreQueue Index of the store instruction that has dependency with the load instruction                                                                                          |
| missMSHRId         | Load instruction's dcache miss request acceptance ID                                                                                                                             |
| tlbHintId          | Load instruction's tlb miss request acceptance ID                                                                                                                                |
| replacementUpdated | Whether the DCache replacement algorithm has been updated                                                                                                                        |
| replayCarry        | DCache way predictor prediction information                                                                                                                                      |
| missDbUpdated      | Miss-related updates in ChiselDB                                                                                                                                                 |
| dataInLastBeatReg  | The data required by the Load instruction is in the last of two refill requests                                                                                                  |


\newpage

### Feature 1: Out-of-order allocation

* After a load request is passed to LoadUnit S3, it first needs to determine
  whether enqueuing is required. No enqueuing is needed if no replay is
  required, an exception occurs, or the request is flushed due to redirect.
  LoadQueueReplay manages queue vacancies using a freelist. The freelist size
  matches the number of entries in the load replay queue, with an allocation
  width equal to the load width (number of LoadUnits) and a deallocation width
  of 4. Additionally, the freelist provides feedback on the remaining entries in
  the load replay queue and whether it is full. LoadQueueReplay employs the
  Freelist for queue vacancy management. The freelist size corresponds to the
  number of entries in LoadQueueReplay, with an allocation width equal to the
  load width (number of LoadUnits) and a deallocation width of 4.

  * Allocation

    * LoadQueueReplay selects an entry index from the free items in the Freelist
      (i.e., the Valid items in Figure \ref{fig:LSQ-LoadQueueReplay-Freelist})
      for each LoadUnit (best-effort allocation of free items, e.g., if valid
      items are 5 and 10, and LoadUnit0 and LoadUnit2 are active, then LoadUnit0
      is assigned 5 and LoadUnit2 is assigned 10). The instruction information
      is then filled into the corresponding entry based on the index.

    ![Freelist](./figure/LSQ-LoadQueueReplay-Freelist.svg){#fig:LSQ-LoadQueueReplay-Freelist
    width=70%}

  * Reclamation

    * Entries occupied by successfully replayed or flushed load instructions
      need to be reclaimed. LoadQueueReplay uses a bitmap FreeMask to track
      entries being released, with a maximum of 4 entries reclaimed per cycle by
      the Freelist.

    ![Freelist
    Recycling](./figure/LSQ-LoadQueueReplay-Freelist-Recycle.svg){#fig:LSQ-LoadQueueReplay-Freelist-Recycle
    width=90%}

### Feature 2: Wake-up

* Different blocking conditions have different wake-up conditions:

  * C_MA: If strict==1, the Load instruction must wait for all preceding store
    instructions to complete their address calculations before being awakened.
    Otherwise, it only needs to wait for the address calculation of the Store
    instruction corresponding to blockSqIdx to complete.

  * C_TM: If the TLB has no extra space to handle the miss request, it can be
    marked as a replay state, waiting for scheduling; otherwise, it needs to
    wait for the TLB to return a hint signal matching tlbHintId to wake up.

  * C_FF: Needs to wait until the data for the Store instruction corresponding
    to blockSqIdx is ready before waking up.

  * C_DR: Can be marked as replay-ready, awaiting scheduling.

  * C_DM: Wait for the L2 Hint signal matching missMSHRId to wake up.

  * C_WF: Can be marked as replay-ready and await scheduling.

  * C_BC: Can be marked as replay-ready state, awaiting scheduling.

  * C_RAR: Can be awakened when there is free space in the LoadQueueRAR or when
    the instruction is the oldest load instruction.

  * C_RAW: The Load instruction can be awakened either when there is free space
    in LoadQueueRAW or after all preceding store instructions have completed
    their address calculations.

  * C_MF: Wait for LoadMisalignBuffer to have free space before it can be woken
    up.

### Feature 3: Selective Scheduling

* LoadQueueReplay has 3 optional scheduling methods:

  * Based on enqueue age

    * LoadQueueReplay uses three age matrices (one for each Bank) to record the
      enqueue time. The age matrix selects the longest-enqueued instruction from
      those ready for replay and schedules it for resending.

  * Based on the age of the Load instruction

    * LoadQueueReplay can determine the oldest Load instruction for replay based
      on LqPtr, with a selection width of OldestSelectStride=4.

  * Load instructions related to DCache data are scheduled with priority

    * LoadQueueReply first schedules the replay triggered by L2 Hint (When a
      dcache miss occurs, it needs to continue querying the lower-level cache L2
      Cache. Two or three cycles before L2 Cache refills, L2 Cache will send an
      early wake-up signal to LoadQueueReplay, known as L2 Hint). Upon receiving
      the L2 Hint, LoadQueueReplay can wake up the Load instruction blocked by
      dcache miss earlier for replay.

    * If there is no L2 Hint scenario, the remaining reasons for Load Replay are
      categorized into high and low priorities. High-priority reasons include
      replay due to dcache misses or st-ld forwarding, while other reasons are
      classified as low priority. If a Load instruction meeting the replay
      conditions (valid, unscheduled, and not blocked waiting for wake-up) can
      be found in the LoadQueueReplay, it is selected for replay. Otherwise, the
      oldest entry in the load replay queue is identified via the AgeDetector
      module based on the enqueue order for replay.

\newpage

## Overall Block Diagram

![LoadQueueReplay Overall Block
Diagram](./figure/LSQ-LoadQueueReplay.svg){#fig:LSQ-LoadQueueReplay}

## Interface timing

### Enqueue Timing

  * Replay enqueue

![LoadQueueReplay Enqueue Timing
Diagram](./figure/LSQ-LoadQueueReplay-Enq-Timing.svg){#fig:LSQ-LoadQueueReplay-Enq-Timing}

\newpage

  * Non-replay enqueue

![LoadQueueReplay Non-Replay Enqueue Timing
Diagram](./figure/LSQ-LoadQueueReplay-NoEnq-Timing.svg){#fig:LSQ-LoadQueueReplay-NoEnq-Timing}

### Replay Timing

![LoadQueueReplay Replay Queue Timing
Diagram](./figure/LSQ-LoadQueueReplay-Deq-Timing.svg){#fig:LSQ-LoadQueueReplay-Deq-Timing}

\newpage

### Freelist Timing

  * Allocation timing

![Freelist Allocation Timing
Diagram](./figure/LSQ-Freelist-Alloc-Timing.svg){#fig:LSQ-Freelist-Alloc-Timing}

  * Reclaim timing

![Freelist Deallocation Timing
Diagram](./figure/LSQ-Freelist-DeAlloc-Timing.svg){#fig:LSQ-Freelist-DeAlloc-Timing}
