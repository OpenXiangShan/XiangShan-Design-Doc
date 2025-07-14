
# Level-3 Module Page Table Walker

Page Table Walker refers to the following module:

* PTW ptw

## Design specifications

1. Supports accessing the first two levels of the page table.
2. Support sending PTW requests to memory
3. Supports forwarding PTW requests to LLPTW.
4. Supports sending refill signals to the Page Cache.
5. Support for exception handling
6. Supports two-stage address translation.

## Function

### Accessing the first two levels of page tables

The Page Table Walker is fundamentally a state machine that traverses the page
table level by level using virtual addresses to obtain physical addresses. It
can handle only one request at a time and accesses at most the first two levels
of the page table, with limited memory access capability. Its behavior in
virtual-to-physical address translation aligns with the manual description,
requiring PMP checks on the physical address before memory access. If a PMP
check fails, it returns immediately; otherwise, it sends a PTW request to memory
or LLPTW. With the addition of the H extension, PTW still handles the first two
levels of translation in the first stage, but the physical addresses calculated
during these translations must undergo a second-stage translation to obtain the
true physical address before memory access. It also supports scenarios with only
second-stage or only first-stage translation. When memory returns a page table
entry, PMP checks are also performed. The Page Table Walker continues these
operations until one of the following three conditions occurs:

1. Accessing a leaf node (large page) directly returns to the L1 TLB (for
   all-stage translations, a second-stage translation is performed before
   returning).
2. Upon accessing the second-level page table, it returns to LLPTW, which
   handles the final level of page table access.
3. A Page fault or Access fault occurred during access.

### Sends a PTW request to memory or llptw.

When the Page Table Walker accesses the first two levels of the page table, it
needs to send a PTW request to memory. Upon completing the access to the first
two levels, it must send a PTW request to LLPTW. Requests sent by PTW, LLPTW,
and HPTW to memory require arbitration before being dispatched, with the
TileLink protocol's A and D channel source signals indicating whether the
request originates from PTW, LLPTW, or HPTW.

### Send a refill signal to the Page Cache

When the PTW request sent by the Page Table Walker to memory receives a
response, it sends a refill request to the Page Cache. Mem will refill the
returned page table entry into the Page Cache, but the Page Table Walker needs
to additionally provide the virtual page number, page table level, and page
table type. Depending on whether the translation request is a two-stage address
translation request, the page tables refilled into the Page Cache are
categorized as noS2xlate and onlyStage1.

### Exception Handling Mechanism

An access fault exception may occur in the Page Table Walker, which will be
delivered to the L1 TLB. The L1 TLB handles it based on the request source.
Refer to Section 6 of this document: Exception Handling Mechanism.

## Overall Block Diagram

The essence of the Page Table Walker is a software state machine divided into
request and response events. Each state is represented by a pair of request and
response events, depicted here using a common state machine transition diagram
and relationships for clarity. For details on the connections between the Page
Table Walker and other modules in the L2 TLB, refer to Section 5.3.3.

The state machine transition diagram is shown in [@fig:PTW-states].

![State transition diagram of the Page Table Walker state
machine](../figure/image40.jpeg){#fig:PTW-states}

To clearly represent the states, different types of requests are divided into
two types of state machines, each with its own transition diagram.

For the state machine of noS2xlate or onlyStage1 requests (left side of the
diagram), the descriptions of each state are as follows:

* idle: The initial state of the Page Table Walker. Upon receiving a request,
  the PTW enters the pmp check state.
* pmp check: In this state, the physical address to be accessed is sent to the
  PMP module for PMP and PMA checks. In the next cycle, it enters the mem req
  state. The PMP module returns the check result in the same cycle, indicating
  whether an access fault occurred.
* mem req: Based on the check results, if an access fault occurs, it directly
  enters the final check pte state (indicated by the mem_addr_update signal
  being valid in the chisel code). If no access fault occurs, a memory access
  request is sent, and the state transitions to mem resp.
* mem resp: This state waits for memory to respond, transitioning to the check
  PTE state upon receipt.
* check pte: In this state, the current request is examined to determine the
  next action:
    1. No leaf node found and no access fault occurred. At this point, the level
       is the first-level page table, transitioning to the mem req state.
    2. If an access fault occurs, it directly returns to the L1TLB,
       transitioning the state to idle.
    3. If a second-level page table is found and it is not a leaf node, it is
       forwarded to LLPTW.
    4. Found a leaf node (large page), returns it to the L1TLB.

For allStage and onlyStage2 requests:

* idle: Upon receiving these two types of requests, it enters the hptw req state
  and immediately begins the second-stage translation.
* hptw req: Sends a request for second-stage translation to the L2TLB, then
  transitions to the hptw resp state after the request is sent.
* hptw resp: Waits for the hptw request to return. Upon return, if the current
  request is onlyStage2, it directly enters the check pte state; otherwise, it
  proceeds to the pmp check state.
* pmp check: In this state, the physical address to be accessed is sent to the
  PMP module for PMP and PMA checks. In the next cycle, it enters the mem req
  state. The PMP module returns the check result in the same cycle, indicating
  whether an access fault occurred.
* mem req: Based on the check results, if an access fault occurs, it directly
  enters the final check pte state (indicated by the mem_addr_update signal
  being valid in the chisel code). If no access fault occurs, a memory access
  request is sent, and the state transitions to mem resp.
* mem resp: This state waits for memory to respond, transitioning to the check
  PTE state upon receipt.
* check pte: For non-onlyStage2 requests (i.e., allStage), if no leaf node is
  found and no access fault occurs, it enters the hptw req state. If no leaf
  node is found and the level is already a second-level page table, the request
  is sent to llptw. If the last s2xlate signal is active at this time, it
  indicates that a second-stage address translation is still required before
  returning (onlyStage2 requests do not need this). If a leaf node is found and
  the final address translation is completed, it returns to the L1TLB.

Note that the PTW also handles allStage requests where stage1 hits. Upon
receiving such a request, it performs a second-stage translation and directly
returns to the L1TLB.

## Interface list

The signal list of the Page Table Walker can be categorized into the following
types:

1.  req: The Page Table Walker only accepts requests from the Page Cache, and
    certain conditions must be met. Refer to Section 5.3.7 for details on the
    Page Cache.
2.  resp: The Page Table Walker returns relevant information to the L1 TLB when
    accessing a large page or encountering a PMP&PMA check error.
3.  llptw: If the Page Table Walker accesses only the last level of the page
    table or if the PMP&PMA check reports an error, the relevant information is
    returned to the L1 TLB.
4.  mem: The interaction between the Page Table Walker and memory when accessing
    memory, involving req and resp. The handshake signals between the Page Table
    Walker and memory also control the state transitions of the Page Table
    Walker state machine.
5.  pmp: Interaction between the Page Table Walker and the PMP module for PMP
    and PMA checks.
6.  refill: After accessing memory and obtaining the result, the Page Table
    Walker needs to refill the memory-returned result and related information
    into the Page Cache.
7.  hptw: After obtaining the guest physical address, the Page Table Walker
    sends a second-stage translation request to the L2TLB. The L2TLB then
    returns the query result to the PTW.

For details, refer to the interface list documentation.

## Interface timing

The Page Table Walker interacts with other modules in the L2 TLB using a
valid-ready handshake. The involved signals are trivial, and there are no
particularly noteworthy timing relationships, so further details are omitted.
