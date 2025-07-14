# Load Memory Access Pipeline LoadPipe

## Functional Description

The pipeline controls the processing of Load requests, tightly coupled with the
Load memory access pipeline, and reads the target data or returns a miss/replay
response through a 4-stage pipeline.

### Feature 1: Functions of LoadPipe pipeline stages:

* Stage 0: Receives the virtual address calculated by the pipeline in the
  LoadUnit; reads tag and meta based on the address;
* Stage 1: Obtains the corresponding tag and meta query results; receives the
  physical address from the LoadUnit, performs tag comparison to determine a
  hit; reads data based on the address; checks l2_error;
* Stage 2: Obtains the corresponding data result; if a load miss occurs, sends a
  miss request to the MissQueue, attempting to allocate an MSHR entry; returns a
  response to the LoadUnit for the load request; checks tag_error;
* Stage 3: Updates the replacement algorithm state; reports 1-bit ECC check
  errors to the bus error unit (including data errors detected by the dcache,
  tag errors detected by the dcache, and errors already present when fetching
  data blocks from L2).

## Overall Block Diagram

The overall architecture of LoadPipe is shown in [@fig:DCache-LoadPipe].

![LoadPipe Accessing DCache
Diagram](./figure/DCache-LoadPipe.svg){#fig:DCache-LoadPipe}

## Interface timing

### Request Interface Timing Example

As shown in [@fig:DCache-LoadPipe-Timing], req1 is received by the LoadPipe in
the first cycle to read meta and tag; in the second cycle, tag comparison
determines a miss; in the third cycle, a response is returned to the LSU, with
lsu_resp_miss asserted indicating no hit and data cannot be returned yet, while
a miss request is sent to the MissQueue; in the fourth cycle, it checks and
reports any ECC errors. req2 and req3 are issued immediately after req1, also
received in stage_0 to read meta and tag; in the second cycle, a hit is
detected, and a data read request is issued; in the third cycle, data is
obtained, and a response with load data is returned to the LSU; in the fourth
cycle, PLRU is updated, and ECC errors are reported.

![LoadPipe
Timing](./figure/DCache-LoadPipe-Timing.svg){#fig:DCache-LoadPipe-Timing}
