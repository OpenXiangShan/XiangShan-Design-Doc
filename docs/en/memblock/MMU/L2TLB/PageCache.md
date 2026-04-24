# Level-3 Module: Page Cache

Page Cache refers to the following module:
* PtwCache cache

## Design specifications

1. Supports separate caching of three-level page tables.
2. Supports receiving PTW requests from L1 TLB
3. Supports receiving PTW requests from the Miss Queue.
4. Support returning hit results to the L1 TLB and sending PTW replies
5. Supports returning miss results to L2 TLB and forwarding PTW requests
6. Support for Page Cache refill
7. Supports ECC verification
8. Supports SFENCE flush
9. Supports exception handling mechanism
10. Support for TLB compression
11. Supports classifying all levels of page tables into three types
12. Supports accepting second-stage translation requests (HPTW requests)
13. Supports HFENCE flush

## Function

### Separately cache the level-3 page tables

The Page Cache is an "enlarged" version of the L1 TLB and effectively serves as
the L2 TLB. It separately caches three-level page tables, enabling single-cycle
queries of three-level information (the H extension further divides each level
into VS-stage page tables, G-stage page tables, and host page tables, which will
be discussed in later chapters). The Page Cache determines hits based on the
requested address, obtaining results closest to the leaf nodes. Since the memory
access width is 512 bits (i.e., 8 page table entries), each Page Cache entry
contains 8 page tables (1 virtual page number corresponding to 8 physical page
numbers and 8 permission bits).

In the Page Cache, entries are cached according to the page table level, divided
into five categories: l3, l2, l1, l0, and sp. The l3, l2, l1, and l0 entries
store only valid page table entries, respectively storing Sv48 root page table
(512GB), Sv39 root page table (1GB), intermediate page table (2MB), and leaf
page table (4KB). l3 and l2 each contain 16 entries in a fully associative
structure; l1 contains 8 entries in a 2-way set-associative structure; l0
contains 256 entries in a 4-way set-associative structure. sp is a 16-entry
fully associative structure that stores large pages (leaf node page tables of
2MB, 1GB, 512GB) as well as invalid (V bit is 0 in the page table, or W bit is 1
and R bit is 0 in the page table, or the page table is misaligned) first-level
and second-level page tables. When storing, l1, l2, and l3 entries do not need
to store permission bits; l0 and sp entries need to store permission bits.

The configuration items of Page Cache are as shown in [@tbl:PageCache-config].

