# TXREQ

## Functional Description
The TXREQ module receives requests from both the MainPipe and MSHR modules
directed to the REQ channel, arbitrates between them, buffers them in a queue,
and finally sends them to the CHI TXREQ bus channel. Requests from the MainPipe
exit are unconditionally accepted, while requests from the MSHR may be blocked.
Therefore, the TXREQ module needs to apply backpressure to the MSHR and
implement flow control at the MainPipe entry to ensure that requests on the
MainPipe can enter TXREQ without being blocked.

## Functional Description
### Feature 1: Flow Control at MainPipe Entry
To ensure that requests on the MainPipe can enter TXREQ non-blockingly at stages
s3/s4/s5, when inflight = the number of potential requests from MainPipe stages
s1/s2/s3/s4/s5 that may need to enter TXREQ + the number of valid entries in the
queue ≥ the total queue size (size=16), the TXREQ module must apply backpressure
to the MainPipe entry at stage s0 (since only MSHR sends requests downstream to
TXREQ, and MSHR tasks enter the pipeline at stage s0, backpressure is only
needed for MSHR requests at s0). Due to tight timing at s1, the handling of
potential TXREQ usage for MainPipe requests at s1 is as follows: initially
assume all s1 requests will use TXREQ, and if s2 finds no usage, the inflight
count is decremented by 1.

For now, the blocking condition is denoted as noSpace.

### Feature 2: Backpressure Logic for MSHR
1. The arbitration priority of MainPipe is higher than that of MSHR, so when a
   request from the MainPipe exit is valid, backpressure must be applied to the
   MainPipe.
2. Backpressure must be applied to the MainPipe when noSpace is true for the
   following reason: in the same cycle that MSHR sends a request, the MainPipe
   may have no requests competing with MSHR, but there could be requests in the
   MainPipe at stages s1/s2. The MSHR request might occupy queue slots that
   would otherwise be available for MainPipe requests, causing insufficient
   queue slots when MainPipe requests reach stages s3/s4/s5. Therefore, MainPipe
   requests must also be blocked in this scenario.

## Overall Block Diagram
![TXREQ](./figure/TXREQ.svg)
