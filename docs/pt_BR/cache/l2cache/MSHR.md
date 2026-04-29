# MSHR {#sec:mshr}

每个任务是否分配 MSHR 由访存流水线（MainPipe）根据其是否命中、是否需要 Probe L1、处理流程的复杂程度等决定，详见
[@sec:reqarb-mainpipe] [请求仲裁器与访存流水线](ReqArb_MainPipe.md)。

## 生命周期

每一项 MSHR 都有自己的生命周期。MSHR 项由 MainPipe 分配，并在 MSHR 完成所有的任务，清空所有状态机状态项后结束生命周期。每一项
MSHR 都可能因为等待总线事务而在较长的一段时间内保持有效，但必须在有限的时间内结束生命周期，否则意味着出现了活锁或死锁。

### MSHR ID

每一项 MSHR 都有自己的 ID 值，并且该值是硬编码的，各项 MSHR 之间的 ID 不同。

由 MSHR 发起的 CHI 请求，其中 TxnID 值的低位与 MSHR ID 绑定。

### 分配

MainPipe 请求分配 MSHR 项时，由 MSHRCtl 模块内部的 MSHRSelector 选定一项未被分配的 MSHR。每一项 MSHR
在分配时，MainPipe 需要提供以下信息：

- 该缓存行的命中情况与一致性状态
- MSHR 状态机的初始状态
- 请求的必要原始信息（来自于 TileLink 请求或 CHI 请求）
- 请求与正在执行的写回（L2 向下的 TileLink Release 或 CHI Copy-Back Write）的嵌套情况

这些信息都会在被分配的 MSHR 项内寄存。

### 释放

