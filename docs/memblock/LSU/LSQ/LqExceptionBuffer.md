\newpage
# Load 异常缓冲 LqExceptionBuffer

## 功能描述

LqExceptionBuffer用于跟踪load指令产生的异常情况，有三种来源：

* 来自LDU s3的标量load指令异常
* 来自vlMergeBuffer的向量load指令异常
* 来自LoadUncacheBuffer的mmio non-data异常 

根据robIdx选择指令中最老的发生异常的指令的虚地址输出。内部有两级流水，第一级流水缓存LDU的s3阶段输出的信息，第二个周期根据robIdx选取最老的发生异常的指令，输出其虚拟地址。

重定向时根据LqExceptionBuffer内缓存的指令robIdx进行是否需要刷掉的判断。

## 整体框图
<!-- 请使用 svg -->
![LqExceptionBuffer整体框图](./figure/LqExceptionBuffer.svg)