# A 通道请求缓冲 RequestBuffer

## 功能描述
Request Buffer用来缓冲那些暂时需要阻塞的 A 通道请求，同时让满足释放条件/不需要阻塞的 A 通道请求先进入主流水线。Request Buffer 可以防止需要阻塞的 A 请求堵住流水线入口，从而避免对后续请求的影响，提高了缓存的处理效率。
另外，如果有新到达的 Acquire 与 MSHR 中正在处理的预取请求地址相同，则可以进行请求融合，将 Acquire 的信息直接传到对应 MSHR 中，让 MSHR 处理完成后同时回复 L1 Acquire，从而加快了 Acquire 的处理流程，并减少了对 ReqBuf 和 MSHR 的占用。

### 特性1：请求融合
当 RequestBuffer 接收到的 Acquire 请求和某一项 MSHR 中的预取请求有相同地址时，RequestBuffer 会将合并请求（aMergeTask）发送到相应的 MSHR entry，该项 MSHR 会被标注 mergeA

### 特性2：请求接收条件
RequestBuffer 入口的请求在哪些情况下允许被接收：
-RequestBuffer 没有满
-RequestBuffer 满了，但是 Acquire 请求可以和前面的预取请求融合
-RequestBuffer 满了，但是该请求是预取请求，并且已经前面已经有一条 Acquire/Prefetch 请求正在被 MSHR 处理

### 特性3：请求的唤醒与发射
哪些请求会分配 RequestBuffer：只有 RequestBuffer 没有满，且 (1) 不能直接 flow 进入流水线，即和 MainPipe或者某项 MSHR 地址冲突，或者 chosenQ 也准备发射，(2) 不能做请求融合 的请求才会分配 RequestBuffer 项。

### 特性4：RequestBuffer项中会记录
-	Rdy：是否准备好被发射/出队
-	Task：请求本身的信息
-	WaitMP：被 MainPipe 哪几级流水线阻塞
-	WaitMS：被哪几项 MSHR 阻塞

### 特性5：RequestBuffer表项如何更新
-	WaitMP：因为 MainPipe 是非阻塞流水线，所以 waitMP 每周期会右移一位，同时每拍会检查 s1 有无新的地址冲突的请求
-	WaitMS：MSHR 被释放的前一拍会将 waitMS 相应的 bit 复位；同时有新的 MSHR 项被分配时会检查有无地址冲突，如果有需要将 waitMS 相应 bit 置位
-	Rdy：当 waitMP 和 waitMS 全部被清零，且和即将进入流水线的 A 通道、B 通道请求没有 set 冲突时，rdy 会被复位

### 特性6：RequestBuffer中的请求如何发射
rdy 被复位后请求即可被发射到流水线上，但是此时也要检查和即将进入流水线的 A 通道、B 通道请求有无 set 冲突



## 整体框图
![](./figure/RequestBuffer.svg)

