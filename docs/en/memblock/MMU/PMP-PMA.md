# Secondary module PMP&PMA

PMP includes the following modules, with PMA checks incorporated within the PMP
module:

1. PMP (Distributed PMP & PMA Registers)
    1. PMP pmp (Frontend)
    2. PMP pmp (Memblock)
    3. PMP pmp (L2TLB)
2. PMPChecker (PMP & PMA checker, returns results in the same cycle)
    1. PMPChecker PMPChecker (Frontend)
    2. PMPChecker PMPChecker_1 (Frontend)
    3. PMPChecker PMPChecker_2 (Frontend)
    4. PMPChecker PMPChecker_3 (Frontend)
    5. PMPChecker PMPChecker (L2TLB)
    6. PMPChecker PMPChecker_1 (L2TLB)
3. PMPChecker_8 (PMP & PMA checker, returns results in the next cycle)
    1. PMPChecker_8 PMPChecker (Memblock)
    2. PMPChecker_8 PMPChecker_1 (Memblock)
    3. PMPChecker_8 PMPChecker_2 (Memblock)
    4. PMPChecker_8 PMPChecker_3 (Memblock)
    5. PMPChecker_8 PMPChecker_4 (Memblock)
    6. PMPChecker_8 PMPChecker_5 (Memblock)

## Design specifications

1. Supports physical address protection
2. Supports physical address attributes
3. Supports parallel execution checks for PMP and PMA
4. Supports dynamic and static checking
5. Supports distributed PMP and distributed PMA
6. Supports exception handling mechanism

## Function

### Supports physical address protection

The Xiangshan processor supports physical address protection (PMP) checks, with
PMP defaulting to 16 entries, which can be modified parametrically. For timing
considerations, a distributed replication implementation method is adopted. The
PMP registers in the CSR unit are responsible for instructions like CSRRW.
Copies of the PMP registers are maintained at the front-end instruction fetch,
back-end memory access, and Page Table Walker locations, with consistency
ensured by pulling CSR write signals to match the PMP registers in the CSR unit.

For the format, reset values, etc., of PMP registers, please refer to the
Xiangshan Open-Source Processor User Manual and the RISC-V Privileged Level
Manual.

### Supports physical address attributes

The implementation of Physical Memory Attributes (PMA) adopts a PMP-like
approach, utilizing two reserved bits in the PMP Configure register, set as
atomic and cacheable, indicating support for atomic operations and cacheability,
respectively. PMP registers have no initial values, while PMA registers default
to initial values that must be manually set to match the platform's address
attributes. PMA registers utilize reserved CSR addresses in M-mode, defaulting
to 16 entries, with parameterizable modifications allowed.

For the default PMA configuration, please refer to the Xiangshan Open-Source
Processor User Manual.

### PMP and PMA perform parallel checks

PMP and PMA checks are performed in parallel. If either permission is violated,
the operation is illegal. All physical address accesses within the core require
physical address permission checks, including after ITLB and DTLB checks and
before Page Table Walker, Hypervisor Page Table Walker, and Last Level Page
Table Walker memory accesses. The distributed PMP, PMA, and the corresponding
PMP and PMA checkers for ITLB, DTLB, Page Table Walker, Last Level Page Table
Walker, and Hypervisor Page Table Walker are shown in [@tbl:PMP-PMA-modules]. In
other words, Frontend, Memblock, and L2 TLB each maintain a copy of the PMP and
PMA registers (see Section 5.2.5), which drive their respective PMP and PMA
checkers.

