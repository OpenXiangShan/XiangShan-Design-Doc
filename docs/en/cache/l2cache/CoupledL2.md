# L2 Cache Base Design: CoupledL2

## Submodule List

The top level of CoupledL2 consists of multiple Slices, MMIOBridge, and prefetchers.

XSAI adds the HBL2 matrix memory extension to CoupledL2. Matrix requests enter through TileLink channel A and share CoupledL2's directory, main pipeline, MSHRs, and coherence mechanism; matrix read data returns through a separate MatrixDataOut interface in each Slice. See [Matrix memory access path HBL2](HBL2.md) for detailed specifications, Get/Put flows, and response ordering, and [Optional matrix-guided prefetching](MatrixPrefetch.md) for matrix prefetching.

The default prefetchers include the L2-local Best-Offset Prefetch (BOP) and a receiver for L1 DCache prefetch requests.

MMIOBridge, or MMIO request bridge, converts TileLink bus MMIO requests into CHI requests. It arbitrates between these and cacheable address space CHI requests, accessing the interconnect bus through a unified CHI interface.

Slices are selected by the low-order bits of the cache-line address, distributing requests and prefetch addresses across different Slices.

The list of submodules in each Slice is as follows:

| Submodule                 | Descrption                                                                                           |
| ------------------------- | ---------------------------------------------------------------------------------------------------- |
| SinkA                     | Upstream TileLink bus A channel controller.                                                          |
| SinkC                     | Upstream TileLink Bus C Channel Controller                                                           |
| GrantBuffer               | Upstream TileLink bus D/E channel controller                                                         |
| TXREQ                     | Downstream CHI bus TXREQ channel controller                                                          |
| TXDAT                     | Downstream CHI bus TXDAT channel controller                                                          |
| TXRSP                     | Downstream CHI Bus TXRSP Channel Controller                                                          |
| RXSNP                     | Downstream CHI bus RXSNP channel controller                                                          |
| RXDAT                     | Downstream CHI bus RXDAT channel controller                                                          |
| RXRSP                     | Downstream CHI Bus RXRSP Channel Controller                                                          |
| Directory                 | Directory, SRAM storing metadata information                                                         |
| DataStorage               | Data SRAM                                                                                            |
| RefillBuffer              | Refill data register file.                                                                           |
| ReleaseBuffer             | Release data register file                                                                           |
| [PutBuffer](PutBuffer.md) | Collects full-line write data for channel A PutFullData requests                                     |
| RequestBuffer             | A-channel request buffer                                                                             |
| RequestArb                | Request arbiter, main pipeline stages s0~s2.                                                         |
| MainPipe                  | Main pipeline stages s3~s5.                                                                          |
| MSHRCtl                   | MSHR (Miss Status Handling Registers) control module                                                 |
| CustomL1Hint              | Manages early-wakeup information for upstream responses                                              |


## Design specifications

- Interconnects with the upstream L1Cache / PTW using the TileLink bus protocol
- Uses the CHI bus protocol with downstream HN-F, supporting the three CHI versions B/C/E.b, selected by `CHIIssue`
- Supports the following CHI Read transactions:

    - ReadNoSnp (B/C/E.b) (used only for MMIO and Uncache requests)
    - ReadNotSharedDirty (B/C/E.b)
    - ReadUnique (B/C/E.b)

- Supports the following CHI Dataless transactions:

    - MakeUnique (B/C/E.b)
    - Evict (B/C/E.b)
    - CleanShared (B/C/E.b)
    - CleanInvalid (B/C/E.b)
    - MakeInvalid (B/C/E.b)

- Supports the following CHI Write transactions:

    - WriteNoSnpPtl (B/C/E.b) (Only used for MMIO and Uncache requests)
    - WriteBackFull (B/C/E.b)
    - WriteCleanFull (B/C/E.b)
    - WriteEvictOrEvict (E.b)

