# 矩阵访存指令执行单元 MLSU

## 功能描述

矩阵访存指令执行单元 `MlsUnit` 接收访存发射队列发出的矩阵 Load / Store 指令，完成基址翻译、权限检查和访存描述符生成，并将控制结果写回后端。指令提交后，CUTE 的加载和存储单元根据描述符，通过二级缓存搬运矩阵数据。

矩阵访存依次经过描述符准备、指令提交和数据搬运。MLSU 写回表示地址准备结果已经送达后端；ROB 提交后，AmuCtrlBuffer 将描述符发送给 CUTE；CUTE 在数据搬运结束后报告任务完成。矩阵任务的执行和完成关系见 [CUTE 矩阵单元](../../cute/index.md)。

## 设计规格

- 支持 A、B、C 矩阵寄存器的 Load / Store 控制请求，以及译码表中定义的转置和整寄存器访存形式。
- 接收整数寄存器提供的基址与步长、mx 寄存器提供的矩阵规模，以及译码时保存的矩阵类型配置。
- 使用 MemBlock 的 Load DTLB 请求端口和对应的 PMP 检查端口；Load / Store 通过 TLB 命令区分权限。
- 支持 TLB 缺失后的 MLSQ 重发，以及重定向后的流水线取消。
- 默认配置例化 1 条 MLSU 流水线；VirtualMlsQueue 和 MlsQueueReplay 各为 8 项。

MLSU 的翻译和权限检查范围为起始基址。地址对齐条件 `s0_addr_aligned` 固定为 true，矩阵访存未实现非对齐异常检测；Load / Store 触发器尚未接入。矩阵数据访问使用 CUTE 与二级缓存之间的通路，未接入标量访存的 MisalignBuffer 和 Uncache 处理流程。

控制核译码表包含 A / B Store，MLSU 可以生成相应描述符。CUTE 的 Store 任务统一送往 CML，以矩阵号低两位选择 C 寄存器；实际写数据来自 C 寄存器，A / B 寄存器的数据存储路径尚未实现。

## 总体设计

MLSU 包含 s0～s3 四级流水线，其功能如 [@fig:MLSU-pipeline] 所示。

