# A Channel Request Buffer RequestBuffer

## Functional Description
- Request Buffer is used to temporarily buffer A channel requests that need to
  be blocked, while allowing A channel requests that meet release conditions/do
  not require blocking to enter the main pipeline first.
- Request Buffer prevents A requests that need to be blocked from clogging the
  pipeline entrance, thereby avoiding impact on subsequent requests and
  improving cache processing efficiency.
- If a newly arrived Acquire request shares the same address as a prefetch
  request being processed in the MSHR, the requests can be merged. The Acquire
  information is directly passed to the corresponding MSHR, allowing the MSHR to
  reply to the L1 Acquire upon completion. This accelerates the processing of
  the Acquire request and reduces the occupancy of the ReqBuf and MSHR.

### Feature 1: Request Merging
When the RequestBuffer receives an Acquire request that shares the same address
as a prefetch request in an MSHR entry, the RequestBuffer sends a merged request
(aMergeTask) to the corresponding MSHR entry. This MSHR entry will be marked as
mergeA, and its relevant fields will be updated.

### Feature 2: Request Acceptance Conditions
Under what conditions are requests at the RequestBuffer entrance allowed to be
accepted:
- RequestBuffer is not full
- RequestBuffer is full, but Acquire requests can merge with preceding prefetch
  requests
- The RequestBuffer is full, but the request is a prefetch request, and there is
  already an Acquire/Prefetch request being processed by the MSHR.

### Feature 3: Allocation of RequestBuffer
Which requests will allocate RequestBuffer:
- RequestBuffer is not full
- Cannot directly flow into the pipeline (i.e., address conflict with MainPipe
  or an MSHR entry) or chosenQ is also ready to issue
- Cannot perform request merging

### Feature 4: Fields in RequestBuffer Entries
- Rdy: Whether it is ready to be issued/dequeued.
- Task: Information about the request itself
- WaitMP: Blocked by which stages of the MainPipe pipeline
- WaitMS: Blocked by which MSHR entries

### Feature 5: How RequestBuffer Updates and Issues
- WaitMP (4-bit): Since the MainPipe is a non-blocking pipeline, waitMP shifts
  right by one bit each cycle. Simultaneously, it checks every cycle for new
  address-conflicting requests in s1 [3] s1, same set conflict [2] s2, same set
  conflict [1] s3, same set conflict [0] reserved.
- WaitMS (16-bit): The corresponding bit in waitMS is reset one cycle before the
  MSHR entry is released; meanwhile, when a new MSHR entry is allocated, address
  conflicts (same set and tag) are checked, and if present, the corresponding
  bit in waitMS is set One-hot encoding, each bit represents an MSHR
- noFreeWay: Since replacements may occur for the same set, when [the number of
  same-set entries in MSHR + the number of same-set entries in pipeline stages
  S2/S3 >= L2 ways], it indicates that all ways of the same set may be replaced.
  In this case, the RequestBuffer is blocked from entering the pipeline. (s2 +
  s3 + MSHR >= ways(L2))
- Ready Condition: rdy is high when all the following conditions are met,
  indicating it can be issued into the pipeline to enter RequestArbiter waitMP +
  waitMS are all cleared noFreeway is low The A/B channel requests about to
  enter the pipeline's s1 stage have no set conflict

## Overall Block Diagram
![RequestBuf](./figure/RequestBuf.svg)
