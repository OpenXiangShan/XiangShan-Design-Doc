
# Third-level module: Last Level Page Table Walker

The Last Level Page Table Walker refers to the following module:

* LLPTW llptw

## Design specifications

1.  Supports accessing the last-level page table.
2.  Supports parallel processing of multiple requests.
3.  Support sending PTW requests to memory
4.  Supports sending refill signals to the Page Cache.
5.  Supports exception handling mechanism
6.  Supports second-stage translation.

## Function

### Access the last-level page table

The Last Level Page Table Walker is responsible for accessing the last-level
page table while enhancing the parallelism of Page Table Walker accesses. The
Page Table Walker can only handle one request at a time, whereas LLPTW can
process multiple requests concurrently. If duplicate requests exist, LLPTW does
not merge them but records these requests to share memory access results,
avoiding redundant memory accesses.

The LLPTW may receive requests from either the Page Cache or the Page Table
Walker. For requests from the Page Cache, they must meet the conditions of
hitting the second-level page table, missing the third-level page table, and not
being a bypass request. For requests from the Page Table Walker, since they
already satisfy the condition of only missing the last-level page table, the
LLPTW can access memory directly. Requests from the Page Cache and Page Table
Walker are arbitrated and then forwarded to the LLPTW.

The Page Table Walker and LLPTW work together to complete the entire Page Table
Walk process. To improve memory access parallelism, the LLPTW assigns different
IDs to requests, allowing multiple inflight requests to coexist. Since the first
two levels of page tables may be the same across different requests, and
considering that the miss probability for the first two levels is lower than for
the last level, there is no need to enhance parallelism for the first two
levels. Instead, the Page Table Walker handles single requests to reduce design
complexity.

### Parallel processing of multiple requests

The LLPTW can handle multiple requests simultaneously, with the number of
parallel processes equal to the number of entries in the LLPTW. If there are
duplicate requests among them, the LLPTW does not merge them but records these
requests and shares the memory access results to avoid redundant memory
accesses. Each entry in the LLPTW maintains the state of memory access through a
state machine. When the LLPTW receives a new request, it compares the address of
the new request with those of existing requests. If the addresses match, the
state of the existing request is copied to the new request. Thus, requests with
the same address can share memory access results, avoiding redundant access
requests.

### Send PTW requests to memory

Similar to the behavior of the Page Table Walker, the LLPTW can also send PTW
requests to memory. The LLPTW merges duplicate requests and shares memory access
results to avoid redundant memory accesses. Since the data returned by memory is
relatively large (512 bits), the returned results are not stored in the LLPTW.
If a PTW request is sent to the LLPTW while it is awaiting a memory response for
a previously sent PTW request, and the physical address of the new request
matches the physical address returned by memory, the new request is forwarded to
the Miss queue to await the next access to the Page Cache.

### Send a refill signal to the Page Cache

The logic for the Last Level Page Table Walker to send a refill signal to the
Page Cache is similar to that of the Page Table Walker and will not be
elaborated here.

### Exception Handling Mechanism

An access fault exception may occur in the Last Level Page Table Walker and will
be delivered to the L1 TLB. The L1 TLB handles it based on the request source.
Refer to Section 6 of this document: Exception Handling Mechanism.

### Supports second-stage translation.

Four new states have been added: state_hptw_req, state_hptw_resp,
state_last_hptw_req, and state_last_hptw_resp. When a two-stage translation
request enters the LLPTW, it first performs a second-stage translation to obtain
the actual physical address of the third-level page table. After address
checking and memory access, once the third-level page table is obtained, another
second-stage translation is required before returning to obtain the final
physical address.

Each entry has been augmented with an hptw resp structure to store the results
of each second-stage translation. Upon the first second-stage translation, when
hptw returns, all entries are checked. If a memory access request for the same
cacheline has already been issued, it directly enters the mem waiting phase.

The LLPTW introduces additional arbiters for the second-stage translation.
hyper_arb1 is used for the first second-stage address translation, corresponding
to the hptw req state; hyper_arb2 is used for the second second-stage address
translation, corresponding to the last hptw req state. The input of hptw_req_arb
consists of hyper_arb1 and hyper_arb2, and the output is the hptw request signal
from the LLPTW.

## Overall Block Diagram

Although the Last Level Page Table Walker can process multiple accesses to the
last-level page table in parallel, its internal logic, like the Page Table
Walker, is implemented via a state machine. This section describes the state
transition diagram and transition relationships of the state machine. For the
connection relationships between the Last Level Page Table Walker and other
modules in the L2 TLB, refer to Section 5.3.3.

