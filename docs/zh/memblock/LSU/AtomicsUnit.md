# 原子指令执行单元 AtomicsUnit

## 功能描述

AtomicsUnit 用于执行原子指令，包括 A 扩展（LR/SC 和 AMO 指令）和 Zacas 扩展（AMOCAS.W，AMOCAS.D 和 AMOCAS.Q）。PMA 默认 DDR 地址空间均支持全部 AMO 和 AMOCAS 指令。

原子指令基本执行流程如下：

1. **sta 发射**：AtomicsUnit 与 StoreUnit 共用发射端口，侦听来自保留站的 sta uop
2. **std 发射**：原子指令与 store 指令共用 StdExeUnit 执行单元，StdExeUnit 的执行结果会发往 AtomicsUnit，AtomicsUnit 负责收集原子指令执行所需的全部数据
3. **地址翻译**：AtomicsUnit 与 LoadUnit_0 共用 DTLB 端口进行地址翻译，同时需要做 PMA / PMP 等物理地址检查
4. **清空 SBuffer**：目前原子指令的执行一律按照 aq/rl 置位处理，因此执行前需要清空 SBuffer
5. **访问 DCache**：向 DCache 发送原子操作请求，DCache 完成后向 AtomicsUnit 返回结果
6. **写回**：AtomicsUnit 将执行结果写回寄存器堆

## 整体框图

AtomicsUnit 的有限状态机如图所示：

![AtomicsUnit 状态机示意图](./figure/atomicsUnitFSM.svg)

- **s_invalid**：AtomicsUnit 空闲，收到保留站发射的 sta uop 后进入 s_tlb_and_flush_sb_req 状态

- **s_tlb_and_flush_sb_req**：访问 TLB 进行地址翻译，如果 TLB 缺失，则持续访问 TLB 直到命中；同时请求 SBuffer 清空。TLB 命中后，如果触发 debug trigger，或者有地址非对齐异常，则直接进入 s_finish 状态写回后端，否则进入 s_pm 状态做物理地址权限检查和进一步的异常检查。其中在访问 TLB 时：
  - 如果是 LR 指令，需要读权限
  - 如果是 SC 指令或其他 AMO 指令，需要写权限

- **s_pm**：物理地址权限检查和异常处理，如果发生下面任何一种异常，则进入 s_finish 状态写回后端：
  - 如果 LR 指令访问 TLB 返回异常，报相应的 LoadPageFault / LoadAccessFault / LoadGuestPageFault 异常
  - 如果除 LR 指令以外的其他原子指令访问 TLB 返回异常，报相应的 StorePageFault / StoreAccessFault / StoreGuestPageFault 异常
  - 如果 PBMT 属性为 PMA，且 PMA 属性为 MMIO，根据是否是 LR 指令报相应的 LoadAccessFault / StoreAccessFault
  - 如果 PBMT 属性为 IO 或 NC，根据是否是 LR 指令报相应的 LoadAccessFault / StoreAccessFault
  - 如果 PMP 属性为 MMIO，或者返回读 / 写权限检查异常，根据是否是 LR 指令报相应的 LoadAccessFault / StoreAccessFault
  
  如果上述异常都没有发生，则开始清空 SBuffer：
  - 如果 SBuffer 不空，进入 s_wait_flush_sbuffer_resp 状态等待 SBuffer 清空
  - 如果 SBuffer 已经清空，进入 s_cache_req 状态访问 DCache

- **s_wait_flush_sbuffer_resp**：等待 SBuffer 清空后，清空后进入 s_cache_req 状态访问 DCache

- **s_cache_req**：在收集全部 std uop 后向 DCache 发送访问请求，成功握手后进入 s_cache_resp 状态等待 DCache 处理完成的响应
  - 需要注意的是，AMOCAS 指令需要从后端接收多个 std uop，AtomicsUnit 在 s_cache_req 状态下需要等到全部 std uop 均接收后才可以开始向 DCache 发请求

- **s_cache_resp**：等待 DCache 处理原子操作并返回结果
  - 如果 DCache 暂时无法处理该请求，需要 AtomicsUnit 重发，则回到 s_cache_req 状态重新发送请求
  - 否则不需要重发，进入 s_cache_resp_latch 状态

- **s_cache_resp_latch**：对 DCache 返回的数据进行移位和有符号 / 无符号扩展，由于时序原因所以加了一拍。下一拍进入 s_finish 状态
  - 如果 DCache 返回了 error，需要记录相应的 LoadAccessFault / StoreAccessFault

- **s_finish**：将原子指令执行结果写回
  - 如果是 LR 指令或 AMO 指令，写回内存中读到的旧值
  - 如果是 SC 指令，写回 SC 指令有无成功执行，成功则写回 0，失败则写回 1
  
  写回成功握手后：
  - 如果是 AMOCAS.Q 指令，总共需要写回 16B 的数据，前面提到 AMOCAS.Q 指令需要接收 2 个 sta uop，同理也需要分 2 拍写回，且 2 次写回的 pdest 需要和 2 次发射的 uop 的 pdest 分别对应。AMOCAS.Q 指令的 2 个 sta uop 是没有固定的发射顺序的，但是写回需要按照顺序写回，所以在 s_finish 状态下做第 1 次写回时，需要保证第 1 个 sta uop 已经收到（这样才能保证写回的 pdest 是正确的）。第 1 次写回成功后进入 s_finish2 状态做第 2 次写回
  - 如果不是 AMOCAS.Q 指令，写回握手成功后进入 s_invalid 状态，状态机结束

