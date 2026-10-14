# 可选矩阵引导预取

矩阵引导预取通过 L2 的 MatrixPrefetchParameters 与 CUTE 的 EnableMatrixPrefetch 配置联合启用。

Table: 矩阵预取配置

| 配置 | 矩阵引导预取 | 其他预取来源 |
| --- | --- | --- |
| DefaultMatrixConfig | 关闭 | 保留基础配置的 BOP / L1 接收器 |
| DefaultMatrixPrefetchConfig | 开启 | 保留基础配置的预取来源 |
| DefaultMatrixOnlyPrefetchConfig | 开启 | 移除其他预取来源 |

CUTE 通过 MatrixPrefetchControl 提供 allocate、activate、retire、cStoreStart 和 cStoreEnd 事件。allocate 携带矩阵描述符，包括任务号、流类型、基址、行跨度、行数、行内范围、分组宽度和转置属性。需求 Get 携带的 matrixPrefetchTag 由 1 bit 有效位、3 bit 流类型和 16 bit 任务号组成，用于把主流水线训练关联到矩阵任务。

## 地址生成与调度

地址生成器按描述符逐组、逐行、逐缓存行遍历实际覆盖的地址范围。起始地址未对齐时，从覆盖首字节的缓存行开始；行跨度不按缓存行对齐时，对每行末尾分别检查，跳过越界候选。

当前预取调度优先利用 C store 窗口生成下一组 A 数据的 lookahead。B-on-A 与 C-on-B 为另外两个可选策略，其独立控制开关初值均为 0。矩阵预取请求以只读 Hint 发往相应 Slice，不把预取数据直接写入 CUTE。

## 队列与需求请求

矩阵来源使用每 bank 独立的无损队列，ready 反压地址生成器；传统推测预取保留 OverwriteQueue 的覆盖行为。两个来源经过仲裁后发送到各个 Slice 的 SinkA，普通需求请求与 Put 最后一个 beat 优先于预取。

矩阵 Get 命中同地址的未完成预取时更新晚到预取统计，`mergeA` 的需求请求类型限定为 AcquireBlock / AcquirePerm。矩阵预取使用 Hint 事务，Get / Put 需求请求按目录状态完成各自的一致性操作。
