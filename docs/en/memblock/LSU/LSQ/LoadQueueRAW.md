\newpage
# Write-After-Read Violation Check LoadQueueRAW

## Functional Description

LoadQueueRAW is designed to handle store-load violations. Since loads and stores
execute out-of-order in the pipeline, it is common for a load to bypass an older
store to the same address. This load should have forwarded data from the store,
but if the store's address or data is not ready, the load may commit without
forwarding the store's data. Subsequent instructions using the load's results
will then be incorrect, resulting in a store-to-load forwarding violation.

When the store address is issued from the STA reservation station and enters the
store pipeline, it queries the LQRAW for all completed loads with the same
address that are after this store, as well as the loads in the load pipeline
that are currently being executed and are after this store with the same
address. If any are found, a store-to-load forwarding violation occurs. There
may be multiple violating loads, and the oldest violating load (i.e., the one
closest to the store) must be identified. A redirect request is then sent to the
RedirectGenerator component to flush the oldest violating load and all
subsequent instructions.

When the store pipeline executes a cbo zero instruction, a store-load violation
check is also required.

### Feature 1: Load query enqueue

When the query reaches the S2 stage of the load pipeline, it is determined
whether the enqueue condition is met. If there are store instructions with
unready addresses before the current load instruction and the current
instruction is not flushed, the current load can be enqueued.

Obtain the allocatable entry and its index from the freelist.

The physical address of the enqueued query is compressed to 24 bits and stored
in the corresponding entry of the PaddrModule.

The mask of the enqueued query is stored in the corresponding entry of the
maskModule.

### Feature 2: Store-Load Violation Check

When a store instruction reaches stage s1 of the store pipeline, a store-load
check is performed. The store is compared against loads in LoadQueueRAW that
have completed memory access, as well as loads in stages s1 and s2 of the load
pipeline that are currently accessing memory. These loads may not have forwarded
data from the store. If the check reveals overlapping physical addresses between
the load and store, and the load is younger than the store, a violation occurs.
The oldest load must be identified, and this load, along with all subsequent
instructions, must be reissued (fetched and executed again). The result of the
store-load violation check is obtained in stage s4 of the store pipeline.

The process is divided into four cycles:

* In the first cycle, physical address matching and condition matching are
  performed to generate a mask. This matches newer loads that occur after the
  store. If these loads have already obtained data (datavalid) or are
  experiencing a dcache miss and waiting for a refill (miss), they definitely
  did not forward data from this store.
* In the second cycle of the store pipeline, the store operation identifies all
  matching loads in LoadQueueRAW based on the mask. LoadQueueRAW has a total of
  32 entries, divided into eight groups of four entries each. From each group,
  the oldest entry is selected, potentially yielding up to four oldest entries.
* In the third cycle, the oldest entry is selected from the four oldest
  candidates.
* In the fourth cycle, if both stores in the store pipelines trigger
  store-to-load violations, the older of the two oldest loads matched in the
  loadQueue from each pipeline is selected, and a rollback request is sent to
  redirect.

## Overall Block Diagram
<!-- 请使用 svg -->
![LoadQueueRAW Overall Block
Diagram](./figure/LoadQueueRAW.svg){#fig:LoadQueueRAW width=80%}

## Interface timing

### Example of LoadQueueRAW Enqueue Request Timing

![LoadQueueRAW Enqueue Request
Timing](./figure/LoadQueueRAW-enqueue.svg){#fig:RAW-enqueue width=70%}

When both io_query_*_req_valid and io_query_*_req_ready are high, it indicates a
successful handshake. When both needEnqueue and io_canAllocate_* are high,
io_doAllocate_* is set to high, indicating that the query needs to be enqueued
and the FreeList can allocate. io_allocateSlot_* represents the entry receiving
the enqueued query. In the next cycle, the corresponding entry's allocate signal
is raised, and sqIdx is written into the entry. In the subsequent cycle, the
mask is written into the corresponding entry of the LqMaskModule, and the
compressed physical address is written into the corresponding entry of the
LqPAddrModule.

### Store-load violation timing example

![Store-Load Violation Check
Timing](./figure/LoadQueueRAW-store-to-load.svg){#fig:RAW-store-to-load
width=70%}

When io_rollback_valid is high, it indicates a store-load violation has
occurred, with the violation details provided by io_rollback_bits_*.
