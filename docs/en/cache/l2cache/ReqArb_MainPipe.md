# Request Arbiter and Main Pipeline {#sec:reqarb-mainpipe}

The request arbiter and memory access pipeline form the overall five-stage
pipeline of CoupledL2, referred to in order as the first stage ```s1```, the
second stage ```s2```, the third stage ```s3```, the fourth stage ```s4```, and
the fifth stage ```s5```. Among them, the request arbiter ReqArbiter mainly
constitutes ```s1``` and ```s2```, while the main pipeline MainPipe mainly
constitutes ```s3```, ```s4```, and ```s5```.

## S0 pipeline stage

```s0``` is only located within the request arbiter ReqArbiter and does not
count as a separate pipeline stage. ```s0``` is only used to generate
backpressure signals for each MSHR entry. ReqArbiter will prevent tasks from
leaving MSHR and entering the pipeline under the following conditions:

- In the previous cycle, there was an MSHR task requiring Directory read that
  was blocked
- There is a blocking signal from GrantBuffer
- There is a blocking signal from upstream TileLink C channel
- There is a blocking signal from the downstream TXDAT channel
- There is a blocking signal from the downstream TXRSP channel
- There is a blocking signal from the downstream TXREQ channel.

## S1 pipeline stage

```s1``` is only located within the request arbiter ReqArbiter.

In ```s1```, arbitration is performed for the following request sources:

- MSHR
- Upstream TileLink C channel
- Upstream TileLink B channel
- Upstream TileLink A channel

In the above list, the request source at the top has the highest priority. When
they simultaneously enter ReqArbiter's ```s1```, the one with the highest
priority is selected for handshake, while other task sources are blocked.
Specifically, MSHR tasks have the highest priority, followed by the upstream
TileLink C channel, upstream TileLink B channel, and upstream TileLink A
channel.

At ```s1```, ReqArbiter must also consider the blocking signals from MainPipe.
Additionally, the request can only leave ```s1``` when ready at ```s2```;
otherwise, the request is blocked and stored at ```s1```.

After arbitration is completed, a read request is sent to Directory at ```s1```.


## S2 pipeline stage

```s2``` is located within the Request Arbiter ReqArbiter and the Main Pipeline
MainPipe.

Due to frequency limitations of CoupledL2's SRAM, a Multi-Cycle Path 2 (MCP2) is
adopted, meaning each SRAM read/write request must last at least two cycles.
Therefore, at ```s2```, ReqArbiter will block all back-to-back requests for one
cycle to ensure the hold time and request intervals on MainPipe comply with MCP2
requirements.

ReqArbiter decides at ```s2``` whether to read the ReleaseBuffer or RefillBuffer
and sends a read request to the ReleaseBuffer or RefillBuffer at ```s2```.

Under any of the following conditions, ReqArbiter will send a read request to
RefillBuffer at ```s2```:

1. This task is triggered by a replacement task, causing downstream cache line
   write-back and eviction (at this point, the write-back data is no longer
   needed, and the replacement-read data is written into DataStorage).
2. This task is an upstream TileLink A channel request but does not use the data
   from the upstream Probe response (if it uses the data from the upstream Probe
   response, it should read from the ReleaseBuffer).

Under any of the following conditions, ReqArbiter will send a read request to
ReleaseBuffer at ```s2```:

1. The task is an MSHR task, and downstream requests need to read data from
   upstream Probe responses
2. This task is an MSHR task, and the upstream TileLink A channel request
   requires the data from the upstream Probe response.
3. The task is not an MSHR task, and downstream Snoop and downstream writeback
   request tasks are nested

ReqArbiter sends tasks into MainPipe at ```s2```.

MainPipe will generate a blocking signal for ```s1``` at ```s2``` and send it
back to ReqArbiter and RequestBuffer. MainPipe needs to send blocking signals to
various components and channels under the following circumstances:

- If it cannot be determined that the task will definitely not perform a write
  operation to the Directory when it reaches ```s2```, a signal to block
  requests of the same Set is sent to the RequestBuffer.
- If it cannot be determined that a task will definitely not perform a write
  operation to Directory when it reaches ```s2```, a signal is sent to
  ReqArbiter to block MSHR requests of the same Set.
- If it cannot be determined that the task will definitely not perform a write
  operation to the Directory when it reaches ```s2```, a signal is sent to
  ReqArbiter to block upstream TileLink C channel requests of the same Set
