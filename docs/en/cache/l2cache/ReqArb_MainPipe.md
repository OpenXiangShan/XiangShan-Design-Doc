# 请求仲裁器与主流水线 {#sec:reqarb-mainpipe}

请求仲裁器与访存流水线组成了 CoupledL2 的整体五级流水线，按顺序简称为第一级 ```s1```、第二级 ```s2```、第三级
```s3```、第四级 ```s4```、第五级 ```s5```。其中请求仲裁器 ReqArbiter 主要组成
```s1```、```s2```，主流水线 MainPipe 主要组成 ```s3```、```s4```、```s5```。

## S0 流水级

```s0``` 仅位于请求仲裁器 ReqArbiter 内，且不算作单独的一个流水级。```s0``` 仅用于产生给每一项 MSHR
的任务反压信号，在以下情况下 ReqArbter 会阻止来自 MSHR 的任务离开 MSHR 并进入流水线：

- 上一周期存在需要读取 Directory 的 MSHR 任务且被阻塞
- 存在来自于 GrantBuffer 的阻塞信号
- 存在来自于上游 TileLink C 通道的阻塞信号
- 存在来自于下游 TXDAT 通道的阻塞信号
- 存在来自于下游 TXRSP 通道的阻塞信号
- 存在来自于下游 TXREQ 通道的阻塞信号

## S1 流水级

```s1``` 仅位于请求仲裁器 ReqArbiter 内。

在 ```s1```，会对以下几种请求来源进行仲裁：

- MSHR
- 上游 TileLink C 通道
- 上游 TileLink B 通道
- 上游 TileLink A 通道

以上列表中，位于上方的请求来源拥有最高的优先级，在他们同时进入 ReqArbiter 的 ```s1```
时，会选择其中优先级最高的一项进行握手，并阻塞其它的任务来源。即其中 MSHR 任务优先级最高，其次是上游 TileLink C 通道、上游 TileLink
B 通道、上游 TileLink A 通道。

在 ```s1```，ReqArbiter 还需要需要考虑来自于 MainPipe 的阻塞信号。并且此时在 ```s2``` 就绪时，请求才可以离开
```s1```，否则请求被阻塞并寄存在 ```s1```。

在完成仲裁后，在 ```s1``` 向 Directory 发送读取请求。


## S2 流水级

```s2``` 位于请求仲裁器 ReqArbiter 与主流水线 MainPipe 内。

由于 CoupledL2 的 SRAM 在频率上有限制，所以采用了多周期路径 MCP2（Multi-Cycle Path 2），意味着 SRAM
的单次读写请求都需要至少持续两个周期。故在 ```s2```，ReqArbiter 会将所有的背靠背请求阻塞一拍，以使得请求在 MainPipe
上的保持时间以及请求间隔符合 MCP2 的要求。

ReqArbiter 于 ```s2``` 决定是否读取 ReleaseBuffer 或 RefillBuffer。并于 ```s2``` 向
ReleaseBuffer 或 RefillBuffer 发送读请求。

于以下情况之一，ReqArbiter 会于 ```s2``` 向 RefillBuffer 发送读请求：

1. 该任务是由替换任务引起的下游缓存行写回、踢出任务（此时写回的数据已不再被需要，替换读取到的数据在此时被写入 DataStorage）
2. 该任务是上游 TileLink A 通道请求，但不使用上游 Probe 回复的数据（若使用上游 Probe 回复的数据，则应当读取
   ReleaseBuffer）

于以下情况之一，ReqArbiter 会于 ```s2``` 向 ReleaseBuffer 发送读请求：

1. 该任务是 MSHR 任务，且下游请求需要读取上游 Probe 回复的数据
2. 该任务是 MSHR 任务，且上游 TileLink A 通道请求需要使用上游 Probe 回复的数据
3. 该任务不是 MSHR 任务，且下游 Snoop 与下游写回请求任务发生了嵌套

ReqArbiter 于 ```s2``` 时将任务送入 MainPipe。

MainPipe 会于 ```s2``` 生成对于 ```s1``` 的阻塞信号并送回 ReqArbiter 与 RequestBuffer。MainPipe
需要于如下情况向各个组件、通道发送阻塞信号：

