# RXDAT

## 功能描述
接受来自RXDAT通道的有数据的响应消息，将数据存入RefillBuffer，同时把响应送到MSHRCtl，用消息中txnID用来识别mshrID。 CHI.IssueB需要处理的响应包括：CompData。CHI.IssueC需要处理的响应包括：DataSepResp

### 接口时序
接收请求的当拍通知 MSHR，如果是第一个 beat 则锁存起来，如果是第二个 beat 则和第一个 beat 的数据组合起来并在当拍写入 RefillBuf。

![RXDAT 整体框图] (./figure/RXDAT.svg)