Table: Correspondence between PMP and PMA check modules {#tbl:PMP-PMA-modules}

| Module  | Channel                      | Distributed PMP & PMA | PMP&PMA Check Unit |
| ------- | ---------------------------- | --------------------- | ------------------ |
| ITLB    |                              |                       |                    |
|         | requestor(0)                 | pmp (Frontend)        | PMPChecker         |
|         | requestor(1)                 | pmp (Frontend)        | PMPChecker_1       |
|         | requestor(2)                 | pmp (Frontend)        | PMPChecker_2       |
|         | requestor(3)                 | pmp (Frontend)        | PMPChecker_3       |
| DTLB_LD |                              |                       |                    |
|         | requestor(0)                 | pmp (Memblock)        | PMPChecker         |
|         | requestor(1)                 | pmp (Memblock)        | PMPChecker_1       |
|         | requestor(2)                 | pmp (Memblock)        | PMPChecker_2       |
| DTLB_ST |                              |                       |                    |
|         | requestor(0)                 | pmp (Memblock)        | PMPChecker_3       |
|         | requestor(1)                 | pmp (Memblock)        | PMPChecker_4       |
| DTLB_PF |                              |                       |                    |
|         | requestor(0)                 | pmp (Memblock)        | PMPChecker_5       |
| L2 TLB  |                              |                       |                    |
|         | Page Table Walker            | pmp (L2 TLB)          | PMPChecker         |
|         | Last Level Page Table Walker | pmp (L2 TLB)          | PMPChecker_1       |
|         | Hypervisor Page Table Walker | Pmp (L2TLB)           | PMPChecker_2       |

According to the RV manual, Page Fault has higher priority than Access Fault.
However, if a Page Table Walker or Last Level Page Table Walker encounters an
Access Fault during PMP or PMA checks, the page table entry is invalid,
resulting in the special case where both Page Fault and Access Fault occur
simultaneously. Xiangshan chooses to report the Access Fault. The manual does
not explicitly address this scenario, or it may contradict the manual. In all
other cases, Page Fault takes precedence over Access Fault.

### Dynamic and static checks

According to the manual, PMP and PMA checks should be dynamic, meaning they must
be performed after TLB translation using the translated physical address for
physical address permission checks. The Frontend, L2 TLB, and the 5 PMPCheckers
in Memblock (see [@tbl:PMP-PMA-modules]) all perform dynamic checks. For timing
considerations, the PMP & PMA check results of the DTLB can be queried in
advance and stored in the TLB entry during backfill, which constitutes static
checking. Specifically, when the L2 TLB's page table entry is backfilled into
the DTLB, the backfilled page table entry is simultaneously sent to PMP and PMA
for permission checks, and the resulting attribute bits (including R, W, X, C,
Atomic; the specific meanings of these bits are detailed in Section 5.4) are
stored in the DTLB. This allows these check results to be directly returned to
MemBlock without rechecking. To implement static checking, the granularity of
PMP and PMA must be increased to 4KB.

It is important to note that currently, PMP & PMA checks are not the timing
bottleneck for Kunming Lake, hence static checks are not employed; all checks
are performed dynamically, i.e., after obtaining the physical address through
TLB lookup. The Kunming Lake V1 code does not include static checks, only
dynamic checks—please take note again. However, for compatibility, the
granularity of PMP and PMA remains at 4KB.

The result information obtained from dynamic and static checks is as follows:

* Dynamic Check: Returns whether an inst access fault, load access fault, or
  store access fault occurred; checks if the physical address belongs to the
  mmio address space.
* Static check: Returns the attribute bits of the checked physical address,
  including R, W, X, C, and Atomic. Note that Kunminghu V1 does not perform
  static checks by default.

### Distributed PMP and PMA

The specific implementation of PMP and PMA includes four parts: CSR Unit,
Frontend, Memblock, and L2 TLB. The CSR Unit is responsible for responding to
CSR instructions like CSRRW for reading and writing these PMP and PMA registers.
Due to the considerable distance between the CSR Unit and ITLB, DTLB, and L2
TLB, copies of PMP and PMA must be stored in ITLB, DTLB, and L2 TLB for physical
address checks and physical attribute checks. To achieve this, we need to
implement distributed PMP and PMA, maintaining backups of these registers near
ITLB, DTLB, and L2 TLB.

Backups of these PMP and PMA registers are stored in the Frontend, Memblock, and
L2 TLB, which are responsible for address checking. Pulling the CSR write
signals ensures the consistency of these register contents. Due to the smaller
size of the L1 TLB, the backups of PMP and PMA registers are stored in the
Frontend or Memblock, providing checks for ITLB and DTLB respectively. The
larger size of the L2 TLB allows the backups of PMP and PMA registers to be
stored directly within it.

### PMP and PMA Check Process

Before obtaining physical addresses from ITLB and DTLB queries, and before L2
TLB's Page Table Walker, Last Level Page Table Walker, and Hypervisor Page Table
Walker access memory, physical address checks must be performed. ITLB, DTLB, and
L2 TLB need to provide PMPChecker with information including PMP and PMA
configuration registers, relevant information from address registers; the number
of consecutive 1s from low to high in PMP and PMA address registers (since the
granularity of PMP and PMA is 4KB, the minimum is 12); the physical address to
be queried; and the type of permission to query, including execute (ITLB),
read/write (L2 TLB, LoadUnits, and StoreUnits), and atomic read/write
(AtomicsUnit).

The relevant information required for PMP and PMA check requests is shown in
[@tbl:PMP-PMA-req-info]:

Table: Relevant information required for PMP and PMA check requests
{#tbl:PMP-PMA-req-info}

| PMPChecker module     | Information required                                                                                                                                           | Source                                                                             |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Frontend              |                                                                                                                                                                |                                                                                    |
|                       | PMP and PMA Configuration Registers                                                                                                                            | Frontend pmp                                                                       |
|                       | PMP and PMA Address Registers                                                                                                                                  | Frontend pmp                                                                       |
|                       | The mask for PMP and PMA, i.e., the number of consecutive 1s from low to high in the address registers, with a minimum of 12                                   | Frontend pmp                                                                       |
|                       | The queried paddr                                                                                                                                              | Icache, IFU                                                                        |
|                       | The queried cmd, ITLB is fixed at 2, indicating execution permission is required                                                                               | Icache, IFU                                                                        |
| Memblock              |                                                                                                                                                                |                                                                                    |
|                       | PMP and PMA Configuration Registers                                                                                                                            | Memblock PMP                                                                       |
|                       | PMP and PMA Address Registers                                                                                                                                  | Memblock PMP                                                                       |
|                       | The mask for PMP and PMA, i.e., the number of consecutive 1s from low to high in the address registers, with a minimum of 12                                   | Memblock PMP                                                                       |
|                       | The queried paddr                                                                                                                                              | LoadUnits, L1 Load Stream & Stride Prefetch StoreUnits, AtomicsUnit, SMSprefetcher |
|                       | The queried cmd, where DTLB may be 0, 1, 4, or 5; representing read, write, atom_read, and atom_write permissions respectively.                                | LoadUnits, L1 Load Stream & Stride Prefetch StoreUnits, AtomicsUnit, SMSprefetcher |
| Memblock static check |                                                                                                                                                                |                                                                                    |
|                       | PMP and PMA Configuration Registers                                                                                                                            | Memblock PMP                                                                       |
|                       | PMP and PMA Address Registers                                                                                                                                  | Memblock PMP                                                                       |
|                       | PMP and PMA mask, where the mask format has the lower i bits as 1 and higher bits as 0, with i being the count of log2(address space matched by the PMP entry) | Memblock PMP                                                                       |
|                       | The queried paddr                                                                                                                                              | PTW returned by L2 TLB                                                             |
| L2 TLB                |                                                                                                                                                                |                                                                                    |
|                       | PMP and PMA Configuration Registers                                                                                                                            | L2 TLB PMP                                                                         |
|                       | PMP and PMA Address Registers                                                                                                                                  | L2 TLB PMP                                                                         |
|                       | PMP and PMA mask, where the mask format has the lower i bits as 1 and higher bits as 0, with i being the count of log2(address space matched by the PMP entry) | L2 TLB PMP                                                                         |
|                       | The queried paddr                                                                                                                                              | Page Table Walker, Last Level Page Table Walker, Hypervisor Page Table Walker      |
|                       | The query cmd for L2 TLB is fixed at 0, indicating read permission is required.                                                                                | Page Table Walker, Last Level Page Table Walker, Hypervisor Page Table Walker      |

PMPChecker needs to return to ITLB, DTLB, and L2 TLB whether an inst access
fault (ITLB), load access fault (LoadUnits, L2 TLB), store access fault
(StoreUnits, AtomicsUnit) occurred, and whether the address belongs to MMIO
space (ITLB, DTLB, L2 TLB). Additionally, static checks need to populate the
DTLB with address attribute bits, including cacheable, atomic, x, w, and r.

For requests from ITLB and L2 TLB, the PMP and PMA check results are provided in
the same cycle; for requests from DTLB, the results are provided in the next
cycle. The relevant information returned by PMP and PMA checks is shown in
[@tbl:PMP-PMA-resp-info]:

Table: Relevant information required for PMP and PMA checks
{#tbl:PMP-PMA-resp-info}

| PMPChecker module      | Information to be returned                | Destination                                                                   |
| ---------------------- | ----------------------------------------- | ----------------------------------------------------------------------------- |
| Frontend               |                                           |                                                                               |
|                        | Whether an inst access fault occurs       | Icache, IFU                                                                   |
|                        | Whether the address belongs to MMIO space | Icache, IFU                                                                   |
| Memblock dynamic check |                                           |                                                                               |
|                        | Whether a load access fault occurs        | LoadUnits                                                                     |
|                        | Whether a store access fault occurs       | StoreUnits, AtomicsUnit                                                       |
|                        | Whether the address belongs to MMIO space | LoadUnits, StoreUnits, AtomicsUnit                                            |
| Memblock static check  |                                           |                                                                               |
|                        | Is the address cacheable                  | DTLB                                                                          |
|                        | Whether the address is atomic             | DTLB                                                                          |
|                        | Whether the address is executable         | DTLB                                                                          |
|                        | Whether the address is writable           | DTLB                                                                          |
|                        | Is the address readable                   | DTLB                                                                          |
| L2 TLB                 |                                           |                                                                               |
|                        | Whether a load access fault occurs        | Page Table Walker, Last Level Page Table Walker, Hypervisor Page Table Walker |
|                        | Whether the address belongs to MMIO space | Page Table Walker, Last Level Page Table Walker, Hypervisor Page Table Walker |


### Exception handling

Exceptions that may arise from PMP and PMA checks include: inst access fault
(ITLB), load access fault (LoadUnits, L2 TLB), store access fault (StoreUnits,
AtomicsUnit). For exceptions generated by ITLB and DTLB, they are respectively
delivered to the module that sent the physical address query based on the
request source. ITLB exceptions are delivered to Icache or IFU; DTLB exceptions
are delivered to LoadUnits, StoreUnits, or AtomicsUnit for handling.

Since Page Table Walker, Last Level Page Table Walker, or Hypervisor Page Table
Walker must perform PMP and PMA checks on the physical address before accessing
memory, L2 TLB may generate an access fault. L2 TLB does not directly handle the
generated access fault but returns this information to L1 TLB. Upon detecting an
access fault during a query, L1 TLB will generate an inst access fault, load
access fault, or store access fault based on the requested cmd and deliver it to
the respective modules for processing according to the request source.

Possible exceptions and the MMU module's handling process are shown in
[@tbl:PMP-PMA-exceptions]:

Table: Possible Exceptions from PMP and PMA Checks and Handling Procedures
{#tbl:PMP-PMA-exceptions}

| **module** |   **Possible Exceptions**    |                                 ** processing flow **                                  |
| :--------: | :--------------------------: | :------------------------------------------------------------------------------------: |
|    ITLB    |                              |                                                                                        |
|            |  Generate inst access fault  |            Deliver to Icache or IFU for processing based on request source             |
|    DTLB    |                              |                                                                                        |
|            | Generate a load access fault |                         Hand over to LoadUnits for processing.                         |
|            | Generate store access fault  | Based on the request source, it is processed by StoreUnits or AtomicsUnit respectively |
|   L2 TLB   |                              |                                                                                        |
|            |    Generate access fault     |          Delivered to L1 TLB, which processes the request based on its origin          |

### Check rules

The checking rules for PMP and PMA in the Xiangshan Kunminghu architecture
follow the PMP and PMA sections of the RV manual. Here, only the matching
patterns are introduced. The physical address range controlled by a PMP or PMA
entry is determined jointly by the A bit in the PMP or PMA configuration
register and the PMP or PMA address register. To support static checking in DTLB
(see Section 5.4.2.4), the granularity of PMP and PMA needs to be increased to
4KB. Therefore, the minimum physical address range controlled by a PMP or PMA
entry is 4KB.

The configuration register A bit corresponds to the following matching modes: A
bit values of 0, 1, 2, and 3 correspond to OFF, TOR, NA4, and NAPOT modes
respectively.

* A is 0, OFF mode: This PMP or PMA entry is disabled and does not match any
  address;
* A is 1, TOR mode (Top of range): Matches addresses from the previous PMP or
  PMA entry's address register up to the current PMP or PMA entry's address
  register;
* A is 2, NA4 mode (Naturally Aligned Four-byte regions): Kunminghu architecture
  in Xiangshan does not support NA4 mode;
* A is 3, NAPOT mode (Naturally Aligned Power-of-two regions): Starting from the
  lower bits of the PMP or PMA address register, count the number of consecutive
  1s. Let the PMP or PMA address register be `ADDR=yyy...111` (with x 1s), then
  the matched address starts from `yyy...000` (`ADDR &gt;&gt; 2` bits) and spans
  $2^{x+3}$ bits. Since the Kunming Lake architecture of Xiangshan specifies the
  minimum granularity for PMP or PMA checks as 4KB, the smallest matched address
  range is 4KB.

To facilitate address matching, distributed PMP and PMA need to send mask
signals to the PMPChecker. The mask format has the lower i bits as 1 and higher
bits as 0, where i is the number of log2(address space matched by the PMP
entry). The mask value is updated simultaneously when PMP and PMA entries are
updated. The Kunming Lake architecture of Xiangshan supports a minimum
granularity of 4KB for PMP and PMA, so the lower 12 bits of the mask signal are
always 1.

For example, if a PMP entry's pmpaddr is `16'b1111_0000_0000_0000`, since the
minimum granularity supported by Kunminghu architecture in Xiangshan for PMP and
PMA is 4KB, the address range matched by napot mode is $2^{12}$ B, i.e., 4 KB,
and the mask signal value is 18'hfff.

For example, if the pmpaddr of a certain PMP entry is `16'b1011_1111_1111_1111`,
the address range matched in NAPOT mode is $2^{17}$ B (128KB), and the mask
signal value is `18'h1ffff`.

## Overall Block Diagram

The overall block diagrams of the PMP module and PMA module are shown in
[@fig:PMP-overall] and [@fig:PMA-overall] respectively. The CSR Unit is
responsible for responding to CSR instructions like CSRRW for read/write
operations on these PMP and PMA registers; backups of these PMP and PMA
registers are included in the Frontend, Memblock, and L2 TLB to handle address
checking. By pulling the write signals from the CSR, the consistency of these
register contents is ensured.

![PMP Module Overall Block Diagram](./figure/image45.png){#fig:PMP-overall}

![Overall block diagram of the PMA
module](./figure/image46.png){#fig:PMA-overall}

## Interface list

Refer to the interface list documentation.

## Interface timing

For ITLB and L2 TLB, PMP and PMA checks must return results in the same cycle;
for DTLB, PMP and PMA checks will return results in the next cycle. The
interface timing for ITLB and L2 TLB PMP modules is shown in
[@fig:PMP-time-ITLB].

![Interface timing diagram of ITLB and L2 TLB PMP
module](./figure/image48.svg){#fig:PMP-time-ITLB}

The timing of the DTLB PMP module interface is shown in [@fig:PMP-time-DTLB],
with identical timing for both static and dynamic checks.

![DTLB PMP Module Interface Timing](./figure/image50.svg){#fig:PMP-time-DTLB}

