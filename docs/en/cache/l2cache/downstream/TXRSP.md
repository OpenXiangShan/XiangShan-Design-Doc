# TXRSP

## Functional Description
The TXRSP module receives requests from both the MainPipe and MSHR modules
directed to the TXRSP channel, arbitrates between them, buffers them in a queue,
and ultimately sends them to the CHI TXRSP bus channel. Requests from the
MainPipe exit are unconditionally accepted, while requests from MSHR may be
blocked. Therefore, the TXRSP module needs to apply backpressure to MSHR and
implement flow control at the MainPipe entry to ensure that requests on the
MainPipe can enter TXRSP without obstruction.

### Feature 1: Flow Control at MainPipe Entry
1. To ensure that requests on the MainPipe can enter TXRSP non-blockingly at
   s3/s4/s5, when [the number of requests on the MainPipe that may need to enter
   TXRSP + the number of valid entries in the queue ≥ the total queue capacity],
   the TXREQ module must apply backpressure at the MainPipe entry, i.e., the
   s0/s1 stages.
2. Backpressure at the s1 stage is necessary because snoops received by RXSNP
   may be processed directly on the MainPipe and then enter the TXRSP channel,
   requiring backpressure on s1's sinkB requests. Backpressure at the s0 stage
   is needed because some MSHR tasks must enter the TXRSP channel, and MSHR
   tasks enter the pipeline at s0, necessitating backpressure on s0's mshrTask.
   The blocking condition is temporarily denoted as noSpace.

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
![TXRSP](./figure/TXRSP.svg)

