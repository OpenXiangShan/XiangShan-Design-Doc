# Secondary Module: Repeater

The repeater consists of the following modules:

* PTWFilter itlbRepeater1
* PTWRepeaterNB itlbRepeater2
* PTWRepeaterNB itlbRepeater3
* PTWNewFilter dtlbRepeater

## Design specifications

1. Supports the transmission of PTW requests and responses between the L1 TLB
   and L2 TLB.
2. Support filtering duplicate requests
3. 支持 TLB Hint 机制

## Function

### Transmits PTW requests from the L1 TLB to the L2 TLB.

There is a significant physical distance between the L1 TLB and L2 TLB,
resulting in considerable wire delay. Therefore, repeater modules are inserted
in between to add pipeline stages. Since both the ITLB and DTLB support multiple
outstanding requests, the repeaters also function similarly to MSHRs, filtering
duplicate requests. The filter can eliminate redundant requests, preventing
duplicates in the L1 TLB. The number of entries in the filter partially
determines the parallelism of the L2 TLB (see Section 5.1.1.2).

昆明湖架构中，L2 TLB 位于 memblock 模块中，但与 ITLB 和 DTLB 均有一定距离。香山的 MMU 包含三个 itlbRepeater
和一个 dtlbRepeater，起到在 L1 TLB 与 L2 TLB 之间加拍的效果，两级 Repeater 之间通过 valid-ready
信号进行交互。ITLB 将 PTW 请求以及虚拟页号发送给 itlbRepeater1，进行仲裁后发送给 itlbRepeater2，并发送给
itlbRepeater3，通过 itlbRepeater3 向 L2 TLB 传递 PTW 请求。L2 TLB 将 PTW 请求对应的虚拟页号，查找 L2
TLB 得到的物理页号、页表的权限位、页表等级、是否发生异常等信号返回给 itlbRepeater3、itlbRepeater2，通过
itlbRepeater1 最终返回给 ITLB。DTLB 与 dtlbRepeater 的交互和 ITLB 类似，dtlbRepeater 和
itlbRepeater1 是 Filter 模块，可以合并 L1 TLB 中重复的请求。由于昆明湖架构中 ITLB 和 DTLB 均为非阻塞式访问，因此这些
repeater 也均为非阻塞式 Repeater。

### Filter duplicate requests

Both ITLB and DTLB include multiple channels, and duplicate requests may occur
between different channels or within the same channel. If only a standard
Arbiter is used, processing one request at a time, other requests accessing the
L1 TLB would be resent, resulting in continued misses and being forwarded to the
L2 TLB. This would reduce L2 TLB utilization and consume processor resources
during resending. Therefore, the Filter module is employed. The Filter is
essentially a multi-input, single-output queue that serves to filter duplicate
requests.

Note that in the Kunminghu architecture, the DTLB repeater is composed of load
entries, store entries, and prefetch entries. Requests from the load DTLB, store
DTLB, and prefetch DTLB are directed to their respective entry types for
processing. The three entry types use a round-robin arbiter to arbitrate and
forward the results to the L2 TLB. Additionally, the ITLB repeater checks all
incoming ITLB requests to filter duplicates, while the DTLB repeater checks for
duplicates at the entry level—only ensuring no duplicates within the same DTLB
(load, store, or prefetch). However, requests from different DTLBs (e.g., load
and store) sent to the L2 TLB may still overlap.

### 支持 TLB Hint 机制

![TLB Hint schematic](./figure/image28.png)

When the TLB hits, it does not affect the lifecycle of a load instruction (cycle
0: loadunit queries the TLB; cycle 1: TLB returns the result). On a TLB miss,
the system continues querying the L2 TLB and the page tables in memory until a
result is returned. However, from the perspective of the load instruction's
lifecycle, the instruction enters the load replay queue to wait after a TLB
miss. Only when the instruction is reissued by the load replay queue and the TLB
query succeeds, obtaining the physical address, can subsequent operations
proceed based on the physical address.

Thus, the timing of reissuing a load instruction is critical to reducing its
execution time. If the load instruction is not reissued promptly, even
shortening the TLB refill cycle will not improve overall memory access
performance. Therefore, the Kunminghu architecture implements a TLB Hint
mechanism to selectively wake up load instructions stalled due to TLB misses.
Specifically, in the load_s0 stage, the vaddr is sent to the TLB. If a miss
occurs, the miss information is returned in the load_s1 stage. Simultaneously,
in the load_s1 stage, the TLB sends the miss information to the DTLB repeater
for processing.

