# 写数据缓冲 PutBuffer

## 设计规格

- 每个 Slice 配置 4 项，每项保存一条 64 B 缓存行。
- 每条写请求由两个 32 B 的 A 通道 beat 组成。
- 支持 SinkA 写入一个 beat，同时由 RequestArb 发起整行读取。
- 首 beat 锁定缓冲项，最后一个 beat 写入后标记整行有效。
- 在 s2 接收读请求，在 s3 提供寄存后的整行数据，并释放被读取项。

## 功能描述

PutBuffer 用于保存矩阵 PutFullData 请求自带的写数据。请求控制信息通过 RequestBuffer 进入主流水线，写数据保留在 PutBuffer，由任务的 `bufIdx` 关联。这样，TaskBundle 不需要携带整行数据。

### 特性 1：分配与写入

SinkA 接收首 beat 时，PutBuffer 从无效项中按优先级选出一项，写入当前 beat，并将项号保存到 `sel_r`。同一条 Put 的后续 beat 使用 `sel_r`，不重新选择空闲项。即使其间其他项被释放，也不会改变该条请求的数据存放位置。

每次写握手按照 beat 编号更新相应的 32 B 数据。只有最后一个 beat 写入后才置该项的 valid，表示整行已经收集完成。SinkA 同时把所选项号放入 Put 任务的 `bufIdx`，随后由 RequestBuffer 保留该索引，直至任务进入主流水线。

PutBuffer 的所有有效项均被占用时，写 ready 拉低，阻塞新的 Put 首 beat。

### 特性 2：读取与释放

RequestArb 在 s2 识别普通 A 通道 PutFullData 任务，使用 `bufIdx` 发起一次整行读请求。PutBuffer 将该项的两个 beat 拼成 DSBlock 并寄存，下一拍交给 MainPipe，同时清除该项 valid。

释放 PutBuffer 不表示写操作已经完成，而是表示整行数据已经移交主流水线。MainPipe 在 s3 根据目录结果选择后续位置：

- 命中可写状态且没有上层 client：直接写入 DataStorage。
- 缺失、权限不足或存在上层 client：将数据写入新分配 MSHR 对应的 RefillBuffer，等待一致性操作和后续回填任务。

转入 RefillBuffer 后，数据由 MSHR 索引管理，原 PutBuffer 项可以用于其他请求。具体条件见 [请求仲裁器与主流水线](ReqArb_MainPipe.md)。

## 接口列表

Table: PutBuffer 主要接口

| 接口 | 方向 | 内容 |
| --- | --- | --- |
| w | SinkA → PutBuffer | Decoupled 写入，包含 data、beat、first、last |
| state.entryIdx | PutBuffer → SinkA | 首 beat 选中并保存的项号 |
| r | RequestArb → PutBuffer | Valid 读请求，包含缓冲项号 id |
| resp.data | PutBuffer → MainPipe | 寄存后的整行 DSBlock |

读接口不使用 ready。读取时整行数据已被主流水线接收，后续等待由 RefillBuffer 和 MSHR 承担。