当 MSHR 内所有的状态机项都被置为已完成时，即可立即原地释放，结束该 MSHR 项的生命周期，并准备好再一次被 MSHRSelector 选中并分配。关于
MSHR 的状态机项，详见 [@sec:mshr-state-machine] [状态机](#sec:mshr-state-machine)。


## 状态机 {#sec:mshr-state-machine}

状态机项主要分为两类：

- Schedule 状态项
- Wait 状态项

Schedule 状态项又称主动动作状态项，主要用来跟踪 MSHR 主动向 MainPipe、下游 CHI 通道、上游 TileLink
通道发送任务与请求的情况。其值为低有效，表示未完成状态，即任务尚未成功离开 MSHR
并被发出，其原因可能是未完成阻塞条件（有必要的前置动作未完成）或通道阻塞；值为高则表示对应任务已经成功发出，或不需要发出任务。

Wait 状态项又称被动动作状态项，主要用来跟踪 MSHR 期望收到的来自下游 CHI 通道、上游 TileLink 通道或 CoupledL2
内部模块的回复。其值为低有效，表示未完成状态，即对应的回复尚未回到 MSHR 项；值为高则表示对应回复已经收到，或不需要收到回复。

状态项会在 MSHR 被 MainPipe 分配时赋值，也会被 MSHR 内部的动作改变。

> 本小节的上游通常指 L1 缓存，下游通常指 NoC、LLC 等。

Schedule 状态项以 ```s_``` 为首命名，其概览如下：

| 名称               | 描述                                                            |
| ---------------- | ------------------------------------------------------------- |
| ```s_acquire```  | 首次需要向下游发送 权限提升请求 或 CMO 请求，或者需要向下发送被重试的写回或踢出请求                 |
| ```s_rprobe```   | 由于替换、写回，需要向上游发送 Probe 请求                                      |
| ```s_pprobe```   | 由于下游的 Snoop 请求，需要向上游发送 Probe 请求                               |
| ```s_release```  | 需要向下游发送的写回或踢出请求                                               |
| ```s_probeack``` | 由于下游的 Snoop 请求，需要向下游发送 Snoop 回复                               |
| ```s_refill```   | 需要向上游发送 Grant 回复                                              |
| ```s_retry```    | 由于没有空闲的路用于替换，向上游发送的 Grant 回复需要重试                              |
| ```s_cmoresp```  | 需要向上游发送 CBOAck 回复                                             |
| ```s_cmometaw``` | 由 CMO 引起的向 MainPipe 发送的目录更新请求                                 |
| ```s_rcompack``` | 由于向下游发送了读请求，需要发送对应的 CompAck 回复                                |
| ```s_wcompack``` | 由于向下游发送了写请求，需要发送对应的 CompAck 回复                                |
| ```s_cbwrdata``` | 由于向下游发送了写请求，需要发送对应的 CopyBackWrData 以写回数据                      |
| ```s_reissue```  | 由于下游回复了 RetryAck，且 MSHR 已获得 PCredit，需要向下游重发请求                 |
| ```s_dct```      | 由于下游的 Forwarding Snoop 请求，需要以 DCT 的形式发送 CompData 以向其它 RN 提供数据 |

Wait 状态项以 ```w_``` 为首命名，其概览如下：

| 名称                     | 描述                                                                                                                |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------- |
| ```w_rprobeackfirst``` | 由于替换、写回，向上游发送了 Probe 请求，需要等待收取来自上游的首个 Probe 回复                                                                    |
| ```w_rprobeacklast```  | 由于替换、写回，向上游发送了 Probe 请求，需要等待收取来自上游的最后一个 Probe 回复（单次回复时与 ```w_rprobeackfirst``` 动作相同）                              |
| ```w_pprobeackfirst``` | 由于下游的 Snoop 请求，向上游发送了 Probe 请求，需要等待收取来自上游的首个 Probe 回复                                                             |
| ```w_pprobeacklast```  | 由于下游的 Snoop 请求，向上游发送了 Probe 请求，需要等待收取来自上游的最后一个 Probe 回复（单次回复时与 ```w_pprobeackfirst``` 动作相同）                       |
| ```w_grantfirst```     | 由于向下发送了 权限提升请求 或 CMO 请求，需要等待下游的首个 Comp、CompData 或 DataSepResp 回复                                                  |
| ```w_grantlast```      | 由于向下发送了 权限提升请求 或 CMO 请求，需要等待下游的最后一个 CompData 或 DataSepResp 回复（在收到 Comp 回复时与 ```w_grantfirst``` 动作相同）              |
| ```w_grant```          | 由于向下发送了 权限提升请求 或 CMO 请求，需要等待下游的 Comp、CompData 或 RespSepData 回复，并在 CompData 与 RespSepData 回复中获得必要的 DBID 与 SrcID 信息 |
| ```w_releaseack```     | 由于向下游发送的写回请求或踢出请求，需要等待下游的 Comp 或 CompDBIDResp 回复                                                                  |
| ```w_replResp```       | 由于替换，需要等待来自 Directory 的替换选择结果                                                                                     |


## 任务分发

在 Schedule 状态项未完成时，MSHR 就会尝试向相应模块、通道发送相应的任务。每一个 MSHR 项经过 MSHRCtl
的仲裁可以直接分发任务到以下模块、通道：

- MainPipe
- 上游 TileLink B 通道
- 下游 TXREQ 通道
- 下游 TXRSP 通道

对于 TXDAT 通道任务的分发，则必须经过 MainPipe，详见 [@sec:reqarb-mainpipe]
[请求仲裁器与访存流水线](ReqArb_MainPipe.md)。

送往 MainPipe 的任务还会在同一周期内经过 RequestArb 的仲裁，详见 [@sec:reqarb-mainpipe]
[请求仲裁器与访存流水线](ReqArb_MainPipe.md)。

各个 Schedule 状态项对应的任务分发方向如下表：

| 名称               | 目标模块/通道          |
| ---------------- | ---------------- |
| ```s_acquire```  | 下游 TXREQ 通道      |
| ```s_rprobe```   | 上游 TileLink B 通道 |
| ```s_pprobe```   | 上游 TileLink B 通道 |
| ```s_release```  | MainPipe         |
| ```s_probeack``` | MainPipe         |
| ```s_refill```   | MainPipe         |
| ```s_retry```    | -                |
| ```s_cmoresp```  | MainPipe         |
| ```s_cmometaw``` | MainPipe         |
| ```s_rcompack``` | 下游 TXRSP 通道      |
| ```s_wcompack``` | 下游 TXRSP 通道      |
| ```s_cbwrdata``` | MainPipe         |
| ```s_reissue```  | -                |
| ```s_dct```      | MainPipe         |

### MainPipe

各个 MSHR 会根据自身状态机项的状态向 MainPipe 发送几种不同类型的任务。

#### 写回请求任务（```mp_release```）

写回请求任务（```mp_release```）由状态机项 ```s_release``` 触发，该任务的作用是在 MainPipe 通过 TXREQ
通道发送需要的缓存行写回请求或踢出请求。在状态机项 ```s_release``` 的状态未完成，且当前 MSHR 的状态符合一定的条件时，MSHR 就会尝试向
MainPipe 发送写回请求任务。

```s_release``` 被置为未完成时，其在各个情况下的 MSHR 状态需要满足以下条件，才可以向 MainPipe 发送写回请求任务：

1. 来自替换任务
    - 已经完成替换路的选择
    - 已经收到向上游的 Probe 的所有回复
    - 替换读请求已经收到来自下游的全部数据
2. 来自 CMO 请求
    - 已经收到向上游的 Probe 的所有回复

写回请求任务会要求 MainPipe 向 TXREQ 通道发送请求：

| 任务来源   | 上游 A 通道请求类型 | 是否有脏数据 | 下游 TXREQ 请求类型     |
| ------ | ----------- | ------ | ----------------- |
| 替换任务   | Acquire*    | 是      | WriteBackFull     |
|        |             | 否      | WriteEvictOrEvict |
| CMO 请求 | CBOClean    | -      | WriteCleanFull    |
|        | CBOFlush    | 是      | WriteBackFull     |
|        |             | 否      | Evict             |
|        | CBOInval    | -      | Evict             |

写回请求任务会按照情况要求 MainPipe 将 MSHR 持有的关联数据写入 DataStorage：

| 任务来源   | 上游 A 通道请求类型 | 是否有脏数据       | 数据来源          | 是否写入 DataStorage |
| ------ | ----------- | ------------ | ------------- | ---------------- |
| 替换任务   | Acquire*    | -            | RefillBuffer  | 是                |
| CMO 请求 | CBO*        | 来自向上游的 Probe | ReleaseBuffer | 是                |
|        |             | 其它           | -             | 否                |

且 CMO 请求在写回请求任务中要求 MainPipe 更新 Directory 中的缓存行状态，且清除缓存行的 Dirty 标记：

| 任务来源   | 上游 A 通道请求类型 | 起始状态    | 写入的状态   |
| ------ | ----------- | ------- | ------- |
| CMO 请求 | CBOClean    | TRUNK   | TIP     |
|        |             | TIP     | TIP     |
|        |             | BRANCH  | BRANCH  |
|        |             | INVALID | INVALID |
|        | CBOFlush    | -       | INVALID |
|        | CBOInval    | -       | INVALID |

#### 下游 Snoop 回复任务（```mp_probeack```）

下游 Snoop 回复任务（```mp_probeack```）由状态机项 ```s_probeack``` 触发。该任务的作用为在 MainPipe 通过
TXRSP 或 TXDAT 通道发送向下游的 Snoop 回复。在状态机项 ```s_probeack``` 的状态未完成，且当前 MSHR
的状态符合一定的条件时，MSHR 就会尝试向 MainPipe 发送下游 Snoop 回复任务。

```s_probeack``` 被置为未完成时，其 MSHR 状态需要满足以下条件，才可以向 MainPipe 发送下游 Snoop 回复任务：

- 已经收到向上游的 Probe 的所有回复

下游 Snoop 回复任务会要求 MainPipe 向 TXRSP 或 TXDAT 通道发送消息，并在 MSHR 内指定回复的 Snoop Response
类型，详见 [@sec:mshr-snoop-details] [Snoop 处理](#sec:mshr-snoop-details)。

下游 Snoop 回复任务会在满足以下情况时要求 MainPipe 将 MSHR 持有的关联数据写入 DataStorage：

- 下游 Snoop 请求的目标状态不是 I
- 上游 L1 在 Probe 过程中返回了脏数据（ProbeAckData）
- 上游 L1 没有在 Probe 结束前嵌套发起脏数据的写回（ReleaseData）

下游 Snoop 回复任务会要求 MainPipe 更新缓存行状态，详见 [@sec:mshr-snoop-details] [Snoop
处理](#sec:mshr-snoop-details)。

#### 替换路查询与上游 Grant/CBOAck 回复任务（```mp_grant```）

替换路查询与上游 Grant/CBOAck 回复任务（```mp_grant```）由状态机项 ```s_refill``` 或 ```s_cmoresp```
触发，且 ```s_refill``` 与 ```s_cmoresp``` 不会被同时置为未完成。该任务的作用为以下几项之一：

1. 在 MainPipe 向 Directory 发起替换路查询请求
2. 在 MainPipe 通过 TileLink D 通道向上游回复 Grant/GrantData
3. 在 MainPipe 通过 TileLink D 通道向上游回复 CBOAck

在状态机项 ```s_release``` 的状态未完成，且当前 MSHR 的状态符合一定的条件时，MSHR 就会尝试向 MainPipe 发送替换路查询或上游
Grant 回复任务；在状态机项 ```s_cmoresp``` 的状态未完成，且当前 MSHR 的状态符合一定的条件时，MSHR 就会尝试向 MainPipe
发送 CBOAck 回复任务。

在 ```s_refill``` 被置为未完成时，其 MSHR 状态需要满足以下条件，才可以向 MainPipe 发送替换路查询与上游 Grant 回复任务：

- 已经收到向上游的 Probe 的所有回复
- 已经收到来自下游的首个 Comp、CompData 或 RespSepData 回复
- 若需要，收到来自下游的所有 Comp、CompData 或 DataSepResp 回复
- 替换路查询重试没有超过重试抑制阈值

在连续多次发送替换路重试请求后，MSHR 会将其抑制一段时间，以防止过于密集、连续的重试导致活锁。

在 ``` s_cmoresp``` 被置为未完成时，其 MSHR 状态需要满足以下条件，才可以向 MainPipe 发送替换路查询与上游 CBOAck
回复任务：

- 已经收到向上游的 Probe 的所有回复
- 已经收到属于 ```w_releaseack``` 的来自下游的 Comp 回复
- 已经收到属于 ```w_grant``` 的来自下游的 Comp 回复（```w_releaseack``` 完成后 ```w_grant```
  才可接收下游的 Comp 回复）
- 若需要，已经完成发送所有的 CopyBackWrData

并且这些条件隐含一个特征，即 ```s_cmoresp``` 在除 CBOAck 回复流程之外的所有 CMO 子动作都已经完成后，才可以发起任务。

在 MSHR 需要等待替换路结果，并且 Directory 给予了重试回复后，MSHR 就会从 ```mp_grant``` 发送替换路重试任务。

替换路查询与上游 Grant 任务会要求 MainPipe 对 Directory 中的缓存行状态进行更新，若为上游 CBOAck
任务则不会要求，其更新规则如下：

| 任务来源            | 请求类型               | 初始状态    | 更新状态         |
| --------------- | ------------------ | ------- | ------------ |
| ```s_refill```  | Get                | TIP     | TIP          |
|                 |                    | TRUNK   | TIP          |
|                 |                    | BRANCH  | BRANCH       |
|                 |                    | INVALID | TIP```*```   |
|                 |                    |         | BRANCH       |
|                 | Acquire* toT       | -       | TRUNK        |
|                 | Acqurie* toB       | -       | TRUNK```*``` |
|                 |                    | -       | BRANCH       |
|                 | Hint PrefetchWrite | -       | TIP          |
|                 | Hint PrefetchRead  | -       | TIP```*```   |
|                 |                    | -       | BRANCH       |
| ```s_cmoresp``` | -                  | -       | -            |

其中 Get 更新为 TIP、Acquire* toB 更新为 TRUNK、Hint PrefetchRead 更新为 TIP 会发生于以下情况：

- 缓存行不存在于上游 L1 内，且在 L2 本地为 TIP 权限
- 正在对缓存行进行的操作不是 Alias 替换，且在 L2 本地为 TIP 或 TRUNK 权限
- 缓存行不存在于 L2 内，且向下游发送的读取请求返回了写权限

替换路查询与上游 Grant 任务在 Directory 未命中时会要求 MainPipe 将 Directory 中被选中替换的缓存行的对应 Tag
值，若为上游 CBOAck 任务则不会要求。

替换路查询与上游 Grant/CBOAck 任务会在满足以下其中一个条件时要求 MainPipe 将 MSHR 持有的关联数据写入 DataStorage：

- 收到来自下游的 CompData 或 DataSepResp 数据回复
- 在完成 Get 或 Alias 替换流程时向上游发送的 Probe 收到了脏数据

#### 下游 CopyBackWrData 任务（```mp_cbwrdata```）

写回请求任务（```mp_cbwrdata```）由状态机项 ```s_cbwrdata``` 触发。该任务的作用是在 MainPipe 通过 TXDAT
通道完成需要向下游发送的 CopyBackWrData。在状态机项 ```s_cbwrdata``` 的状态未完成，且当前 MSHR
的状态符合一定的条件时，MSHR 就会尝试向 MainPipe 发送写回请求任务。

```s_cbwrdata``` 通常被 ```s_release``` 与 ```w_releaseack``` 的以下动作置为未完成：

- 写回请求任务正离开 MSHR，即 ```s_release``` 状态项正被置为完成时

需要注意的是，在发送 WriteEvictOrEvict 后收到的回复为 Comp 时，```s_cbwrdata``` 会在 MSHR 未向 MainPipe
发送任何下游 CopyBackWrData 任务的前提下将 ```s_cbwrdata``` 置为已完成。

其 MSHR 状态需要满足以下条件，才可以向 MainPipe 发送写回请求任务：

- 写回请求任务已离开 MSHR，即 ```s_release``` 状态项已完成

#### 下游 DCT CompData 任务（```mp_dct```）

下游 DCT CompData 任务（```mp_dct```）由状态机项 ```s_dct``` 触发。该任务的作用是在 MainPipe 通过 TXDAT
通道完成 Forwarding Snoop 中 DCT 的部分。在状态机项 ```s_dct``` 的状态未完成，且当前 MSHR
的状态符合一定的条件时，MSHR 就会尝试向 MainPipe 发送下游 DCT CompData 任务。

在 ```s_dct``` 被置为未完成时，其 MSHR 状态需要满足以下条件，才可以向 MainPipe 发送下游 DCT CompData 任务：

- 在 Fowarding Snoop 流程中目标为 HN 的 Snoop 回复任务已经离开 MSHR，即 ```s_probeack``` 状态项为已完成

下游 DCT CompData 任务会要求 MainPipe 通过 TXDAT 通道发送 CompData 回复。且根据 DCT 的定义，该 CompData
回复的目标是另一个处理器核（即 RN）。

#### CMO 缓存状态更新任务（```mp_cmometaw```）

CMO 缓存状态更新任务（```mp_cmometaw```）由状态机项 ```s_cmometaw``` 触发。该任务的作用是在 CBOClean
操作不需要进行 WriteCleanFull 写回时，在 MainPipe 更新缓存行状态。

在 ```s_cmometaw``` 被置为未完成时，MSHR 就可以向 MainPipe 发送 CMO 缓存状态更新任务，并进行如下更新：

- 在收到 ProbeAck toN 时更新记录为缓存行不存在于上游 L1
- 清除状态至 Clean
- 更新权限为 TIP

### 上游 TileLink B 通道

向上游 TileLink B 通道的请求发送由状态机项 ```s_pprobe``` 或 ```s_rprobe``` 触发。且 ```s_pprobe```
与 ```s_rprobe``` 不会被同时置为未完成。

在 ```s_pprobe``` 或 ```s_rprobe``` 中的任意一个状态机项被置为未完成时，MSHR 就可以向上游 TileLink B
通道发送请求。在各情况下的请求类型见下表：

| 任务来源           | 上游请求类型   | 下游请求类型               | 缓存行状态 | 发送请求类型    |
| -------------- | -------- | -------------------- | ----- | --------- |
| ```s_pprobe``` | -        | SnpOnce              | -     | Probe toT |
|                | -        | SnpClean             | -     | Probe toB |
|                | -        | SnpShared            | -     | Probe toB |
|                | -        | SnpNotSharedDirty    | -     | Probe toB |
|                | -        | SnpUnique            | -     | Probe toN |
|                | -        | SnpCleanShared       | -     | Probe toT |
|                | -        | SnpCleanInvalid      | -     | Probe toN |
|                | -        | SnpMakeInvalid       | -     | Probe toN |
|                | -        | SnpMakeInvalidStash  | -     | Probe toN |
|                | -        | SnpUniqueStash       | -     | Probe toN |
|                | -        | SnpStashUnique       | -     | Probe toT |
|                | -        | SnpStashShared       | -     | Probe toT |
|                | -        | SnpOnceFwd           | -     | Probe toT |
|                | -        | SnpCleanFwd          | -     | Probe toB |
|                | -        | SnpNotSharedDirtyFwd | -     | Probe toB |
|                | -        | SnpSharedFwd         | -     | Probe toB |
|                | -        | SnpUniqueFwd         | -     | Probe toN |
|                | -        | SnpQuery             | -     | Probe toT |
| ```s_rprobe``` | Get      | -                    | TRUNK | Probe toB |
|                | Acquire* | -                    | -     | Probe toN |
|                | CBOClean | -                    | TRUNK | Probe toB |

### 下游 TXREQ 通道

向下游 TXREQ 通道的请求发送由状态机项 ```s_acquire``` 或 ```s_reissue``` 触发。且 ```s_acquire``` 与
```s_reissue``` 不会被同时置为未完成。

在 ```s_acquire``` 被置为未完成时，对于替换任务，可以立即向下游发送权限提升请求。但对于 CMO 任务，需要满足以下条件后，才可以向下游发送
CMO 请求：

- 向上游的 Probe 已经收到所有回复
- 向下游的写回请求已经收到 Comp 或 CompDBIDResp
- 向下游的 CopyBackWrData 任务已经离开 MSHR 或不需要该任务

在 ```s_reissue``` 被置为未完成时，需要满足以下条件，才可以向下游重发被重试的请求：

- 已收到来自下游的 RetryAck
- 已收到并被分配到来自下游的 PCrdGrant
- 处于存在已离开 MSHR 的 ```mp_release``` 或下游 TXREQ 通道任务但未收到任何回复的状态，即 ```s_release```
  状态项已完成但 ```w_releaseack``` 状态项未完成，或 ```s_acquire``` 状态项已完成但 ```w_grant```
  状态项未完成

向下游 TXREQ 通道在各个情况下发送的请求类型如下表：

| 任务来源            | 未完成状态              | 上游请求类型             | 未完成请求类型            | 发送请求类型             |
| --------------- | ------------------ | ------------------ | ------------------ | ------------------ |
| ```s_acquire``` | -                  | Get                | -                  | ReadNotSharedDirty |
|                 |                    | AcquirePerm toT    | -                  | MakeUnique         |
|                 |                    | AcquireBlock toT   | -                  | ReadUnique         |
|                 |                    | AcquireBlock toB   | -                  | ReadNotSharedDirty |
|                 |                    | Hint PrefetchWrite | -                  | ReadUnique         |
|                 |                    | Hint PrefetchRead  | -                  | ReadNotSharedDirty |
|                 |                    | CBOClean           | -                  | CleanShared        |
|                 |                    | CBOFlush           | -                  | CleanInvalid       |
|                 |                    | CBOInval           | -                  | MakeInvalid        |
| ```s_reissue``` | ```w_grant```      | Get                | ReadNotSharedDirty | ReadNotSharedDirty |
|                 |                    | AcquirePerm toT    | MakeUnique         | MakeUnique         |
|                 |                    | AcquireBlock toT   | ReadUnique         | ReadUnique         |
|                 |                    | AcquireBlock toB   | ReadNotSharedDirty | ReadNotSharedDirty |
|                 |                    | Hint PrefetchWrite | ReadUnique         | ReadUnique         |
|                 |                    | Hint PrefetchRead  | ReadNotSharedDirty | ReadNotSharedDirty |
|                 |                    | CBOClean           | CleanShared        | CleanShared        |
|                 |                    | CBOFlush           | CleanInvalid       | CleanInvalid       |
|                 |                    | CBOInval           | MakeInvalid        | MakeInvalid        |
| ```s_reissue``` | ```w_releaseack``` | Acquire*           | WriteBackFull      | WriteBackFull      |
|                 |                    |                    | WriteEvictOrEvict  | WriteEvictOrEvict  |
|                 |                    | CBOClean           | WriteCleanFull     | WriteCleanFull     |
|                 |                    | CBOFlush           | WriteBackFull      | WriteBackFull      |
|                 |                    |                    | Evict              | Evict              |
|                 |                    | CBOInval           | Evict              | Evict              |

### 下游 TXRSP 通道

向下游 TXRSP 通道的消息发送由状态机项 ```s_rcompack``` 或 ```s_wcompack``` 触发，该通道主要用来向下游发送
CompAck 消息。其中 ```s_rcompack``` 与 ```s_wcompack``` 可能被同时置为未完成，且 ```s_rcompack```
的优先级更高。

在 ```s_rcompack``` 被置为未完成时，需要满足以下条件，才可以向下游发送 CompAck 消息：

1. 配置为 Issue B 时
    - 收到下游的 Comp 或所有 CompData
2. 配置为 Issue C 以及更新版本时
    - 收到下游的 Comp 或 首个 CompData 或 RespSepData 与首个 DataSepResp

在 ```s_wcompack``` 被置为未完成时，需要满足以下条件，才可以向下游发送 CompAck 消息：

- ```s_rcompack``` 已完成或未被置为未完成

## Snoop 处理 {#sec:mshr-snoop-details}

### 非嵌套 Snoop

当没有同地址的写回请求未完成时，收到的 Snoop 即为非嵌套的普通 Snoop，是 Snoop 最基本的处理情况。非嵌套 Snoop 在 MSHR
中的处理方式如下：

| Snoop 请求类型            | 起始状态 | 最终状态 | RetToSrc | Snoop 回复                   |
| --------------------- | ---- | ---- | -------- | -------------------------- |
| SnpOnce               | I    | -    | -        | -                          |
|                       | UC   | UC   | X        | SnpRespData_UC             |
|                       | UD   | UD   | X        | SnpRespData_UD_PD          |
|                       | SC   | -    | -        | -                          |
| SnpClean,             | I    | -    | -        | -                          |
| SnpShared,            | UC   | SC   | X        | SnpResp_SC                 |
| SnpNotSharedDirty     | UD   | SC   | X        | SnpRespData_SC_PD          |
|                       | SC   | -    | -        | -                          |
| SnpUnique             | I    | -    | -        | -                          |
|                       | UC   | I    | X        | SnpResp_I                  |
|                       | UD   | I    | X        | SnpRespData_I_PD           |
|                       | SC   | I    | 0        | SnpResp_I                  |
|                       |      |      | 1        | SnpRespData_I              |
| SnpCleanShared        | I    | -    | -        | -                          |
|                       | UC   | UC   | 0        | SnpResp_UC                 |
|                       | UD   | UC   | 0        | SnpRespData_UC_PD          |
|                       | SC   | -    | -        | -                          |
| SnpCleanInvalid       | I    | -    | -        | -                          |
|                       | UC   | I    | 0        | SnpResp_I                  |
|                       | UD   | I    | 0        | SnpRespData_I_PD           |
|                       | SC   | I    | 0        | SnpResp_I                  |
| SnpMakeInvalid        | -    | I    | 0        | SnpResp_I                  |
| SnpMakeInvalidStash   | -    | I    | 0        | SnpResp_I                  |
| SnpUniqueStash        | I    | -    | -        | -                          |
|                       | UC   | I    | 0        | SnpResp_I                  |
|                       | UD   | I    | 0        | SnpRespData_I_PD           |
|                       | SC   | I    | 0        | SnpResp_I                  |
| SnpStashUnique,       | I    | -    | -        | -                          |
| SnpStashShared        | UC   | UC   | 0        | SnpResp_UC                 |
|                       | UD   | UD   | 0        | SnpResp_UD                 |
|                       | SC   | -    | -        | -                          |
| SnpOnceFwd            | I    | I    | 0        | SnpResp_I                  |
|                       | UC   | UC   | 0        | SnpResp_UC_Fwded_I         |
|                       | UD   | UD   | 0        | SnpResp_UD_Fwded_I         |
|                       | SC   | SC   | 0        | SnpResp_SC_Fwded_I         |
| SnpCleanFwd,          | I    | I    | X        | SnpResp_I                  |
| SnpNotSharedDirtyFwd, | UC   | SC   | 0        | SnpResp_SC_Fwded_SC        |
| SnpSharedFwd          |      |      | 1        | SnpRespData_SC_Fwded_SC    |
|                       | UD   | SC   | X        | SnpRespData_SC_PD_Fwded_SC |
|                       | SC   | SC   | 0        | SnpResp_SC_Fwded_SC        |
|                       |      |      | 1        | SnpRespData_SC_Fwded_SC    |
| SnpUniqueFwd          | I    | I    | 0        | SnpResp_I                  |
|                       | UC   | I    | 0        | SnpResp_I_Fwded_UC         |
|                       | UD   | I    | 0        | SnpResp_I_Fwded_UD_PD      |
|                       | SC   | I    | 0        | SnpResp_I_Fwded_UC         |
| SnpQuery              | I    | -    | -        | -                          |
|                       | UC   | UC   | 0        | SnpResp_UC                 |
|                       | UD   | UD   | 0        | SnpResp_UD                 |
|                       | SC   | -    | -        | -                          |

> “-” 以及未列出的缓存状态表示在相应情况下的该类请求不会进入 MSHR。

关于具体 Snoop 请求在什么情况下会分配 MSHR，详见 [@sec:reqarb-mainpipe]
[请求仲裁器与访存流水线](ReqArb_MainPipe.md)。


### 嵌套 Snoop

在 MSHR 处理向下游的写回请求过程中，仍然需要保证 CoupledL2 需要能够响应下游的 Snoop 请求以及上游的 Release
请求。此时，未完成的写回请求则视为被 Snoop 请求嵌套，或被上游的 Release 请求嵌套。需要注意的是，由于 CHI 协议中存在 Silent
Eviction，且 Evict 请求的初始状态为 I，故不发生数据写回的踢出请求（Evict）不会被视为嵌套。

> “-” 以及未列出的缓存状态表示在相应情况下的该类请求不会进入 MSHR，或不在嵌套情况范围内。

关于具体 Snoop 请求在什么情况下会分配 MSHR，详见 [@sec:reqarb-mainpipe]
[请求仲裁器与访存流水线](ReqArb_MainPipe.md)。

可能在 MSHR 内发生并处理的下游 Snoop 请求嵌套如下。

#### 特性1：Snoop 与 WriteBackFull 的嵌套

| Snoop 请求类型           | 起始状态 | 嵌套前状态 | 嵌套后状态 | RetToSrc | Snoop 回复                  |
| -------------------- | ---- | ----- | ----- | -------- | ------------------------- |
| SnpOnce              | -    | -     | -     | -        | -                         |
| SnpClean             | -    | -     | -     | -        | -                         |
| SnpShared            | -    | -     | -     | -        | -                         |
| SnpNotSharedDirty    | -    | -     | -     | -        | -                         |
| SnpCleanShared       | -    | -     | -     | -        | -                         |
| SnpCleanInvalid      | -    | -     | -     | -        | -                         |
| SnpMakeInvalid       | -    | -     | -     | -        | -                         |
| SnpUnique            | -    | -     | -     | -        | -                         |
| SnpUniqueStash       | -    | -     | -     | -        | -                         |
| SnpMakeInvalidStash  | -    | -     | -     | -        | -                         |
| SnpStashUnique       | -    | -     | -     | -        | -                         |
| SnpStashShared       | -    | -     | -     | -        | -                         |
| SnpOnceFwd           | UD   | UD    | I     | X        | SnpRespData_I_PD_Fwded_I  |
| SnpCleanFwd          | UD   | UD    | I     | X        | SnpRespData_I_PD_Fwded_SC |
| SnpSharedFwd         | UD   | UD    | I     | X        | SnpRespData_I_PD_Fwded_SC |
| SnpNotSharedDirtyFwd | UD   | UD    | I     | X        | SnpRespData_I_PD_Fwded_SC |
| SnpUniqueFwd         | UD   | UD    | I     | X        | SnpResp_I_Fwded_UD_PD     |
| SnpQuery             | -    | -     | -     | -        | -                         |

#### 特性2：Snoop 与 WriteEvictOrEvict 的嵌套

| Snoop 请求类型           | 起始状态 | 嵌套前状态 | 嵌套后状态 | RetToSrc | Snoop 回复               |
| -------------------- | ---- | ----- | ----- | -------- | ---------------------- |
| SnpOnce              | -    | -     | -     | -        | -                      |
| SnpClean             | -    | -     | -     | -        | -                      |
| SnpShared            | -    | -     | -     | -        | -                      |
| SnpNotSharedDirty    | -    | -     | -     | -        | -                      |
| SnpCleanShared       | -    | -     | -     | -        | -                      |
| SnpCleanInvalid      | -    | -     | -     | -        | -                      |
| SnpMakeInvalid       | -    | -     | -     | -        | -                      |
| SnpUnique            | -    | -     | -     | -        | -                      |
| SnpUniqueStash       | -    | -     | -     | -        | -                      |
| SnpMakeInvalidStash  | -    | -     | -     | -        | -                      |
| SnpStashUnique       | -    | -     | -     | -        | -                      |
| SnpStashShared       | -    | -     | -     | -        | -                      |
| SnpOnceFwd           | UC   | UC    | I     | X        | SnpRespData_I_Fwded_I  |
| SnpCleanFwd          | UC   | UC    | I     | 0        | SnpResp_I_Fwded_SC     |
|                      |      |       |       | 1        | SnpRespData_I_Fwded_SC |
| SnpSharedFwd         | UC   | UC    | I     | 0        | SnpResp_I_Fwded_SC     |
|                      |      |       |       | 1        | SnpRespData_I_Fwded_SC |
| SnpNotSharedDirtyFwd | UC   | UC    | I     | 0        | SnpResp_I_Fwded_SC     |
|                      |      |       |       | 1        | SnpRespData_I_Fwded_SC |
| SnpUniqueFwd         | UC   | UC    | I     | 0        | SnpResp_I_Fwded_UC     |
| SnpQuery             | -    | -     | -     | -        | -                      |

#### 特性3：Snoop 与 WriteCleanFull 的嵌套

| Snoop 请求类型           | 起始状态 | 嵌套前状态 | 嵌套后状态 | RetToSrc | Snoop 回复                   |
| -------------------- | ---- | ----- | ----- | -------- | -------------------------- |
| SnpOnce              | -    | -     | -     | -        | -                          |
| SnpClean             | -    | -     | -     | -        | -                          |
| SnpShared            | -    | -     | -     | -        | -                          |
| SnpNotSharedDirty    | -    | -     | -     | -        | -                          |
| SnpCleanShared       | -    | -     | -     | -        | -                          |
| SnpCleanInvalid      | UD   | UD    | I     | 0        | SnpRespData_I_PD           |
|                      |      | UC    | I     | 0        | SnpResp_I                  |
|                      |      | SC    | I     | 0        | SnpResp_I                  |
| SnpMakeInvalid       | UD   | UD    | I     | 0        | SnpResp_I                  |
|                      |      | UC    | I     | 0        | SnpResp_I                  |
|                      |      | SC    | I     | 0        | SnpResp_I                  |
| SnpUnique            | UD   | UD    | I     | X        | SnpRespData_I_PD           |
|                      |      | UC    | I     | X        | SnpResp_I                  |
|                      |      | SC    | I     | 0        | SnpResp_I                  |
|                      |      |       |       | 1        | SnpRespData_I              |
| SnpUniqueStash       | UD   | UD    | I     | 0        | SnpRespData_I_PD           |
|                      |      | UC    | I     | 0        | SnpResp_I                  |
|                      |      | SC    | I     | 0        | SnpResp_I                  |
| SnpMakeInvalidStash  | UD   | UD    | I     | 0        | SnpResp_I                  |
|                      |      | UC    | I     | 0        | SnpResp_I                  |
|                      |      | SC    | I     | 0        | SnpResp_I                  |
| SnpStashUnique       | -    | -     | -     | -        | -                          |
| SnpStashShared       | -    | -     | -     | -        | -                          |
| SnpOnceFwd           | UD   | UD    | SC    | 0        | SnpRespData_SC_PD_Fwded_I  |
|                      |      | UC    | UC    | 0        | SnpResp_UC_Fwded_I         |
|                      |      | SC    | SC    | 0        | SnpResp_SC_Fwded_I         |
| SnpCleanFwd          | UD   | UD    | SC    | X        | SnpRespData_SC_PD_Fwded_SC |
|                      |      | UC    | SC    | 0        | SnpResp_SC_Fwded_SC        |
|                      |      |       |       | 1        | SnpRespData_SC_Fwded_SC    |
|                      |      | SC    | SC    | 0        | SnpResp_SC_Fwded_SC        |
|                      |      |       |       | 1        | SnpRespData_SC_Fwded_SC    |
| SnpSharedFwd         | UD   | UD    | SC    | X        | SnpRespData_SC_PD_Fwded_SC |
|                      |      | UC    | SC    | 0        | SnpResp_SC_Fwded_SC        |
|                      |      |       |       | 1        | SnpRespData_SC_Fwded_SC    |
|                      |      | SC    | SC    | 0        | SnpResp_SC_Fwded_SC        |
|                      |      |       |       | 1        | SnpRespData_SC_Fwded_SC    |
| SnpNotSharedDirtyFwd | UD   | UD    | SC    | X        | SnpRespData_SC_PD_Fwded_SC |
|                      |      | UC    | SC    | 0        | SnpResp_SC_Fwded_SC        |
|                      |      |       |       | 1        | SnpRespData_SC_Fwded_SC    |
|                      |      | SC    | SC    | 0        | SnpResp_SC_Fwded_SC        |
|                      |      |       |       | 1        | SnpRespData_SC_Fwded_SC    |
| SnpUniqueFwd         | UD   | UD    | I     | 0        | SnpResp_I_Fwded_UD_PD      |
|                      |      | UC    | I     | 0        | SnpResp_I_Fwded_UC         |
|                      |      | SC    | I     | 0        | SnpResp_I_Fwded_UC         |
| SnpQuery             | -    | -     | -     | -        | -                          |


## 写回嵌套处理

在可能发生嵌套时，每一项 MSHR 会收到 MainPipe 广播的请求嵌套信息，其中包含可能发生嵌套的缓存行的 Tag 与 Set
地址以及嵌套行为。具体信号为 MSHR 内的 ```nestwb``` 端口与 NestedWriteback Bundle 类。

考虑可能导致嵌套的上游 Release/ReleaseData 请求与下游 Snoop 请求，在 MSHR 内需要的各种嵌套处理逻辑如下。

### 特性1：正被替换的缓存行与上游的 ReleaseData TtoN 嵌套

当 MSHR 中被替换的缓存行的 Tag 和 Set 地址与由 MainPipe 广播到各项 MSHR 的 ReleaseData TtoN 的 Tag 和
Set 地址相同时，发生此种嵌套。对应的信号名为 ```c_set_dirty```。

此种嵌套通常出现在 CoupledL2 已经或正在向上游 L1 缓存发送由替换引起的 Probe toN 请求，且上游 L1 缓存对于该 Probe toN
的回复尚未被 CoupledL2 观测到时，上游 L1 缓存主动向 CoupledL2 发起了 ReleaseData TtoN。

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- 标记为 Dirty
- 更新状态为 TIP
- 更新状态为上游 L1 不再持有该缓存行

### 特性2：正被替换的缓存行与上游的 Release TtoN 嵌套

当 MSHR 中被替换的缓存行的 Tag 和 Set 地址与由 MainPipe 广播到各项 MSHR 的 Release TtoN 的 Tag 和 Set
地址相同时，发生此种嵌套。对应的信号名为 ```c_set_tip```。

此种嵌套通常出现在 CoupledL2 已经或正在向上游 L1 缓存发送由替换引起的 Probe toN 请求，且上游 L1 缓存对于该 Probe toN
的回复尚未被 CoupledL2 观测到时，上游 L1 缓存主动向 CoupledL2 发起了 Release TtoN。

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- 更新状态为 TIP
- 更新状态为上游 L1 不再持有该缓存行

### 特性3：正被替换的缓存行与下游的 Snoop 嵌套

当 MSHR 中被替换的缓存行的 Tag 和 Set 地址与由 MainPipe 广播到各项 MSHR 的下游 Snoop 的 Tag 和 Set
地址相同时，发生此嵌套。对应的信号名为 ```b_inv_dirty```。

此处的下游 Snoop 需要排除在 CHI 规定中不可改变缓存行状态的一类 Snoop，包括
SnpQuery、SnpStashUnique、SnpStashShared。

此种嵌套通常出现在 CoupledL2 已经或正在向下游发送由替换引起的写回请求，且下游尚未回复 CompDBIDResp 时，下游向 CoupledL2
发起了新的 Snoop 请求。

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- 清除状态至 Clean
- 更新状态为 INVALID
- 清除由于上游 L1 缓存回复 ProbeAckData 而置的 Dirty 标志

### 特性4：在下游 Snoop 发生嵌套时向目录写入 BRANCH 状态

当 MSHR 的 Tag 和 Set 地址与由 MainPipe 广播到各项 MSHR 的下游 Snoop 的 Tag 和 Set 地址相同，且该 Snoop
请求在 MainPipe 上写入了 BRANCH 的缓存行状态时，发生此嵌套。

此种嵌套通常出现在 CoupledL2 已经或正在向下游发送由替换引起的写回请求，且下游尚未回复 CompDBIDResp 时，下游向 CoupledL2
发起了新的 Snoop 请求。

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- 清除状态至 Clean
- 若缓存行权限不为 INVALID，则更新为 BRANCH
- 清除由于上游 L1 缓存回复 ProbeAckData 而置的 Dirty 标志

### 特性5：在下游 Snoop 发生嵌套时向目录写入 INVALID 状态

当 MSHR 的 Tag 和 Set 地址与由 MainPipe 广播到各项 MSHR 的下游 Snoop 的 Tag 和 Set 地址相同，且该 Snoop
请求在 MainPipe 上写入了 INVALID 的缓存行状态时，发生此嵌套。

此种嵌套通常出现在 CoupledL2 已经或正在向下游发送由替换引起的写回请求，且下游尚未回复 CompDBIDResp 时，下游向 CoupledL2
发起了新的 Snoop 请求。

此时需要对 MSHR 内记录的缓存行状态进行如下更新：

- 清除状态至 Clean
- 更新状态为 INVALID
- 更新状态为上游 L1 不再持有该缓存行
- 清除由于上游 L1 缓存回复 ProbeAckData 而置的 Dirty 标志
- 若为需要执行替换的请求，重新选择被替换的行

## Retry 与 P-Credit 机制

若收到了来自下游的 RetryAck 回复，MSHR 就会拉高 P-Credit 查询的有效位，并且将 CHI 的 PCrdType 与 SrcID 域发送给
MainPipe，由 MainPipe 决定是否向 MSHR 的对应事务分配 P-Credit 以进行重试。关于 P-Credit 的接收与分配，详见
[@sec:reqarb-mainpipe] [请求仲裁器与访存流水线](ReqArb_MainPipe.md)。
