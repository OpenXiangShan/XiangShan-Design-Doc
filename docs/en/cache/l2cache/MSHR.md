# MSHR {#sec:mshr}

Whether a task is allocated an MSHR is determined by the memory access pipeline
(MainPipe) based on factors such as cache hit status, the need for L1 probing,
and the complexity of the processing flow. For details, refer to
[@sec:reqarb-mainpipe] [Request Arbiter and Memory Access
Pipeline](ReqArb_MainPipe.md).

## Lifecycle

Each MSHR has its own lifecycle. An MSHR entry is allocated by MainPipe and ends
its lifecycle when the MSHR completes all tasks and clears all state machine
status entries. Each MSHR may remain valid for an extended period due to waiting
for bus transactions but must end its lifecycle within a finite time; otherwise,
it indicates a livelock or deadlock.

### MSHR ID

Each MSHR has its own ID value, which is hard-coded, and the IDs differ among
the various MSHRs.

CHI requests initiated by the MSHR, where the lower bits of the TxnID value are
bound to the MSHR ID.

### Allocate

When the MainPipe requests the allocation of an MSHR entry, an unallocated MSHR
is selected by the MSHRSelector within the MSHRCtl module. For each MSHR
allocation, the MainPipe needs to provide the following information:

- The hit status and coherence state of the cache line
- Initial state of the MSHR state machine
- Essential original information of the request (from TileLink request or CHI
  request)
- Nesting of requests and ongoing writebacks (TileLink Release from L2 downward
  or CHI Copy-Back Write)

All this information is registered within the allocated MSHR entry.

### Release

