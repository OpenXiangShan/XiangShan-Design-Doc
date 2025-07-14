\newpage
# Read-After-Read Violation Check LoadQueueRAR

## Functional Description

Load-to-load violations can occur in a multi-core environment. In a single-core
environment, out-of-order execution of loads to the same address is generally
not a concern. However, if another core performs a store to the same address
between two loads, and the two loads on the original core are scheduled out of
order, it may result in the newer load not seeing the updated result from the
store while the older load does, leading to a sequence error.

In a multi-core environment, a load-load violation has a characteristic where
the current DCache will inevitably receive a Probe request from the L2 cache,
prompting the DCache to actively release this data copy. At this point, the
DCache will notify the load queue to mark the entries in the load queue that
have already completed memory access for the same address with a release flag.
Subsequent load instructions sent to the pipeline will query the load queue for
load instructions with the same address that come after them. If a release flag
is found, a load-load violation occurs.

LoadQueueRAR stores information for completed load instructions to detect
load-to-load violations. When a load instruction is at the s2 stage of the load
pipeline, it queries and allocates a free entry to save the information into
LQRAR. At the s3 stage, the load-to-load violation check result is obtained. If
a violation occurs, the pipeline is flushed, and a redirect request is sent to
the RedirectGenerator unit to squash all instructions following the violating
load.

The following information needs to be marked in LoadQueueRAR:

* Allocated: Indicates whether the entry is valid.
* Uop: MicroOp-related information.
* Paddr: The compressed physical address of the instruction entering
  LoadQueueRAR, totaling 16 bits.
* Released: Indicates whether the cacheline accessed by the instruction has been
  released. In a multi-core environment, the L1 cache receives probe requests
  from the L2 cache. Note that if the instruction is non-cacheable (nc), it will
  be marked as released upon entry.

### Feature 1: Request Enqueue

When the query reaches stage s2 of the load pipeline, it determines whether the
enqueue condition is met. If there are unfinished load instructions before the
current load instruction and the current instruction has not been flushed, the
current load can be enqueued.

Obtain the allocatable entry and its index from the freelist.

The enqueued information is stored in the PaddrModule, including the compressed
physical address (16 bits) of the query and the index of the allocated entry.


### Feature 2: Load-to-Load Violation Check

When a load reaches stage s2 of the pipeline, it checks whether there are any
younger load instructions in the RAR queue with the same physical address as the
current load instruction. If these loads have already obtained the data and are
marked as released, it indicates a load-load violation. All instructions
following the violating load must be flushed.

It is divided into two cycles:

* The first cycle performs condition matching to generate the mask.
* The second cycle generates the response signal indicating whether a violation
  occurred.

### Feature 3: Release Conditions

There are four scenarios where a load instruction in LoadQueueRAR is marked as
released:

* The replace_req signal in the missQueue module initiates the release of a
  dcache block at the s3 stage of the mainpipe pipeline. The release signal
  enters the loadQueue in the next cycle.
* The probe_req signal in the probeQueue module initiates the release of a
  dcache block at the s3 stage of the mainpipe pipeline. The release signal
  enters the loadQueue in the next cycle.
* When a request from the atomicsUnit module misses in the s3 stage of the
  mainpipe pipeline, the dcache block must be released. The release signal
  enters the loadQueue in the next cycle.
* If the enqueue request is non-cacheable (nc), it is marked as released upon
  enqueue.

## Overall Block Diagram
<!-- 请使用 svg -->
![LoadQueueRAR Overall Block
Diagram](./figure/LoadQueueRAR.svg){#fig:LoadQueueRAR width=80%}

\newpage
## Interface timing

### Example of LoadQueueRAR Request Enqueue Timing

![LoadQueueRAR Request Enqueue
Timing](./figure/LoadQueueRAR-enqueue.svg){#fig:LoadQueueRAR-enqueue width=70%}

When both io_query_*_req_valid and io_query_*_req_ready are high, it signifies a
successful handshake. If both needEnqueue and io_canAllocate_* are high,
io_doAllocate_* is set high, indicating the query needs to be enqueued and the
FreeList can allocate. io_allocateSlot_* represents the entry receiving the
enqueued query, and the information written to the entry is io_w*.

### Timing Example of Load-Load Violation Check

![Load-Load Violation Check
Timing](./figure/LoadQueueRAR-load-to-load.svg){#fig:RAR-load-to-load width=70%}

When both io_query_*_req_valid and io_query_*_req_ready are high, it indicates a
successful handshake. The LoadQueueRAR receives the ld-ld violation query
request, obtains the mask result in the same cycle, and sets
io_query_*_resp_valid high in the next cycle to provide the response.

In the diagram, the first violation query request is received in cycle 3, and
the response to the violation query request is obtained in cycle 4. The request
information is io_query_*_req_bits_, and the response information is
io_query_*_resp_bits_. When both io_query_*_resp_valid and
io_query_*_resp_bits_rep_frm_fetch are high, it indicates a load-load violation,
and all instructions following the current violating load must be flushed.
