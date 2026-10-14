# Request Arbiter and Main Pipeline {#sec:reqarb-mainpipe}

The request arbiter and memory access pipeline form the overall five-stage pipeline of CoupledL2, referred to in order as the first stage ```s1```, the second stage ```s2```, the third stage ```s3```, the fourth stage ```s4```, and the fifth stage ```s5```. Among them, the request arbiter ReqArbiter mainly constitutes ```s1``` and ```s2```, while the main pipeline MainPipe mainly constitutes ```s3```, ```s4```, and ```s5```.

## S0 pipeline stage

```s0``` is only located within the request arbiter ReqArbiter and does not count as a separate pipeline stage. ```s0``` is only used to generate backpressure signals for each MSHR entry. ReqArbiter will prevent tasks from leaving MSHR and entering the pipeline under the following conditions:

- In the previous cycle, there was an MSHR task requiring Directory read that was blocked
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

In the above list, the request source at the top has the highest priority. When they simultaneously enter ReqArbiter's ```s1```, the one with the highest priority is selected for handshake, while other task sources are blocked. Specifically, MSHR tasks have the highest priority, followed by the upstream TileLink C channel, upstream TileLink B channel, and upstream TileLink A channel.

At ```s1```, ReqArbiter must also consider blocking signals from MainPipe. Only when ```s2``` is ready can the request leave ```s1```; otherwise, it is blocked and stored at ```s1```.

After arbitration is completed, a read request is sent to Directory at ```s1```.


## S2 pipeline stage

```s2``` is located within the Request Arbiter ReqArbiter and the Main Pipeline MainPipe.

CoupledL2 supports configurable MCP2 (Multi-Cycle Path 2). When enabled, a DataStorage access lasts two cycles, and RequestArb inserts an interval between requests to meet this requirement. XSAI's `DefaultMatrixConfig` sets `enableMCP2` to false, omitting this fixed interval. Blocking due to address conflicts or insufficient channel resources still applies.

In ```s2```, RequestArb selects ReleaseBuffer, RefillBuffer, or PutBuffer and issues the corresponding read request. The registered full-line result is available to MainPipe in ```s3```.

Under any of the following conditions, ReqArbiter will send a read request to RefillBuffer at ```s2```:

1. This task is triggered by a replacement task, causing downstream cache line write-back and eviction (at this point, the write-back data is no longer needed, and the replacement-read data is written into DataStorage).
2. The task is an upstream response produced by an MSHR, needs to read refill data, and does not use upstream Probe response data (which would require reading ReleaseBuffer instead)

The AccessAck refill task for a matrix Put reads RefillBuffer, writes the new Put data to DataStorage, and schedules an upstream response without data.

Under any of the following conditions, ReqArbiter will send a read request to ReleaseBuffer at ```s2```:

1. The task is an MSHR task, and downstream requests need to read data from upstream Probe responses
2. This task is an MSHR task, and the upstream TileLink A channel request requires the data from the upstream Probe response.
3. The task is not an MSHR task, and downstream Snoop and downstream writeback request tasks are nested

A regular channel A PutFullData task reads PutBuffer in ```s2``` using `bufIdx`. This read releases the PutBuffer entry. The directory result in ```s3``` then determines whether DataStorage is written.

ReqArbiter sends tasks into MainPipe at ```s2```.

MainPipe generates a blocking signal in ```s2``` for ```s1``` and sends it back to ReqArbiter and RequestBuffer. MainPipe needs to send blocking signals to various components and channels under the following circumstances:

- If it cannot be determined that the task will definitely not perform a write operation to the Directory when it reaches ```s2```, a signal to block requests of the same Set is sent to the RequestBuffer.
- If it cannot be determined that a task will definitely not perform a write operation to Directory when it reaches ```s2```, a signal is sent to ReqArbiter to block MSHR requests of the same Set.
- If it cannot be determined that the task will definitely not perform a write operation to the Directory when it reaches ```s2```, a signal is sent to ReqArbiter to block upstream TileLink C channel requests of the same Set
- When the task reaches ```s2``` (as well as ```s3```, ```s4```, ```s5```, i.e., all tasks still in the MainPipe, which will not be reiterated in subsequent sections), a signal is sent to ReqArbiter to block downstream RXSNP channel requests with the same address.


## S3 pipeline stage

```s3``` is only located within the MainPipe pipeline. Most of the request judgment, distribution logic, and interactions with other modules are located in the ```s3``` stage.


### Cache line state collection

The read request issued by ReqArbiter to the Directory at ```s1``` can obtain the read result at ```s3```. If a request from the downstream RXSNP channel results in nesting with an MSHR, i.e., the address of the downstream Snoop request matches that of an outstanding MSHR, the cache line state from that MSHR entry will override the Directory read result.

### MSHR allocation