- Supports the following CHI Snoop transactions:

    - SnpOnceFwd (B/C/E.b)
    - SnpOnce (B/C/E.b)
    - SnpStashUnique (B/C/E.b)
    - SnpStashShared (B/C/E.b)
    - SnpCleanFwd (B/C/E.b)
    - SnpClean (B/C/E.b)
    - SnpNotSharedDirtyFwd (B/C/E.b)
    - SnpNotSharedDirty (B/C/E.b)
    - SnpSharedFwd (B/C/E.b)
    - SnpShared (B/C/E.b)
    - SnpUniqueFwd (B/C/E.b)
    - SnpUnique (B/C/E.b)
    - SnpUniqueStash (B/C/E.b)
    - SnpCleanShared (B/C/E.b).
    - SnpCleanInvalid (B/C/E.b)
    - SnpMakeInvalid (B/C/E.b)
    - SnpMakeInvalidStash (B/C/E.b)
    - SnpQuery (E.b)

- Adopting a MESI-like cache coherence protocol
- Adopts a strict inclusion policy with DCache and a non-strict inclusion policy with ICache / PTW.
- Adopts a non-blocking main pipeline structure
- Supports parallel access to requests in the same set.
- Supports selecting and replacing the replacement way after receiving the refill data for L2 Cache misses.
- Supports merging an Acquire request with an outstanding prefetch at the same address
- Supports generating L2 Refill Hint signals for early wake-up of Load instructions.
- Supports BOP prefetcher
- Supports handling prefetch requests trained by L1 and backfilled to L2.
- Supports replacement algorithms such as DRRIP / PLRU, defaulting to DRRIP
- Supports hardware handling of cache aliasing
- Supports MMIO request handling. MMIO requests are converted from TileLink to CHI in CoupledL2 and arbitrated with cacheable requests from the Slices

## Functional Description

CoupledL2 receives TileLink refill and replacement requests from the Xiangshan core's DCache / ICache / PTW. It transfers the corresponding data blocks and updates coherence states, while acting as RN-F in the on-chip network to maintain the Xiangshan core's cache coherence in the on-chip interconnect.

The CoupledL2 module receives requests through the upstream TileLink channel controllers (SinkA / SinkC) and converts them into internal requests. The requests enter the main pipeline through request arbitration, read the directory to obtain the cache block state, and determine whether they can be processed based on the cache block state and request information:

- If this cache level can directly process the request, it continues with data reads, directory updates, and other operations in the main pipeline, then enters GrantBuffer.
- If interaction with other caches is required to process the request, an MSHR is allocated. The MSHR sends sub-requests to upper and lower-level caches as needed. Upon receiving responses and meeting release conditions, the task is released back into the main pipeline for operations like reading buffers, reading/writing data, and updating the directory. It then proceeds to the channel controller module, converting into a TileLink bus response.

When all operations required by a request are completed in the MSHR, the MSHR is released and waits to receive a new request.

### Adopting a MESI-like cache coherence protocol

The cache subsystem of the Xiangshan core follows the rules of the TileLink consistency tree. The cache line states in CoupledL2 include N (Nothing), B (Branch), T (Trunk), and TT (Tip) four states:

- N: Invalid
- B: Read-only permission
- T: The current core has write permission, but the write permission is located in the upstream cache, and the current cache level is neither readable nor writable.
- TT: Readable and writable.

The coherence tree grows from the bottom up in the order of memory, L3, L2, and L1, with memory as the root node having read-write permissions. The permissions of child nodes cannot exceed those of their parent nodes. Here, TT represents the topmost child node with T permissions (also the leaf node of the T permission tree), indicating that only N or B permissions exist above this node. Conversely, a node with T permissions but not TT permissions signifies that there must be T/TT permission nodes above it. For detailed rules, please refer to the TileLink manual.

### Uses a directory to record cache line information

CoupledL2 is a directory-based Inclusive Cache (the "directory" here is broadly defined, including metadata and Tag). Metadata includes: state bits / dirty bit / whether in upper-level cache clients / alias bits in upper level / whether prefetched / prefetch source / whether accessed.

