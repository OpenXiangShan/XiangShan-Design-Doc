# RXDAT

## Functional Description
Accept the response message with data from the RXDAT channel, store the data in
the RefillBuffer, and simultaneously send the response to MSHRCtl, using the
txnID in the message to identify the mshrID. The responses that CHI.IssueB needs
to handle include: CompData. The responses that CHI.IssueC needs to handle
include: DataSepResp.

## Overall Block Diagram
![RXDAT](./figure/RXDAT.svg)

## Interface timing
Notify MSHR in the same cycle when receiving the request. If it is the first
beat, latch it; if it is the second beat, combine it with the data from the
first beat and write it into the RefillBuf in the same cycle.


