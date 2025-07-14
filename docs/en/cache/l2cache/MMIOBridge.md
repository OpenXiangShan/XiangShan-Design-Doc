# MMIO Bridge MMIOBridge

The MMIOBridge operates independently of the four slices in CoupledL2, receiving
MMIO and Uncache requests from the IFU/LSU. It interacts with the downstream
NoC/LLC via the CHI bus to complete peripheral read/write operations. By
default, the MMIOBridge contains eight MMIOBridgeEntry items, each of which is
an independent state machine handling one MMIO or Uncache request.

## State machine

State machine entries are primarily divided into two categories:

- Schedule state entry
- Wait state item

The Schedule state item, also known as the active action state item, is
primarily used to track the active tasks and requests sent by MMIOBridgeEntry to
the upstream TileLink bus and downstream CHI bus. Its value is active-low,
indicating an incomplete state—meaning the task has not yet successfully left
MMIOBridgeEntry and been issued, possibly due to unmet blocking conditions
(necessary preceding actions not completed) or channel blocking; a high value
indicates the corresponding task has been successfully issued or does not need
to be issued.

Wait state entries, also known as passive action state entries, are primarily
used to track the responses expected by an MMIOBridgeEntry from downstream CHI
channels or upstream TileLink channels. A low value indicates an incomplete
state, meaning the corresponding response has not yet returned to the current
entry; a high value indicates the response has been received or no response is
needed.

Status registers include:

| Name                | Descrption                                                                                                                                                 |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ```s_txreq```       | Send ReadNoSnp / WriteNoSnpPtl requests to the downstream TXREQ channel                                                                                    |
| ```s_ncbwrdata```   | (For write operations) Send NCBWrData packets to the downstream TXDAT channel. The prerequisite for sending NCBWrData is that ```w_dbidresp``` is asserted |
| ```s_resp```        | The CHI read/write transaction is completed, returning an AccessAckData/AccessAck response to the upstream TileLink D channel.                             |
| ```w_comp```        | (For write operations) Wait for the Comp / CompDBIDResp response returned by the downstream RXRSP channel                                                  |
| ```w_dbidresp```    | (For write operations) Wait for the CompDBIDResp / DBIDResp / DBIDRespOrd response returned by the downstream RXRSP channel                                |
| ```w_compdata```    | (For read operations) Wait for the CompData returned by the downstream RXDAT channel                                                                       |
| ```w_pcrdgrant```   | For read/write requests that encounter protocol layer retransmission, it is necessary to wait for the downstream to return a PCrdGrant.                    |
| ```w_readreceipt``` | (For read requests where Order is not None) Wait for the ReadReceipt returned by the downstream RXRSP channel                                              |

## Sequencing

The CHI requests initiated by the MMIOBridge default to RequestOrder or
EndpointOrder. When the core initiates a TileLink read/write request, it
includes the **PMA attribute in the custom field of the A channel to indicate
whether it is Memory**:

- If the PMA attribute of the address is Memory, but the PBMT attribute is IO or
  NC, the Order of the initiated CHI transaction is RequestOrder
- If the PMA attribute of the address is Memory, but the PBMT attribute is IO or
  NC, the Order of the initiated CHI transaction is EndpointOrder

Whether RequestOrder or EndpointOrder, initiated ReadNoSnp requires downstream
to return ReadReceipt for read operation ordering. Thus, MMIOBridge monitors
whether each entry is waiting for ReadReceipt (i.e., whether ```w_readreceipt```
is pulled low). If any entry is waiting for ReadReceipt, no new ReadNoSnp can be
sent downstream from any entry.

## Memory Attributes

The CHI bus protocol defines the following four dimensions of memory attributes:

- Allocate
- Cacheable
- Device
- EWA (Early Write Acknowledgment)

For requests initiated by MMIOBridge, Allocate and Cacheable are always 0;
Device depends on the PMA attribute—if the PMA attribute is Memory, Device is 0,
otherwise Device is 1; EWA can be understood as whether the address can be
Buffered. If the PMA attribute of the address is Memory, or the PMA attribute is
not Memory but the PBMT attribute is NC, the address is considered Bufferable,
and EWA is set to 1; otherwise, EWA is set to 0.

## P-Credit arbitration

MMIOBridge supports protocol-layer retransmission on the CHI bus. According to
the CHI bus protocol, a transaction can initiate protocol-layer retransmission
only after receiving RetryAck and PCrdGrant. The TxnID of RetryAck matches the
TxnID of the request on the TXREQ channel, so RetryAck can be mapped one-to-one
with entries in MMIOBridge via TxnID. However, PCrdGrant only requires the SrcID
and PCrdType fields to match RetryAck, and cannot be directly matched with
entries in MMIOBridge via TxnID.

Based on the CHI protocol specifications, when CoupledL2 receives a PCrdGrant,
it cannot directly determine whether the P-Credit should be arbitrated to the
MMIOBridge or the four slices based on the PCrdGrant fields, nor can it
determine how to map the P-Credit to a specific MMIOBridgeEntry or MSHR.
Therefore, the P-Credit arbitration logic resides at the top level of CoupledL2.
Upon receiving a PCrdGrant, CoupledL2 temporarily stores it in a top-level
register (recording key fields such as SrcID and PCrdType). The
MSHR/MMIOBridgeEntry that receives a RetryAck will match the RetryAck's SrcID
and PCrdType with the PCrdGrant register bank. If a match is found, the
corresponding register entry is released; if not, it will wait for a downstream
PCrdGrant until a successful match occurs.