Table: Page Cache Entry Configuration {#tbl:PageCache-config}

| **entry** |     **item count**     | ** organizational structure ** | **Implementation method** | **Replacement Algorithm** |                                                       **stored content**                                                       |
| :-------: | :--------------------: | :----------------------------: | :-----------------------: | :-----------------------: | :----------------------------------------------------------------------------------------------------------------------------: |
|    l0     | 256 (64 sets × 4 ways) |     4-way set-associative      |           SRAM            |           PLRU            |                                         4KB page table, needs to store permission bits                                         |
|    l1     |  8 (4 sets × 2 ways)   |     2-way set-associative      |           SRAM            |           PLRU            |                                     2MB page table, does not need to store permission bits                                     |
|    l2     |           16           |       Fully associative        |       Register heap       |           PLRU            |                                     1GB page table, does not need to store permission bits                                     |
|    l3     |           16           |       Fully associative        |       Register heap       |           PLRU            |                                    512GB page table, does not need to store permission bits                                    |
|    sp     |           16           |       Fully associative        |       Register heap       |           PLRU            | Large pages (leaf node page tables of 2MB, 1GB, 512GB) and invalid page table entries, need to store permission bits and level |

The information that a Page Cache entry needs to store includes: tag, asid, ppn,
perm (optional), level (optional), prefetch. The H extension adds vmid and h
(used to distinguish three types of page tables). Among them, the stored
information for each entry is related to the address translation mode (Sv39 or
Sv48), as follows: The l3 entry exists only in Sv48 mode, adopts a fully
associative structure, the tag width is vpnnlen (9) + H extension bits (2) = 11
bits. The l2 entry adopts a fully associative structure; in Sv39 mode, the tag
width is vpnnlen (9) + H extension bits (2) = 11 bits; in Sv48 mode, the tag
width is 2 * vpnnlen (18) + H extension bits (2) = 20 bits. The l1 entry adopts
a 2-way set-associative structure (4 sets × 2 ways); in Sv39 mode, the tag width
is 2 * vpnnlen(18) - log2(4) - log2(8) + H extension bits (2) = 18 - 2 - 3 + 2 =
15 bits; in Sv48 mode, the tag width is 3 * vpnnlen(27) - log2(4) - log2(8) + H
extension bits (2) = 27 - 2 - 3 + 2 = 24 bits. The l0 entry adopts a 4-way
set-associative structure (64 sets × 4 ways); in Sv39 mode, the tag width is 3 *
vpnnlen(27) - log2(64) - log2(8) + H extension bits (2) = 27 - 6 - 3 + 2 = 20
bits; in Sv48 mode, the tag width is 4 * vpnnlen(36) - log2(64) - log2(8) + H
extension bits (2) = 36 - 6 - 3 + 2 = 29 bits. The sp entry adopts a fully
associative structure; in Sv39 mode, the tag width is 3 * vpnnlen(27) + H
extension bits (2) = 29 bits; in Sv48 mode, the tag width is 4 * vpnnlen(36) + H
extension bits (2) = 38 bits. For l3 and sp entries, since they store leaf
nodes, they need to store the perm entry, while l1 and l2 entries do not. The
perm entry stores the D, A, G, U, X, W, R bits defined in the RISC-V manual, and
does not need to store the V bit. For the sp entry, it needs to store the level,
indicating the level of the page table (first or second). prefetch indicates
that the page table entry was obtained by a prefetch request; vmid is only used
in VS-stage page tables and G-stage page tables; asid is not used in G-stage
page tables; h is a two-bit register that distinguishes these three types of
page tables, with encoding consistent with s2xlate. The information that a Page
Cache entry needs to store is shown in [@tbl:PageCache-store-info], and the
attribute bits of the page table are shown in [@tbl:PageCache-item-attribute]:

Table: Information to be stored in Page Cache entries
{#tbl:PageCache-store-info}

| **entry** | **tag (Sv39 / Sv48)** | **asid** | **vmid** | **ppn** | **perm** | **level** | **prefetch** | **h** |
| :-------: | :-------------------: | :------: | :------: | :-----: | :------: | :-------: | :----------: | :---: |
|    l0     |   20 bits / 29 bits   |   Yes    |   Yes    |   Yes   |   YES    |    NO     |     Yes      |  Yes  |
|    l1     |   15 bits / 24 bits   |   Yes    |   Yes    |   Yes   |    NO    |    NO     |     Yes      |  Yes  |
|    l2     |    11-bit / 20-bit    |   Yes    |   Yes    |   Yes   |    NO    |    NO     |     Yes      |  Yes  |
|    l3     |    0-bit / 11-bit     |   Yes    |   Yes    |   Yes   |    NO    |    NO     |     Yes      |  Yes  |
|    sp     |    29-bit / 38-bit    |   Yes    |   Yes    |   Yes   |   Yes    |    Yes    |     Yes      |  Yes  |

<!-- -->

Table: Attribute Bits of Page Table Entries {#tbl:PageCache-item-attribute}

| ** bit ** | **field** |                                                                       ** describing **                                                                        |
| :-------: | :-------: | :-----------------------------------------------------------------------------------------------------------------------------------------------------------: |
|     7     |     D     |                               Dirty, indicates that since the last time the D bit was cleared, the virtual page has been read.                                |
|     6     |     A     |                          Accessed, indicating that since the last A bit clear, this virtual page has been read, written, or fetched.                          |
|     5     |     G     | Indicates whether the page is a global mapping. When this bit is 1, it means the page is a global mapping, i.e., a mapping that exists in all address spaces. |
|     4     |     U     |    Indicates whether the page can be accessed by User Mode. A value of 0 means it cannot be accessed by User Mode; a value of 1 means it can be accessed.     |
|     3     |     X     |                  Indicates whether the page is executable; a value of 0 means not executable, and a value of 1 means the page is executable.                  |
|     2     |     W     |                     Indicates whether the page is writable; a value of 0 means not writable, and a value of 1 means the page is writable.                     |
|     1     |     R     |                     Indicates whether the page is readable; a value of 0 means not readable, and a value of 1 means the page is readable.                     |
|     0     |     V     |      Indicates whether the page table entry is valid. If this bit is 0, the entry is invalid, and other bits of the entry can be freely used by software      |

<!-- -->

Table: h Encoding Description

| **h** |         ** describing **         |
| :---: | :------------------------------: |
|  00   |    noS2xlate, host page table    |
|  01   | onlyStage1, VS-stage page tables |
|  10   |  onlyStage2, G-stage page table  |


The manual permits updating the A/D bits via either software or hardware.
Xiangshan opts for the software approach, where a page fault is triggered under
the following two conditions, and the page table is updated by software.

1. accessing a page where the A bit of its page table is 0
2. Writing to a page where the D bit of its page table entry is 0.

Possible combinations and meanings of the X, W, and R bits in a page table entry
are shown in [@tbl:PageCache-item-xwr]:

Table: Possible combinations and meanings of X, W, R bits in page table entries
{#tbl:PageCache-item-xwr}

| **X** | **W** | **R** |                                                      ** describing **                                                      |
| :---: | :---: | :---: | :------------------------------------------------------------------------------------------------------------------------: |
|   0   |   0   |   0   | Indicates that the page table entry is not a leaf node and requires indexing the next-level page table through this entry. |
|   0   |   0   |   1   |                                              Indicates the page is read-only                                               |
|   0   |   1   |   0   |                                                          Reserved                                                          |
|   0   |   1   |   1   |                                     Indicates that the page is readable and writable.                                      |
|   1   |   0   |   0   |                                          Indicates that the page is execute-only                                           |
|   1   |   0   |   1   |                                     Indicates that the page is readable and executable                                     |
|   1   |   1   |   0   |                                                          Reserved                                                          |
|   1   |   1   |   1   |                                  Indicates the page is readable, writable, and executable                                  |

### Receives PTW requests and returns results

The Page Cache receives PTW requests from the L2 TLB, which are arbitrated by an
arbiter before being sent to the Page Cache. These PTW requests may originate
from the Miss Queue, L1 TLB, hptw_req_arb, or Prefetcher. Since the Page Cache
can only process one request per query, for allStage requests, it first queries
the first stage. For allStage requests, when querying each h, only the
onlyStage1 page tables are queried. The second-stage translation is handled by
PTW or LLPTW after the request is forwarded to them. The Page Cache query
process is as follows:

* Cycle 0: Issue read requests for five entries l0, l1, l2, l3, sp
  simultaneously
* Cycle 1: Obtain results read from the register stack (l2, l3, sp entries) and
  SRAM (for l0, l1 entries), but not directly used in the current cycle due to
  timing reasons; wait for the next cycle for subsequent operations.
* Cycle 2: Compare the tag stored in each entry of the Page Cache with the tag
  of the incoming request; compare the h register of each entry with the
  incoming s2xlate (allStage converted to query onlyStage1); simultaneously
  check if there is a match among the l0, l1, l2, l3, sp entries; additionally,
  an ECC check is required.
* Cycle 3: Summarize the results obtained from matching the five entries l0, l1,
  l2, l3, sp, as well as the results of the ECC check.

After the aforementioned Page Cache lookup process, if a leaf node is found in
the Page Cache, it is returned to the L1 TLB (for allStage requests, if the
first stage hits, it is sent to PTW for processing); otherwise, the request is
forwarded to LLPTW, PTW, HPTW, or the Miss Queue based on different scenarios.

### Send a PTW request to the L2 TLB

The Page Cache forwards requests to LLPTW, PTW, HPTW, or the Miss Queue
depending on the situation.

1.  For noS2xlate, onlyStage1, and allStage, if the Page Cache misses the leaf
    node but hits the second-level page table (for onlyStage1 and allStage, it's
    a first-stage second-level page table hit), and this PTW request is not a
    bypass request, the Page Cache forwards the request to llptw.
2.  For noS2xlate, onlyStage1, and allStage, if the Page Cache misses the leaf
    node and the second-level page table also misses (for onlyStage1 and
    allStage, this refers to the first-stage second-level page table miss), the
    request must be forwarded to the Miss Queue or PTW. If the request is not a
    bypass request, originates directly from the Miss Queue, and the PTW is
    idle, the PTW request is forwarded to the PTW. For allStage requests, if the
    first-stage translation hits a leaf node, it is also sent to the PTW for the
    final second-stage translation. For onlyStage2 requests, missing the
    second-stage leaf node also triggers sending to the PTW for further
    translation.
3.  If the request is a second-stage translation request (hptwReq) from PTW or
    LLPTW, a hit will send it to hptw_resp_arb, while a miss will forward it to
    HPTW for processing. If HPTW is busy at this time, the Page Cache will be
    blocked.
4.  If the Page Cache misses the leaf node and the request is neither from a
    prefetch request nor an hptwReq request, it must meet one of the following
    three conditions to enter the miss queue.
    1.  This request is a bypass request
    2.  This request misses in the L2 page table or hits in the first-stage
        translation, and the request originates from the L1 TLB or PTW cannot
        accept Page Cache requests.
    3.  The request hits the second-level page table, but the LLPTW cannot
        accept the request

It is important to note that points 1, 2, 3, and 4 are parallel processes. For
every request forwarded by the Page Cache, it will always satisfy exactly one of
the conditions in 1, 2, 3, or 4. However, these four conditions are evaluated
independently, with no sequential relationship between them. To clarify the
request forwarding scenario, a serialized flowchart is provided for
illustration, but in reality, the hardware description is inherently parallel,
with no sequential dependencies. The serialized flowchart is shown in
[@fig:PageCache-query-flow].

![Serialized Page Cache Query Flow
Diagram](../figure/image39.jpeg){#fig:PageCache-query-flow}

### Refill Cache

When a PTW request sent by PTW or LLPTW to mem receives a reply, a refill
request is simultaneously sent to the Page Cache. The information passed to the
Page Cache includes: the page table entry, the level of the page table, the
virtual page number, the page table type, etc. After this information is passed
into the Cache, it will be filled into the l0, l1, l2, l3, or sp entry according
to the level of the refilled page table and the attribute bits of the page
table. If the page table is valid, it is filled into the five entries l0, l1,
l2, l3, sp according to the different levels of the page table; if the page
table is invalid and the page table is not a leaf node page table, it is filled
into the sp entry. For the replaced Page Cache entry, the replacement policy can
be selected via the ReplacementPolicy. Currently, XiangShan's Page Cache uses
the PLRU replacement policy.

### Supports bypass access

When a Page Cache request misses, but data for the requested address is
simultaneously being written into the Cache, the Page Cache request will be
bypassed. If this situation occurs, the data being written into the Cache will
not be directly handed over to the request accessing the Page Cache. The Page
Cache will send a miss signal to the L2 TLB, and simultaneously send a bypass
signal to the L2 TLB, indicating that this request is a bypass request and needs
to access the Page Cache again to obtain the result. The bypassed PTW request
will not enter the PTW but will directly enter the MissQueue, waiting for the
next access to the Page Cache to get the result. However, it should be noted
that for the second-stage translation request of hptw req (from PTW and LLPTW),
a bypass may also occur, but the hptw req does not enter the miss queue.
Therefore, to avoid duplicate fills into the Page Cache, the signal sent by the
Page Cache to the HPTW includes a bypassed signal. When this signal is valid,
the results of the memory access performed by this request after entering the
HPTW will not be refilled into the Page Cache.

### Supports ECC verification

Page Cache supports ECC verification. When accessing L0 or L1 entries, an ECC
check is performed simultaneously. If the ECC check reports an error, it does
not raise an exception but instead sends a miss signal for that request to the
L2 TLB. At the same time, the Page Cache flushes the entry with the ECC error
and re-sends a PTW request. The remaining behavior is the same as when a Page
Cache miss occurs. The ECC check uses the SECDED strategy.

### Supports SFENCE flush

When the sfence signal is valid, the Page Cache flushes cache entries based on
the rs1 and rs2 signals of sfence and the current virtualization mode. The
flushing of the Page Cache is performed by setting the v bit of the
corresponding cache line to 0. Since L0 and L1 entries are stored in SRAM, ASID
comparison cannot be performed in the current cycle. Therefore, for flushing L0
and L1, the ASID is ignored (the handling of VMID and ASID is the same), and
instead, a partial match is performed using the hash value; L2, L3, and SP
entries are stored in register files, allowing complete ASID/VMID comparison.
For information related to the sfence signal, refer to the RISC-V manual. Under
virtualization, sfence flushes the page tables of the VS stage (first-stage
translation, where VMID needs to be considered); under non-virtualization,
sfence flushes the page tables of the G stage (second-stage translation, where
VMID is not considered).

### Support for exception handling

ECC verification errors may occur in the Page Cache, in which case the Page
Cache invalidates the current entry, returns a miss result, and reinitiates the
Page Walk. Refer to Section 6 of this document: Exception Handling Mechanism.

### Support for TLB compression

To support TLB compression, when the Page Cache hits a 4KB page, it must return
8 consecutive page table entries. In fact, due to the 512-bit memory access
width, each Page Cache entry inherently contains 8 page tables, which can be
directly returned. Unlike the L1TLB, the L2TLB still uses TLB compression under
the H extension.

### Supports classifying all levels of page tables into three types

In the H extension, there are three types of page tables, managed by vsatp,
hgatp, and satp, respectively. The Page Cache adds an h register to distinguish
these page tables: onlyStage1 represents those related to vsatp, onlyStage2
represents those related to hgatp (where asid is invalid), and noS2xlate
represents those related to satp (where vmid is invalid).

### Supports accepting second-stage translation requests (HPTW requests)

In L2TLB, PTW and LLPTW send second-stage translation requests (indicated by the
isHptwReq signal). These requests first query the Page Cache, following the same
process as onlyStage2 requests—only querying page tables of the onlyStage2 type.
However, depending on whether they hit, these requests are forwarded to either
hptw_resp_arb or HPTW. The hptwReq return signal from the Page Cache includes an
id signal to determine whether the response should go to PTW or LLPTW. The
return signal also contains a bypassed signal, indicating that the request was
bypassed. If such a request proceeds to HPTW for translation, none of the page
tables obtained by HPTW's memory accesses will be refilled into the Page Cache.
HptwReq requests also support l1Hit and l2Hit functionality.

### Supports HFENCE flush

The hfence instruction can only be executed in non-virtualization mode. There
are two instructions of this type, responsible for flushing the VS stage page
tables (first-stage translation, the h field is onlyStage1) and the G stage page
tables (second-stage translation, the h field is onlyStage2), respectively. The
content to be flushed is determined based on rs1 and rs2 of hfence, as well as
the added VMID and h fields. Similarly, because ASID and VMID are stored in SRAM
for L0 and L1, flushing L0 and L1 does not consider VMID and ASID. Furthermore,
for the implementation of flushing L0 and L1, a simple approach is adopted:
directly flush the VS or G stage page tables (in the future, if necessary, the
flushing can be further refined to the set where the addr resides).

## Overall Block Diagram

The essence of the Page Cache is a cache. The internal implementation of the
Page Cache has been detailed above, and the internal block diagram of the Page
Cache is of limited reference value. For the connection relationships between
the Page Cache and other modules in the L2 TLB, see Section 5.3.3.

## Interface list

The signal list of Page Cache can be mainly categorized into the following 3
types:

1.  req: arb2 sends PTW requests to the Page Cache.
2.  resp: The response from Page Cache to L2 TLB's PTW, where Page Cache may
    send requests to PTW, LLPTW, Miss Queue, and HPTW; and send responses to
    mergeArb and hptw_resp_arb.
3.  refill: The Page Cache receives refill data returned from memory.

Please refer to the interface list documentation for details.

## Interface timing

The Page Cache interacts with other modules in the L2 TLB using a valid-ready
handshake mechanism. The signals involved are relatively trivial, and there are
no particularly noteworthy timing relationships, so they will not be elaborated
further.