![MLSU 流水线与矩阵访存描述符路径](./figure/xsai-mlsu.svg){#fig:MLSU-pipeline}

Table: MLSU 各级流水线功能 {#tbl:MLSU-stages}

| 流水级 | 主要功能 | 输出 |
| --- | --- | --- |
| s0 | 仲裁首次发射与 MLSQ 重发，选择基址、步长和规模，检查矩阵号及规模，发送 DTLB 请求 | 虚拟基址与指令信息 |
| s1 | 接收 DTLB 结果，生成物理基址，收集页故障、客户机页故障和访问故障 | 物理基址、TLB 缺失和异常信息 |
| s2 | 整合 PMP / PMA 结果，判断是否重发，生成发射队列反馈 | 权限检查结果与重发原因 |
| s3 | 更新 MLSQ，生成 AmuLsuIO，向后端写回指令控制结果 | 矩阵访存描述符与异常信息 |

### s0：请求仲裁与地址翻译请求

s0 的请求来源包括发射队列的首次发射和 MlsQueueReplay 的重发。通常优先处理重发请求；如果当前首次发射的指令比重发指令更老，则暂缓该重发，让更老的指令先执行。

首次发射的基址来自 `src(0)`，普通访存的行步长来自 `src(1)`，两项规模来自 `src(2)` 和 `src(3)`。规模的含义随目标矩阵变化：A 为 M、K，B 为 K、N，C 为 M、N。重发保留原指令、虚拟基址、步长和两项规模，再次进入同一翻译路径。

两项规模表示架构矩阵形状，CUTE 根据矩阵类别和转置标志确定源内存布局。普通 B 加载以 N 为外层、K 为连续维，转置 B 从 K 行、每行 N 个元素的源矩阵加载。`stride` 是源内存相邻两行起始地址之间的字节距离。

Table: A / B 加载描述符与源内存布局 {#tbl:MLSU-source-layout}

| 加载形式 | 描述符 `row`、`column` | 源内存行数 | 每行连续元素数 |
| --- | --- | --- | --- |
| 普通 A | M、K | M | K |
| 转置 A | M、K | K | M |
| 普通 B | K、N | N | K |
| 转置 B | K、N | K | N |

TaskController 根据上表中的外层行数和连续维规模，配置普通 loader 或共享转置引擎。相关地址生成和 bank 映射见 [矩阵加载与存储](../../cute/MemoryLoader.md)。

整寄存器访存不读取普通的行步长和 mx 规模。其步长由寄存器种类确定：A / B 使用 `TRLEN / 8`，C 使用 `ARLEN / 8`；输出描述符的规模在 s3 中生成。

s0 检查矩阵寄存器号是否与 A / B 或 C 类型匹配。非整寄存器访存还根据元素位宽和 `ROWNUM`、`TRLEN`、`ARLEN` 检查各维上界，超限时设置非法指令异常。CUTE 对尺寸和尾块的处理条件见 [矩阵加载与存储](../../cute/MemoryLoader.md) 与 [矩阵计算](../../cute/Compute.md)。

DTLB 请求的虚拟地址为起始基址，Load 使用 `TlbCmd.read`，Store 使用 `TlbCmd.write`。当前矩阵请求不作为 hypervisor 专用访存指令发出，`hyperinst` 为无效。

### s1：接收 DTLB 结果

s1 接收 DTLB 返回的物理地址和缺失信息。Load 收集 `loadPageFault`、`loadGuestPageFault`、`loadAccessFault`，Store 收集对应的 Store 异常。指令的 ROB 索引随流水线传递，用于在重定向时取消受影响请求。

MLSU 的 s1 数据通路接收 DTLB 结果。矩阵数据随后由 CUTE 访问二级缓存，该路径没有 StoreQueue / SBuffer 的数据前递接口。标量 Store 的可见性由 `mfence` 等待 SBuffer 排空；CUTE 任务之间使用 `mrelease` / `macquire` 和同步计数器建立依赖，其中 `mrelease` 等待更老的 CUTE Store。

### s2：权限检查与重发判断

s2 将 PMP 返回的 Load / Store 访问故障与已有异常合并。若 DTLB 缺失，则清除该拍的异常向量，并将指令标记为 `C_TM` 重发。`C_TM` 是当前唯一的矩阵重发原因，后续缓存访问的排队和等待由 CUTE 与二级缓存管理。

MLSU 同时向发射队列反馈重发队列是否能接收请求等信息。成功完成翻译和权限检查的指令可以继续写回；需要重发的指令由 [矩阵访存队列 MLSQ](./LSQ/MLSQ.md) 保留和重新发射。

### s3：描述符生成与写回

s3 向 MLSQ 更新地址准备状态，并组装 `AmuLsuIO`。描述符包含读写方向、目标矩阵号、元素位宽、物理基址、行步长、转置标志、矩阵种类和两项规模。

Table: MLSU 生成的矩阵访存控制信息 {#tbl:MLSU-descriptor}

| 字段 | 含义 |
| --- | --- |
| `ls` | 是否为 Store |
| `ms` | 指令指定的矩阵寄存器号 |
| `widths` | 普通访存来自 mcfg 类型；整寄存器 A / B 为 8 bit，C 为 32 bit |
| `baseAddr` | DTLB 返回的物理基址 |
| `stride` | 普通访存的行步长，或整寄存器访存生成的步长 |
| `transpose` | 是否为转置访存 |
| `isA` / `isB` / `isacc` | A、B 或 C 矩阵选择 |
| `row` / `column` | 普通访存的两项规模，或整寄存器访存的固定规模 |

整寄存器 C 访存的 `row` 为 `ROWNUM`，`column` 为 `ARLEN / 32`。整寄存器 A 的规模为 `ROWNUM × (TRLEN / 8)`；B 的描述符使用 `(TRLEN / 8) × ROWNUM`。整寄存器 B 加载仍采用普通 B 的源布局：默认描述符为 64×128，源内存实际为 128 行、每行 64 个字节，行步长为 64 B。

普通 C 访存的 `widths` 由 mcfg 生成。默认 CML 的存储重排数据以 32 bit 元素组织，尚未实现由 `widths` 控制的结果类型转换和压缩存储；有效数据写回范围见 [C 存储边界](../../cute/MemoryLoader.md#sec:cute-store-boundary)。

MLSU 将描述符放在后端写回接口的 `amuCtrl` 中，并沿后端异常与提交路径处理。AmuCtrlBuffer 在指令正常退休后向 CUTE 转发控制请求；异常或重定向取消的未退休指令不向 CUTE 发起数据搬运。

## 地址与异常边界

MLSU 对起始基址执行一次地址翻译和权限检查。CUTE 根据该物理基址、步长和规模生成各行请求；LocalMMU 负责请求仲裁和事务标识路由，未实现页表遍历与逐行地址翻译。后续行的物理地址须能由该物理基址和步长直接生成，跨页访问的后续行不会再次经过控制核的翻译和权限检查。

512 bit 矩阵返回接口包含数据、任务索引和通道号，未携带 TileLink `denied` / `corrupt`。Cute2TL 的响应路径也未将总线错误转换为控制核的精确矩阵异常；控制核收到的矩阵访存异常来自任务发送前的 MLSU 检查。

## 对应实现

- [MlsUnit.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/mem/pipeline/MlsUnit.scala)
- [MemBlock.scala](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/mem/MemBlock.scala)
- [矩阵控制接口定义](https://github.com/OpenXiangShan/XSAI/blob/ee268923b7175d79a9d0183a0181a684ccec9487/src/main/scala/xiangshan/backend/fu/matrix/Bundles.scala)
