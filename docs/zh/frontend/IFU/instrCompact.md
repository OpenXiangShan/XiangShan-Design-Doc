# IFU 子模块 instrCompact

## 功能描述

### 功能描述


### 紧密排列信号描述
根据InstrBoundary计算出来的InstrValid序列信息，我们可以将稀疏分布的有效指令信息进行紧密排列。在此之前，让我们首先解释一下需要紧密排列的信号分别是：instrIndex，selectBlock，isRVC，pcLowerResult，instrEndOffset。

instrIndex是指令索引，用于从ICache返回的数据中截取对应的指令。你可以这么理解，如果instrIndex的3号位有效，则instrIndex(3)作为地址从ICacheData读出的指令数据，就是预测块按照两字节划分时，序号位为3的有效指令数据。未进行紧密排列时rawInstrIndex(i) = (startAddr + 2*i)(5,1)，startAddr是预测块的首地址。

selectBlock是选择信号，用于指示当前指令数据来自于1号预测块还是2号预测块。如果selectBlock(i)为1，我们就根据instrIndex(i)值从1号预测块对应的ICacheData中取出指令数据。相应的rawSelectBlock(i) = i > 0号预测块的Size。稍微解释一下，以两字节为单位。如果序号i< 0号预测块的Szie，则说明rawInstr(i)的指令数据来自0号预测块。因为原始指令的数据的拼接关系是1号预测块的指令数据拼接在0号预测块的后面。

instrEndOffset，用于指示当前指令末尾地址相对于预测块的偏移值。如果是RVC指令或者说当前指令开头位置相对于预测块的首地址偏移值，就很好理解，因为第i条指令的相对于预测块的偏移值为i。所以instrEndOffset(i) = i + !isRVC。

我们需要强调一点的是rawInstr与instr。前者我们认为预测块每两字节划分的位置是一条指令，后者我们指代的是真实指令。本节的作用就是从rawInstr中刷选出对应的有效instr，就是从rawInstrIndex，rawInstrEndOffset，刷选出对应的有效instrIndex以及instrEndOffset。请注意指令信息与指令数据是一一绑定。

### 原理说明
我们根据instrValid序列计算出对应的instrCount序列，其中instrCount(i)代表instrValid(0)~instrValid(i-1)的sum。当instrValid(i)有效时，其对应的sum(i)，就是紧密排列后对应指令有效信息要写入的位置。不存在instrValid(i)与instrValid(j)有效时，sum(i) == sum(j)。所以有如下代码，我可以将每个位置序号，与sum序列对比，找到命中的项进行写入。更进一步的，我们考虑到有效指令的稀疏排布也是有规律的，比如有效指令之间不存在连续的不有效指令.....。根据这一点确定instrIndex(4)，我们只需要考虑rawInstrIndex(4)~rawInstrIndex(9)，因为最好情况rawInstrIndex每一条都是有效指令，则instrIndex(4) = rawInstrIndex(4)，最差情况rawInstrIndex全是I指令instrIndex(4) = rawInstrIndex(8)，嗯，好像混入了啥。（思路就是这样）

```plain
for(idx <- 0 until PredictWidth){  
  val instrRange = 0 until PredictWidth  
  val validOH = instrRange.map {i => rawInstrValid(i) && instrCount(i) === idx.U}  
  val instrIndex(idx) = Mux1H(validOH, rawInstrIndex)  
  val instrIsRVC(idx) = Mux1H(validOH, rawIsRVC)  
  ....  
}

```