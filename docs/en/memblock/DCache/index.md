# Data Cache DCache

<!-- TODO: 填写版本信息 -->

- Version: V2R2
- Status: WIP
- Date: 2025/02/28.
  <!-- TODO: 填写 commit -->
- commit:
  [b6c14329cbd4a204593ce03d130052f820439a08](https://github.com/OpenXiangShan/XiangShan/tree/b6c14329cbd4a204593ce03d130052f820439a08)

## Glossary of Terms

| Abbreviation | Full name | Description |
| ------------ | --------- | ----------- |
| TODO         | TODO      | TODO        |

## Submodule List

| Submodule       | Description                                  |
| --------------- | -------------------------------------------- |
| BankedDataArray | Data and ECC SRAM                            |
| MetaArray       | Metadata Register File                       |
| TagArray        | Tag and ECC SRAM                             |
| ErrorArray      | Error Flag Register Bank                     |
| PrefetchArray   | Prefetch Metadata Register File              |
| AccessArray     | Access Metadata Register File                |
| LoadPipe        | Load Access DCache Pipeline                  |
| StorePipe       | Store Access DCache Pipeline                 |
| MainPipe        | DCache Main Pipeline                         |
| MissQueue       | DCache Miss Status Handling Queue            |
| WritebackQueue  | DCache Data Writeback Request Handling Queue |
| ProbeQueue      | Probe/Snoop Request Handling Queue           |
| CtrlUnit        | DCache ECC Injection Controller              |
| AtomicsUnits    | Atomic Instruction Operation Unit            |

## DCache Design Specification

| Feature              | Description                                            |
| -------------------- | ------------------------------------------------------ |
| Data Cache           | 64KB, 4-way set-associative, 256 sets, 8 banks per set |
|                      | Virtually Indexed, Physically Tagged (VIPT)            |
|                      | Tag and each bank employ SEC-DED ECC                   |
| Cacheline            | 64 Bytes                                               |
| Replacement          | Pseudo-Least Recently Used (PLRU)                      |
| Read/Write Interface | 3*128-bit read pipeline                                |
|                      | 1*512-bit Write Pipeline                               |

### Data RAM

For each request accessing the DCache Data, the returned data from the DCache
Data SRAM follows the format represented in the table below.

| Bit Field | Description                     |
| --------- | ------------------------------- |
| [71, 64]  | 64-bit data ECC encoding result |
| [63, 0]   | 64-bit Data                     |

### Tag RAM

For each request accessing the DCache Tag, the returned data from the DCache Tag
SRAM follows the format shown in the table below.

| Bit Field | Description                    |
| --------- | ------------------------------ |
| [42, 36]  | 36-bit Tag ECC Encoding Result |
| [35, 0]   | 36-bit Tag                     |

### Meta

For each request accessing the DCache Meta, the returned data from DCache Meta
follows the format represented in the table below.

| Bit Field | Description                  |
| --------- | ---------------------------- |
| [1 : 0]   | Cacheline Coherence Metadata |
|           | 2'b00 Nothing                |
|           | 2'b01 Branch                 |
|           | 2'b10 Trunk                  |
|           | 2'b11 Dirty                  |

## Overall Block Diagram

The overall architecture of the DCache module is shown in [@fig:DCache-DCache].

![Overall DCache Architecture](./figure/DCache-DCache.svg){#fig:DCache-DCache}

## Functional Description
### Feature 1: Load Request Handling

For regular Load requests, after receiving a load instruction from the LoadUnit
(the implemented Load pipeline has three stages, capable of processing three
load requests in parallel), the DCache queries the tagArray and metaArray based
on the calculated address to determine a hit: if the cache line is hit, it
returns the data response; if a miss occurs, it allocates an MSHR (MissEntry)
entry and hands the request to the MissQueue for processing. The MissQueue is
responsible for sending an Acquire request to the L2 Cache to retrieve and
refill the data, and waits for the hint signal returned by the L2 Cache. Upon
arrival of the l2_hint, it initiates a refill request to the MainPipe, selects
the replacement way, writes the refilled data block into the storage unit, and
forwards the retrieved refill data to the LoadUnit to complete the response. If
the replaced block needs to be written back, it sends a Release request to the
L2 via the WritebackQueue to perform the writeback. If the MSHR allocation fails
for the missed request, the DCache returns an MSHR allocation failure signal,
prompting the LoadUnit and LoadQueueReplay to reschedule the load request.

### Feature 2: Store Request Handling

For a regular Store request, after receiving a store instruction from the
StoreBuffer, the DCache uses the MainPipe pipeline to calculate the address,
query the tag and meta, and determine if it hits. If the cache line is hit, it
directly updates the DCache data and returns a response. If it misses, it
allocates an MSHR to hand the request to the MissQueue, requests the original
target data line to be filled back from L2, and waits for the hint signal
returned by the L2 Cache. When the l2_hint arrives, it initiates a fill-back
request to the MainPipe, selects the replacement way, writes the refill data
block into the DCache storage unit, and returns a response to the StoreBuffer
after completing the store operation on the data. If the replaced block needs to
be written back, it sends a Release request to the L2 in the WritebackQueue to
write it back. If the MSHR allocation fails for the missing request, the DCache
will feedback an MSHR allocation failure signal, and the StoreBuffer will
subsequently reschedule the store request.

### Feature 3: Atomic Instruction Handling

For atomic instructions, the DCache's MainPipe pipeline completes the
instruction operations and read/write operations, then returns the response. In
case of a data miss, it also initiates a request to the MissQueue, retrieves the
data, and continues executing the atomic instruction. For AMO instructions, the
operation is completed first, then the result is written back. For LR/SC
instructions, the reservation set is set/checked. During the execution of atomic
instructions, no other requests are issued to the DCache from within the core
(refer to the Memblock documentation).

### Feature 4: Probe Request Handling

For Probe requests, after receiving a Probe request from the L2 Cache, the
DCache enters the MainPipe pipeline to modify the permissions of the probed data
block. Upon a hit, the response is returned in the next cycle.

### Feature 5: Replacement and Writeback

The DCache adopts a write-back and write-allocate policy, with a replacer module
calculating and deciding the block to be replaced after a miss request is filled
back. It can be configured with random, lru, or plru replacement strategies,
with plru selected by default. After selecting the replacement block, it is
placed in the WritebackQueue to send a Release request to the L2 Cache. The
missing request then reads the target data block from L2 and fills it into the
corresponding Cacheline.
