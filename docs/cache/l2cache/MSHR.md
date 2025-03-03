# MSHR

每个任务是否分配 MSHR 由访存流水线（MainPipe）根据其是否命中、是否需要 Probe L1、处理流程的复杂程度等决定，详见 [@sec:reqarb-mainpipe] [请求仲裁器与访存流水线](ReqArb_MainPipe.md)。

## 生命周期

每一项 MSHR 都有自己的生命周期。MSHR 项由 MainPipe 分配，并在 MSHR 完成所有的任务，清空所有状态机状态项后结束生命周期。每一项 MSHR 都可能因为等待总线事务而在较长的一段时间内保持有效，但必须在有限的时间内结束生命周期，否则意味着出现了活锁或死锁。

### MSHR ID

每一项 MSHR 都有自己的 ID 值，并且该值是硬编码的，各项 MSHR 之间的 ID 不同。

由 MSHR 发起的 CHI 请求，其中 TxnID 值的低位与 MSHR ID 绑定。

### 分配

MainPipe 请求分配 MSHR 项时，由 MSHRCtl 模块内部的 MSHRSelector 选定一项未被分配的 MSHR。每一项 MSHR 在分配时，MainPipe 需要提供以下信息：

- 该缓存行的命中情况与一致性状态
- MSHR 状态机的初始状态
- 请求的必要原始信息（来自于 TileLink 请求或 CHI 请求）
- 请求与正在执行的写回（L2 向下的 TileLink Release 或 CHI Copy-Back Write）的嵌套情况

这些信息都会在被分配的 MSHR 项内寄存。

### 释放

