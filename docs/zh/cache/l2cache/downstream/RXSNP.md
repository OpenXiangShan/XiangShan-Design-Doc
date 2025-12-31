# RXSNP

## 功能描述
RXSNP模块把来自RXSNP总线通道的Snoop请求进行处理，转化为内部任务格式，然后发给RequestArb。同时如果MSHR中有正在进行符合以下条件的，则阻塞RXSNP总线进入SinkB：
- 地址相同，且不能被这笔Snoop请求嵌套
- 准备替换的数据块与这笔Snoop请求地址相同且不能被这笔Snoop嵌套

### 特性1：Snoop(addr=X)何时嵌套正在处理的相同地址MSHR正在进行的一笔读操作(addr=X)？
1. 在MSHR收到第一笔响应数据前，相同地址的Snoop有更高优先级，应该先做。
2. 在MSHR收到第一笔响应数据后，相同地址的Snoop应该等待这笔MSHR做完后再被响应。
3. 在MSHR送出 WriteBackFull/Evict要把回填数据写入DS前，Snoop应该被阻塞，因为Snoop需要的数据仍然在refillBuffer里，而不是DS中。
4. 在MSHR送出 WriteBackFull/Evict已经把回填数据写入DS，Snoop应该优先被响应，因为Snoop有更高优先级。

### 特性2： Snoop(addr=Y）何时嵌套正在进行替换的 MSHR (被替换的行地址 addr=Y）？
1. 当MSHR确定那一路被替换并且这个替换产生的向Core的probe没有完成时，这个Snoop被阻塞，因为这笔Snoop有可能产生相同地址的一笔相同probe到Core。
2. 如果MSHR的所有向Core的probe都完成了，Snoop应该嵌套MSHR。
3. 当MSHR是一笔CMO操作，在产生的所有Probe操作完成前Snoop都被屏蔽。

## 整体框图
![RXSNP](./figure/RXSNP.svg)
