# Load instruction execution unit LoadUnit

## Functional Description

The load instruction pipeline receives load instructions from the load dispatch
queue. After processing in the pipeline, the results are written back to the
LoadQueue and ROB for instruction commit and to wake up subsequent instructions
dependent on this one. Meanwhile, the LoadUnit provides necessary feedback to
the dispatch queue and Load/StoreQueue. The LoadUnit supports a data width of
128 bits.

### Feature 1: Functions of LoadUnit Pipeline Stages

* Stage 0.

    * Receive requests from different sources and perform arbitration.

    * The arbitrated instruction sends query requests to the TLB and D-cache.

    * Pipeline flows to stage 1.

  The arbitration priorities from highest to lowest are listed in the table
  below.

  Table: LoadUnit Request Priority.

  | Stage 0 request source.                                 | Priority |
  | ------------------------------------------------------- | -------- |
  | Load requests from the MisalignBuffer.                  | High.    |
  | Resending due to loadQueueReplay caused by dcache miss. |          |
  | Fast replay of LoadUnit                                 |          |
  | Uncacheable request                                     |          |
  | Non-cacheable request.                                  |          |
  | Other replays from LoadQueueReplay                      |          |
  | High-confidence hardware prefetch requests.             |          |
  | Vector load request                                     |          |
  | Scalar load/software prefetch requests.                 |          |
  | load pointchaising request                              |          |
  | Low-confidence hardware prefetch request                | Low.     |

  The current Kunminghu architecture does not support load pointchaising.

* stage 1

    * Receive requests from stage 0.

    * s1_kill: The s1_kill signal is set to true when fast replay
      virtual-physical address matching fails, L2L forwarding fails, or the
      redirect signal is active.

    * May issue a kill signal to the TLB or D-cache.

    * Upon receiving a response from the TLB, query the DCache based on the
      physical address; for hint cases, send them to the DCache simultaneously.

    * Queries storequeue && sbuffer for st-ld forward.

    * Receives store unit requests and checks for st-ld violations.

    * Check if an exception occurs.

    * For NC instructions, perform PBMT check

    * If it is a prf_i instruction, send a request to the frontend.

* Stage 2.

    * Receive requests from stage 1.

    * Receives the PMP check response to determine if an exception occurred;
      simultaneously integrates the source of the exception.

    * Receives the response from the dcache to determine if a resend is needed.

    * Queries LoadQueue and StoreQueue for ld-ld or st-ld violations

    * Send fast wake-up signal to the backend

    * Integrates reasons for resending.

    * For non-cacheable (nc) instructions, perform PMA & PMP checks.

* stage 3

    * Receive requests from stage 2.

    * Send prefetch requests to the SMS prefetcher and L1 prefetcher.

    * Receive data returned from dcache or forwarded data, perform concatenation
      and selection

    * Receives uncache load request writeback

    * Writes back completed load requests to the backend.

    * Update the execution status of the load instruction in the LoadQueue

    * Send a redirect request to the backend.

### Feature 2: Supports vector load instructions.

* The LoadUnit handles unaligned load instructions similarly to scalar ones,
  with lower priority than scalar. Specifically:

    * Stage 0:

        * Accept execution requests from vlSplit, which have higher priority
          than scalar requests and do not require virtual address calculation

    * Stage 1:

        * Calculate vecVaddrOffset and vecTriggerMask

    * Stage 3:

        * No need to send a feedback_slow response to the backend

        * Vector load initiates Writeback and sends it to the backend via
          vecldout.

### Feature 3: Supports MMIO load instructions

* MMIO load instructions are only intended to wake up consumer instructions
  dependent on them.

    * MMIO load instruction sends wake-up request to the backend in s0

    * MMIO load writes back data in stage s3.

### Feature 4: Supports Non-cacheable load instructions.