当 MSHR 内所有的状态机项都被置为已完成时，即可立即原地释放，结束该 MSHR 项的生命周期，并准备好再一次被 MSHRSelector 选中并分配。关于 MSHR 的状态机项，详见 [@sec:mshr-state-machine] [状态机](MSHR.md#状态机)。


## 状态机 {#sec:mshr-state-machine}

状态机项主要分为两类：

- Schedule 状态项
- Wait 状态项

Schedule 状态项又称主动动作状态项，主要用来跟踪 MSHR 主动向 MainPipe、下游 CHI 通道、上游 TileLink 通道发送任务与请求的情况。其值为低有效，表示未完成状态，即任务尚未成功离开 MSHR 并被发出，其原因可能是未完成阻塞条件（有必要的前置动作未完成）或通道阻塞；值为高则表示对应任务已经成功发出，或不需要发出任务。

Wait 状态项又称被动动作状态项，主要用来跟踪 MSHR 期望收到的来自下游 CHI 通道、上游 TileLink 通道或 CoupledL2 内部模块的回复。其值为低有效，表示未完成状态，即对应的回复尚未回到 MSHR 项；值为高则表示对应回复已经收到，或不需要收到回复。

> 本小节的上游通常指 L1 缓存，下游通常指 NoC、LLC 等。

Schedule 状态项以 ```s_``` 为首命名，其概览如下：

| 名称 | 描述 |
| --- | ------ |
| ```s_acquire``` | 首次需要向下游发送 权限提升请求 或 CMO 请求，或者需要向下发送被重试的写回或踢出请求 |
| ```s_rprobe``` | 由于替换、写回，需要向上游发送 Probe 请求 |
| ```s_pprobe``` | 由于下游的 Snoop 请求，需要向上游发送 Probe 请求 |
| ```s_release``` | 需要向下游发送的写回或踢出请求 |
| ```s_probeack``` | 由于下游的 Snoop 请求，需要向下游发送 Snoop 回复 |
| ```s_refill``` | 需要向上游发送 Grant 回复 |
| ```s_retry``` | 由于没有空闲的路用于替换，向上游发送的 Grant 回复需要重试 |
| ```s_cmoresp``` | 需要向上游发送 CBOAck 回复 |
| ```s_cmometaw``` | 由 CMO 引起的向 MainPipe 发送的目录更新请求 |
| ```s_rcompack``` | 由于向下游发送了读请求，需要发送对应的 CompAck 回复 |
| ```s_wcompack``` | 由于向下游发送了写请求，需要发送对应的 CompAck 回复 |
| ```s_cbwrdata``` | 由于向下游发送了写请求，需要发送对应的 CopyBackWrData 以写回数据 |
| ```s_reissue``` | 由于下游回复了 RetryAck，且 MSHR 已获得 PCredit，需要向下游重发请求 |
| ```s_dct``` | 由于下游的 Forwarding Snoop 请求，需要以 DCT 的形式发送 CompData 以向其它 RN 提供数据 |

Wait 状态项以 ```w_``` 为首命名，其概览如下：

| 名称 | 描述 |
| --- | ------ |
| ```w_rprobeackfirst``` | 由于替换、写回，向上游发送了 Probe 请求，需要等待收取来自上游的首个 Probe 回复 |
| ```w_rprobeacklast``` | 由于替换、写回，向上游发送了 Probe 请求，需要等待收取来自上游的最后一个 Probe 回复（单次回复时与 ```w_rprobeackfirst``` 动作相同） |
| ```w_pprobeackfirst``` | 由于下游的 Snoop 请求，向上游发送了 Probe 请求，需要等待收取来自上游的首个 Probe 回复 |
| ```w_pprobeacklast``` | 由于下游的 Snoop 请求，向上游发送了 Probe 请求，需要等待收取来自上游的最后一个 Probe 回复（单次回复时与 ```w_pprobeackfirst``` 动作相同） |
| ```w_grantfirst``` | 由于向下发送了 权限提升请求 或 CMO 请求，需要等待下游的首个 Comp、CompData 或 DataSepResp 回复 |
| ```w_grantlast``` | 由于向下发送了 权限提升请求 或 CMO 请求，需要等待下游的最后一个 CompData 或 DataSepResp 回复（在收到 Comp 回复时与 ```w_grantfirst``` 动作相同） |
| ```w_grant``` | 由于向下发送了 权限提升请求 或 CMO 请求，需要等待下游的 Comp、CompData 或 RespSepData 回复，并在 CompData 与 RespSepData 回复中获得必要的 DBID 与 SrcID 信息 |
| ```w_releaseack``` | 由于向下游发送的写回请求或踢出请求，需要等待下游的 Comp 或 CompDBIDResp 回复 |
| ```w_replResp``` | 由于替换，需要等待来自 Directory 的替换选择结果 |


## 任务分发

在 Schedule 状态项未完成时，MSHR 就会尝试向相应模块、通道发送相应的任务。每一个 MSHR 项经过 MSHRCtl 的仲裁可以直接分发任务到以下模块、通道：

- MainPipe
- 上游 TileLink B 通道
- 下游 TXREQ 通道
- 下游 TXRSP 通道

对于 TXDAT 通道任务的分发，则必须经过 MainPipe，详见 [@sec:reqarb-mainpipe] [请求仲裁器与访存流水线](ReqArb_MainPipe.md)。

送往 MainPipe 的任务还会在同一周期内经过 RequestArb 的仲裁，详见 [@sec:reqarb-mainpipe] [请求仲裁器与访存流水线](ReqArb_MainPipe.md)。

各个 Schedule 状态项对应的任务分发方向如下表：

| 名称 | 目标模块/通道 |
| --- | ------ |
| ```s_acquire``` | 下游 TXREQ 通道 |
| ```s_rprobe``` | 上游 TileLink B 通道 |
| ```s_pprobe``` | 上游 TileLink B 通道 |
| ```s_release``` | MainPipe |
| ```s_probeack``` | MainPipe |
| ```s_refill``` | MainPipe |
| ```s_retry``` | - |
| ```s_cmoresp``` | MainPipe |
| ```s_cmometaw``` | MainPipe |
| ```s_rcompack``` | 下游 TXRSP 通道 |
| ```s_wcompack``` | 下游 TXRSP 通道 |
| ```s_cbwrdata``` | MainPipe |
| ```s_reissue``` | - |
| ```s_dct``` | MainPipe |

### MainPipe

### 上游 TileLink B 通道

### 下游 TXREQ 通道

### 下游 TXRSP 通道


## Snoop 嵌套处理

在 MSHR 处理向下游的写回请求过程中，仍然需要保证 CoupledL2 需要能够响应下游的 Snoop 请求以及上游的 Release 请求。此时，未完成的写回请求则视为被 Snoop 请求嵌套，或被上游的 Release 请求嵌套。需要注意的是，由于 CHI 协议中存在 Silent Eviction，且 Evict 请求的初始状态为 I，故不发生数据写回的踢出请求（Evict）不会被视为嵌套。 

关于具体 Snoop 请求在什么情况下会分配 MSHR，详见 [@sec:reqarb-mainpipe] [请求仲裁器与访存流水线](ReqArb_MainPipe.md)。

可能在 MSHR 内发生并处理的下游 Snoop 请求嵌套如下。

### 特性1：Snoop 与 WriteBackFull 的嵌套

| Snoop 请求类型 | 起始状态 | 嵌套前状态 | 嵌套后状态 | RetToSrc | Snoop 回复 |
| --------------------- | --------- | ------- | ------- | ------- | ------------------------------ |
| SnpOnce               | -         | -       | -       | -       | -                              |
| SnpClean              | -         | -       | -       | -       | -                              |
| SnpShared             | -         | -       | -       | -       | -                              |
| SnpNotSharedDirty     | -         | -       | -       | -       | -                              |
| SnpCleanShared        | -         | -       | -       | -       | -                              |
| SnpCleanInvalid       | -         | -       | -       | -       | -                              |
| SnpMakeInvalid        | -         | -       | -       | -       | -                              |
| SnpUnique             | -         | -       | -       | -       | -                              |
| SnpUniqueStash        | -         | -       | -       | -       | -                              |
| SnpMakeInvalidStash   | -         | -       | -       | -       | -                              |
| SnpStashUnique        | -         | -       | -       | -       | -                              |
| SnpStashShared        | -         | -       | -       | -       | -                              |
| SnpOnceFwd            | UD        | UD      | I       | X       | SnpRespData_I_PD_Fwded_I       |
| SnpCleanFwd           | UD        | UD      | I       | X       | SnpRespData_I_PD_Fwded_SC      |
| SnpSharedFwd          | UD        | UD      | I       | X       | SnpRespData_I_PD_Fwded_SC      |
| SnpNotSharedDirtyFwd  | UD        | UD      | I       | X       | SnpRespData_I_PD_Fwded_SC      |
| SnpUniqueFwd          | UD        | UD      | I       | X       | SnpResp_I_Fwded_UD_PD          |
| SnpQuery              | -         | -       | -       | -       | -                              |

### 特性2：Snoop 与 WriteEvictOrEvict 的嵌套

| Snoop 请求类型 | 起始状态 | 嵌套前状态 | 嵌套后状态 | RetToSrc | Snoop 回复 |
| --------------------- | --------- | ------- | ------- | ------- | ------------------------------ |
| SnpOnce               | -         | -       | -       | -       | -                              |
| SnpClean              | -         | -       | -       | -       | -                              |
| SnpShared             | -         | -       | -       | -       | -                              |
| SnpNotSharedDirty     | -         | -       | -       | -       | -                              |
| SnpCleanShared        | -         | -       | -       | -       | -                              |
| SnpCleanInvalid       | -         | -       | -       | -       | -                              |
| SnpMakeInvalid        | -         | -       | -       | -       | -                              |
| SnpUnique             | -         | -       | -       | -       | -                              |
| SnpUniqueStash        | -         | -       | -       | -       | -                              |
| SnpMakeInvalidStash   | -         | -       | -       | -       | -                              |
| SnpStashUnique        | -         | -       | -       | -       | -                              |
| SnpStashShared        | -         | -       | -       | -       | -                              |
| SnpOnceFwd            | UC        | UC      | I       | X       | SnpRespData_I_PD_Fwded_I       |
| SnpCleanFwd           | UC        | UC      | I       | X       | SnpRespData_I_PD_Fwded_SC      |
| SnpSharedFwd          | UC        | UC      | I       | X       | SnpRespData_I_PD_Fwded_SC      |
| SnpNotSharedDirtyFwd  | UC        | UC      | I       | X       | SnpRespData_I_PD_Fwded_SC      |
| SnpUniqueFwd          | UC        | UC      | I       | X       | SnpResp_I_Fwded_UD_PD          |
| SnpQuery              | -         | -       | -       | -       | -                              |

### 特性3：Snoop 与 WriteCleanFull 的嵌套

| Snoop 请求类型 | 起始状态 | 嵌套前状态 | 嵌套后状态 | RetToSrc | Snoop 回复 |
| --------------------- | ----------- | ------- | ------- | ------- | ------------------------------ |
| SnpOnce               | -           | -       | -       | -       | -                              |
| SnpClean              | -           | -       | -       | -       | -                              |
| SnpShared             | -           | -       | -       | -       | -                              |
| SnpNotSharedDirty     | -           | -       | -       | -       | -                              |
| SnpCleanShared        | -           | -       | -       | -       | -                              |
| SnpCleanInvalid       | UD          | UD      | I       | 0       | SnpRespData_I_PD               |
|                       | UD, UC      | UC      | I       | 0       | SnpResp_I                      |
|                       | UD, UC, SC  | SC      | I       | 0       | SnpResp_I                      |
| SnpMakeInvalid        | UD          | UD      | I       | 0       | SnpResp_I                      |
|                       | UD, UC      | UC      | I       | 0       | SnpResp_I                      |
|                       | UD, UC, SC  | SC      | I       | 0       | SnpResp_I                      |
| SnpUnique             | UD          | UD      | I       | X       | SnpRespData_I_PD               |
|                       | UD, UC      | UC      | I       | X       | SnpResp_I                      |
|                       | UD, UC, SC  | SC      | I       | 0       | SnpResp_I                      |
|                       |             |         |         | 1       | SnpRespData_I                  |
| SnpUniqueStash        | UD          | UD      | I       | 0       | SnpRespData_I_PD               |
|                       | UD, UC      | UC      | I       | 0       | SnpResp_I                      |
|                       | UD, UC, SC  | SC      | I       | 0       | SnpResp_I                      |
| SnpMakeInvalidStash   | UD          | UD      | I       | 0       | SnpResp_I                      |
|                       | UD, UC      | UC      | I       | 0       | SnpResp_I                      |
|                       | UD, UC, SC  | SC      | I       | 0       | SnpResp_I                      |
| SnpStashUnique        | -           | -       | -       | -       | -                              |
| SnpStashShared        | -           | -       | -       | -       | -                              |
| SnpOnceFwd            | UD          | UD      | SC      | 0       | SnpRespData_SC_PD_Fwded_I      |
|                       | UD, UC      | UC      | UC      | 0       | SnpResp_UC_Fwded_I             |
|                       | UD, UC, SC  | SC      | SC      | 0       | SnpResp_SC_Fwded_I             |
| SnpCleanFwd           | UD          | UD      | SC      | X       | SnpRespData_SC_PD_Fwded_SC     |
|                       | UD, UC      | UC      | SC      | 0       | SnpResp_SC_Fwded_SC            |
|                       |             |         |         | 1       | SnpRespData_SC_Fwded_SC        |
|                       | UD, UC, SC  | SC      | SC      | 0       | SnpResp_SC_Fwded_SC            |
|                       |             |         |         | 1       | SnpRespData_SC_Fwded_SC        |
| SnpSharedFwd          | UD          | UD      | SC      | X       | SnpRespData_SC_PD_Fwded_SC     |
|                       | UD, UC      | UC      | SC      | 0       | SnpResp_SC_Fwded_SC            |
|                       |             |         |         | 1       | SnpRespData_SC_Fwded_SC        |
|                       | UD, UC, SC  | SC      | SC      | 0       | SnpResp_SC_Fwded_SC            |
|                       |             |         |         | 1       | SnpRespData_SC_Fwded_SC        |
| SnpNotSharedDirtyFwd  | UD          | UD      | SC      | X       | SnpRespData_SC_PD_Fwded_SC     |
|                       | UD, UC      | UC      | SC      | 0       | SnpResp_SC_Fwded_SC            |
|                       |             |         |         | 1       | SnpRespData_SC_Fwded_SC        |
|                       | UD, UC, SC  | SC      | SC      | 0       | SnpResp_SC_Fwded_SC            |
|                       |             |         |         | 1       | SnpRespData_SC_Fwded_SC        |
| SnpUniqueFwd          | UD          | UD      | I       | 0       | SnpResp_I_Fwded_UD_PD          |
|                       | UD, UC      | UC      | I       | 0       | SnpResp_I_Fwded_UC             |
|                       | UD, UC, SC  | SC      | I       | 0       | SnpResp_I_Fwded_UC
| SnpQuery              | -           | -       | -       | -       | -                              |


## 写回的嵌套处理

在可能发生嵌套时，每一项 MSHR 会收到 MainPipe 广播的请求嵌套信息，其中包含可能发生嵌套的缓存行的 Tag 与 Set 地址以及嵌套行为。具体信号为 MSHR 内的 ```nestwb``` 端口与 NestedWriteback Bundle 类。

考虑可能导致嵌套的上游 Release/ReleaseData 请求与下游 Snoop 请求，在 MSHR 内需要的各种嵌套处理逻辑如下。

### 特性1：正被替换的缓存行与上游的 ReleaseData TtoN 嵌套

当 MSHR 中被替换的缓存行的 Tag 和 Set 地址与由 MainPipe 广播到各项 MSHR 的 ReleaseData TtoN 的 Tag 和 Set 地址相同时，发生此种嵌套。对应的信号名为 ```c_set_dirty```。

此种嵌套通常出现在 CoupledL2 已经或正在向上游 L1 缓存发送由替换引起的 Probe toN 请求，且上游 L1 缓存对于该 Probe toN 的回复尚未被 CoupledL2 观测到时，上游 L1 缓存主动向 CoupledL2 发起了 ReleaseData TtoN。

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- 标记为 Dirty
- 更新状态为 TIP
- 更新状态为上游 L1 不再持有该缓存行

### 特性2：正被替换的缓存行与上游的 Release TtoN 嵌套

当 MSHR 中被替换的缓存行的 Tag 和 Set 地址与由 MainPipe 广播到各项 MSHR 的 Release TtoN 的 Tag 和 Set 地址相同时，发生此种嵌套。对应的信号名为 ```c_set_tip```。

此种嵌套通常出现在 CoupledL2 已经或正在向上游 L1 缓存发送由替换引起的 Probe toN 请求，且上游 L1 缓存对于该 Probe toN 的回复尚未被 CoupledL2 观测到时，上游 L1 缓存主动向 CoupledL2 发起了 Release TtoN。

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- 更新状态为 TIP
- 更新状态为上游 L1 不再持有该缓存行

### 特性3：正被替换的缓存行与下游的 Snoop 嵌套

当 MSHR 中被替换的缓存行的 Tag 和 Set 地址与由 MainPipe 广播到各项 MSHR 的下游 Snoop 的 Tag 和 Set 地址相同时，发生此嵌套。对应的信号名为 ```b_inv_dirty```。

此处的下游 Snoop 需要排除在 CHI 规定中不可改变缓存行状态的一类 Snoop，包括 SnpQuery、SnpStashUnique、SnpStashShared。

此种嵌套通常出现在 CoupledL2 已经或正在向下游发送由替换引起的写回请求，且下游尚未回复 CompDBIDResp 时，下游向 CoupledL2 发起了新的 Snoop 请求。

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- 清除状态至 Clean
- 更新状态为 INVALID
- 清除由于上游 L1 缓存回复 ProbeAckData 而置的 Dirty 标志

### 特性4：在下游 Snoop 发生嵌套时向目录写入 BRANCH 状态

当 MSHR 的 Tag 和 Set 地址与由 MainPipe 广播到各项 MSHR 的下游 Snoop 的 Tag 和 Set 地址相同，且该 Snoop 请求在 MainPipe 上写入了 BRANCH 的缓存行状态时，发生此嵌套。

此种嵌套通常出现在 CoupledL2 已经或正在向下游发送由替换引起的写回请求，且下游尚未回复 CompDBIDResp 时，下游向 CoupledL2 发起了新的 Snoop 请求。

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- 清除状态至 Clean
- 若缓存行权限不为 INVALID，则更新为 BRANCH
- 清除由于上游 L1 缓存回复 ProbeAckData 而置的 Dirty 标志

### 特性5：在下游 Snoop 发生嵌套时向目录写入 INVALID 状态

当 MSHR 的 Tag 和 Set 地址与由 MainPipe 广播到各项 MSHR 的下游 Snoop 的 Tag 和 Set 地址相同，且该 Snoop 请求在 MainPipe 上写入了 INVALID 的缓存行状态时，发生此嵌套。

此种嵌套通常出现在 CoupledL2 已经或正在向下游发送由替换引起的写回请求，且下游尚未回复 CompDBIDResp 时，下游向 CoupledL2 发起了新的 Snoop 请求。

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- 清除状态至 Clean
- 更新状态为 INVALID
- 更新状态为上游 L1 不再持有该缓存行
- 清除由于上游 L1 缓存回复 ProbeAckData 而置的 Dirty 标志
- 若为需要执行替换的请求，重新选择被替换的行


## Retry 与 P-Credit 机制

若收到了来自下游的 RetryAck 回复，MSHR 就会拉高 P-Credit 查询的有效位，并且将 CHI 的 PCrdType 与 SrcID 域发送给 MainPipe，由 MainPipe 决定是否向 MSHR 的对应事务分配 P-Credit 以进行重试。关于 P-Credit 的接收与分配，详见 [@sec:reqarb-mainpipe] [请求仲裁器与访存流水线](ReqArb_MainPipe.md)。
