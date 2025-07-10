# 链路层控制器 LinkMonitor

## 功能描述
LinkMonitor 模块将基于 Valid-Ready 握手的消息转化为基于 L-Credit 的握手，同时会维护 TX、RX 两条方向的 Link 的功耗状态。具体内容详见 CHI Spec Link Handshake 一章。

### 特性1：Decoupled 握手转 L-Credit 握手
从三个 TX 通道接出的 Decoupled 握手经过 Decoupled2LCredit 模块转化为 LCredit 握手。Decoupled2LCredit 模块会记录下游 ICN 收到的 LCredit 数量（lcreditPool），当 lcreditPool 大于 0 时，才能接收上游的 Decoupled 请求；Decoupled 请求握手成功时，lcreditPool 数量减一。

TX 链路状态的影响：
如果 TX 链路状态为 STOP 或者 ACTIVATE 时，应该停止接收 Decoupled 消息。
如果 TX 链路状态为 STOP 时，应当停止接收 LCredit，即便下游 lcrdv 信号拉高 lcreditPool 也应该保持不变。

### 特性2：L-Credit 握手转 Decoupled 握手
从三个 RX 通道收到的 LCredit 握手经过 LCredit2Decoupled 模块转化为 Decoupled 握手。
LCredit2Decoupled 模块会维护一个默认 4 项（lcreditNum 可配，要求 lcreditNum ≤ 15）的队列用于暂存消息，即一个 RX 通道最多向下游发送 lcreditNum 个 outstanding 的 LCredit；同时会维护一个初始值为 lcreditNum 的计数器（lcreditPool），用于记录当前通道最多可以发送多少 LCredit。当 lcreditPool > 队列有效项项数（queueCnt）时，说明该通道已经发出的 outstanding LCredit 数量小于该通道队列所能接收的消息数量，此时该通道可以向下发送 LCredit；当 lcreditPool < lcreditNum 时，该通道应该无条件接收下游的有效请求，即 flitv 拉高且上一拍 flitpending 拉高的请求。

RX 链路状态的影响：
如果 RX 链路状态不是 RUN，则该通道不应该向下游发送 LCredit，即便 lcreditPool > 队列有效项项数。

### 特性3：TXSACTIVE与RXSACTIVE
TXSACTIVE 永远拉高。RXSACTIVE 暂时没有用到。

### 特性4：Interface activation and deactivation
TXLINKACTIVEREQ 在复位后就一直拉高。
RXLINKACTIVEACK 在 RXLINKACTIVEREQ 置 true 后的下一拍置 true；RXLINKACTIVEREQ 置 false的下一拍开始侦听三条 RX 通道的状态，当各个 RX 通道都收回所有 outstanding 的 LCredit 后（即 lcreditPool 等于 lcreditNum），RXLINKACTIVEACK 即可置 false。

## 整体框图
![LinkMonitor](./figure/LinkMonitor.svg)
