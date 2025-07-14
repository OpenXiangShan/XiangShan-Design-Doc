# Level-3 Module: Prefetcher

The Prefetcher refers to the following module:

* L2TlbPrefetch prefetch

## Design specifications

1. Supports Next-line prefetching algorithm
2. Supports filtering duplicate historical requests

## Function

### Issue a prefetch request

A prefetch request is issued when either of the following two conditions is met:

1.  Page Cache miss
2.  Page Cache hit, but the hit is on a prefetched entry

The Prefetcher employs the Next-Line prefetching algorithm. Prefetched results
are stored in the Page Cache and are not returned to the L1 TLB. Due to the
limited memory access capability of the Page Table Walker, prefetch requests do
not enter the Page Table Walker or Miss Queue but are directly discarded. When a
prefetch request is only missing the last-level page table, it can access the
LLPTW. Additionally, a Filter Buffer is added to the Prefetcher to filter
duplicate prefetch requests.

### Filter duplicate historical requests

To avoid wasting L2 TLB resources with duplicate requests and improve Prefetcher
utilization, when the two conditions described in Section 5.3.11.2 are met and a
prefetch request is issued, it checks whether a prefetch request for the same
address has already been issued. If so, the newly received prefetch request is
discarded. The current Prefetcher module filters the most recent 4 requests.

## Overall Block Diagram

The overall block diagram of the Prefetcher is shown in
[@fig:MMU-prefetcher-overall]. A prefetch request is generated when the Page
Cache misses or hits on a prefetched entry. The Filter Buffer can be used to
filter duplicate prefetch requests.

![Overall block diagram of the
Prefetcher](../figure/image44.png){#fig:MMU-prefetcher-overall}

## Interface timing

The Prefetcher is a next-line prefetcher with relatively simple interface
timing, which will not be elaborated here.

