# Probe Queue: ProbeQueue

## Functional Description
Responsible for receiving and processing coherence requests from L2, comprising
8 ProbeEntries, each handling one Probe request. It converts Probe requests into
internal signals and sends them to the MainPipe, which modifies the permissions
of the probed block. The ProbeEntry is released once the MainPipe returns a
response.

The ProbeQueue only interacts with L2 through Channel B and connects with the
MainPipe. Internally, it consists of 8 ProbeEntry items, each controlled by a
set of status registers for receiving, converting, and sending request signals.

### Feature 1: Aliasing Issue

The Kunminghu architecture employs a 64KB VIPT cache, introducing cache aliasing
issues. To address aliasing, the L2 Cache directory maintains alias bits for
each physical block stored in the DCache. When the DCache attempts to access a
block with a different alias bit at a physical address, the L2 Cache initiates a
Probe request to evict the original aliased block from the DCache, recording its
alias bit in the TileLink B channel. Upon receiving the request, the ProbeQueue
concatenates the alias bit with the page offset, converts it into an internal
signal, and sends it to the MainPipe, which then accesses the DCache storage
module to read the data.

### Feature 2: Blocking Caused by Atomic Instructions

Since atomic operations (including lr-sc) are completed in the DCache, when
executing an LR instruction, it ensures the target address is already in the
DCache. To simplify the design, the LR instruction registers a reservation set
in the MainPipe, recording the LR address and blocking Probes to that address.
To avoid deadlocks, the MainPipe will stop blocking Probes after waiting for the
SC instruction for a certain period (determined by parameters LRSCCycles and
LRSCBackOff). At this point, any received SC instruction is considered an SC
fail. Therefore, during the time between registering the reservation set by LR
and waiting for the matching SC, Probe requests must be blocked from operating
on the DCache.

## Overall Block Diagram

The overall architecture of the ProbeQueue is shown in [@fig:DCache-ProbeSnoop].

![ProbeSnoop Flowchart](./figure/DCache-ProbeSnoop.svg){#fig:DCache-ProbeSnoop}



## Interface timing
### Request Interface Timing Example

[@fig:DCache-ProbeSnoop-Timing] illustrates the interface timing for the Probe
Queue processing a probe request. The Probe Queue first receives the probe
request from L2, converts it into an internal request, and allocates an empty
ProbeEntry. After a one-cycle state transition, it can send the probe request to
the MainPipe. However, due to timing considerations, this request is delayed by
another cycle (as selecting an entry in the ProbeQueue involves an arbiter, and
the MainPipe entry also has an arbiter to choose requests from various
sources—completing both arbitrations in one cycle is challenging, hence the
additional cycle of latching). Thus, pipe_req_valid is asserted two cycles
later. Subsequently, upon receiving the MainPipe's response, the ProbeEntry is
released.

![ProbeSnoop
Timing](./figure/DCache-ProbeSnoop-Timing.png){#fig:DCache-ProbeSnoop-Timing}

## ProbeEntry module

The Probe Entry is controlled by a series of status registers, with a state
machine executing Probe transactions. [@tbl:ProbeEntry-state] illustrates the
meaning of the three status registers contained in each Entry, and the state
machine design is shown in [@fig:DCache-ProbeEntry].

Table: ProbeEntry Status Register Descriptions {#tbl:ProbeEntry-state}

| Status      | Descrption                                                             |
| ----------- | ---------------------------------------------------------------------- |
| s_invalid   | Reset state: This Probe Entry is empty.                                |
| s_pipe_req  | Probe request allocated, sending Main Pipe request                     |
| s_wait_resp | Main Pipe request transmission completed, awaiting Main Pipe response. |

![ProbeEntry State
Machine](./figure/DCache-ProbeEntry.svg){#fig:DCache-ProbeEntry}

