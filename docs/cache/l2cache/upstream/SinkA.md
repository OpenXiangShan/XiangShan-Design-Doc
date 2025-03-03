# SinkA

## 功能描述
SinkA把来自【①总线A通道，②预取器】的请求进行处理，转化为内部任务格式，然后发送给RequestBuffer。二者同时来请求时，总线A通道的请求有着更高的优先级。

### 特性1：A通道/预取器阻塞
当RequestBuffer不能接收SinkA的申请时，总线A通道接口/预取器通过valid/ready协议来阻塞后面的申请。

## 整体框图
