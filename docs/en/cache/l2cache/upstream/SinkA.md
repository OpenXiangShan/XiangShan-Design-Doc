# SinkA

## Functional Description
SinkA processes requests from [Bus A channel, prefetcher], converts them into
the internal task format, and then sends them to the RequestBuffer. When
requests arrive simultaneously, those from the Bus A channel have higher
priority.

### Feature 1: A channel/prefetcher blocking
When the RequestBuffer cannot accept requests from SinkA, the Bus A channel
interface/prefetcher blocks subsequent requests using the valid/ready protocol.

## Overall Block Diagram
![SinkA](./figure/SinkA.svg)