The DTLB repeater produces two possible outcomes: returning an MSHRid or a full
signal. In the load entry of the DTLB repeater, new requests are first checked
for duplication against existing entries. If a duplicate is found, the MSHRid of
the existing entry is returned. If no duplicate exists, the repeater checks for
available entries, returning an MSHRid if space is available or a full signal
otherwise. If two load channels send requests to the DTLB repeater
simultaneously with the same virtual address, the MSHRid from loadunit(0) takes
precedence.

In the Kunminghu architecture, all instructions entering the load replay queue
due to TLB misses can only wait to be woken up and resent. If a load instruction
in the load replay queue never receives a wake-up signal, it may lead to a
deadlock. To prevent deadlocks, when the DTLB sends a request to dtlbrepeater
and dtlbrepeater has no available entries to receive it, a full signal must be
returned, indicating that dtlbrepeater is full and cannot accept the PTW request
corresponding to this load instruction. Consequently, the load replay queue will
not receive a Hint signal, and it must ensure the instruction can be resent
without causing a deadlock. Additionally, a full signal is returned to loadunit
when a refilled entry has reached dtlb or dtlbrepeater but has not yet been
written into the dtlb entry, indicating the need for resending.

During the load_s2 stage, dtlbrepeater returns mshrid information to loadunit,
which is written into the load replay queue in the load_s3 stage. If the MSHRid
is valid, the load replay queue must wait for the PTW refill information to
match the MSHRid stored in dtlbrepeater. At this point, dtlbrepeater sends a
wake-up (Hint) signal to the load replay queue, indicating that the MSHRid has
been refilled and needs to be resent, allowing it to hit the dtlb. Moreover,
when a PTW refill request corresponds to multiple MSHR entries (e.g., two VPNs
within the same 2M space, with the PTW refill page table level being 2MB pages),
dtlbrepeater sends a replay_all signal to the load replay queue, indicating that
all load requests blocked due to dtlb misses must be resent. Since this scenario
is rare, it is a convenient solution with almost no performance loss.

## Overall Block Diagram

The overall block diagram of the repeater is described in
[@fig:MMU-repeater-overall], featuring three ITLB repeaters and one DTLB
repeater, which serve to pipeline stages between the L1 TLB and L2 TLB. The two
levels of repeaters interact via valid-ready signals. The repeater accepts PTW
requests from the ITLB and DTLB upstream, both of which support non-blocking
access, so these repeaters are also non-blocking. Downstream, the repeater
forwards PTW requests from the L1 TLB to the L2 TLB. The dtlbRepeater and
itlbRepeater1 are filter modules that can merge duplicate requests from the L1
TLB.

Except for itlbRepeater1, the remaining two levels of itlbRepeater essentially
serve only to add pipeline stages. The number of stages added depends on the
physical distance. In the Kunminghu architecture of Xiangshan, the L2 TLB is
located in the Memblock, which is physically distant from the Frontend module
where the ITLB resides. Therefore, two levels of repeaters are added in the
Frontend, and one level of Repeater is added in the Memblock. The DTLB is
located in the Memblock, close to the L2 TLB, requiring only one level of
Repeater to meet timing requirements.

![Overall block diagram of Repeater
module](./figure/image29.png){#fig:MMU-repeater-overall}

## Interface list

Refer to the interface list documentation.

## Interface timing

### Timing interface between Repeater1 and L1 TLB

Refer to [@sec:L1TLB-tlbRepeater-time] [TLB and tlbRepeater timing
interface](./L1TLB.md#sec:L1TLB-tlbRepeater-time).

### Timing interface between itlbRepeater3, dtlbRepeater1, and L2 TLB

The interface timing between itlbRepeater3, dtlbRepeater1, and the L2 TLB is
shown in [@fig:MMU-tlbrepeater-time-L2TLB]. Handshaking is performed via
valid-ready signals. The repeater forwards PTW requests and virtual addresses
from the L1 TLB to the L2 TLB. The L2 TLB returns the physical address and
corresponding page table to the repeater after completing the lookup.

![Timing interface between itlbRepeater3, dtlbRepeater1, and L2
TLB](./figure/image31.svg){#fig:MMU-tlbrepeater-time-L2TLB}

### Timing interface between multi-level itlbrepeaters

The timing interface between multi-level ITLB repeaters is shown in
[@fig:MMU-multi-itlbrepeater-time]. Handshaking between the two levels of
repeaters is performed via valid-ready signals.

![Interface timing between multi-level ITLB
repeaters](./figure/image33.svg){#fig:MMU-multi-itlbrepeater-time}