* The process for handling non-aligned Load instructions in LoadUnit is similar
  to scalar requests, with higher priority than scalar requests. Specifically,
  Noncacheable load instructions will engage the pipeline twice:

    * First pipeline stage: determines the NC attribute of the instruction

    * Second pipeline stage:

        * Stage 0: Identifies NC instructions, no TLB translation required.

        * Stage 1: Send forwarding request to StoreQueue

        * Stage 2: Determines store data forwarding conditions (data not ready -
          replay handling, virtual-physical address mismatch - redirect N
          handling). Sends RAR/RAW violation requests.

        * Stage 3: Determine violation scenarios (ldld vio-redirect, stld
          vio-redirect handling). If RAR or RAW is full/not ready, a resend from
          LoadQueueUncache is required. If no resend is needed, write back via
          ldout.

* Non-aligned Noncacheable load instructions are not supported.

* Supports obtaining forwarded data from the LoadQueueUncache.

### Feature 5: Support for misaligned load instructions

* Non-aligned load instructions will engage the pipeline four times:

    * First pipeline stage: Determine if it is a misaligned instruction; if so,
      the LoadMisalignedBuffer sends a misaligned request

    * The second time the pipeline is engaged, the first aligned load
      instruction from the split is executed. Upon successful execution, a
      response is sent to the LoadMisalignBuffer; otherwise, it is resent from
      the LoadMisalignBuffer.

    * The third time in the pipeline, executing the second split aligned load
      instruction. Upon successful execution, a response is sent to the
      LoadMisalignBuffer; otherwise, it is resent from the LoadMisalignBuffer.

    * The fourth pipeline stage wakes up the consumers following the load
      instruction in s0, while the load instruction writes back from the
      LoadMisalignBuffer.

* The process for handling non-aligned Store instructions in Load is similar to
  that of scalar operations, with the following specifics:

    * Stage 0:

        * Accept requests from the LoadMisalignBuffer with higher priority than
          vector and scalar requests, and without the need to calculate virtual
          addresses.

    * Stage 3:

        * If the request is not from the LoadMisalignBuffer and is a non-aligned
          request that does not cross a 16-byte boundary, it needs to be
          processed by the LoadMisalignBuffer. A queue request is sent to the
          LoadMisalignBuffer via the io_misalign_buf interface.


        * If the request is from LoadMisalignBuffer and does not cross a 16-byte
          boundary, it needs to send a replay or writeback response to
          LoadMisalignBuffer. The response is sent via the io_misalign_ldout
          interface.


        * If misalignNeedWakeUp == true, write back directly; otherwise, proceed
          to the LoadMisalignBuffer for retransmission.

### Feature 6: Supports prefetch requests

* The LoadUnit accepts two types of prefetch requests.

    * High-confidence prefetch (confidence > 0)

    * Low-confidence prefetch (confidence == 0)

* Support for prefetch training

    * stage s2:

        * Trains the L1 prefetch via io_prefetch_train_l1.

        * Trains SMS prefetch via io_prefetch_train

\newpage

## Overall Block Diagram

![Overall Block Diagram of
LoadUnit](./figure/LSU-LoadUnit.svg){#fig:LSU-LoadUnit}


\newpage

## Interface timing

### LoadUnit interface timing example.

![LoadUnit interface
timing](./figure/LSU-LoadUnit-Timing.svg){#fig:LSU-LoadUnit-timing}

After a load instruction enters the LoadUnit, it requests TLB and DCache in
stage 0, obtains the paddr returned by TLB in stage 1, and determines DCache
hit/miss in stage 2. RAW and RAR violation checks are performed in stage 2. The
LoadQueue is updated via io_lsq_ldin in stage 3. Write-back occurs via ldout in
stage 3.


\newpage

### Timing example of arbitration for different sources in stage 0

![Timing diagram of arbitration for different sources in stage
0](./figure/LSU-LoadUnit-s0-arb.svg){#fig:LSU-LoadUnit-s0-arb}

The diagram illustrates arbitration of load instructions from different sources
in stage 0. In the third clock cycle, only io_ldin_valid is active and the
handshake succeeds, advancing to stage 1 in the next cycle. In the fifth clock
cycle, both io_ldin_valid and io_replay_valid are active, but since replay
requests have higher priority than scalar loads, the replay request wins
arbitration and proceeds to stage 1.
