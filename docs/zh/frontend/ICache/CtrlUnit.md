# CtrlUnit 子模块文档

目前 CtrlUnit 主要负责 ECC 校验使能/错误注入等功能

## mmio-mapped CSR

CtrlUnit 内实现了一组 mmio-mapped CSR，连接在 tilelink 总线上，地址可由参数 `cacheCtrlAddressOpt` 配置，默认地址为`0x38022080`。总大小为 128B。

当参数 `cacheCtrlAddressOpt` 为 `None` 时，CtrlUnit **不会实例化**。此时 ECC 校验使能**默认开启**，软件不可控制关闭；软件不可控制错误注入。

目前实现的 CSR 如下：

```plain
              64     10        7         4         2        1        0
0x00 eccctrl   | WARL | ierror | istatus | itarget | inject | enable |

              64 PAddrBits-1               0
0x08 ecciaddr  | WARL |       paddr        |
```

| CSR | field | desp |
| --- | --- | --- |
| eccctrl | enable | ECC 错误校验使能，原 `sfetchctl(0)` |
| eccctrl | inject | ECC 错误注入使能，写 1 开始注入，读恒 0 |
| eccctrl | itarget | ECC 错误注入目标，见后表 |
| eccctrl | istatus | ECC 错误注入状态（read-only），见后表 |
| eccctrl | ierror | ECC 错误原因（read-only），仅在`eccctrl.istatus===error`时有效，见后表 |
| ecciaddr | paddr | ECC 错误注入物理地址 |

`eccctrl.itarget`:

| value | target |
| --- | --- |
| 0 | metaArray |
| 2 | dataArray |
| 1/3 | rsvd |

`eccctrl.istatus`:

| value | status |
| --- | --- |
| 0 | idle |
| 1 | working |
| 2 | injected |
| 7 | error |
| 3-6 | rsvd |

`eccctrl.ierror`:

| value | error |
| --- | --- |
| 0 | ECC 未使能 (i.e. `!eccctrl.enable`) |
| 1 | inject 目标 SRAM 无效 (i.e. `eccctrl.itarget==rsvd`) |
| 2 | inject 目标地址 (i.e. `ecciaddr.paddr`) 不在 ICache 中 |
| 3-7 | rsvd |

## 错误校验使能

CtrlUnit 的 `eccctrl.enable` 位直接连接到 MainPipe，控制 ECC 校验使能。当该位为 0 时，ICache 不会进行 ECC 校验。但仍会在重填时计算校验码并存储，这可能会有少量的额外功耗；如果不计算，则在未使能转换成使能时需要冲刷 ICache（否则读出的 parity code 可能是错的）。

## 错误注入使能

CtrlUnit 内部使用一个状态机控制错误注入过程，其 status （注意：与 `eccctrl.istatus` 不同）有：

- idle：注入控制器闲置
- readMetaReq：发送读取 metaArray 请求
- readMetaResp：接收读取 metaArray 响应
- writeMeta：写入 metaArray
- writeData：写入 dataArray

当软件向 `eccctrl.inject` 写入 1 时，进行以下简单检查，检查通过时状态机进入 `readMetaReq` 状态：

- 若 `eccctrl.enable` 为 0，报错 `eccctrl.ierror=0`
- 若 `eccctrl.itarget` 为 rsvd(1/3)，报错 `eccctrl.ierror=1`

在 `readMetaReq` 状态下，CtrlUnit 向 MetaArray 发送 `ecciaddr.paddr` 地址对应的 set 读取的请求，等待握手。握手后转移到 `readMetaResp` 状态。

在 `readMetaResp` 状态下，CtrlUnit 接收到 MetaArray 的响应，检查 `ecciaddr.paddr` 地址对应的 ptag 是否命中，若未命中则报错 `eccctrl.ierror=2`。否则，根据 `eccctrl.itarget` 进入 `writeMeta` 或 `writeData` 状态。

在 `writeMeta` 或 `writeData` 状态下，CtrlUnit 向 MetaArray/DataArray 写入任意数据，同时拉高 `poison` 位，写入完成后状态机进入 `idle` 状态。

ICache 顶层中实现了一个 Mux，当 CtrlUnit 的状态机不为 `idle` 时，将 MetaArray/DataArray 的读写口连接到 CtrlUnit，而非 MainPipe/IPrefetchPipe/MissUnit。当状态机 `idle` 时反之。
