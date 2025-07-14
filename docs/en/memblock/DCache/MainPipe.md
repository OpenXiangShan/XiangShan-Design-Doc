# Main Pipeline MainPipe

## Functional Description

Pipeline control manages Store, Probe, Refill, and atomic operations (i.e., all
instructions requiring contention for WritebackQueue to initiate
requests/writeback data to the lower-level cache).

### Feature 1: Functions Completed by Each Stage of the MainPipe Pipeline:

  * Stage 0: Arbitrate incoming MainPipe requests, selecting the one with the
    highest priority; determine whether the resources required by the request
    are ready based on the request information; issue tag and meta read
    requests.
  * Stage 1: Obtain tag and meta read request results; perform tag matching
    check to determine hit status; if replacement is needed, obtain
    PLRU-provided replacement selection; perform permission checks based on read
    meta; pre-determine if MissQueue access is required.
  * Stage 2: Obtain the read data result and combine it with the data to be
    written; if a miss occurs, attempt to write this request's information into
    MissQueue; check tag_error and l2_error.
  * Stage 3: Update meta, data, and tag based on the operation's results; return
    a store response to lsu if there's a hit; if the instruction requires
    accessing/writing back data to the lower-level cache, generate a
    WritebackQueue access request in this stage and attempt to write to
    WritebackQueue; check data_error; special support for atomic instructions:
    AMO instructions stay in this stage for two cycles, first completing the AMO
    instruction's operation, then writing the result back to dcache and
    returning a response; LR/SC instructions set/check their reservation set
    here.

### Feature 2: MainPipe Contention and Blocking

MainPipeline contention follows this priority: probe_req > refill_req >
store_req > atomic_req. A request is only accepted if all requested resources
are ready, there is no set conflict, and no higher-priority request exists.
Write requests from the committed store buffer have separate check logic due to
timing reasons.

### Feature 3: Set Blocking Logic

Ensuring parallel instructions do not simultaneously access different rows in
the same set maintains data consistency and correctness, preventing scenarios
where s3 (or s1, s2) processes data not yet written while s0 reads incorrect
data. Under valid conditions, MainPipe set conflicts compare s0 and s1, s0 and
s1, and s0 and s2 address indices. If they match, a set conflict is triggered,
blocking s0.

### Feature 4: Meta Update

Meta updates occur in s3. Among the four different types of requests in Main
Pipe, all require updating the corresponding cacheline's meta data in MainPipe.
These requests update via the meta_write port, but their specific behaviors
differ.

In stage s3, the Probe request generates the required meta_coh to be written
based on the probe_param parameter carried in the request, corresponding to the
permission modification intended by this Probe request.

For hit Store and AMO requests, the coh of the corresponding data block is
obtained in s1, and the new_coh after this access is generated in s2. In s3, the
two are compared to determine whether a meta write is needed. If a write is
required, it is updated to the new_coh generated in s2.

For requests that miss on the first attempt and subsequently re-enter MainPipe
via MissQueue backfill, in s3, the miss_new_coh required for updating during
this backfill access is generated based on the Acquire-related parameters
carried in the MissQueue backfill request, followed by meta writing.

### Feature 5: AMO Instruction Handling

After contending for priority, AMO requests enter MainPipe. In the first two
pipeline stages, their execution flow is largely consistent with other types of
instructions. In s1, they obtain tag and meta read request results, perform tag
matching checks and meta permission checks to determine whether amo_hit occurs,
deciding if the AMO request needs to enter MissQueue. If the current AMO request
misses the cache, its request information is written into MissQueue in s2; if it
hits, the read data result is obtained in s2, and the request proceeds to s3.
Upon entering s3, the AMO instruction stays in this stage for two cycles: the
first cycle performs the AMO instruction's operation, and the second cycle
writes the result modification back to dcache and returns a response to the
atomic instruction processing unit.

For LR/SC instructions, the reservation set is set/checked in the s3 stage, the
lrsc_count is updated to maintain execution correctness, preventing
interruptions or deadlocks during execution.

### Feature 6: MainPipe Writeback

