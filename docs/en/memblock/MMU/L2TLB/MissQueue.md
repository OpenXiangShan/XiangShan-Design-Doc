# Level-3 Module: Miss Queue

The Miss Queue refers to the following module:

* L2TlbMissQueue missQueue

## Design specifications

1. 缓冲请求等待资源

## Function

### 缓冲请求等待资源

The essence of the Miss Queue is a queue that receives requests from the Page
Cache and the Last Level Page Table Walker, and sends them to the Page Cache. If
the Page Cache sends a request to the PTW but the request is isFirst or the PTW
is busy, it is sent to the Miss Queue. Similarly, if the Page Cache sends a
request to the LLPTW but the LLPTW is busy, it is also sent to the Miss Queue.

## Overall Block Diagram

The overall structure of the Miss Queue is relatively simple and will not be
elaborated further. For the connection relationships between the Miss Queue and
other modules in the L2 TLB, refer to Section 5.3.3.

## Interface timing

The essence of the Miss Queue is a queue, and its interface timing is relatively
straightforward, so it will not be elaborated further.