MainPipe allocates an MSHR at ```s3``` when one of the following conditions is met:

1. The task originates from the upstream TileLink A channel
    - Acquire*, Hint, Get, or PutFullData misses the cache line
    - An Acquire* requiring write permission or PutFullData hits a cache line in BRANCH state
    - CBO* class CMO requests
    - Alias replacement request
    - Any task that needs to send a Probe request upstream
        - A Get request hits a cache line in TRUNK state that exists in the upstream L1.
        - A PutFullData request hits a cache line present in upstream L1
        - A CBOClean request hits a cache line in TRUNK state that exists in the upstream L1.
        - The cache line hit by a CBOFlush request exists in the upstream L1
        - The cache line hit by the CBOInval request exists in the upstream L1
2. Tasks originate from the downstream RXSNP channel
    - Snoop hits the corresponding cache line state for the corresponding type.
    - Forwarding Snoop with cache line hit

For non-Forwarding Snoop type Snoop requests from downstream, the conditions requiring MSHR allocation are listed below:

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

MainPipe will send a write request to the Directory at ```s3``` as required by the task.

For a PutFullData that completes directly, the updated cache line is marked dirty, with TIP permission and clients equal to 0. A Get hit that requires no MSHR allocation only reads data without updating the directory. For a Put requiring an MSHR, the task returning to the main pipeline updates the directory after permission acquisition, Probe, and replacement processing meet the refill conditions. clients is cleared after upper-level copies are invalidated.

### DataStorage read/write

MainPipe sends read or write requests to DataStorage in ```s3``` according to task requirements.

#### Matrix Put Data Source Selection

New matrix Put data is read from PutBuffer in ```s2```. Only on a directory hit whose state satisfies `isT` and whose clients is 0 can it be written directly to DataStorage in ```s3```. Other cases allocate an MSHR and write the full-line data to RefillBuffer addressed by that MSHR's index.

Table: Main-pipeline processing of PutFullData

| Directory result                          | Coherence action                                             | New data storage and write path                                                         |
| ----------------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| Writable-state hit, no upper-level client | Complete directly                                            | PutBuffer → DataStorage                                                                 |
| BRANCH hit, no upper-level client         | MakeUnique obtains write permission                          | PutBuffer → RefillBuffer; write DataStorage after permission is obtained                |
| Hit with an upper-level client            | Probe toN; BRANCH also requires MakeUnique                   | PutBuffer → RefillBuffer; write DataStorage after required coherence responses complete |
| Miss                                      | MakeUnique obtains write permission; query a replacement way | PutBuffer → RefillBuffer; write DataStorage through the replacement flow                |

For a Put waiting on an MSHR, the returning MSHR task sets `useProbeData` to false to write the new data from RefillBuffer. If the selected replacement way already holds valid data, the old line is first read from DataStorage into ReleaseBuffer. A later release task writes the new data from RefillBuffer into DataStorage.

PutBuffer is released after its data is read in s2. The MSHR tracks writes awaiting coherence operations; a later refill task schedules the DataStorage write and upstream AccessAck. The MSHR is released after all required tasks complete.

### Request and message distribution

MainPipe will send requests to one of the following channel directions at ```s3``` according to task requirements:

- Upstream TileLink D channel
- Downstream TXREQ channel
- Downstream TXRSP channel
- Downstream TXDAT channel

The specific distribution direction is determined by the task itself. For details, refer to [@sec:mshr] [MSHR](MSHR.md).

All upstream responses are sent to GrantBuffer. A matrix Get returns AccessAckData carrying `matrixTask`, `ameIndex`, and `ameChannel`, which GrantBuffer routes to the separate matrix data interface. A matrix Put returns AccessAck without data through regular channel D.

### Snoop Request Processing

Snoop requests from downstream may not allocate an MSHR but directly complete the response action in MainPipe. The state transition of Snoop requests is determined at ```s3``` in MainPipe. Snoop requests occurring at ```s3``` and their corresponding state transitions are as follows:

| Snoop Request Type    | Initial state | Final State | RetToSrc | Snoop reply                |
| --------------------- | ------------- | ----------- | -------- | -------------------------- |
| SnpOnce               | I             | I           | X        | SnpResp_I                  |
|                       | UC            | UC          | X        | SnpRespData_UC             |
|                       | UD            | UD          | X        | SnpRespData_UD_PD          |
|                       | SC            | SC          | 0        | SnpResp_SC                 |
|                       |               |             | 1        | SnpRespData_SC             |
| SnpClean,             | I             | I           | X        | SnpResp_I                  |
| SnpShared,            | UC            | SC          | X        | SnpResp_SC                 |
| SnpNotSharedDirty     | UD            | SC          | X        | SnpRespData_SC_PD          |
|                       | SC            | SC          | 0        | SnpResp_SC                 |
|                       |               |             | 1        | SnpRespData_SC             |
| SnpUnique             | I             | I           | X        | SnpResp_I                  |
|                       | UC            | I           | X        | SnpResp_I                  |
|                       | UD            | I           | X        | SnpRespData_I_PD           |
|                       | SC            | I           | 0        | SnpResp_I                  |
|                       |               |             | 1        | SnpRespData_I              |
| SnpCleanShared        | I             | I           | 0        | SnpResp_I                  |
|                       | UC            | UC          | 0        | SnpResp_UC                 |
|                       | UD            | UC          | 0        | SnpRespData_UC_PD          |
|                       | SC            | SC          | 0        | SnpResp_SC                 |
| SnpCleanInvalid       | I             | I           | 0        | SnpResp_I                  |
|                       | UC            | I           | 0        | SnpResp_I                  |
|                       | UD            | I           | 0        | SnpRespData_I_PD           |
|                       | SC            | I           | 0        | SnpResp_I                  |
| SnpMakeInvalid        | -             | I           | 0        | SnpResp_I                  |
| SnpMakeInvalidStash   | -             | I           | 0        | SnpResp_I                  |
| SnpUniqueStash        | I             | I           | 0        | SnpResp_I                  |
|                       | UC            | I           | 0        | SnpResp_I                  |
|                       | UD            | I           | 0        | SnpRespData_I_PD           |
|                       | SC            | I           | 0        | SnpResp_I                  |
| SnpStashUnique,       | I             | I           | 0        | SnpResp_I                  |
| SnpStashShared        | UC            | UC          | 0        | SnpResp_UC                 |
|                       | UD            | UD          | 0        | SnpResp_UD                 |
|                       | SC            | SC          | 0        | SnpResp_SC                 |
| SnpOnceFwd            | I             | I           | 0        | SnpResp_I                  |
|                       | UC            | UC          | 0        | SnpResp_UC_Fwded_I         |
|                       | UD            | UD          | 0        | SnpResp_UD_Fwded_I         |
|                       | SC            | SC          | 0        | SnpResp_SC_Fwded_I         |
| SnpCleanFwd,          | I             | I           | X        | SnpResp_I                  |
| SnpNotSharedDirtyFwd, | UC            | SC          | 0        | SnpResp_SC_Fwded_SC        |
| SnpSharedFwd          |               |             | 1        | SnpRespData_SC_Fwded_SC    |
|                       | UD            | SC          | X        | SnpRespData_SC_PD_Fwded_SC |
|                       | SC            | SC          | 0        | SnpResp_SC_Fwded_SC        |
|                       |               |             | 1        | SnpRespData_SC_Fwded_SC    |
| SnpUniqueFwd          | I             | I           | 0        | SnpResp_I                  |
|                       | UC            | I           | 0        | SnpResp_I_Fwded_UC         |
|                       | UD            | I           | 0        | SnpResp_I_Fwded_UD_PD      |
|                       | SC            | I           | 0        | SnpResp_I_Fwded_UC         |
| SnpQuery              | I             | I           | 0        | SnpResp_I                  |
|                       | UC            | UC          | 0        | SnpResp_UC                 |
|                       | UD            | UD          | 0        | SnpResp_UD                 |
|                       | SC            | SC          | 0        | SnpResp_SC                 |

### Early termination of a task

Tasks on MainPipe can terminate early at stage ```s3``` without proceeding to subsequent pipeline stages when one of the following conditions is met:

1. The task does not need to migrate data from DataStorage to ReleaseBuffer and meets one of the following conditions:
    - Requests from tasks to upstream/downstream channels (upstream TileLink D, downstream TXREQ, downstream TXRSP, downstream TXDAT) successfully leave MainPipe at ```s3```
    - The task requires MSHR allocation
2. An MSHR refill task retries because its replacement-way query failed, including AccessAckData, AccessAck, HintAck, GrantData, and Grant


## S4 pipeline stage

Tasks in MainPipe that are not terminated early at stage ```s3``` will proceed to stage ```s4```. A task can terminate early at stage ```s4``` without entering subsequent pipeline stages if it meets all the following conditions:

- The task does not need to move data from DataStorage to ReleaseBuffer
- The request to the upstream and downstream channels (upstream TileLink D, downstream TXREQ, downstream TXRSP, downstream TXDAT) smoothly exits the MainPipe at ```s4```.

If the task is not completed at ```s4```, it continues to the ```s5``` stage.


## Pipeline stage S5

If a task on MainPipe is not terminated early at stage ```s4```, it proceeds to stage ```s5```.

If a read request to DataStorage is initiated at stage ```s3```, the corresponding cache line data can be obtained at ```s5```.

At ```s5```, MainPipe will write data from DataStorage or MainPipe into ReleaseBuffer based on task requirements and request nesting.