The state transition diagram of the state machine is shown in
[@fig:LLPTW-states], which illustrates the state transitions for requests
involving non-two-stage address translation.

![State transition diagram of the Last Level Page Table
Walker](../figure/image41.png){#fig:LLPTW-states}

After adding the virtualization extension, the state machine of the LLPTW when
receiving a two-stage address translation request is as shown in
[@fig:LLPTW-allstage-states].

![State transition diagram of the Last Level Page Table Walker handling allStage
requests](../figure/image42.jpeg){#fig:LLPTW-allstage-states}

Requests entering the LLPTW do not all start from the idle state. Depending on
the existing entries in the LLPTW, they may enter idle, addr_check, mem_waiting,
mem_out, or cache states. For two-stage address translation requests, they may
enter hptw_req, cache, mem_waiting, or last_hptw_req states.

* idle: Initial state. After completing an LLPTW request, it returns to the idle
  state, indicating that the entry in LLPTW is empty. When a prefetch request
  enters LLPTW and duplicates an existing request in LLPTW, the prefetch request
  is not accepted, keeping the LLPTW entry idle. Possible transitions back to
  idle occur under three scenarios:
    1. Currently in the mem_out state, a PMP&PMA check results in an access
       fault, which is returned to the L1 TLB, transitioning the state to idle.
    2. Currently in the mem_out state, the last-level page table is queried and
       returned to the L1 TLB, transitioning the state to idle.
    3. Currently in the cache state, the queried page table has been written
       into the Page Cache and needs to be returned to the Page Cache for
       further querying, transitioning the state to idle.
* hptw_req: This state is entered when the incoming request is for two-stage
  address translation. In this state, an hptw request is sent to the L2TLB.
* hptw_resp: After issuing an hptw request, it enters this state to await the
  hptw response. Upon receiving the response, if it duplicates an existing LLPTW
  entry in mem_waiting, it transitions to mem_waiting; otherwise, it proceeds to
  addr_check.
* addr_check: This state is entered when the incoming request to the LLPTW does
  not duplicate any existing requests and is not a two-stage translation
  request. Additionally, for two-stage address translation requests, this state
  is entered after the hptw request returns, and the physical address must be
  sent to the PMP module for PMP&PMA checks. The PMP module must return the
  check result in the same cycle. If no access fault occurs, the state
  transitions to mem_req; otherwise, it transitions to mem_out.
* mem_req: This state has completed PMP&PMA checks and can issue requests to
  memory (mem_arb). For each LLPTW entry, when the memory access request sent by
  mem_arb matches the virtual page number in the LLPTW entry, it transitions to
  the mem_waiting state to await memory's response.
* mem_waiting: When the incoming request to the LLPTW matches the virtual page
  number of a PTW request already sent to memory by the LLPTW, the state of the
  new LLPTW entry is set to mem_waiting. This state waits for a response from
  memory. When the memory returns a page table entry corresponding to this LLPTW
  entry, for non-two-stage address translation LLPTW entries, the state
  transitions to mem_out, while for two-stage address translation LLPTW entries,
  the state transitions to last_hptw_req.
* last_hptw_req: When the incoming LLPTW request matches the virtual page number
  of the request being responded to by memory for LLPTW and the request involves
  two-stage translation, upon obtaining the final page table from memory, it
  enters this state to perform the last second-stage address translation and
  issue an hptw request.
* last_hptw_resp: Waits for the hptw request to return. After the hptw request
  returns, it transitions to the mem_out state.
* mem_out: When the incoming request to the LLPTW matches the virtual page
  number of a request being responded to by memory and the request is not a
  two-stage translation request, the state of the new LLPTW entry is set to
  mem_out. Since the three-level page table lookup is already completed, the
  virtual address and page table entry are returned to the L1 TLB. Additionally,
  for cases where an access fault occurs in the addr_check state, it must also
  be reported to the L1 TLB. After successfully returning the information to the
  L1 TLB, the state transitions to idle.
* cache: When an incoming LLPTW request matches the virtual page number of an
  LLPTW entry currently in mem_out/last_hptw_req/last_hptw_resp, the page table
  entry obtained from memory has been written back to Cache. Thus, a query
  request is sent to Cache, and the new request's LLPTW entry state is set to
  cache. Once Cache (specifically mq_arb) accepts the request, the state
  transitions to idle.

## Interface timing

The Last Level Page Table Walker interacts with other modules in the L2 TLB
using a valid-ready protocol. The signals involved are relatively trivial, and
there are no particularly noteworthy timing relationships, so they will not be
elaborated further.