At pipeline stage s1, RequestArb issues a directory read, checks the Tag Array for a hit, and returns the hit way's metadata to MainPipe s3. A miss first allocates an MSHR. After data or the required permission returns, the MSHR task queries a replacement way and schedules release of the old cache line.

### Adopts a non-blocking pipeline structure

CoupledL2 adopts a main pipeline architecture. Requests from various channels are arbitrated into the main pipeline for directory operations. Based on the request information and directory results, corresponding response operations are arranged:

#### Acquire Request Processing Flow

As shown in [@fig:acquire].

![Acquire request processing flow](./figure/CHI-CoupledL2-Acquire.svg){#fig:acquire}

#### Snoop Request Processing Flow

As shown in [@fig:snoop].

![Snoop Request Processing Flow](./figure/CHI-CoupledL2-Snoop.svg){#fig:snoop}

#### Release request processing flow.

The Release request processing flow is as follows:

1. Receives Release requests from L1 DCache from SinkC and converts them into internal requests.
2. s1 Release request enters the pipeline and queries the directory
3. s3 obtains the directory lookup result (since L1 DCache and L2 have a strict inclusion relationship, Release will always hit); s3 writes the directory, and if there is dirty data, it needs to be written into DataStorage at s3
4. s3 generates a ReleaseAck response, which exits the pipeline at one of the stages between s3 and s5, enters the GrantBuffer, and returns the ReleaseAck to L1.

### Replace path selection and replacement are performed after receiving the refill data.

When the cache receives a new request but the set is full, according to conventional logic, it first needs to select a replacement way, write it to the lower-level cache to free up space for the upcoming refill of missing data, then wait for the new data block to be refilled from the lower-level cache before writing it in. However, this approach can lead to certain issues:

1. On one hand, refilling from lower-level caches often involves long latencies (tens to thousands of cycles). During this period, the old data block has been evicted while the new one hasn't arrived, leaving the cache location effectively empty. This results in idle and wasted cache resources, reducing the effective cache capacity.

2. On the other hand, if during this period the upper-level cache attempts to access the replaced data block again, since the data block has already been released, it can only be fetched again from the lower-level cache, significantly increasing the access latency.

CoupledL2 delays the selection of the replacement way and the release of the replaced data until the refill data is received. Specifically, when a request enters the cache, directory information is read to determine whether it is a hit. If it is a hit, the data is read and returned (standard process). If it is a miss, CoupledL2 does not select a replacement block based on the directory read result or schedule the release of the replacement block. Instead, it only allocates an MSHR entry and sends a request to the lower-level cache to fetch the data. After the lower level returns the refill data, the MSHR task reads the directory again, at which point the replacement block is selected, the data of the replacement block is read from the data storage unit, and released to the lower-level cache. Finally, the new data block is written into the storage unit.

Since interaction with DataStorage only occurs at stage s3 of the MainPipe, and the SRAM in DataStorage is single-ported, we cannot use a single MSHR Task to simultaneously (1) read out the content of the replaced data block and release it to the lower-level cache, and (2) write the new data block. Therefore, these two operations need to be divided into two tasks: MSHR Refill and MSHR Release, with Refill being issued before Release. Based on two additional considerations: (1) reading the old data must occur before writing the new data, and (2) data must be returned to L1 as quickly as possible, we assign the following tasks to the two MSHR Tasks respectively:

- MSHR Refill: Read the RefillBuffer to obtain the refill data and feed it back to L1; read DataStorage to retrieve the old data and store it in ReleaseBuf; update the directory with the metadata of the new data.
- MSHR Release: Read the ReleaseBuf and release the data to L3; read the RefillBuffer and write the refill data into DataStorage.

### Supports parallel access to requests within the same Set

CoupledL2 supports parallel access for multiple requests to the same set. For multiple requests to the same set, these requests do not need to select a replacement way before receiving refill data, and can therefore be accessed in parallel until the refill data arrives. Upon receiving the refill data, the MSHR begins selecting a replacement way and writes the evicted block to the next-level cache. When selecting a replacement way, the directory must ensure it does not select a way that is currently being replaced, thereby guaranteeing that multiple requests to the same set will always select different replacement ways.

### Early wake-up of Load instructions

CoupledL2 sends Refill Hints through CustomL1Hint before returning response data, allowing the core's LoadQueue to wake Loads waiting for refill. Hints and responses are processed in queue order; their actual separation depends on the pipeline and response-channel handshakes.

### Supports hardware prefetching

CoupledL2's hardware prefetcher receives BOP prefetch requests and requests from L1 DCache and sends them to each Slice's prefetch queue. Conventional speculative prefetching uses OverwriteQueue, allowing new requests to overwrite older ones when full.

### Supports request merging {#sec:coupledl2-request-merge}

Experimental observations reveal that a significant portion of untimely prefetches exist in the L2 Cache. Although the prefetcher predicts future data needs, the requests are sent too late. When the cache miss caused by prefetching is still waiting for data from the lower-level cache in the MSHR, an Acquire request for the same address has already arrived at L2. To prevent such Acquire requests from being blocked at the RequestBuffer entry, which would occupy the L2 entry and prevent subsequent requests from entering, the current L2 design implements a mechanism to merge untimely Prefetch requests with subsequent Acquire requests for the same address. The request merging functionality is implemented as follows:

1.  At the RequestBuffer entry of the SinkA channel, determine whether an A request from L1 meets the merge conditions: the new request is an Acquire, and there exists a miss request in MSHRs that is a Prefetch with the same address as the Acquire.
2.  If the merge conditions are met, the new request does not need to enter the queue and be blocked. Instead, it directly enters the MSHR entry corresponding to the same-address Prefetch, marks the entry with mergeA, and adds a series of new request status information to include the contents of both requests.
3.  When the target data returns from L3, the MSHR entry is awakened, and a task is sent to the main pipeline for processing. In the main pipeline, a replacement way is selected and new data is backfilled, while the meta of the data block is updated to the state after the Acquire request is processed. At the same time, the request also passes information to the prefetcher as training.
4.  When processing request responses, this merge request enters the GrantBuffer from the main pipeline. For Prefetch requests, L2 returns a prefetch response; for Acquire requests, L2 returns data and responses to the upstream node that issued the Acquire via the grantQueue queue.

### Supports hardware handling of cache aliasing

The L1 Cache of the Xiangshan core adopts the VIPT indexing method, where the DCache is a 64KB 4-way set-associative structure. The index and block offset used to access the DCache exceed the page offset of a 4KB page, introducing the Cache alias problem: as shown in [@fig:cache-alias], when two virtual pages map to the same physical page, the alias bits (the portion of the index exceeding the 4KB page offset) of the two virtual pages are likely to differ. Without additional handling, the VIPT indexing would place the cache blocks from the two virtual pages in different sets of the DCache, resulting in the same physical address being cached twice in the DCache. If the DCache does not handle this, it could lead to cache coherence errors.

![Cache alias principle diagram](./figure/CHI-CoupledL2-cache-alias.svg){#fig:cache-alias}

The Xiangshan core resolves cache aliasing issues in hardware via CoupledL2. Specifically, CoupledL2 records the alias bits of upper-level data, ensuring that a physical address cache block has at most one alias bit in the L1 DCache. When an upper-level cache sends an Acquire request with alias bits, the L2 Cache checks the directory. If it hits but the alias bits are inconsistent, it Probes the previously recorded alias bits to the upper-level cache and writes the Acquire's alias bits into the directory.

## Overall design

### Overall Block Diagram

The connection between the Xiangshan core and CoupledL2 is shown below. See the [HBL2 matrix path diagram](HBL2.md#fig:xsai-hbl2) for matrix request and response paths.

![XSTile Block Diagram](./figure/CHI-CoupledL2-SoC.svg){#fig:xstile}


The microarchitecture block diagram of CoupledL2 is shown in [@fig:coupledl2-microarch].

![CoupledL2 Microarchitecture Diagram](./figure/CHI-CoupledL2-microArch.svg){#fig:coupledl2-microarch}