When all state machine entries within the MSHR are marked as completed, it can
be immediately released in place, ending the lifecycle of that MSHR entry and
preparing it to be selected and allocated again by the MSHRSelector. For details
on the MSHR state machine entries, refer to [@sec:mshr-state-machine] [State
Machine](#sec:mshr-state-machine).


## State Machine {#sec:mshr-state-machine}

State machine entries are primarily divided into two categories:

- Schedule state entry
- Wait state item

The Schedule state item, also known as the active action state item, is
primarily used to track the MSHR's active sending of tasks and requests to
MainPipe, downstream CHI channels, and upstream TileLink channels. Its value is
active-low, indicating an incomplete state where the task has not yet
successfully left the MSHR and been issued, possibly due to unmet blocking
conditions (necessary prerequisites not completed) or channel blocking; a high
value indicates the corresponding task has been successfully issued or does not
need to be issued.

Wait state entries, also known as passive action state entries, are primarily
used to track replies expected by the MSHR from downstream CHI channels,
upstream TileLink channels, or internal CoupledL2 modules. Their value is
active-low, indicating an incomplete state where the corresponding reply has not
yet returned to the MSHR entry; a high value indicates that the corresponding
reply has been received or is not required.

Status entries are assigned when the MSHR is allocated by MainPipe and can also
be modified by internal MSHR actions.

> The upstream in this section typically refers to the L1 cache, while the
> downstream usually refers to the NoC, LLC, etc.

Schedule state items are named with ```s_``` as the prefix, and their overview
is as follows:

| Name             | Description                                                                                                                |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------- |
| ```s_acquire```  | 首次需要向下游发送 权限提升请求 或 CMO 请求，或者需要向下发送被重试的写回或踢出请求                                                                              |
| ```s_rprobe```   | Due to replacement or writeback, a Probe request needs to be sent upstream                                                 |
| ```s_pprobe```   | Due to a downstream Snoop request, a Probe request needs to be sent upstream.                                              |
| ```s_release```  | Writeback or eviction requests that need to be sent downstream                                                             |
| ```s_probeack``` | Due to downstream Snoop requests, a Snoop response needs to be sent downstream                                             |
| ```s_refill```   | Need to send a Grant response upstream                                                                                     |
| ```s_retry```    | Due to no available way for replacement, the Grant response sent upstream needs to be retried                              |
| ```s_cmoresp```  | Need to send a CBOAck response upstream                                                                                    |
| ```s_cmometaw``` | Directory update requests sent to MainPipe caused by CMO                                                                   |
| ```s_rcompack``` | 由于向下游发送了读请求，需要发送对应的 CompAck 回复                                                                                             |
| ```s_wcompack``` | Since a write request was sent downstream, a corresponding CompAck response needs to be sent.                              |
| ```s_cbwrdata``` | Due to a write request sent downstream, the corresponding CopyBackWrData needs to be sent to write back the data           |
| ```s_reissue```  | Due to a RetryAck received from downstream and the MSHR having obtained PCredit, the request needs to be resent downstream |
| ```s_dct```      | Due to downstream Forwarding Snoop requests, CompData needs to be sent in the form of DCT to provide data to other RNs.    |

Wait state entries are named with ```w_``` as the prefix, and their overview is
as follows:

| Name                   | Description                                                                                                                                                                                                                                        |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ```w_rprobeackfirst``` | Due to replacement or writeback, a Probe request was sent upstream, requiring waiting for the first Probe response from upstream                                                                                                                   |
| ```w_rprobeacklast```  | Due to replacement or writeback, a Probe request was sent upstream, and it is necessary to wait for the last Probe reply from upstream (for a single reply, the action is the same as ```w_rprobeackfirst```)                                      |
| ```w_pprobeackfirst``` | Due to a downstream Snoop request, a Probe request was sent upstream, requiring waiting for the first Probe response from upstream                                                                                                                 |
| ```w_pprobeacklast```  | Due to a downstream Snoop request, a Probe request was sent upstream, and it is necessary to wait for the final Probe response from upstream (for a single response, the action is the same as ```w_pprobeackfirst```)                             |
| ```w_grantfirst```     | Due to sending a permission escalation request or CMO request downstream, it is necessary to wait for the first Comp, CompData, or DataSepResp reply from downstream.                                                                              |
| ```w_grantlast```      | Due to sending a permission escalation request or CMO request downstream, it is necessary to wait for the final CompData or DataSepResp response from downstream (when receiving a Comp response, the action is the same as ```w_grantfirst```).   |
| ```w_grant```          | Due to sending a permission upgrade request or CMO request downstream, it is necessary to wait for downstream Comp, CompData, or RespSepData responses, and obtain the required DBID and SrcID information from CompData and RespSepData responses |
| ```w_releaseack```     | Due to the writeback or eviction request sent downstream, waiting for a Comp or CompDBIDResp response from downstream                                                                                                                              |
| ```w_replResp```       | Due to replacement, waiting for the replacement selection result from Directory                                                                                                                                                                    |


## Task dispatch

When the Schedule state entry is incomplete, the MSHR will attempt to send
corresponding tasks to the relevant modules or channels. Each MSHR entry can
directly distribute tasks to the following modules or channels via MSHRCtl
arbitration:

- MainPipe
- Upstream TileLink B channel
- Downstream TXREQ channel
- Downstream TXRSP channel

For the distribution of TXDAT channel tasks, they must pass through the
MainPipe, as detailed in [@sec:reqarb-mainpipe] [Request Arbiter and Memory
Pipeline](ReqArb_MainPipe.md).

Tasks sent to the MainPipe also undergo arbitration by the RequestArb in the
same cycle. For details, refer to [@sec:reqarb-mainpipe] [Request Arbiter and
Memory Pipeline](ReqArb_MainPipe.md).

The task distribution directions corresponding to each Schedule state item are
as follows:

| Name             | Target Module/Channel       |
| ---------------- | --------------------------- |
| ```s_acquire```  | Downstream TXREQ channel    |
| ```s_rprobe```   | Upstream TileLink B channel |
| ```s_pprobe```   | Upstream TileLink B channel |
| ```s_release```  | MainPipe                    |
| ```s_probeack``` | MainPipe                    |
| ```s_refill```   | MainPipe                    |
| ```s_retry```    | -                           |
| ```s_cmoresp```  | MainPipe                    |
| ```s_cmometaw``` | MainPipe                    |
| ```s_rcompack``` | Downstream TXRSP channel    |
| ```s_wcompack``` | Downstream TXRSP channel    |
| ```s_cbwrdata``` | MainPipe                    |
| ```s_reissue```  | -                           |
| ```s_dct```      | MainPipe                    |

### MainPipe

Each MSHR will send several different types of tasks to the MainPipe based on
the state of its state machine entry.

#### Writeback request task (```mp_release```)

The writeback request task (```mp_release```) is triggered by the state machine
entry ```s_release```. This task's purpose is to send the required cache line
writeback or eviction request via the TXREQ channel in MainPipe. When the state
machine entry ```s_release``` is incomplete and the current MSHR state meets
certain conditions, the MSHR will attempt to send a writeback request task to
MainPipe.

When ```s_release``` is marked as incomplete, the MSHR state must meet the
following conditions in all scenarios before it can send a writeback request
task to the MainPipe:

1. From replacement task
    - The replacement way selection has been completed
    - All responses to the upstream Probe have been received
    - The replacement read request has received all data from downstream.
2. From CMO request
    - All responses to the upstream Probe have been received

The writeback request task will require MainPipe to send a request on the TXREQ
channel:

| Task Source      | Upstream A channel request type | Whether there is dirty data | Downstream TXREQ request type |
| ---------------- | ------------------------------- | --------------------------- | ----------------------------- |
| Replacement Task | Acquire*                        | Yes                         | WriteBackFull                 |
|                  |                                 | No                          | WriteEvictOrEvict             |
| CMO request      | CBOClean                        | -                           | WriteCleanFull                |
|                  | CBOFlush                        | Yes                         | WriteBackFull                 |
|                  |                                 | No                          | Evict                         |
|                  | CBOInval                        | -                           | Evict                         |

The write-back request task will, depending on the situation, require the
MainPipe to write the associated data held by the MSHR into DataStorage:

| Task Source      | Upstream A channel request type | Whether there is dirty data | Data source   | Whether to write to DataStorage |
| ---------------- | ------------------------------- | --------------------------- | ------------- | ------------------------------- |
| Replacement Task | Acquire*                        | -                           | RefillBuffer  | Yes                             |
| CMO request      | CBO*                            | Probe from upstream         | ReleaseBuffer | Yes                             |
|                  |                                 | Others                      | -             | No                              |

Additionally, the CMO request in the writeback request task requires MainPipe to
update the cache line state in the Directory and clear the Dirty flag of the
cache line:

| Task Source | Upstream A channel request type | Initial state | Write status |
| ----------- | ------------------------------- | ------------- | ------------ |
| CMO request | CBOClean                        | TRUNK         | TIP          |
|             |                                 | TIP           | TIP          |
|             |                                 | BRANCH        | BRANCH       |
|             |                                 | INVALID       | INVALID      |
|             | CBOFlush                        | -             | INVALID      |
|             | CBOInval                        | -             | INVALID      |

#### Downstream Snoop Response Task (```mp_probeack```)

The downstream Snoop reply task (```mp_probeack```) is triggered by the state
machine entry ```s_probeack```. This task serves to send downstream Snoop
replies via the TXRSP or TXDAT channels in the MainPipe. When the state of the
state machine entry ```s_probeack``` is incomplete and the current MSHR state
meets certain conditions, the MSHR will attempt to send downstream Snoop reply
tasks to the MainPipe.

When ```s_probeack``` is marked as incomplete, its MSHR state must meet the
following conditions before it can send a downstream Snoop response task to the
MainPipe:

- All responses to the upstream Probe have been received

The downstream Snoop response task will require MainPipe to send messages on the
TXRSP or TXDAT channel and specify the Snoop Response type in the MSHR. For
details, see [@sec:mshr-snoop-details] [Snoop
Processing](#sec:mshr-snoop-details).

下游 Snoop 回复任务会在满足以下情况时要求 MainPipe 将 MSHR 持有的关联数据写入 DataStorage：

- The target state of the downstream Snoop request is not I.
- 上游 L1 在 Probe 过程中返回了脏数据（ProbeAckData）
- The upstream L1 does not initiate a dirty data writeback (ReleaseData) nested
  before the Probe ends.

The downstream Snoop response task will require MainPipe to update the cache
line state. For details, refer to [@sec:mshr-snoop-details] [Snoop
Handling](#sec:mshr-snoop-details).

#### Replacement way queries and upstream Grant/CBOAck response tasks (```mp_grant```)

The replacement way query and upstream Grant/CBOAck response task
(```mp_grant```) are triggered by state machine entries ```s_refill``` or
```s_cmoresp```, and ```s_refill``` and ```s_cmoresp``` cannot be simultaneously
marked as incomplete. The purpose of this task is one of the following:

1. When MainPipe initiates a replacement way query request to Directory
2. When the MainPipe replies with Grant/GrantData to the upstream via the
   TileLink D channel
3. The MainPipe replies with CBOAck to upstream via the TileLink D channel

When the state machine item ```s_release``` is incomplete and the current MSHR
state meets certain conditions, the MSHR will attempt to send a replacement way
query or upstream Grant response task to the MainPipe. When the state machine
item ```s_cmoresp``` is incomplete and the current MSHR state meets certain
conditions, the MSHR will attempt to send a CBOAck response task to the
MainPipe.

When ```s_refill``` is marked as incomplete, the MSHR state must meet the
following conditions before it can send a replacement way query and upstream
Grant response task to the MainPipe:

- All responses to the upstream Probe have been received
- The first Comp, CompData, or RespSepData response from downstream has been
  received
- If required, receive all Comp, CompData, or DataSepResp responses from
  downstream.
- The replacement way query retry does not exceed the retry suppression
  threshold

After continuously sending replacement way retry requests multiple times, the
MSHR will suppress them for a period to prevent livelock caused by overly dense
and consecutive retries.

When ```s_cmoresp``` is marked as incomplete, the MSHR state must meet the
following conditions to send a replacement way query to MainPipe and an upstream
CBOAck response task:

- All responses to the upstream Probe have been received
- A Comp response belonging to ```w_releaseack``` has been received from
  downstream
- The Comp response from downstream belonging to ```w_grant``` has been received
  (```w_grant``` can only receive the downstream Comp response after
  ```w_releaseack``` is completed).
- If needed, all CopyBackWrData have been sent.

Moreover, these conditions imply a feature where ```s_cmoresp``` can only
initiate the task after all CMO sub-actions, except for the CBOAck response
process, have been completed.

When the MSHR needs to wait for the replacement way result and the Directory has
given a retry response, the MSHR will send a replacement way retry task from
```mp_grant```.

The replacement way query and upstream Grant tasks require the MainPipe to
update the cache line state in the Directory, whereas upstream CBOAck tasks do
not require such updates. The update rules are as follows:

| Task Source     | Request Type       | Initial state | Update State |
| --------------- | ------------------ | ------------- | ------------ |
| ```s_refill```  | Get                | TIP           | TIP          |
|                 |                    | TRUNK         | TIP          |
|                 |                    | BRANCH        | BRANCH       |
|                 |                    | INVALID       | TIP```*```   |
|                 |                    |               | BRANCH       |
|                 | Acquire* toT       | -             | TRUNK        |
|                 | Acquire* toB       | -             | TRUNK```*``` |
|                 |                    | -             | BRANCH       |
|                 | Hint PrefetchWrite | -             | TIP          |
|                 | Hint PrefetchRead  | -             | TIP```*```   |
|                 |                    | -             | BRANCH       |
| ```s_cmoresp``` | -                  | -             | -            |

The following updates occur under certain conditions: Get updates to TIP,
Acquire* toB updates to TRUNK, and Hint PrefetchRead updates to TIP

- The cache line does not exist in the upstream L1 and has TIP permission
  locally in L2
- The operation being performed on the cache line is not an Alias replacement,
  and the L2 local permission is either TIP or TRUNK
- The cache line does not exist in L2, and the read request sent downstream
  returns write permission

When a replacement way query and an upstream Grant task miss in the Directory,
it will request the MainPipe to provide the corresponding Tag value of the
selected cache line for replacement in the Directory. However, this is not
required for an upstream CBOAck task.

Replacement way queries and upstream Grant/CBOAck tasks require the MainPipe to
write the associated data held by the MSHR into DataStorage when one of the
following conditions is met:

- Received CompData or DataSepResp data response from downstream
- Dirty data was received in the Probe sent upstream upon completion of the Get
  or Alias replacement process

#### Downstream CopyBackWrData Task (```mp_cbwrdata```)

The writeback request task (```mp_cbwrdata```) is triggered by the state machine
item ```s_cbwrdata```. This task's purpose is to complete the CopyBackWrData
that needs to be sent downstream via the TXDAT channel in MainPipe. When the
state machine item ```s_cbwrdata``` is not completed and the current MSHR state
meets certain conditions, the MSHR will attempt to send the writeback request
task to MainPipe.

```s_cbwrdata``` is typically set as incomplete by the following actions of
```s_release``` and ```w_releaseack```:

- The writeback request task is leaving the MSHR, i.e., when the ```s_release```
  state entry is being marked as complete.

Note that when a Comp reply is received after sending WriteEvictOrEvict,
```s_cbwrdata``` will mark ```s_cbwrdata``` as completed without the MSHR
sending any downstream CopyBackWrData tasks to the MainPipe.

The MSHR state must meet the following conditions to send a writeback request
task to MainPipe:

- The writeback request task has left the MSHR, meaning the ```s_release```
  status entry is completed.

#### Downstream DCT CompData task (```mp_dct```)

The downstream DCT CompData task (```mp_dct```) is triggered by the state
machine entry ```s_dct```. This task completes the DCT portion of Forwarding
Snoop in the MainPipe via the TXDAT channel. When the state machine entry
```s_dct``` is incomplete and the current MSHR state meets certain conditions,
the MSHR will attempt to send the downstream DCT CompData task to the MainPipe.

When ```s_dct``` is marked as incomplete, its MSHR state must meet the following
conditions before it can send a downstream DCT CompData task to MainPipe:

- In the Fowarding Snoop process, the Snoop response task targeting the HN has
  left the MSHR, meaning the ```s_probeack``` status entry is completed.

The downstream DCT CompData task will require the MainPipe to send a CompData
response via the TXDAT channel. According to the definition of DCT, the target
of this CompData response is another processor core (i.e., RN).

#### CMO cache state update task (```mp_cmometaw```)

The CMO cache state update task (```mp_cmometaw```) is triggered by the state
machine entry ```s_cmometaw```. This task updates the cache line state in the
MainPipe when a WriteCleanFull writeback is not required for the CBOClean
operation.

When ```s_cmometaw``` is set to incomplete, the MSHR can send a CMO cache state
update task to MainPipe and perform the following updates:

- When ProbeAck toN is received, the record is updated to indicate the cache
  line does not exist in the upstream L1
- Clear State to Clean
- Update the permission to TIP

### Upstream TileLink B channel

The request transmission to the upstream TileLink B channel is triggered by the
state machine items ```s_pprobe``` or ```s_rprobe```. Moreover, ```s_pprobe```
and ```s_rprobe``` will not be set as incomplete simultaneously.

When either ```s_pprobe``` or ```s_rprobe``` is set as incomplete, the MSHR can
send a request to the upstream TileLink B channel. The request types for each
scenario are listed in the table below:

| Task Source    | Upstream request type | Downstream request type | Cache Line State | Send request type |
| -------------- | --------------------- | ----------------------- | ---------------- | ----------------- |
| ```s_pprobe``` | -                     | SnpOnce                 | -                | Probe toT         |
|                | -                     | SnpClean                | -                | Probe toB         |
|                | -                     | SnpShared               | -                | Probe toB         |
|                | -                     | SnpNotSharedDirty       | -                | Probe toB         |
|                | -                     | SnpUnique               | -                | Probe toN         |
|                | -                     | SnpCleanShared          | -                | Probe toT         |
|                | -                     | SnpCleanInvalid         | -                | Probe toN         |
|                | -                     | SnpMakeInvalid          | -                | Probe toN         |
|                | -                     | SnpMakeInvalidStash     | -                | Probe toN         |
|                | -                     | SnpUniqueStash          | -                | Probe toN         |
|                | -                     | SnpStashUnique          | -                | Probe toT         |
|                | -                     | SnpStashShared          | -                | Probe toT         |
|                | -                     | SnpOnceFwd              | -                | Probe toT         |
|                | -                     | SnpCleanFwd             | -                | Probe toB         |
|                | -                     | SnpNotSharedDirtyFwd    | -                | Probe toB         |
|                | -                     | SnpSharedFwd            | -                | Probe toB         |
|                | -                     | SnpUniqueFwd            | -                | Probe toN         |
|                | -                     | SnpQuery                | -                | Probe toT         |
| ```s_rprobe``` | Get                   | -                       | TRUNK            | Probe toB         |
|                | Acquire*              | -                       | -                | Probe toN         |
|                | CBOClean              | -                       | TRUNK            | Probe toB         |

### Downstream TXREQ channel

Requests sent to the downstream TXREQ channel are triggered by the state machine
entries ```s_acquire``` or ```s_reissue```. Additionally, ```s_acquire``` and
```s_reissue``` will not be marked as incomplete simultaneously.

When ```s_acquire``` is marked as incomplete, for replacement tasks, a
permission escalation request can be immediately sent downstream. However, for
CMO tasks, the following conditions must be met before a CMO request can be sent
downstream:

- All responses to the upstream Probe have been received
- The downstream writeback request has received Comp or CompDBIDResp
- The CopyBackWrData task to downstream has left the MSHR or is not required

When ```s_reissue``` is set as pending, the following conditions must be met
before the retried request can be resent downstream:

- RetryAck has been received from downstream
- PCrdGrant received from downstream and allocated
- In a state where there exists a ```mp_release``` or downstream TXREQ channel
  task that has left the MSHR but has not received any response, i.e., the
  ```s_release``` status entry is completed but the ```w_releaseack``` status
  entry is not, or the ```s_acquire``` status entry is completed but the
  ```w_grant``` status entry is not

The request types sent downstream on the TXREQ channel under various conditions
are as follows:

| Task Source     | Incomplete state   | Upstream request type | Outstanding request type | Send request type  |
| --------------- | ------------------ | --------------------- | ------------------------ | ------------------ |
| ```s_acquire``` | -                  | Get                   | -                        | ReadNotSharedDirty |
|                 |                    | AcquirePerm toT       | -                        | MakeUnique         |
|                 |                    | AcquireBlock toT      | -                        | ReadUnique         |
|                 |                    | AcquireBlock toB      | -                        | ReadNotSharedDirty |
|                 |                    | Hint PrefetchWrite    | -                        | ReadUnique         |
|                 |                    | Hint PrefetchRead     | -                        | ReadNotSharedDirty |
|                 |                    | CBOClean              | -                        | CleanShared        |
|                 |                    | CBOFlush              | -                        | CleanInvalid       |
|                 |                    | CBOInval              | -                        | MakeInvalid        |
| ```s_reissue``` | ```w_grant```      | Get                   | ReadNotSharedDirty       | ReadNotSharedDirty |
|                 |                    | AcquirePerm toT       | MakeUnique               | MakeUnique         |
|                 |                    | AcquireBlock toT      | ReadUnique               | ReadUnique         |
|                 |                    | AcquireBlock toB      | ReadNotSharedDirty       | ReadNotSharedDirty |
|                 |                    | Hint PrefetchWrite    | ReadUnique               | ReadUnique         |
|                 |                    | Hint PrefetchRead     | ReadNotSharedDirty       | ReadNotSharedDirty |
|                 |                    | CBOClean              | CleanShared              | CleanShared        |
|                 |                    | CBOFlush              | CleanInvalid             | CleanInvalid       |
|                 |                    | CBOInval              | MakeInvalid              | MakeInvalid        |
| ```s_reissue``` | ```w_releaseack``` | Acquire*              | WriteBackFull            | WriteBackFull      |
|                 |                    |                       | WriteEvictOrEvict        | WriteEvictOrEvict  |
|                 |                    | CBOClean              | WriteCleanFull           | WriteCleanFull     |
|                 |                    | CBOFlush              | WriteBackFull            | WriteBackFull      |
|                 |                    |                       | Evict                    | Evict              |
|                 |                    | CBOInval              | Evict                    | Evict              |

### Downstream TXRSP channel

The message transmission to the downstream TXRSP channel is triggered by the
state machine items ```s_rcompack``` or ```s_wcompack```. This channel is
primarily used to send CompAck messages downstream. Among them, ```s_rcompack```
and ```s_wcompack``` may be set as incomplete simultaneously, with
```s_rcompack``` having higher priority.

When ```s_rcompack``` is marked as incomplete, the following conditions must be
met to send a CompAck message downstream:

1. When configured as Issue B
    - Receive downstream Comp or all CompData
2. When configured as Issue C or later versions
    - Receive downstream Comp or the first CompData or RespSepData and the first
      DataSepResp

When ```s_wcompack``` is set as incomplete, the following conditions must be met
before a CompAck message can be sent downstream:

- ```s_rcompack``` is completed or not marked as incomplete

## Snoop processing {#sec:mshr-snoop-details}

### Non-nested Snoop

When there are no pending writeback requests for the same address, the received
Snoop is a non-nested ordinary Snoop, representing the most basic case of Snoop
handling. The processing method for non-nested Snoop in MSHR is as follows:

| Snoop Request Type    | Initial state | Final State | RetToSrc | Snoop reply                |
| --------------------- | ------------- | ----------- | -------- | -------------------------- |
| SnpOnce               | I             | -           | -        | -                          |
|                       | UC            | UC          | X        | SnpRespData_UC             |
|                       | UD            | UD          | X        | SnpRespData_UD_PD          |
|                       | SC.           | -           | -        | -                          |
| SnpClean,             | I             | -           | -        | -                          |
| SnpShared,            | UC            | SC.         | X        | SnpResp_SC                 |
| SnpNotSharedDirty     | UD            | SC.         | X        | SnpRespData_SC_PD          |
|                       | SC.           | -           | -        | -                          |
| SnpUnique             | I             | -           | -        | -                          |
|                       | UC            | I           | X        | SnpResp_I                  |
|                       | UD            | I           | X        | SnpRespData_I_PD           |
|                       | SC.           | I           | 0        | SnpResp_I                  |
|                       |               |             | 1        | SnpRespData_I              |
| SnpCleanShared        | I             | -           | -        | -                          |
|                       | UC            | UC          | 0        | SnpResp_UC                 |
|                       | UD            | UC          | 0        | SnpRespData_UC_PD          |
|                       | SC.           | -           | -        | -                          |
| SnpCleanInvalid       | I             | -           | -        | -                          |
|                       | UC            | I           | 0        | SnpResp_I                  |
|                       | UD            | I           | 0        | SnpRespData_I_PD           |
|                       | SC.           | I           | 0        | SnpResp_I                  |
| SnpMakeInvalid        | -             | I           | 0        | SnpResp_I                  |
| SnpMakeInvalidStash   | -             | I           | 0        | SnpResp_I                  |
| SnpUniqueStash        | I             | -           | -        | -                          |
|                       | UC            | I           | 0        | SnpResp_I                  |
|                       | UD            | I           | 0        | SnpRespData_I_PD           |
|                       | SC.           | I           | 0        | SnpResp_I                  |
| SnpStashUnique,       | I             | -           | -        | -                          |
| SnpStashShared        | UC            | UC          | 0        | SnpResp_UC                 |
|                       | UD            | UD          | 0        | SnpResp_UD                 |
|                       | SC.           | -           | -        | -                          |
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
| SnpQuery              | I             | -           | -        | -                          |
|                       | UC            | UC          | 0        | SnpResp_UC                 |
|                       | UD            | UD          | 0        | SnpResp_UD                 |
|                       | SC.           | -           | -        | -                          |

> "-" and unlisted cache states indicate that such requests will not enter the
> MSHR under the corresponding conditions.

For details on when specific Snoop requests allocate an MSHR, refer to
[@sec:reqarb-mainpipe] [Request Arbiter and Memory
Pipeline](ReqArb_MainPipe.md).


### Nested Snoop

During the MSHR's processing of downstream writeback requests, it must still
ensure that CoupledL2 can respond to downstream Snoop requests and upstream
Release requests. In this case, incomplete writeback requests are considered
nested by Snoop requests or nested by upstream Release requests. Note that due
to Silent Eviction in the CHI protocol and the initial state of Evict requests
being I, eviction requests (Evict) that do not involve data writeback are not
considered nested.

> "-" and unlisted cache states indicate that such requests under the
> corresponding conditions will not enter the MSHR or fall outside the scope of
> nesting scenarios.

For details on when specific Snoop requests allocate an MSHR, refer to
[@sec:reqarb-mainpipe] [Request Arbiter and Memory
Pipeline](ReqArb_MainPipe.md).

The following nested downstream Snoop requests may occur and be handled within
the MSHR.

#### Feature 1: Nesting of Snoop and WriteBackFull

| Snoop Request Type   | Initial state | Pre-nesting state | Post-nesting state | RetToSrc | Snoop reply               |
| -------------------- | ------------- | ----------------- | ------------------ | -------- | ------------------------- |
| SnpOnce              | -             | -                 | -                  | -        | -                         |
| SnpClean             | -             | -                 | -                  | -        | -                         |
| SnpShared            | -             | -                 | -                  | -        | -                         |
| SnpNotSharedDirty    | -             | -                 | -                  | -        | -                         |
| SnpCleanShared       | -             | -                 | -                  | -        | -                         |
| SnpCleanInvalid      | -             | -                 | -                  | -        | -                         |
| SnpMakeInvalid       | -             | -                 | -                  | -        | -                         |
| SnpUnique            | -             | -                 | -                  | -        | -                         |
| SnpUniqueStash       | -             | -                 | -                  | -        | -                         |
| SnpMakeInvalidStash  | -             | -                 | -                  | -        | -                         |
| SnpStashUnique       | -             | -                 | -                  | -        | -                         |
| SnpStashShared       | -             | -                 | -                  | -        | -                         |
| SnpOnceFwd           | UD            | UD                | I                  | X        | SnpRespData_I_PD_Fwded_I  |
| SnpCleanFwd          | UD            | UD                | I                  | X        | SnpRespData_I_PD_Fwded_SC |
| SnpSharedFwd         | UD            | UD                | I                  | X        | SnpRespData_I_PD_Fwded_SC |
| SnpNotSharedDirtyFwd | UD            | UD                | I                  | X        | SnpRespData_I_PD_Fwded_SC |
| SnpUniqueFwd         | UD            | UD                | I                  | X        | SnpResp_I_Fwded_UD_PD     |
| SnpQuery             | -             | -                 | -                  | -        | -                         |

#### Feature 2: Nesting of Snoop and WriteEvictOrEvict

| Snoop Request Type   | Initial state | Pre-nesting state | Post-nesting state | RetToSrc | Snoop reply            |
| -------------------- | ------------- | ----------------- | ------------------ | -------- | ---------------------- |
| SnpOnce              | -             | -                 | -                  | -        | -                      |
| SnpClean             | -             | -                 | -                  | -        | -                      |
| SnpShared            | -             | -                 | -                  | -        | -                      |
| SnpNotSharedDirty    | -             | -                 | -                  | -        | -                      |
| SnpCleanShared       | -             | -                 | -                  | -        | -                      |
| SnpCleanInvalid      | -             | -                 | -                  | -        | -                      |
| SnpMakeInvalid       | -             | -                 | -                  | -        | -                      |
| SnpUnique            | -             | -                 | -                  | -        | -                      |
| SnpUniqueStash       | -             | -                 | -                  | -        | -                      |
| SnpMakeInvalidStash  | -             | -                 | -                  | -        | -                      |
| SnpStashUnique       | -             | -                 | -                  | -        | -                      |
| SnpStashShared       | -             | -                 | -                  | -        | -                      |
| SnpOnceFwd           | UC            | UC                | I                  | X        | SnpRespData_I_Fwded_I  |
| SnpCleanFwd          | UC            | UC                | I                  | 0        | SnpResp_I_Fwded_SC     |
|                      |               |                   |                    | 1        | SnpRespData_I_Fwded_SC |
| SnpSharedFwd         | UC            | UC                | I                  | 0        | SnpResp_I_Fwded_SC     |
|                      |               |                   |                    | 1        | SnpRespData_I_Fwded_SC |
| SnpNotSharedDirtyFwd | UC            | UC                | I                  | 0        | SnpResp_I_Fwded_SC     |
|                      |               |                   |                    | 1        | SnpRespData_I_Fwded_SC |
| SnpUniqueFwd         | UC            | UC                | I                  | 0        | SnpResp_I_Fwded_UC     |
| SnpQuery             | -             | -                 | -                  | -        | -                      |

#### Feature 3: Nesting of Snoop and WriteCleanFull

| Snoop Request Type   | Initial state | Pre-nesting state | Post-nesting state | RetToSrc | Snoop reply                |
| -------------------- | ------------- | ----------------- | ------------------ | -------- | -------------------------- |
| SnpOnce              | -             | -                 | -                  | -        | -                          |
| SnpClean             | -             | -                 | -                  | -        | -                          |
| SnpShared            | -             | -                 | -                  | -        | -                          |
| SnpNotSharedDirty    | -             | -                 | -                  | -        | -                          |
| SnpCleanShared       | -             | -                 | -                  | -        | -                          |
| SnpCleanInvalid      | UD            | UD                | I                  | 0        | SnpRespData_I_PD           |
|                      |               | UC                | I                  | 0        | SnpResp_I                  |
|                      |               | SC.               | I                  | 0        | SnpResp_I                  |
| SnpMakeInvalid       | UD            | UD                | I                  | 0        | SnpResp_I                  |
|                      |               | UC                | I                  | 0        | SnpResp_I                  |
|                      |               | SC.               | I                  | 0        | SnpResp_I                  |
| SnpUnique            | UD            | UD                | I                  | X        | SnpRespData_I_PD           |
|                      |               | UC                | I                  | X        | SnpResp_I                  |
|                      |               | SC.               | I                  | 0        | SnpResp_I                  |
|                      |               |                   |                    | 1        | SnpRespData_I              |
| SnpUniqueStash       | UD            | UD                | I                  | 0        | SnpRespData_I_PD           |
|                      |               | UC                | I                  | 0        | SnpResp_I                  |
|                      |               | SC.               | I                  | 0        | SnpResp_I                  |
| SnpMakeInvalidStash  | UD            | UD                | I                  | 0        | SnpResp_I                  |
|                      |               | UC                | I                  | 0        | SnpResp_I                  |
|                      |               | SC.               | I                  | 0        | SnpResp_I                  |
| SnpStashUnique       | -             | -                 | -                  | -        | -                          |
| SnpStashShared       | -             | -                 | -                  | -        | -                          |
| SnpOnceFwd           | UD            | UD                | SC.                | 0        | SnpRespData_SC_PD_Fwded_I  |
|                      |               | UC                | UC                 | 0        | SnpResp_UC_Fwded_I         |
|                      |               | SC.               | SC.                | 0        | SnpResp_SC_Fwded_I         |
| SnpCleanFwd          | UD            | UD                | SC.                | X        | SnpRespData_SC_PD_Fwded_SC |
|                      |               | UC                | SC.                | 0        | SnpResp_SC_Fwded_SC        |
|                      |               |                   |                    | 1        | SnpRespData_SC_Fwded_SC    |
|                      |               | SC.               | SC.                | 0        | SnpResp_SC_Fwded_SC        |
|                      |               |                   |                    | 1        | SnpRespData_SC_Fwded_SC    |
| SnpSharedFwd         | UD            | UD                | SC.                | X        | SnpRespData_SC_PD_Fwded_SC |
|                      |               | UC                | SC.                | 0        | SnpResp_SC_Fwded_SC        |
|                      |               |                   |                    | 1        | SnpRespData_SC_Fwded_SC    |
|                      |               | SC.               | SC.                | 0        | SnpResp_SC_Fwded_SC        |
|                      |               |                   |                    | 1        | SnpRespData_SC_Fwded_SC    |
| SnpNotSharedDirtyFwd | UD            | UD                | SC.                | X        | SnpRespData_SC_PD_Fwded_SC |
|                      |               | UC                | SC.                | 0        | SnpResp_SC_Fwded_SC        |
|                      |               |                   |                    | 1        | SnpRespData_SC_Fwded_SC    |
|                      |               | SC.               | SC.                | 0        | SnpResp_SC_Fwded_SC        |
|                      |               |                   |                    | 1        | SnpRespData_SC_Fwded_SC    |
| SnpUniqueFwd         | UD            | UD                | I                  | 0        | SnpResp_I_Fwded_UD_PD      |
|                      |               | UC                | I                  | 0        | SnpResp_I_Fwded_UC         |
|                      |               | SC.               | I                  | 0        | SnpResp_I_Fwded_UC         |
| SnpQuery             | -             | -                 | -                  | -        | -                          |


## Writeback nested handling

When nesting may occur, each MSHR receives the request nesting information
broadcast by the MainPipe, which includes the Tag and Set addresses of the cache
line where nesting may occur, as well as the nesting behavior. The specific
signals are the ```nestwb``` port within the MSHR and the NestedWriteback Bundle
class.

Considering the potential nesting of upstream Release/ReleaseData requests and
downstream Snoop requests, the various nested processing logics required within
the MSHR are as follows.

### Feature 1: The cache line being replaced is nested with an upstream ReleaseData TtoN

This nesting occurs when the Tag and Set address of the evicted cache line in
the MSHR match the Tag and Set address of the ReleaseData TtoN broadcast from
MainPipe to all MSHRs. The corresponding signal name is ```c_set_dirty```.

This nesting typically occurs when CoupledL2 has already or is in the process of
sending a Probe toN request upstream to the L1 cache due to replacement, and the
L1 cache's reply to this Probe toN has not yet been observed by CoupledL2,
prompting the L1 cache to actively initiate a ReleaseData TtoN to CoupledL2.

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- 标记为 Dirty
- Update state to TIP.
- Update status to upstream L1 no longer holds this cache line

### Feature 2: The cache line being replaced is nested with an upstream Release TtoN

This nesting occurs when the Tag and Set address of the replaced cache line in
the MSHR match the Tag and Set address of the Release TtoN broadcast from
MainPipe to each MSHR. The corresponding signal name is ```c_set_tip```.

This type of nesting typically occurs when CoupledL2 has already or is currently
sending a Probe toN request to the upstream L1 cache due to replacement, and the
response from the upstream L1 cache to this Probe toN has not yet been observed
by CoupledL2, while the upstream L1 cache proactively initiates a Release TtoN
to CoupledL2.

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- Update state to TIP.
- Update status to upstream L1 no longer holds this cache line

### Feature 3: The cache line being replaced is nested with a downstream Snoop

This nesting occurs when the Tag and Set address of the replaced cache line in
the MSHR match the Tag and Set address of the downstream Snoop broadcast from
MainPipe to various MSHR entries. The corresponding signal name is
```b_inv_dirty```.

The downstream Snoop here must exclude the types of Snoops that cannot change
the cache line state under CHI protocol, including SnpQuery, SnpStashUnique, and
SnpStashShared.

This type of nesting typically occurs when CoupledL2 has already or is currently
sending a writeback request caused by replacement downstream, and before
receiving a CompDBIDResp response from downstream, a new Snoop request is
initiated by downstream to CoupledL2.

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- Clear State to Clean
- Update the state to INVALID
- Clear the Dirty flag set due to the upstream L1 cache responding with
  ProbeAckData

### Feature 4: Writes BRANCH state to the directory when nested snooping occurs downstream

This nesting occurs when the MSHR's Tag and Set address match the Tag and Set
address of a downstream Snoop broadcast from the MainPipe to each MSHR entry,
and the Snoop request writes the BRANCH cache line state in the MainPipe.

This type of nesting typically occurs when CoupledL2 has already or is currently
sending a writeback request caused by replacement downstream, and before
receiving a CompDBIDResp response from downstream, a new Snoop request is
initiated by downstream to CoupledL2.

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- Clear State to Clean
- If the cache line permission is not INVALID, update it to BRANCH
- Clear the Dirty flag set due to the upstream L1 cache responding with
  ProbeAckData

### Feature 5: Writing INVALID state to the directory when nested Snoop occurs downstream

This nesting occurs when the Tag and Set address of the MSHR match the Tag and
Set address of the downstream Snoop broadcast from MainPipe to each MSHR, and
the Snoop request writes an INVALID cache line state in MainPipe.

This type of nesting typically occurs when CoupledL2 has already or is currently
sending a writeback request caused by replacement downstream, and before
receiving a CompDBIDResp response from downstream, a new Snoop request is
initiated by downstream to CoupledL2.

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- Clear State to Clean
- Update the state to INVALID
- Update status to upstream L1 no longer holds this cache line
- Clear the Dirty flag set due to the upstream L1 cache responding with
  ProbeAckData
- If it is a request requiring replacement, reselect the line to be replaced

## Retry and P-Credit mechanism

If a RetryAck reply is received from downstream, the MSHR will assert the valid
bit for P-Credit query and send the CHI PCrdType and SrcID fields to the
MainPipe, which decides whether to allocate P-Credit to the corresponding
transaction in the MSHR for retry. For details on P-Credit reception and
allocation, refer to [@sec:reqarb-mainpipe] [Request Arbiter and Memory
Pipeline](ReqArb_MainPipe.md).
