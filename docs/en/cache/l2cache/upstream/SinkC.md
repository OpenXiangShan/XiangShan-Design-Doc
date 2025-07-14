# SinkC

## Functional Description
SinkC receives requests from the C channel of the bus
(Release/ReleaseData/ProbeAck/ProbeAckData), with an internal Buffer depth of 3.
It uses the valid/ready handshake protocol to block the C channel and performs
the following operations: a. If the request is Release(Data), it allocates a
buffer entry to save it, and when the pipeline is ready to accept the C request,
sends it to RequestArb to enter the main pipeline; if it contains data, delays
it by two cycles and sends the data to MainPipe when the request reaches S3; b.
If the request is ProbeAckData, it directly sends feedback to MSHR while writing
its data into ReleaseBuf.

### Feature 1: RefillBuffer Override
Currently, the missing refill operation first returns data to L1, then schedules
the refill data (in RefillBuf) to be written into L2's DataStorage, creating a
time gap between these two steps. If dirty data is released from L1 during this
interval, to ensure the latest data is written to L2, we have ReleaseData also
synchronously write its data into RefillBuf, overriding the existing refill
data.

### Feature 2: ReleaseBuffer Override
When MSHR processes a release that requires probing L1D$, this ProbeAckData,
upon matching the release in MSHR, actively writes the data into ReleaseBuf.

## Overall Block Diagram
![SinkC](./figure/SinkC.svg)
