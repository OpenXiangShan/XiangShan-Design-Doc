# TXDAT

## Functional Description
The TXDAT module unconditionally accepts requests from the MainPipe destined for
the WDAT channel, buffers them in a queue, and ultimately sends them to the CHI
TXDAT bus channel. The TXDAT module must control the flow at the MainPipe entry
to ensure that requests on the MainPipe can enter TXDAT without being blocked.

## Functional Description
### Feature 1: Backpressure on the MainPipe
To ensure that requests on the MainPipe can non-blockingly enter TXDAT at stages
s3/s4/s5, when [the number of requests on the MainPipe that may need to enter
TXDAT + the number of valid entries in the queue ≥ the total queue capacity],
the TXDAT module must apply backpressure to the MainPipe entry stages, i.e.,
s0/s1.
1. Backpressure is applied at stage s1 because snoops received by RXSNP may be
   directly processed on the MainPipe and then enter the TXDAT channel, so
   backpressure must be applied to the sinkB requests at s1.
2. Backpressure is applied at stage s0 because some MSHR tasks need to enter the
   TXDAT channel. Since MSHR tasks enter the pipeline at s0, backpressure must
   be applied to the mshrTask at s0.

![TXDAT](./figure/TXDAT.svg)
