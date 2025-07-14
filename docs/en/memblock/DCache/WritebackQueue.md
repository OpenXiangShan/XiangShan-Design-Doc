# Write Back Queue WritebackQueue

## Functional Description

The Writeback Queue contains 18 WritebackEntry items, responsible for writing
back replacement blocks to the L2 Cache through the C channel of TL-C (Release)
and responding to Probe requests (ProbeAck).

### Feature 1: WritebackQueue Entry Allocation and Rejection

For timing considerations, new requests will be rejected when the wbq is full;
when the wbq is not full, all requests will be accepted, and an empty entry will
be allocated for the new request. The current version no longer supports merging
requests in the WritebackQueue.

### Feature 2: Request Blocking Conditions

The TileLink specification imposes restrictions on concurrent transactions,
requiring that if a master has a pending Grant (i.e., GrantAck has not yet been
sent), it cannot issue a Release for the same address. Consequently, any miss
request entering the MissQueue that detects an entry with the same address in
the WritebackQueue will be blocked.

## Overall Block Diagram

The overall architecture of the WritebackQueue is shown in
[@fig:DCache-WritebackQueue].

![WritebackQueue
Flowchart](./figure/DCache-WritebackQueue.svg){#fig:DCache-WritebackQueue}


## Interface timing

### Request Interface Timing Example

[@fig:DCache-WritebackQueue-timing] shows the interface timing of a request that
needs to be written back to L2 in the WritebackQueue.

![WritebackQueue
Timing](./figure/DCache-WritebackQueue-timing.svg){#fig:DCache-WritebackQueue-timing}

## WritebackEntry Module
### WritebackEntry State Machine Design
State Design: The state machine design in WritebackEntry is shown in
[@tbl:WritebackEntry-state] and [@fig:DCache-WritebackEntry]:

Table: WritebackEntry State Register Descriptions {#tbl:WritebackEntry-state}

| Status         | Descrption                                         |
| -------------- | -------------------------------------------------- |
| s_invalid      | Reset state, this WritebackEntry is an empty entry |
| s_release_req  | Sending a Release or ProbeAck request              |
| s_release_resp | Waiting for ReleaseAck Request                     |

![WriteBackEntry State Machine
Diagram](./figure/DCache-WritebackEntry.svg){#fig:DCache-WritebackEntry}
