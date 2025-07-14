# Store address execution unit StoreUnit

## Functional Description

The store instruction address pipeline is divided into five stages:
S0/S1/S2/S3/S4, as shown in \ref{fig:LSU-StoreUnit-Pipeline}. It receives
requests from the store address issue queue, processes them, and then responds
to the backend and vector units. During processing, it provides feedback to the
issue queue and StoreQueue, and finally performs writeback. If an exception
occurs midway, the instruction is reissued from the issue queue.

![StoreUnit
pipeline](./figure/LSU-StoreUnit-Pipeline.svg){#fig:LSU-StoreUnit-Pipeline}

### Feature 1: The StoreUnit supports scalar store instructions.

* stage 0:

    * Calculate VA address

    * Address misalignment check updates to
      uop.cf.exceptionVec(storeAddrMisaligned)

    * Issue a DTLB read request to the TLB

    * Update the instruction's mask information to s0_mask_out and send it to
      StoreQueue

    * Determine if it is a store instruction with a data width of 128 bits.

* Stage 1:

    * Update DTLB query results to storeQueue

    * Send a store-load violation check request to the LoadQueue

    * If DTLB hits, send the store issue information to the backend

* stage 2:

    * MMIO/PMP checks and updates the storeQueue

    * Update DTLB results to the backend via feedback_slow

* stage 3

    * To synchronize with RAW violation checks when sending to the backend, an
      additional cycle is required

* stage 4

    * Scalar store initiates Writeback and sends it to the backend via stout

### Feature 3: StoreUnit supports vector Store instructions

The StoreUnit handles misaligned store instructions similarly to scalar
operations, with the following specifics:

* stage 0:

    * Accept vsSplit execution request, which has higher priority than scalar
      requests and does not require virtual address calculation

* Stage 1:

    * Calculate vecVaddrOffset and vecTriggerMask

* stage 2:

    * No need to send a feedback_slow response to the backend

* stage 4:

    * Vector store initiates writeback and sends it to the backend via vecstout.

### Feature 2: StoreUnit supports non-aligned Store instructions

The StoreUnit handles misaligned store instructions similarly to scalar
operations, with the following specifics:

* stage 0:

    * Accepts requests from StoreMisalignBuffer with higher priority than vector
      and scalar requests, and does not require virtual address calculation

* stage 2:

    * No need to send feedback response to the backend,

    * If the request is not from StoreMisalignBuffer and is a non-aligned
      request that does not cross a 16-byte boundary, it must be processed by
      StoreMisalignBuffer

        * Send an enqueue request to StoreMisalignBuffer via the io_misalign_buf
          interface

        * Does not enter stage 3

    * If the request is from StoreMisalignBuffer and does not cross a 16-byte
      boundary, a retry or writeback response must be sent to
      StoreMisalignBuffer

        * Send a response to StoreMisalignBuffer via the io_misalign_sout
          interface

        * If a TLB miss occurs, retry is required; otherwise, write back

        * Does not enter stage 3

\newpage

## Overall Block Diagram

![Overall block diagram of
StoreUnit](./figure/LSU-StoreUnit.svg){#fig:LSU-StoreUnit}

\newpage

## Interface timing

### Interface timing example

As shown in Figure \ref{fig:LSU-StoreUnit-Timing}, after the store instruction
enters the StoreUnit, it requests the TLB in stage 0 and obtains the paddr
returned by the TLB in stage 1. In stage 0, the mask is written to the
StoreQueue, and in stage 1, a request is sent to RAW, while other information of
the store instruction is updated to the LoadStoreQueue via io_lsq. In stage 2,
feedback-related information is obtained, and in stage 4, writeback is performed
via stout.

![StoreUnit Interface
Timing](./figure/LSU-StoreUnit-Timing.svg){#fig:LSU-StoreUnit-Timing}
