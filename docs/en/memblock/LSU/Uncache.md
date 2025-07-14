# Uncache Handling Unit Uncache

| Update time | Code Version                                                                                                                                            | Updated by                                     | Notes                     |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- | ------------------------- |
| 2025.02.26  | [eca6983](https://github.com/OpenXiangShan/XiangShan/blob/eca6983f19d9c20aa907987dff616649c3d204a2/src/main/scala/xiangshan/cache/dcache/Uncache.scala) | [Maxpicca-Li](https://github.com/Maxpicca-Li/) | Initial version completed |
|             |                                                                                                                                                         |                                                |                           |

## Functional Description

The Uncache serves as a bridge between the LSQ and the bus, primarily handling
uncache access requests and responses to the bus. Currently, the Uncache does
not support vector accesses, unaligned accesses, or atomic accesses.

The functional overview of Uncache is as follows:

1. Receives uncache requests from LSQ, including uncache load requests from
   LoadQueueUncache and uncache store requests from StoreQueue.
2. Selecting a pending uncache request to send to the bus and waiting for the
   bus response
3. Return the processed uncache request to LSQ
4. Forwarding the registered uncache store request data to the load being
   executed in LoadUnit

In the Uncache Buffer structure, there are currently 4 entries (configurable)
for Entries and States, along with a global state `uState`. Below are the
specific details for each entry.

The structure of an Uncache Entry is as follows:

* `cmd`: Identifies whether the request is a load or store. In the current
  version, 0 indicates load and 1 indicates store.
* `addr`: Physical address of the request.
* `vaddr`: The virtual address of the request. Mainly used to determine
  virtual-physical address matches during forwarding.
* `data`: Stores the data to be written or the data to be read for load
  operations. Currently, only data accesses within 64 bits are supported.
* `mask`: The access mask for the request, with each byte represented by one bit
  to indicate whether data is present, totaling 8 bits.
* `nc`: Indicates whether the request is an NC (Non-Cacheable) access.
* `atomic`: Indicates whether the request is an atomic access.
* `memBackTypeMM`: Indicates whether the requested address is of PMA type main
  memory but PBMT type NC. Primarily used for L2 Cache NC-related logic.
* `resp_nderr`: The bus indicates whether the request can be processed as
  Uncache.

The State structure of the Uncache is as follows:

* `valid`: Indicates whether the entry is valid.
* `inflight`: 1 indicates the request has been sent to the bus.
* `waitSame`: 1 indicates that there are other requests in the current buffer
  that overlap with the data block accessed by this request and have already
  been sent to the bus.
* `waitReturn`: 1 indicates the request has received a bus response and is
  waiting to write back to LSQ.

Uncache's `uState`, representing the various states of a request entry when
ignoring outstanding:

* `s_idle` Default state
* `s_inflight`: Indicates that a request has been sent to the bus but no
  response has been received yet.
* `s_wait_return` has received a response but has not yet returned it to the LSQ

State transitions are as follows:

![ustate state transition diagram](./figure/Uncache-uState.svg)

### Feature 1: Enqueue Logic

(1) Each cycle processes at most one request from the LSQ, then checks if the
request can enter the Buffer. If it can, it further checks whether to merge it
with an existing entry or allocate a new one. The enqueue behavior for this
request includes:

1. Allocate a new entry, mark it as valid

   1. No entry with the same block address
2. Allocate a new entry, mark it as valid and waitSame

   1. Entries with the same block address: Meet the primary merging condition
      but not the secondary merging condition.
3. Merge into existing entry

   1. Entry with the same block address: Meets the primary merging condition and
      the secondary merging condition.
4. Reject

   1. ubuffer full
   2. Entries with the same block address: Primary merging condition not met

Here, block address (blockAddr) refers to the starting address of every 8 bytes.
The primary merging condition means both the incoming and existing entries are
NC accesses, share identical attributes, the merged mask is contiguous and
naturally aligned, and the entry has not **initiated or completed** a bus access
in the current cycle. The secondary merging condition requires the existing
entry to be valid, not yet sent for bus access, and not selected for bus access
in the current cycle (since once a bus request is initiated or completed, it
cannot be altered, necessitating a new entry allocation to wait for the existing
request to complete before sending the new one).

Additionally, allocating a new entry will set all contents of the entry; merging
into an existing entry will update mask, data, addr, etc. The addr update must
ensure natural alignment.

> Due to potential non-sequential bus access, especially during outstanding
> operations, multiple uncache access requests may be processed simultaneously
> on the bus. Thus, requests with the same address cannot coexist on the bus to
> ensure sequential access to the data block. Therefore, a new entry can only
> merge with an older one if it meets both primary and secondary merging
> conditions.

(2) In the next cycle, return the allocated Uncache Buffer entry ID. This ID is
held by LoadQueueUncache or StoreQueue to map the uncache response. Since the
Uncache Buffer supports merging, its returned response may correspond to
multiple entries in LoadQueueUncache.

### Feature 2: Dequeue Logic

From entries that have completed bus access in the current cycle (i.e., those
with `valid` and `waitReturn` set in the high bits of their state), select one
to return to LSQ and clear all state flags.

### Feature 3: Bus interaction and outstanding logic

Bus interaction and outstanding logic are divided into two parts:

(1) Initiate request

Without outstanding, requests can only be sent to the bus when `ustate` is
`s_idle`. Select one request from the entries that is currently eligible for bus
transmission, i.e., only the `valid` status bit is set to 1, and send it to the
bus. With outstanding, requests can be selected and sent to the bus regardless
of `ustate`, where `source` indicates the request entry's ID.

When a request is sent to the bus, it is necessary to traverse the request
entries and set the `waitSame` flag for other entries with the same block
address.

(2) Upon receiving a response

When a bus response is received, the corresponding buffer entry is determined
based on the `source` bits, and the data is updated with the `waitReturn` flag
set.

Additionally, it is necessary to traverse the request entries and clear any
`waitSame` with the same block address.

### Feature 4: Forwarding logic

Theoretically, the forwarding logic primarily targets NC accesses. When
outstanding is enabled, once an uncache NC store successfully writes from the
StoreQueue into the Uncache Buffer, the StoreQueue dequeues that entry and no
longer maintains it. Hence, the Uncache Buffer assumes responsibility for
forwarding the store data. Due to the merging logic in the Uncache Buffer's
enqueue process, the same address can appear in at most 2 entries
simultaneously. If there are 2 entries, one must be `inflight` and the other
`waitSame`. Because the StoreQueue dequeues in order, the former contains older
data while the latter has newer data.

In actual processing, when an uncache NC load initiates a forwarding request to
the Uncache Buffer, the Uncache compares the block addresses of existing
entries. A matching entry may be found, which could either be one already sent
to the bus or one yet to be sent. The former contains older data, while the
latter has newer data with higher priority. In the first cycle `f0`, virtual
block address matching is primarily performed to return `forwardMaskFast` within
the same cycle. In the second cycle `f1`, physical block address matching and
data merging are performed, and the result is returned.

### Feature 5: Flush logic

Flushing refers to completing all bus accesses for entries in the Uncache Buffer
and returning them to the LSQ before accepting new entries. The Uncache Buffer
is flushed when a fence, atomic, or cmo operation occurs, or when a forwarding
request results in a virtual-physical address mismatch. At this time,
`do_uarch_drain` is set, and no new entries are accepted. Once all entries have
completed their tasks, `do_uarch_drain` is cleared, and the buffer resumes
normal operation to accept new entries.

## Overall Block Diagram

<!-- 请使用 svg -->

![Overall Block Diagram of ubuffer](./figure/Uncache.svg)

## Interface timing

### LSQ Interface Timing Example

The figure below shows a detailed interface example with four uncache accesses.
Before the 5th cycle, m1, m2, and m3 are received sequentially, and `idResp` is
returned in the cycle following their request initiation. By the 6th cycle, the
Uncache is full, and m4 is stalled. By the 9+n cycle, all accesses for s1 are
completed and written back, freeing one entry. Thus, in the 10+n cycle,
`io_lsq_req_ready` is asserted, and m4 is accepted. Subsequent cycles gradually
write back other uncache access requests. ![Schematic of Uncache and LSQ
Interface Timing](./figure/Uncache-timing-with-lsq.svg)

<!--
{
  signal: [
    {name: 'clk',                     wave: 'p......|.......'},
    {name: 'io_lsq_req_valid',        wave: '0101...|..0....'},
    {name: 'io_lsq_req_ready',        wave: '1....0.|.1.....'},
    {name: 'io_lsq_req_bits_id',      wave: 'x3x456.|..x....', data:['m1','m2','m3','m4']},
    {name: 'io_lsq_idResp_valid',     wave: '0.101.0|..10...'},
    {name: 'io_lsq_idResp_bits_mid',  wave: 'x.3x45x|..6x...', data: ['m1', 'm2', 'm3', 'm4']},
    {name: 'io_lsq_idResp_bits_sid',  wave: 'x.3x45x|..5x...', data: ['s1', 's2', 's3', 's4']},
    {name: 'io_lsq_resp_valid',       wave: '0......|10.1010'},
    {name: 'io_lsq_resp_bits_id',     wave: 'x......|3x.4x5x', data: ['s1', 's2', 's3']},
  ],
  config: { hscale: 1 },
  head: {
    text:'LSQ <=> Uncache',
    tick:1,
    every:1
  },
}
-->

### Bus interface timing example

(1) When there are no outstanding requests, only one uncache request can be
issued per segment (controlled by `uState` for outflow regulation). Another
uncache request can only be initiated after receiving a response on the d
channel. ![Uncache Interface Timing Diagram with
Bus](./figure/Uncache-timing-with-bus.svg)

<!-- 
{
  signal: [
    {name: 'clk',                           wave: 'p..|.....|...'},
    {name: 'auto_client_out_a_ready',       wave: '1..|.....|...'},
    {name: 'auto_client_out_a_valid',       wave: '010|...10|...'},
    {name: 'auto_client_out_a_bits_source', wave: 'x3x|...4x|...', data: ['s1','s2']},
    {name: 'auto_client_out_d_valid',       wave: '0..|10...|10.'},
    {name: 'auto_client_out_d_bits_source', wave: 'x..|3x...|3x.', data: ['s1', 's2']},
  ],
  config: { hscale: 1 },
  head: {
    text:'Uncache <=> Bus',
    tick:1,
    every:1
  },
}
 -->

(2) When there are outstanding requests, multiple uncache accesses can be issued
per segment (controlled by `auto_client_out_a_ready` for outflow rate). As shown
in the figure below, two requests are issued consecutively in cycles 2 and 3,
and the access results are received in cycles 6+n and 8+n.

![Schematic of Uncache and Bus Interface Timing During Outstanding
Operations](./figure/Uncache-timing-with-bus-outstanding.svg)

<!-- 
{
  signal: [
    {name: 'clk',                           wave: 'p..|......'},
    {name: 'auto_client_out_a_ready',       wave: '1..|......'},
    {name: 'auto_client_out_a_valid',       wave: '01.0|.....'},
    {name: 'auto_client_out_a_bits_source', wave: 'x34x|.....', data: ['s1','s2']},
    {name: 'auto_client_out_d_valid',       wave: '0...|1010.'},
    {name: 'auto_client_out_d_bits_source', wave: 'x...|3x4x.', data: ['s1', 's2']},
  ],
  config: { hscale: 1 },
  head: {
    text:'Uncache <=> Bus when outstanding',
    tick:1,
    every:1
  },
}
 -->