- **s_finish2**：对于 AMOCAS.Q 指令，AtomicsUnit 需要做第 2 次写回来写回 16B 中的高 8B 数据。写回的条件是需要确保已收到第 2 个 sta uop。写回握手成功后进入 s_invalid 状态，状态机结束


## Zacas 扩展

1. AMOCAS.W 指令从内存中加载 rs1 所指向的 4B 数据，并和 rd 的低 4B 数据作比较，如果相等则将 rs2 的低 4B 写入 rs1 所指向的内存；最终内存加载的旧值写回 rd 寄存器
2. AMOCAS.D 指令从内存中加载 rs1 所指向的 8B 数据，并和 rd 作比较，如果相等则将 rs2 写入 rs1 所指向的内存；最终内存加载的旧值写回 rd 寄存器
3. AMOCAS.Q 指令从内存中加载 rs1 所指向的 16B 数据，并和 rd 和 rd+1 拼接的数据作比较，如果相等则将 rs2 和 rs2+1 拼接的 16B 数据写入 rs1 所指向的内存；最终内存加载的旧值低 8B 写回 rd 寄存器，高 8B 写回 rd+1 寄存器
  - 需要注意的是，关于 rs2 和 rd 的寄存器对，如果源操作数是 x0 寄存器，那么寄存器对的读结果为全 0；如果目的寄存器是 x0 寄存器，那么寄存器对的每一个寄存器都不会被写

## 原子指令的 Uop 拆分

A 扩展中每条指令会拆分成一个 sta uop 和一个 std uop，做一次写回（写回次数和 sta uop 数量相同，std uop 不需要写回）。

AMOCAS 在指令 uop 拆分、发射和写回上和其他 A 扩展的指令有所不同。AMOCAS 指令在发射时除了需要提供写入内存的数据还需要用于比较的数据，所以一条 AMOCAS 指令会被拆分成多个 std uop，甚至多个 sta uop。

AMOCAS 指令复用 fuOpType 来区分多个 std uop 或多个 sta uop。fuOpType 共 9 bits，原子指令只用到了 6 bits，因此高 3 bits 用于标记 uopIdx。

具体的 uop 拆分规则如下：

1. **A 扩展指令（包括 LR / SC 和普通 AMO 指令）**：sta 和 std 的 uopIdx 均为 0，分别携带 rs1 和 rs2 的数据，存入 AtomicsUnit 中的 rs1 和 rs2_l 寄存器；AtomicsUnit 做一次写回操作，写回的 uopIdx 为 0，写回的 pdest 等于 sta uop 的 pdest
   
![A 扩展原子指令的 Uop 拆分示意图](./figure/atomicsUnitAMOUop.svg)

2. **AMOCAS.W 和 AMOCAS.D 指令**：后端发射 1 个 sta uop 和 2 个 std uop：
   
  - 1 个 sta uop 的 uopIdx 为 0
  - 2 个 std uop 的 uopIdx 分别为 0 和 1，分别保存 rd（用于比较的数据）和 rs2（如果比较成功需要存储的数据），写入 AtomicsUnit 中的 rd_l 和 rs2_l 寄存器
  - 最终做 1 次写回，写回的 uopIdx 为 0，写回的 pdest 等于 sta uop 的 pdest

![AMOCAS.W 和 AMOCAS.D 指令的 Uop 拆分示意图](./figure/atomicsUnitAMOCASWUop.svg)

3. **AMOCAS.Q 指令**：后端发射 2 个 sta uop 和 4 个 std uop：

  - 2 个 sta uop 的 uopIdx 分别为 0 和 2，两个 uop 的 pdest 记为 pdest1 和 pdest2
  - 4 个 std uop 的 uopIdx 为 0-3，其中 0 号和 2 号 uop 分别保存 rd 的低位和高位，写入 rd_l 和 rd_h 寄存器；1 号和 3 号 uop 分别保存 rs2 的低位和高位，写入 rs2_l 和 rs2_h 寄存器
  - 最终做 2 次写回，写回的 uopIdx 分别为 0 和 2，pdest 分别为 pdest1 和 pdest2，写回数据分别为内存加载的旧值的低位和高位

![AMOCAS.Q 指令的 Uop 拆分示意图](./figure/atomicsUnitAMOCASQUop.svg)

## 异常汇总

原子指令可能发生的异常包括：

- **地址非对齐异常**：原子操作的地址必须根据操作类型（字/双字/四字）对齐（4B / 8B / 16B），否则报地址非对齐异常
- **非法指令异常**（后端译码级完成检查，与访存无关）：AMOCAS.Q 指令要求寄存器对 rs2 和 rd 的寄存器号必须是偶数，如果是奇数需要报非法指令异常
- **断点异常**：如果 trigger 比较命中，需要报断点异常
- **地址翻译与权限检查有关的异常**
  - 如果 TLB 地址翻译返回异常，根据是否是 LR 指令报相应的 Load 或 Store 的 PageFault / AccessFault / GuestPageFault 异常
  - 如果 PMP 属性为 MMIO，或者 PMP 没有相应读 / 写权限，报 LoadAccessFault / StoreAccessFault
  - 如果 PMA + PBMT 属性为 IO 或 NC（包括下面 3 种情况），报 LoadAccessFault / StoreAccessFault
    - PBMT = IO
    - PBMT = NC
    - PBMT = PMA 且 PMA = MMIO
