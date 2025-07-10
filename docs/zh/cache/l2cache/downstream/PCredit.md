# P-Credit 管理机制

## 功能描述
根据CHI协议2.3.2关于Retry的描述，P-Credit管理遵循以下规则：
1. 当RXRSP通道收到PCrdGrant时，会有一个CAM记录下这笔操作中的PCrdType和SrcID
2. 此时如果有某个Slice中有MSHR正在等待相同类型{PCrdType,SrcID}的PCredit，则把这个PCredit分配给这个Slice
   -如果多个Slice同时命中，则按RoundRobin分配这笔PCredit，同时删除这笔PCredit在CAM中的记录。
   -如果没有Slice命中，CAM则保存PCrdType和SrcID后续使用 (协议允许PCrdGrant先于RetryAck发出)
4. 对于命中的Slice，如果有多个MSHR命中{PCrdType,SrcID}，则按RoundRobin分配到某一个MSHR中。
5. 对于每个MSHR：
   -如果收到RetryAck时会保存PType和SrcID，同时拉高表示正在等待PCredit的pValid信号通知CAM
   -如果在CAM中找到匹配的PCredit，则MSHR完成操作拉低pValid并删除CAM中匹配的项。
   -如果在CAM中没有找到匹配的PCredit，则pValid一直拉高直到收到响应的PCredit。
  