MainPipe's writeback requests are initiated in s3. For instructions requiring
access/writeback to the lower-level L2 Cache, writeback requests are sent to the
WritebackQueue, which subsequently processes them to complete the actual write
to L2 Cache. There are three types of writeback requests in MainPipe.

For refill requests sent back by MissQueue, if the backfilled data requires
replacing a data block that is currently valid in dcache (not Nothing), this
data block needs to be released to L2 Cache. In s3, an attempt is made to write
it into wbq.

For Probe requests, a ProbeAck must be returned to the lower-level cache,
requiring a write request to wbq. If the probed data block contains dirty data,
it must be written back to the lower-level L2 Cache, replying with ProbeAckData,
which also requires sending a writeback request to wbq.

For miss AMO requests requiring writeback, the process is similar to the refill
flow. Miss AMO requests re-enter the MainPipe pipeline after refill. If the
refilled data block needs to replace a valid one, the latter must be released to
the lower-level cache, generating a writeback request to wbq in s3.

### Feature 7: MainPipe Backfill Data Exception Handling

Currently, all refill requests are initiated in advance by the MissQueue upon
receiving a hint signal to MainPipe. The refill data block is obtained via
refill_info forwarding when the request is processed to s2 in MainPipe. This may
lead to abnormal intervals between l2_hint and refill data, causing the request
to enter s2 without the corresponding MSHR forwarding valid refill data. For
such abnormal cases, the following two measures are taken.

To ensure the efficiency of backfilling and reduce the number of replays, the s2
stage allows an additional cycle of tolerance for delayed data arrival. When a
backfill request enters the s2 stage, if refill_info is found to be invalid
(s2_req_miss_without_data), it can be blocked for an additional cycle to wait
for the backfill data to arrive in the next cycle for subsequent processing.

If valid refill data is still not received after blocking for one cycle,
s2_replay_to_mq notifies the corresponding MSHR to resend the refill_req. The
current request exits MainPipe without further data operations.

In cases of cache aliasing and other special scenarios, a refill request may
need to replace a Cacheline that is currently in a valid MSHR, awaiting a
response to an L2 Acquire request. To ensure correctness and compliance with the
manual, this replacement operation cannot proceed. The refill request is also
notified via s2_replay_to_mq to resend the refill_req, and the current request
exits MainPipe without further data operations.

## Overall Block Diagram

The overall architecture of MainPipe is shown in [@fig:DCache-MainPipe].

![Schematic Diagram of MainPipe Accessing
DCache](./figure/DCache-MainPipe.svg){#fig:DCache-MainPipe}

## Interface timing

### Request Interface Timing Example

Interface timing is shown in [@fig:DCache-MainPipe-Timing]. req1 is a store
request: cycle 1 reads meta and tag, cycle 2 performs tag comparison and detects
a miss, cycle 3 sends the miss request to MissQueue, and cycle 4 does not return
a response to StoreBuffer due to the miss. req2 is a probe request: cycle 1
reads meta and tag, cycle 2 reads data, cycle 3 obtains probe data block
results, cycle 4 updates meta based on probe command, initiates a wb request to
WritebackQueue, and returns a probeAck response. req3 is an AMO instruction:
cycle 1 reads meta and tag, cycle 2 performs tag comparison and hits, issues a
data read request, cycle 3 obtains data results, cycles 4 and 5 are in stage_3,
with cycle 4 executing the instruction operation and cycle 5 issuing a data
write to update the original data block content and returning a response to
AtomicsUnit. req4 is the refill request for req1: cycle 1 reads meta, but req2
is writing meta (metaArray write takes priority over read), so req4 stalls in
stage_0 for one cycle; cycle 3 (stage_1) reads data and obtains PLRU replacement
selection, but req3 is writing data, so it stalls again in stage_1; cycle 5
(stage_2) obtains the data block to be replaced and refill data forwarded from
MissQueue; cycle 6 (stage_3) initiates a wb request to WritebackQueue to queue
the replacement block, writes the refill data to storage, and returns a refill
completion response to MissQueue.


![MainPipe
Timing](./figure/DCache-MainPipe-Timing.svg){#fig:DCache-MainPipe-Timing}
