# RXRSP

## 功能描述
接受来自RXRSP通道的无数据的响应消息，直接把响应送到MSHRCtl，用消息中txnID用来识别mshrID。
CHI.IssueB需要处理的响应包括：Comp, CompDBIDResp, Retry, PCrdGrant.
CHI.IssueC需要响应：RespSepData

## 整体框图
![RXRSP](./figure/RXRSP.svg)
