# GrantBuffer

## 基本功能
GrantBuf接收来自MainPipe的任务，并根据任务类型进行转发。主要分为：
1.预取响应（opcode = HintAck），会安排其进入预取响应队列 pftRespQueue(size=10)，按FIFO顺序向预取器发出。
2.D通道响应（opcode = Grant/GrantData/ReleaseAck），会安排其进入grantQueue(size=16)，按FIFO顺序向总线D通道发出；
  如果是Grant/GrantAck，则还需要将其信息进入到inflightGrant缓冲区(size=16)（表明Grant已发送但是还没收到GrantAck），等待L1从E通道返回GrantAck后再将信息清除掉。
3.融合请求（task.mergeA = true），同时执行1和2。

### 特性1：阻塞MainPipe入口
GrantBuf 还会根据: 【流水线入口信息 + 流水线是S1/S2/S3/S4/S5级状态 + 内部 pftRespQueue，inflightGrant，grantQueue状态】，来向ReqArb给出【请求入口的阻塞信息】。

3种资源的统计:
  c1: GrantBuf资源不足：已占用的GrantBuf数量 + 流水线S1/S2/S3/S4/S5中是可能GrantBuf的数量(from sinkA or sinkC） > 16
  c2: E通道资源不足：inflightGrant +  流水线S1/S2/S3/S4/S5中可能需要E通道回GrantAck的数量(from sinkA） > 16
  c3: Prefetch的RespQueue资源不足：已占用的pftRespQueue数量 + 流水线S1/S2/S3/S4/S5中可能用到preRespQueue数量(from sinkA） > 10
在S1阻塞A/B/C通道进入MainPipe的条件：
  A：c1或c2或c3
  B: 只要inflightGrant缓冲区有和B通道地址一样的未完成操作
  C: c1

MSHR的3种资源不足(资源最大数-1)：
  c4: GrantBuf的资源不足：已占用的GrantBuf数量 + 流水线S1/S2/S3/S4/S5中是可能GrantBuf的数量(from sinkA or sinkC） > 15
  c5: E通道资源不足：inflightGrant +  流水线S1/S2/S3/S4/S5中可能需要E通道回GrantAck的数量(from sinkA） > 15
  c6: Prefetch的RespQueue资源不足：已占用的pftRespQueue数量 + 流水线S1/S2/S3/S4/S5中可能用到preRespQueue数量(from sinkA） > 9
阻塞MSHR进入Mainpipe的阻塞条件为以上3种任意一种


### 特性2：提前唤醒
MainPipe中的CustomL1Hint模块会在GrantBuf发出前3拍发出l1Hint信号用于L1D$中missq的提前唤醒。GrantBuffer负责给出资源信息在S1阻塞流水线入口， 而MainPipe会根据已经进入流水线中场景精确预测何时发出l1Hint信号。

### 特性3：不同数据宽度处理
对于包含一个beat的Grant/ReleaseAck，从grantQueue出队直接向总线发出。
对于包含两个beat的GrantData，在从grantQueue出队的时候，第一个beat的数据直接向总线发出，同时将第二个beat的数据存入grantBuf；接下来优先发送grantBuf里的数据。grantBuf发送完后，可以出队下一个grantQueue元素。

## 整体框图
![GrantBuffer](./figure/GrantBuf.svg)




