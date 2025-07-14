# Uncache Load Handling Unit LoadQueueUncache

| Update time | Code Version                                                                                                                                                    | Updated by                                     | Notes                     |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- | ------------------------- |
| 2025.02.26  | [eca6983](https://github.com/OpenXiangShan/XiangShan/blob/eca6983f19d9c20aa907987dff616649c3d204a2/src/main/scala/xiangshan/mem/lsqueue/LoadQueueUncache.scala) | [Maxpicca-Li](https://github.com/Maxpicca-Li/) | Initial version completed |
|             |                                                                                                                                                                 |                                                |                           |

## Functional Description

For uncache load access requests, LoadQueueUncache and the Uncache module serve
as an intermediate station between the LoadUnit pipeline and bus access. The
Uncache module, being closer to the bus side, functions as described in
[Uncache](../Uncache.md "Uncache Handling Unit Uncache"). LoadQueueUncache, as
the pipeline-side component, is responsible for the following tasks:

1. Receives uncache load requests passed from the LoadUnit pipeline.
2. Select a ready uncache load request and send it to the Uncache Buffer.
3. Receives processed uncache load requests from the Uncache Buffer.
4. Returns the processed uncache load requests to the LoadUnit.

Structurally, the LoadQueueUncache currently has 4 entries (configurable in
number) of UncacheEntry, each independently responsible for a request and
utilizing a set of status registers to control its specific processing flow;
there is a FreeList managing the allocation and recycling of each entry. The
LoadQueueUncache primarily coordinates the overarching logic for new entry
allocation, request selection, response dispatch, dequeueing, etc., among the 4
entries.

### Feature 1: Enqueue Logic

LoadQueueUncache is responsible for receiving requests from LoadUnit 0, 1, and
2. These requests can be MMIO requests or NC requests. First, the system sorts
the requests by their robIdx in chronological order (oldest to newest) to ensure
the earliest requests are prioritized for allocation to free entries, avoiding
deadlocks caused by rollbacks of older entries under special circumstances. The
conditions for processing are: the request is not resent, has no exceptions, and
the system allocates entries sequentially from the FreeList's available free
entries to the requests.

When the LoadQueueUncache reaches its capacity limit and there are still
requests that have not been allocated entries, the system selects the earliest
unallocated request for rollback.

### Feature 2: Dequeue Logic

When an entry completes the Uncache access operation and is returned to the
LoadUnit, or is flushed due to a redirect, the entry is dequeued and the flag
for that entry in the FreeList is released. Multiple entries may be dequeued in
the same cycle. Requests returned to the LoadUnit are selected in the first
cycle and returned in the second cycle.

Among them, the LoadUnit ports available for handling uncache return requests
are pre-configured. Currently, MMIO only returns to LoadUnit 2; NC can return to
LoadUnit 1\2. In cases where multiple ports are available for returns, the
remainder of the uncache entry id divided by the number of ports is used to
specify which LoadUnit port each entry can return to, and an entry is selected
from the candidate entries of that port for return.

### Feature 3: Uncache interaction logic

(1) Send `req`

In the first cycle, select one from the currently ready uncache accesses, and in
the second cycle, send it to the Uncache Buffer. The sent request will mark the
selected entry's id, referred to as `mid`. Whether it is successfully received
can be determined by `req.ready`.

(2) Receives `idResp`

If the sent request is accepted by the Uncache Buffer, the Uncache's `idResp`
will be received in the next cycle after acceptance. This response includes
`mid` and the entry id (referred to as `sid`) allocated by the Uncache Buffer
for the request. The LoadQueueUncache uses `mid` to locate the corresponding
internal entry and stores `sid` in that entry.

(3) Receives `resp`

After the Uncache Buffer completes the bus access for the request, it returns
the access result to LoadQueueUncache. The response includes `sid`. Due to the
merging feature of the Uncache Buffer (detailed merging logic can be found in
[Uncache](../Uncache.md)), one `sid` may correspond to multiple entries in
LoadQueueUncache. LoadQueueUncache uses `sid` to locate all relevant internal
entries and passes the access result to them.

## Overall Block Diagram

<!-- 请使用 svg -->

![LoadQueueUncache Overall Block Diagram](./figure/LoadQueueUncache.svg)

## Interface timing

### Enqueue interface timing example

As shown in the diagram below, assume five consecutive NC requests enter through
LoadUnit 0\1\2 in sequence, and the current LoadQueueUncache has only four
entries. Therefore, the first four requests are normally allocated to the
available entries. The `r5` appearing in the third cycle cannot be allocated an
entry due to the buffer being full, resulting in a rollback in the fifth cycle.
Note that the diagram assumes each NC request enters in order per cycle, i.e.,
`r1` < `r2` < `r3` and `r4` < `r5`. If sorting is required, replace `io_req`
with the sorted results in sequence, while the rest of the logic remains the
same.

![LoadQueueUncache Enqueue Interface Timing
Diagram](./figure/LoadQueueUncache-timing-enq.svg)

<!-- 
{
  signal: [
    {name: 'clk',                       wave: 'p.....'},
    {name: 'io_req_0_valid',            wave: '01.0..'},
    {name: 'io_req_1_valid',            wave: '01.0..'},
    {name: 'io_req_2_valid',            wave: '010...'},
    {name: 'io_req_0_bits*robIdx*',     wave: 'x36x..', data: ['r1','r4']},
    {name: 'io_req_0_bits*robIdx*',     wave: 'x47x..', data: ['r2','r5']},
    {name: 'io_req_0_bits*robIdx*',     wave: 'x5x...', data: ['r3']},
    {},
    {name: 'freeList_io_doAllocate_0',  wave: '0.1.0.'},
    {name: 'freeList_io_doAllocate_1',  wave: '0.10..'},
    {name: 'freeList_io_doAllocate_2',  wave: '0.10..'},
    {},
    {name: 'io_rollback_valid',         wave: '0...10'},
    {name: 'io_rollback_bits*robIdx*',  wave: 'x...7x', data: ['r5']},
  
    // 先不绘制 freeList 和 Entry 的更新
    // {name: 'freeList_io_canAllocate_0',  wave: '01.0|.....'},
    // {name: 'freeList_io_canAllocate_1',  wave: '01.0|.....'},
    // {name: 'freeList_io_canAllocate_2',  wave: '01.0|.....'},
    // {name: 'freeList_io_allocateSlot_0', wave: 'x34x|.....', data: ['s1','s2']},
    // {name: 'freeList_io_allocateSlot_1', wave: 'x34x|.....', data: ['s1','s2']},
    // {name: 'freeList_io_allocateSlot_2', wave: 'x34x|.....', data: ['s1','s2']},
    // {name: 'entries_0_req_valid',        wave: '01.0|.....'},
    // {name: 'entries_1_req_valid',        wave: '01.0|.....'},
    // {name: 'entries_2_req_valid',        wave: '01.0|.....'},
    // {name: 'entries_3_req_valid',        wave: '01.0|.....'},
    // {name: 'entries_0_req_bits*robIdx*', wave: 'x34x|.....', data: ['s1','s2']},
    // {name: 'entries_1_req_bits*robIdx*', wave: 'x34x|.....', data: ['s1','s2']},
    // {name: 'entries_2_req_bits*robIdx*', wave: 'x34x|.....', data: ['s1','s2']},
    // {name: 'entries_3_req_bits*robIdx*', wave: 'x34x|.....', data: ['s1','s2']},
  ],
  config: { hscale: 1 },
  head: {
    text:'enq from LoadUnit',
    tick:1,
    every:1
  },
}
 -->

### Example of dequeue interface timing

The figure below illustrates scenarios with `mmioOut`, one `ncOut` per cycle,
and two `ncOut` per cycle. Using the first example for detailed explanation: in
cycle 2, the writeback entry is selected, and the freeList is updated. After
being held for one cycle, it is written back to the LoadUnit in cycle 3. The
subsequent examples follow the same logic.

![LoadQueueUncache Dequeue Interface Timing
Diagram](./figure/LoadQueueUncache-timing-writeback.svg)

<!-- 
{
  signal: [
    {name: 'clk',                 wave: 'p.............'},
    {name: 'io_mmioOut_2_valid',  wave: '0.10|.........'},
    {name: 'io_ncOut_1_valid',    wave: '0...|.10..|.10'},
    {name: 'io_ncOut_2_valid',    wave: '0...|...10|.10'},
    {},
    {name: 'freeList_io_free',    wave: 'x3x.|4x5x.|6x.', data: ['0b0001', '0b0010','0b0100', '0b1001']},
  ],
  config: { hscale: 2 },
  head: {
    text:'writeback to LoadUnit',
    tick:1,
    every:1
  },
}
 -->

### Uncache interface timing example

(1) When there are no outstanding requests, only one uncache access can be
issued per segment (controlled by `io_uncache_req_ready`) until the uncache
response is received. As shown in the figure, in cycle 5, `io_uncache_req_ready`
goes high, and the uncache request is issued. In cycle 6, the Uncache receives
the request and returns `idResp` in cycle 7. After some access time, the Uncache
access result is received in cycle 10+n.

![Timing Diagram of LoadQueueUncache and Uncache
Interface](./figure/LoadQueueUncache-timing-uncache.svg)

<!--
{
  signal: [
    {name: 'clk',                         wave: 'p.......|..'},
    {name: 'io_uncache_req_ready',        wave: '0...1...|..'},
    {name: 'io_uncache_req_valid',        wave: '01...0..|..'},
    {name: 'io_uncache_req_bits_id',      wave: 'x3...x..|..', data:['m1','m2','m3','m4']},
    {name: 'io_uncache_idResp_valid',     wave: '0.....10|..'},
    {name: 'io_uncache_idResp_bits_mid',  wave: 'x.....3x|..', data: ['m1', 'm2', 'm3', 'm4']},
    {name: 'io_uncache_idResp_bits_mid',  wave: 'x.....3x|..', data: ['s1', 's2', 's3', 's4']},
    {name: 'io_uncache_resp_valid',       wave: '0.......|10'},
    {name: 'io_uncache_resp_bits_id',     wave: '0.......|3x', data: ['s1', 's2']},
  ],
  config: { hscale: 1 },
  head: {
    text:'LSQ <=> Uncache',
    tick:1,
    every:1
  },
}
-->

(1) When there are outstanding requests, multiple uncache accesses can be issued
per segment (controlled by `io_uncache_req_ready`). As shown in the figure,
requests m1, m2, m3, and m4 are issued consecutively. In cycles 4 and 5, the
Uncache dispatch results for the first two requests are received. At this point,
the Uncache is full, m3 is held by the intermediate register, and m4 waits for
`io_uncache_req_ready` to go high. In cycle 9+n, `io_uncache_req_ready` goes
high, and m4 is also issued. The Uncache dispatch results for m3 and m4 are
received in cycles 10+n and 11+n, respectively. Subsequent cycles will receive
the Uncache access responses.

![Outstanding Timing Diagram of LoadQueueUncache and Uncache
Interface](./figure/LoadQueueUncache-timing-uncache-outstanding.svg)

<!--
{
  signal: [
    {name: 'clk',                         wave: 'p.....|。.......'},
    {name: 'io_uncache_req_ready',        wave: '01..0.|.10.....'},
    {name: 'io_uncache_req_valid',        wave: '01....|..0.....'},
    {name: 'io_uncache_req_bits_id',      wave: 'x3456.|..x.....', data:['m1','m2','m3','m4']},
    {name: 'io_uncache_idResp_valid',     wave: '0..1.0|..1.0...'},
    {name: 'io_uncache_idResp_bits_mid',  wave: 'x..34x|..56x...', data: ['m1', 'm2', 'm3', 'm4']},
    {name: 'io_uncache_idResp_bits_mid',  wave: 'x..34x|..56x...', data: ['s1', 's2', 's3', 's4']},
    {name: 'io_uncache_resp_valid',       wave: '0.....|....1010'},
    {name: 'io_uncache_resp_bits_id',     wave: 'x.....|....3x4x', data: ['s1', 's2']},
  ],
  config: { hscale: 1 },
  head: {
    text:'LSQ <=> Uncache when outstanding',
    tick:1,
    every:1
  },
}
-->

## UncacheEntry Module

UncacheEntry is responsible for independently managing the lifecycle of a
request and uses a set of state registers to control its specific processing
flow. Key structures are as follows:

* `req_valid`: Indicates whether the entry is valid.
* `req`: Stores all relevant content of the received request.
* `uncacheState`: Records the current lifecycle stage of this entry.
* `slaveAccept`, `slaveId`: Records whether the entry is allocated to the
  Uncache Buffer and the assigned Uncache Buffer ID.
* `needFlushReg`: Indicates whether the item needs delayed flushing.

### Feature 1: Lifecycle and State Machine

The lifecycle of each UncacheEntry can be fully described by `uncacheState`,
which includes the following states:

* `s_idle`: Default state, indicating no request or a request exists but is not
  yet ready to be sent to the Uncache Buffer.
* `s_req`: Indicates the request is now ready to be sent to the Uncache Buffer,
  awaiting selection by LoadQueueUncache and reception by its intermediate
  register (theoretically, it should be received by the Uncache Buffer, but
  after selection by LoadQueueUncache, the request is stored for one cycle
  before being sent to the Uncache Buffer; if not received by the Uncache
  Buffer, it remains in the intermediate register). For UncacheEntry, it is
  unaware of the intermediate register's existence—it only knows the request has
  been sent and successfully received.
* `s_resp`: Indicates that the request has been received by the intermediate
  register and is awaiting the access result from the Uncache Buffer.
* `s_wait`: Indicates the Uncache Buffer's access result has been received,
  awaiting selection by LoadQueueUncache and reception by LoadUnit.

The state transition diagram is as follows, where black indicates the normal
lifecycle of the item, and red indicates an abnormal termination of the item's
lifecycle due to a redirect requiring the item to be flushed.

![UncacheEntry Finite State Machine
Diagram](./figure/LoadQueueUncache-Entry-FSM.svg)

For the normal lifecycle, the triggering events are detailed as follows:

* `canSendReq`: For MMIO requests, when the corresponding instruction reaches
  the head of the ROB, the Uncache access can be sent. For NC requests, when
  `req_valid` is valid, the Uncache access can be sent.
* `uncacheReq.fire`: The entry is received by the LoadQueueUncache intermediate
  register. In the next cycle, it receives the `idResp` from the Uncache Buffer
  and updates `slaveAccept` and `slaveId`.
* `uncacheResq.fire`: The access result returned by the Uncache Buffer for this
  entry.
* `writeback`: When in the `s_wait` state, the writeback request can be sent.
  Note that the writeback signals for MMIO requests and NC requests differ and
  need to be distinguished.

### Feature 2: Redirect Flush Logic

For cases with abnormal lifecycles, they are typically triggered by pipeline
redirects.

Upon receiving a pipeline redirect signal, it checks whether the current entry
is newer than the redirected entry. If the current entry is newer, it needs to
flush the entry and generate the `needFlush` signal. Normally, the entry's
contents are flushed immediately, and the entry is reclaimed by the FreeList.
However, Uncache requests and responses must fully correspond to the same
uncache load request. Therefore, if the entry has already issued an uncache
request, its lifecycle can only be terminated upon receiving the Uncache
response, resulting in a "delayed flush" scenario. Hence, when the `needFlush`
signal is generated, if the entry cannot be flushed immediately, the signal must
be stored in the `needFlushReg` register. The flush operation is executed only
upon receiving the Uncache response, and the `needFlushReg` is cleared.

### Feature 3: Exception Cases

Exception cases in LoadQueueUncache include:

1. When the request is sent to the bus, the bus returns corrupt or denied. This
   exception needs to be flagged during UncacheEntry writeback and handled by
   the LoadUnit.