- 在任务到达 ```s2``` 时若无法确定其一定不会对 Directory 进行写操作，则向 RequestBuffer 发送阻塞同 Set 请求的信号
- 在任务到达 ```s2``` 时若无法确定其一定不会对 Directory 进行写操作，则向 ReqArbiter 发送阻塞同 Set 的 MSHR
  请求的信号
- 在任务到达 ```s2``` 时若无法确定其一定不会对 Directory 进行写操作，则向 ReqArbiter 发送阻塞同 Set 的上游
  TileLink C 通道请求的信号
- 在任务到达 ```s2```（以及 ```s3```、```s4```、```s5``` 时，即包括所有在仍 MainPipe
  上的任务，在后续章节中不再赘述）时，向 ReqArbiter 发送阻塞同地址的下游 RXSNP 通道请求的信号

## S3 流水级

```s3``` 仅位于主流水线 MainPipe 内。大部分请求的判断、分发逻辑，以及与各个其它模块的交互都位于 ```s3``` 阶段。


### 缓存行状态收集

在 ```s1``` 由 ReqArbiter 向 Directory 发出的读取请求在 ```s3``` 可以得到读取结果。若来自下游 RXSNP
通道的请求出现了与 MSHR 的嵌套，即下游 Snoop 请求的地址与某一项未完成的 MSHR 地址相同，则会使用该项 MSHR 中的缓存行状态覆盖
Directory 的读取结果。

### MSHR 分配

MainPipe 在 ```s3``` 阶段满足以下条件之一时会分配 MSHR：

1. 任务来自于上游 TileLink A 通道
    - Acquire*、Hint、Get 请求未命中缓存行
    - Acquire* toT 命中 BRANCH 状态的缓存行
    - CBO* 类 CMO 请求
    - 别名（Alias）替换请求
    - 任意需要向上游发送 Probe 请求的任务
        - Get 请求命中 TRUNK 状态的缓存行且其存在于上游 L1
        - CBOClean 请求命中 TRUNK 状态的缓存行且其存在于上游 L1
        - CBOFlush 请求命中的缓存行存在于上游 L1
        - CBOInval 请求命中的缓存行存在于上游 L1
2. 任务来自于下游 RXSNP 通道
    - Snoop 对应类型命中对应缓存行状态
    - Forwarding Snoop 且命中缓存行

对于来自下游的非 Forwarding Snoop 类型的 Snoop 请求，需要分配 MSHR 的情况见下表：

| Snoop 请求类型          | 命中状态  | 存在于 L1 |
| ------------------- | ----- | ------ |
| SnpOnce             | TRUNK | 是      |
| SnpClean            | TRUNK | 是      |
| SnpShared           | TRUNK | 是      |
| SnpNotSharedDirty   | TRUNK | 是      |
| SnpUnique           | -     | 是      |
| SnpCleanShared      | TRUNK | 是      |
| SnpCleanInvalid     | -     | 是      |
| SnpMakeInvalid      | -     | 是      |
| SnpMakeInvalidStash | -     | 是      |
| SnpUniqueStash      | -     | 是      |
| SnpStashUnique      | TRUNK | 是      |
| SnpStashShared      | TRUNK | 是      |
| SnpQuery            | TRUNK | 是      |

### Directory 写入

MainPipe 在 ```s3``` 会按照任务的要求向 Directory 发送写请求。

### DataStorage 读写

MainPipe 在 ```s3``` 会按照人物的要求向 DataStorage 发送读或写请求。

### 请求与消息分发

MainPipe 在 ```s3``` 会按照任务的要求向以下通道方向之一发送请求：

- 上游 TileLink D 通道
- 下游 TXREQ 通道
- 下游 TXRSP 通道
- 下游 TXDAT 通道

具体的分发方向由任务本身决定，详见 [@sec:mshr] [MSHR](MSHR.md)。

### Snoop 请求处理

来自下游的 Snoop 请求可能不分配 MSHR，而直接在 MainPipe 中完成回复动作。其 Snoop 请求的状态转移在 MainPipe 的
```s3``` 决定。在 ```s3``` 发生的 Snoop 请求与其相应的状态转移如下表：