- When the task reaches ```s2``` (as well as ```s3```, ```s4```, ```s5```, i.e.,
  all tasks still in the MainPipe, which will not be reiterated in subsequent
  sections), a signal is sent to ReqArbiter to block downstream RXSNP channel
  requests with the same address.

## S3 pipeline stage

```s3``` is only located within the MainPipe pipeline. Most of the request
judgment, distribution logic, and interactions with other modules are located in
the ```s3``` stage.


### Cache line state collection

The read request issued by ReqArbiter to the Directory at ```s1``` can obtain
the read result at ```s3```. If a request from the downstream RXSNP channel
results in nesting with an MSHR, i.e., the address of the downstream Snoop
request matches that of an outstanding MSHR, the cache line state from that MSHR
entry will override the Directory read result.

### MSHR allocation

MainPipe allocates an MSHR at ```s3``` when one of the following conditions is
met:

1. The task originates from the upstream TileLink A channel
    - Acquire*, Hint, Get requests miss the cache line
    - Acquire* toT cache line hit in BRANCH state
    - CBO* class CMO requests
    - Alias replacement request
    - Any task that needs to send a Probe request upstream
        - A Get request hits a cache line in TRUNK state that exists in the
          upstream L1.
        - A CBOClean request hits a cache line in TRUNK state that exists in the
          upstream L1.
        - The cache line hit by a CBOFlush request exists in the upstream L1
        - The cache line hit by the CBOInval request exists in the upstream L1
2. Tasks originate from the downstream RXSNP channel
    - Snoop hits the corresponding cache line state for the corresponding type.
    - Forwarding Snoop with cache line hit

For non-Forwarding Snoop type Snoop requests from downstream, the conditions
requiring MSHR allocation are listed below:

| Snoop Request Type  | Hit status | Exists in L1 |
| ------------------- | ---------- | ------------ |
| SnpOnce             | TRUNK      | Yes          |
| SnpClean            | TRUNK      | Yes          |
| SnpShared           | TRUNK      | Yes          |
| SnpNotSharedDirty   | TRUNK      | Yes          |
| SnpUnique           | -          | Yes          |
| SnpCleanShared      | TRUNK      | Yes          |
| SnpCleanInvalid     | -          | Yes          |
| SnpMakeInvalid      | -          | Yes          |
| SnpMakeInvalidStash | -          | Yes          |
| SnpUniqueStash      | -          | Yes          |
| SnpStashUnique      | TRUNK      | Yes          |
| SnpStashShared      | TRUNK      | Yes          |
| SnpQuery            | TRUNK      | Yes          |

### Directory write

MainPipe will send a write request to the Directory at ```s3``` as required by
the task.

### DataStorage read/write

MainPipe will send read or write requests to DataStorage at ```s3``` according
to task requirements.

### Request and message distribution

MainPipe will send requests to one of the following channel directions at
```s3``` according to task requirements:

- Upstream TileLink D channel
- Downstream TXREQ channel
- Downstream TXRSP channel
- Downstream TXDAT channel

The specific distribution direction is determined by the task itself. For
details, refer to [@sec:mshr] [MSHR](MSHR.md).

### Snoop Request Processing

Snoop requests from downstream may not allocate an MSHR but directly complete
the response action in MainPipe. The state transition of Snoop requests is
determined at ```s3``` in MainPipe. Snoop requests occurring at ```s3``` and
their corresponding state transitions are as follows:

| Snoop Request Type    | Initial state | Final State | RetToSrc | Snoop reply                |
| --------------------- | ------------- | ----------- | -------- | -------------------------- |
| SnpOnce               | I             | I           | X        | SnpResp_I                  |
|                       | UC            | UC          | X        | SnpRespData_UC             |
|                       | UD            | UD          | X        | SnpRespData_UD_PD          |
|                       | SC.           | SC.         | 0        | SnpResp_SC                 |
|                       |               |             | 1        | SnpRespData_SC             |
| SnpClean,             | I             | I           | X        | SnpResp_I                  |
| SnpShared,            | UC            | SC.         | X        | SnpResp_SC                 |
| SnpNotSharedDirty     | UD            | SC.         | X        | SnpRespData_SC_PD          |
|                       | SC.           | SC.         | 0        | SnpResp_SC                 |
|                       |               |             | 1        | SnpRespData_SC             |
| SnpUnique             | I             | I           | X        | SnpResp_I                  |
|                       | UC            | I           | X        | SnpResp_I                  |
|                       | UD            | I           | X        | SnpRespData_I_PD           |
|                       | SC.           | I           | 0        | SnpResp_I                  |
|                       |               |             | 1        | SnpRespData_I              |
| SnpCleanShared        | I             | I           | 0        | SnpResp_I                  |
|                       | UC            | UC          | 0        | SnpResp_UC                 |
|                       | UD            | UC          | 0        | SnpRespData_UC_PD          |
|                       | SC.           | SC.         | 0        | SnpResp_SC                 |
| SnpCleanInvalid       | I             | I           | 0        | SnpResp_I                  |
|                       | UC            | I           | 0        | SnpResp_I                  |
|                       | UD            | I           | 0        | SnpRespData_I_PD           |
|                       | SC.           | I           | 0        | SnpResp_I                  |
| SnpMakeInvalid        | -             | I           | 0        | SnpResp_I                  |
| SnpMakeInvalidStash   | -             | I           | 0        | SnpResp_I                  |
| SnpUniqueStash        | I             | I           | 0        | SnpResp_I                  |
|                       | UC            | I           | 0        | SnpResp_I                  |
|                       | UD            | I           | 0        | SnpRespData_I_PD           |
|                       | SC.           | I           | 0        | SnpResp_I                  |
| SnpStashUnique,       | I             | I           | 0        | SnpResp_I                  |
| SnpStashShared        | UC            | UC          | 0        | SnpResp_UC                 |
|                       | UD            | UD          | 0        | SnpResp_UD                 |
|                       | SC.           | SC.         | 0        | SnpResp_SC                 |
| SnpOnceFwd            | I             | I           | 0        | SnpResp_I                  |
|                       | UC            | UC          | 0        | SnpResp_UC_Fwded_I         |
|                       | UD            | UD          | 0        | SnpResp_UD_Fwded_I         |
|                       | SC.           | SC.         | 0        | SnpResp_SC_Fwded_I         |
| SnpCleanFwd,          | I             | I           | X        | SnpResp_I                  |
| SnpNotSharedDirtyFwd, | UC            | SC.         | 0        | SnpResp_SC_Fwded_SC        |
| SnpSharedFwd          |               |             | 1        | SnpRespData_SC_Fwded_SC    |
|                       | UD            | SC.         | X        | SnpRespData_SC_PD_Fwded_SC |
|                       | SC.           | SC.         | 0        | SnpResp_SC_Fwded_SC        |
|                       |               |             | 1        | SnpRespData_SC_Fwded_SC    |
| SnpUniqueFwd          | I             | I           | 0        | SnpResp_I                  |
|                       | UC            | I           | 0        | SnpResp_I_Fwded_UC         |
|                       | UD            | I           | 0        | SnpResp_I_Fwded_UD_PD      |
|                       | SC.           | I           | 0        | SnpResp_I_Fwded_UC         |
| SnpQuery              | I             | I           | 0        | SnpResp_I                  |
|                       | UC            | UC          | 0        | SnpResp_UC                 |
|                       | UD            | UD          | 0        | SnpResp_UD                 |
|                       | SC.           | SC.         | 0        | SnpResp_SC                 |

### Early termination of a task

Tasks on MainPipe can terminate early at stage ```s3``` without proceeding to
subsequent pipeline stages when one of the following conditions is met:

1. The task does not need to migrate data from DataStorage to ReleaseBuffer and
   meets one of the following conditions:
    - Requests from tasks to upstream/downstream channels (upstream TileLink D,
      downstream TXREQ, downstream TXRSP, downstream TXDAT) successfully leave
      MainPipe at ```s3```
    - The task requires MSHR allocation
2. The task's request to the upstream TileLink D channel (AccessAckData,
   HintAck, GrantData, Grant) is retried.

## S4 pipeline stage

Tasks in MainPipe that are not terminated early at stage ```s3``` will proceed
to stage ```s4```. A task can terminate early at stage ```s4``` without entering
subsequent pipeline stages if it meets all the following conditions:

- The task does not need to move data from DataStorage to ReleaseBuffer
- The request to the upstream and downstream channels (upstream TileLink D,
  downstream TXREQ, downstream TXRSP, downstream TXDAT) smoothly exits the
  MainPipe at ```s4```.

If the task is not completed at ```s4```, it continues to the ```s5``` stage.


## Pipeline stage S5

If a task on MainPipe is not terminated early at stage ```s4```, it proceeds to
stage ```s5```.

If a read request to DataStorage is initiated at stage ```s3```, the
corresponding cache line data can be obtained at ```s5```.

At ```s5```, MainPipe will write data from DataStorage or MainPipe into
ReleaseBuffer based on task requirements and request nesting.

