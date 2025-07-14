\newpage
# Store Commit Buffer (SBuffer)

## Functional Description

Each entry in the sbuffer is a cacheline, with each cacheline being 64 bytes (4
vwords, where each vword is 16 bytes).

Each byte is indicated by a single-bit mask to show whether it currently
contains data.

Meta information includes ptag, vtag, state, cohCount, and missqReplayCount,
with specific functions as follows:

* ptag: Physical address tag, the remaining part of the physical address
  excluding the cacheline offset.

* vtag: Virtual address tag, the remaining part of the virtual address excluding
  the cacheline offset.

* state: Status, indicating the current state of the entry.
    * state_valid: Indicates whether the entry is valid.
    * state_inflight: Indicates that the entry has sent a write request to the
      dcache but has not yet received a response, or the dcache responded with a
      miss.
    * w_timeout: The request sent to the dcache missed and is waiting to be
      resent.
    * w_sameblock_inflight: There are other entries with the same cache block
      address as this entry. The other entries are already inflight, while the
      current entry has just been allocated and needs to wait for the others to
      complete the dcache writeback.

* cohCount: A counter that increments from 0 to 1M before writing the entry to
  the dcache.

* missqReplayCount: A counter that increments from 0 to 16 when a previously
  sent request to the dcache results in a miss, after which the entry is resent
  to the dcache.

### Feature 1: Enqueue logic of the sbuffer

* Each cycle can process up to two requests from the StoreQueue. It then checks
  if the requests require allocation of new entries. If both need new entries,
  two free entries are selected based on odd-even allocation. If the two
  requests share the same ptag, they are allocated to the same free entry.

* If an entry with the same cacheline already exists, there is no need to
  allocate a new entry; the data can be merged into the existing one. However,
  if the same cacheline has already been sent to the dcache (state_inflight is
  true), merging is not allowed, and a new entry must be allocated. The new
  entry must also record its dependency on the inflight entry (by setting
  w_sameblock_inflight to true and waitInflightMask to the inflight entry's ID).
  This dependency ensures that the new entry can only be written to the dcache
  after the inflight entry has been processed, maintaining store order.

* Set the state bit of this entry to valid.

* When a request enters the sbuffer for merging, if this entry happens to be
  selected for writing to the dcache, the dcache write must be blocked until the
  merge is completed before proceeding with the write.

### Feature 2: Dequeue logic of the sbuffer

* Entries in the sbuffer are written to the dcache under both passive and active
  conditions.
    * Passive: The number of entries in the sbuffer reaches the threshold,
      requiring replacement.
    * Active: Signals to flush the sbuffer from the atomicsUnit and fenceUnit,
      or when a tag mismatch occurs during merging or forwarding to a load, or
      when a previously missed request is resent.

* Exiting the sbuffer takes two cycles: the first cycle selects and latches the
  entry to be written to the dcache, and the second cycle sends the write
  request to the dcache.

### Feature 3: Writing sbuffer data

When a request arrives at the sbuffer, it either allocates a new entry or merges
into an existing one. Writing data and mask is done in two cycles: the first
cycle latches the request, and the second cycle writes the data based on the
request's mask (sb, sh, sw, sd) and sets the corresponding mask (a signal
indicating whether a specific byte in the cache line is valid).

For example: When request S0 arrives at the sbuffer, S0 performs judgment logic
and determines that the request can be merged into an existing entry, which is
the 2nd entry. A one-hot write encoding of 16'b0000000000000100 is generated.
Using this write encoding, the write signal for the 2nd entry is produced,
latched to S1, and the write address (e.g., cache block offset 0), mask (e.g.,
sw, writing 4 bytes), and data from S0 are latched to S1. S1 then uses the
information latched from S0 to assert the write signal for the lower 4 bytes of
the 0th word in the 2nd entry, writes the corresponding data, and asserts the
mask write signal for the lower 4 bytes of the 0th word, setting it to true.

### Feature 4: Forwarding logic of the sbuffer

* A load operation needs to find data from a store that precedes it, which could
  be in the store queue, the sbuffer, or already written to the cache.

* When searching in the sbuffer, it compares the tags of existing entries. It
  may find a matching entry, which could be one that has not yet sent a request
  to the dcache or one that has already sent a request but not yet completed.
  The entry that has not yet sent the request is the latest, so it has higher
  priority, and the matched data is forwarded to the load.

As shown in the figure below, the forwarding query request matches both the 0th
and 15th entries in the sbuffer simultaneously. The data in the 0th entry is the
latest, while the 15th entry is outdated. Therefore, the priority of the 0th
entry is higher than the 15th entry in the forwarding result.

![Forwarding diagram of the sbuffer](./figure/sbuffer-forward.svg)

## Overall Block Diagram
<!-- 请使用 svg -->

![Overall block diagram of the sbuffer](./figure/sbuffer.svg)

## Interface timing

### Example of timing for receiving store instruction writes

When io_in_*_valid and io_in_*_ready handshake, the sbuffer receives a write
request from the storeQueue. The address is used to check whether to allocate a
new entry or merge into an existing one, and the io_in_*_bits information is
used to update the entry.

![Timing diagram for receiving store instruction
writes](./figure/sbuffer-stin.svg)

### Timing example of writing to dcache

When io_dcache_req_ready and io_dcache_req_valid handshake, the
io_dcache_req_bits_* signals are passed to the dcache, forwarding the request
for the dcache to process.

![Timing of writing to dcache](./figure/sbuffer-en-dcache-timing.svg)

### Forwarding request timing example

Forwarding requests do not require a ready signal. Once io_forward_*_valid is
high, the request must be processed. The request's paddr and varddr are used for
the query, and the data and other information are valid in the next cycle after
io_forward_*_valid goes high.

![Forwarding Request Timing](./figure/sbuffer-fwdtiming.svg)