| Snoop 请求类型            | 起始状态 | 最终状态 | RetToSrc | Snoop 回复                   |
| --------------------- | ---- | ---- | -------- | -------------------------- |
| SnpOnce               | I    | I    | X        | SnpResp_I                  |
|                       | UC   | UC   | X        | SnpRespData_UC             |
|                       | UD   | UD   | X        | SnpRespData_UD_PD          |
|                       | SC   | SC   | 0        | SnpResp_SC                 |
|                       |      |      | 1        | SnpRespData_SC             |
| SnpClean,             | I    | I    | X        | SnpResp_I                  |
| SnpShared,            | UC   | SC   | X        | SnpResp_SC                 |
| SnpNotSharedDirty     | UD   | SC   | X        | SnpRespData_SC_PD          |
|                       | SC   | SC   | 0        | SnpResp_SC                 |
|                       |      |      | 1        | SnpRespData_SC             |
| SnpUnique             | I    | I    | X        | SnpResp_I                  |
|                       | UC   | I    | X        | SnpResp_I                  |
|                       | UD   | I    | X        | SnpRespData_I_PD           |
|                       | SC   | I    | 0        | SnpResp_I                  |
|                       |      |      | 1        | SnpRespData_I              |
| SnpCleanShared        | I    | I    | 0        | SnpResp_I                  |
|                       | UC   | UC   | 0        | SnpResp_UC                 |
|                       | UD   | UC   | 0        | SnpRespData_UC_PD          |
|                       | SC   | SC   | 0        | SnpResp_SC                 |
| SnpCleanInvalid       | I    | I    | 0        | SnpResp_I                  |
|                       | UC   | I    | 0        | SnpResp_I                  |
|                       | UD   | I    | 0        | SnpRespData_I_PD           |
|                       | SC   | I    | 0        | SnpResp_I                  |
| SnpMakeInvalid        | -    | I    | 0        | SnpResp_I                  |
| SnpMakeInvalidStash   | -    | I    | 0        | SnpResp_I                  |
| SnpUniqueStash        | I    | I    | 0        | SnpResp_I                  |
|                       | UC   | I    | 0        | SnpResp_I                  |
|                       | UD   | I    | 0        | SnpRespData_I_PD           |
|                       | SC   | I    | 0        | SnpResp_I                  |
| SnpStashUnique,       | I    | I    | 0        | SnpResp_I                  |
| SnpStashShared        | UC   | UC   | 0        | SnpResp_UC                 |
|                       | UD   | UD   | 0        | SnpResp_UD                 |
|                       | SC   | SC   | 0        | SnpResp_SC                 |
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
| SnpQuery              | I    | I    | 0        | SnpResp_I                  |
|                       | UC   | UC   | 0        | SnpResp_UC                 |
|                       | UD   | UD   | 0        | SnpResp_UD                 |
|                       | SC   | SC   | 0        | SnpResp_SC                 |

### 任务的提前结束

在 MainPipe 上的任务在符合以下条件之一时，可以在 ```s3``` 阶段提前结束，不进入后续的流水级：

1. 任务不需要将 DataStorage 中的数据搬移到 ReleaseBuffer 并符合以下条件之一：
    - 任务向上下游通道（上游 TileLink D、下游 TXREQ、下游 TXRSP、下游 TXDAT）的请求在 ```s3``` 顺利离开
      MainPipe
    - 任务需要分配 MSHR
2. 任务向上游 TileLink D 通道的请求（AccessAckData、HintAck、GrantData、Grant）被重试

## S4 流水级

在 MainPipe 上的任务若没有在 ```s3``` 阶段被提前结束，则进入 ```s4``` 阶段。任务符合以下所有条件时，可以在 ```s4```
阶段提前结束，不进入后续的流水级：

- 任务不需要将 DataStorage 中的数据搬移到 ReleaseBuffer
- 任务向上下游通道（上游 TileLink D、下游 TXREQ、下游 TXRSP、下游 TXDAT）的请求在 ```s4``` 顺利离开 MainPipe

若任务没有在 ```s4``` 被结束，则继续进入 ```s5``` 阶段。


## S5 流水级

在 MainPipe 上的任务若没有在 ```s4``` 阶段被提前结束，则进入 ```s5``` 阶段。

若 ```s3``` 阶段发起了对 DataStorage 的读取请求，则在 ```s5``` 可以得到相应缓存行的数据。

MainPipe 在 ```s5``` 会根据任务的要求，以及请求的嵌套情况，将来自 DataStorage 或 MainPipe 上的数据写入
ReleaseBuffer。

