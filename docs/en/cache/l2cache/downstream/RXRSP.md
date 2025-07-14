# RXRSP

## Functional Description
Receives response messages without data from the RXRSP channel and directly
forwards them to MSHRCtl, using the txnID in the message to identify the mshrID.
Responses that CHI.IssueB needs to handle include: Comp, CompDBIDResp, Retry,
PCrdGrant. CHI.IssueC requires responses: RespSepData

## Overall Block Diagram
![RXRSP](./figure/RXRSP.svg)
