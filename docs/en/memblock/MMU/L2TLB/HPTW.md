
# Level-3 Module: Hypervisor Page Table Walker

Hypervisor Page Table Walker refers to the following module:

* HPTW hptw

## Design Specifications

1. Supports accessing the three-level page table of G-stage
2. Supports sending requests to memory
3. Supports sending refill signals to the Page Cache
4. Support for exception handling
5. Bypass special handling

## Function

### Supports accessing the three-level page table of G-stage

The overall design of HPTW is fundamentally the same as PTW, capable of
processing only one request at a time. HPTW can perform a complete second-stage
translation of the three-level page table. If memory access is required during
translation, it will perform PMP checks on the memory access address. If an
error is detected, it returns immediately; otherwise, it sends a memory access
request. The scenarios in which HPTW returns include:

1. Accessing a leaf node
2. A pagefault or accessfault occurs during access

### Supports sending requests to memory

Similar to PTW and LLPTW, HPTW needs to send requests to memory when accessing
page tables, which are sent through an arbiter.

### Send a refill signal to the Page Cache

After receiving the result from PTW, HPTW sends a refill request to the Page
Cache to fill in the returned page table entry. HPTW provides the information
required for filling the Page Cache.

### Exception Handling Mechanism

When a pagefault or accessfault exception occurs, HPTW will directly return to
PTW or LLPTW.

### Bypass special handling

For bypass requests, they are generally placed in the MissQueue for re-querying.
However, for hptw requests (i.e., when isHptwReq is valid), they are not placed
in the MissQueue (to avoid blocking). Therefore, when a bypass request occurs,
to prevent duplicate page table entries from being filled into the Page Cache,
if the bypass signal is valid when the hptw request is passed to HPTW, the
result returned by memory will not refill the Page Cache.

## Overall Block Diagram

The state transition diagram of HPTW is shown in [@fig:HPTW-states].

![Hypervisor Page Table Walker state machine transition
diagram](../figure/image43.jpeg){#fig:HPTW-states}

The descriptions of each state in the state machine are as follows:

* idle: The initial state of the Hypervisor Page Table Walker state machine.
  Upon receiving a PTW request, it transitions to the pmp_check state.
* pmp_check: In this state, the physical address to be accessed is sent to the
  PMP module for PMP and PMA checks, transitioning to the mem_req state in the
  next cycle. The PMP module must return the physical address check result for
  access faults within the same cycle.
* mem_req: Based on the PMP and PMA check results, if an access fault is
  detected, it transitions to the check_pte state; otherwise, it sends a request
  to memory. In the mem_req state, it continues to wait until the handshake with
  memory is successful, indicating the request has been sent, and then
  transitions to the mem_resp state.
* mem_resp: In the mem_req state, the Hypervisor Page Table Walker has sent a
  PTW request to memory. In the mem_resp state, the Hypervisor Page Table Walker
  waits for a response from memory. Upon receiving the memory response and
  successfully handshaking with memory, it transitions to the check_pte state.
* check_pte: This state evaluates the current query situation to determine the
  next operation. The scenarios handled in this state include:
    1. In case of accessfault or pagefault, it returns to PTW or LLPTW.
    2. If the page table returned by memory is a leaf node, it is directly
       returned to PTW or LLPTW.
    3. If it is not a leaf node, the physical address is sent to the PMP module
       for PMP&PMA checks, and the state transitions to mem_req, repeating the
       process described above.

## Interface timing

Similar to PTW, no further elaboration is provided.
