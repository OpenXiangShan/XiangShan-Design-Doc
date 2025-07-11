# CtrlBlock

- 版本：V2R2
- 状态：OK
- 日期：2025/01/15
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## 术语说明

Table: 术语说明

| 缩写    | 全称                         | 描述     |
| ----- | -------------------------- | ------ |
| -     | Decode Unit                | 译码单元   |
| -     | Fusion Decoder             | 指令融合   |
| ROB   | Reorder Buffer             | 重排序缓存  |
| RAT   | Register Alias Table       | 重命名映射表 |
| -     | Rename                     | 重命名    |
| LSQ   | Load Store Queue           | 访存指令队列 |
| -     | Dispatch                   | 派遣     |
| IntDq | Int Dispatch Queue         | 定点派遣队列 |
| fpDq  | Float Point Dispatch Queue | 浮点派遣队列 |
| lsDq  | Load Store Dispatch Queue  | 访存派遣队列 |
| -     | Redirect                   | 指令重定向  |
| pcMem | PC MEM                     | 指令地址缓存 |

## 子模块列表

Table: 子模块列表

| 子模块           | 描述          |
| ------------- | ----------- |
| dispatch      | 指令派遣模块      |
| decode        | 指令译码模块      |
| fusionDecoder | 指令融合模块      |
| rat           | 重命名表        |
| rename        | 重命名模块       |
| redirectGen   | 重定向生成模块     |
| pcMem         | 指令地址缓存      |
| rob           | 重排序缓冲       |
| trace         | 指令 trace 模块 |
| snpt          | 快照模块        |

## 设计规格

译码宽度：6

重命名宽度：6

分派宽度：6

rob 提交宽度：8

rab 提交宽度：6

rob 大小：160

快照大小：4 项

整型物理寄存器数：224

浮点物理寄存器数：192

向量物理寄存器数：128

向量 v0 物理寄存器数：22

向量 vl 物理寄存器数：32

支持重命名快照

支持 trace 扩展

## 功能

CtrlBlock
模块包含指令译码（Decode）、指令融合（FusionDecoder）、寄存器重命名（Rename，RenameTable）、指令分派（Dispatch）、提交部件（ROB）、重定向处理（RedirectGenerator）和快照重命名恢复（SnapshotGenerator）。

译码功能部件在每个时钟周期会从指令队列头部取出 6
条指令进行译码。译码过程是将指令码翻译为方便功能部件处理的内部码，标识出指令类型、所需要操作的寄存器号以及指令码中可能包含的立即数，用于接下来的寄存器重命名阶段。对于复杂指令，选出后通过复杂译码器
DecodeCompunit 一次一条进行指令拆分，对于 vset 指令存储到 Vtype 中指导指令拆分。最后以复杂指令在前，简单指令在后每周期选出 6 个
uop 传递到重命名阶段。译码阶段还包括发出读 RenameTable 请求。

指令融合会对指令译码得到的 6 个 uop 凑成（uop0, uop1）, (uop1, uop2), (uop2, uop3), (uop3, uop4）,
(uop4, uop5) 的至多 5
对待融合指令对。然后判断每一对指令是否能够进行指令融合。当前我们支持两种类型的指令融合，分别是融合成为一个带有新的控制信号的指令，以及将第一条指令的操作编码替换为另一个的形式。在判断可以进行指令融合后，我们会对
uop 的操作数，如逻辑寄存器号重新赋值，选择新的操作数。另外，HINT 类指令不支持被指令融合，例如 fence 指令不能够被融合。

重命名阶段负责管理和维护寄存器与物理寄存器之间的映射，通过对逻辑寄存器的重命名，实现指令间依赖的消除，完成指令的乱序调度。重命名模块主要包含
Rename、RenameTable 两个模块，分别负责 Rename 流水级的控制、(体系结构/推测)重命名表的维护，Rename 中包括 FreeList
以及 CompressUnit 两个模块，负责空闲寄存器的维护以及 Rob 压缩。

派遣阶段将重命名后的指令根据指令类型分发到 4 个调度器中，分别对应于整型，浮点，向量和访存。每个调度器中根据不同的运算操作类型又分为若干的发射队列（issue
queue），每个发射队列的入口大小为 2。

指令流在 CtrlBlock 的传递过程为：CtrlBlock 读取 Frontend 传入的 6 条指令对应 ctrlflow，经过 decode
增加译码逻辑寄存器、运算操作符等信息，复杂指令经过 DecodeComp 添加指令拆分信息，每周期选出六条 uop 输出，并发出读 RAT
请求。对于可以进行指令融合的 uop，在进入 rename 时进行融合以及清除。之后经过 rename 增加物理寄存器信息以及 rob 压缩信息后传入
dispatch，最后通过 dispatch 进到 rob / rab / vtype 申请 entry，根据指令类型输出到 issue
queue。这些模块中只有 issue queue 顺序进，乱序出，其他模块都是顺序进，顺序出。

![CtrlBlock 总览](./figure/CtrlBlock-Overview.svg)

# 译码

标量指令的译码过程同南湖。

对于向量指令，先使用和标量指令相同结构的译码表进行译码，译码的同时拿到指令拆分类型，接下来会根据指令拆分类型进行拆分，拆分的过程相当于重新修改源寄存器号、源寄存器类型、目标寄存器号、目标寄存器类型、更新
uop 数量，用于控制 rob 写回时一条指令需要写回的数量。直到拆分出的所有 uop 完成 rename 过程后，译码 ready 信号才能够置为 1。

由于除了 i2f 的标量浮点指令现在使用向量浮点模块运行，因此 fpdecoder 中的译码信号只使用其中用到的 4
种（typeTagOut、wflags、typ、rm），用法与南湖相同。使用向量浮点模块运行的浮点指令，需要在向量译码单元中获得使用的 futype 以及
fuoptype，并使用 1bit isFpToVecInst 信号区分，该浮点指令是浮点指令还是向量浮点指令，从而在共用向量运算单元时能进行区分。

## 译码阶段输入

译码阶段除了接受来自前端的指令流，还需要接受来自 rob 的 Vtype 相关：walk，commit，vsetvl 信息，指导向量复杂指令译码。

## 译码输出

与 fusionDecode：输出指令流以及控制指令融合是否开启。

与 rename：流水输出 6 个 uop；如果出现 redirect 阻塞直到 Ctrlblock 中 redirect 发往前端后，前端发出正确指令流。

与 RAT：译码发出读推测重命名请求。

# FusionDecoder

指令融合模块负责找出译码模块译码后的 uop 是否存在一定的联系，从而可以将多个 uop （当前仅支持两条指令的融合）需要做的事情融合为一条 uop
能够完成的事情。

指令融合会对指令译码得到的 6 个 uop 凑成（uop0, uop1）, (uop1, uop2), (uop2, uop3), (uop3, uop4）,
(uop4, uop5) 形式的至多 5
对待融合指令对。然后判断每一对指令是否能够进行指令融合。当前我们支持两种类型的指令融合，分别是融合成为一个带有新的控制信号的指令，以及将第一条指令的操作编码替换为另一个的形式。在判断可以进行指令融合后，我们会对
uop 的操作数，如逻辑寄存器号重新赋值，选择新的操作数。另外，HINT 类指令不支持被指令融合，例如 fence 指令不能够被融合。

例如，slli r1, r0, 32 和 srli r1, r1, 32 将 r0 中的数左移 32 位后存入 r1，然后再次右移 32 位。其等价于
add.uw r1, r0, zero （伪指令 zext.w r1, r0），即将 r0 中的数扩展后移动到 r1 中。

输入为译码后的至多 6 条 uop 以及他们的原始指令编码，以及相应的 valid 信号，这里输入 inready 只有 5
位（即译码宽度减一），因为我们需要将 uop 错位两两配对为至多 5 对待融合指令。inReady[i] 表示已经准备好可以接受 in(i+1)。

输出宽度为译码宽度减一，包括指令融合替换，需要替换
fuType，fuOpType，lsrc2（第二个操作数的逻辑寄存器号，如有），src2Type（第二个操作数的类型），selImm（立即数类型）。以及指令融合信息，如
rs2 来自于 rs1/rs2/zero。同时还需要输出一组译码宽度的布尔向量 clear，表征该 uop
是否被指令融合需要被清除掉，当前设想每条指令融合后会将第二条指令清除掉。第 0 个 uop 的 clear 是不会为 true
的，因为我们默认将后面的指令融合到前面的指令上，因此无论是否融合，uop 0 始终不会因为指令融合而消失。

输出有效要求：指令对有效（从译码模块传来的 uop 对有效），不能被指令融合清除掉，有可行的指令融合结果，以及不能是 Hint 类指令。同时将
fuType，src2Type，rs2FromZero ……等信息赋值

![fusion decoder 总览](./figure/Fusion-Decoder-Overview.svg)

# Redirect

在 ctrlblock 中主要负责 redirect 的生成以及发往各个模块。

## RedirectGenerator

RedirectGenerator 模块管理不同来源的重定向信号（如执行单元和 load
），并决定是否发生重定向，如何刷新相关信息。它通过多级寄存器和同步机制确保数据流的正确性，且通过地址转换和错误检测保证指令执行的正确性。

将当前最老的执行 redirect 的 fullTarget 和 cfiUpdate.target 拼接得到 fullTarget 字段。另外如果当前最老的执行
redirect 不是来自于 CSR，则还需要基于指令地址的翻译类型检查 IAF，IPF 和 IGPF 等地址的合法性。

然后从最老的执行 redirect 和 load redirect 中选出一个最老的 redirect，同时还需要保证这个最老的 redirect 不会被
robFlush 或者之前的 redirect 刷掉。

![redirect 总览](./figure/Redirect-Overview.svg)

## redirect 的生成

Ctrlblock 中生成的 Redirect 主要包括两个来源：

* 通过 redirectgen 汇总的处理器执行时发生的错误(包含分支预测和访存违例)（后面称这部分重定向为exuredirect）；
* 以及来自 rob exceptiongen 生成的 robflush :
  中断(csr)/异常/刷流水（csr+fence+load+store+varith+vload+vstore）+前端异常。Rob中发来的异常/中断/刷流水重定向处理类似。

对于 redirectgen 汇总的重定向：

* 功能单元写回的 redirect(jump, brh) 在打一拍且没有被更老的已经处理过 redirect 取消的情况下输入到 redirectgen
  模块。
* Memblock 写回的 violation（访存违例）在打一拍且没有被更老的已经处理过的 redirect 取消的情况下输入到 redirectgen。

Redirectgen 选择最老的 redirect 在输入后等待一拍，加上从 pcMem 读回的数据后再输出。

对于 robflush 信号，在接收到后，同样需要等待一拍加上从 pcMem 读回的数据。

Ctrlblock 生成 Redirect 时会优先重定向 robflush 信号，当不存在 robflush 时才会处理 exuredirect。

上述部分整体框图如下：

![redirect 的生成](./figure/Redirect-Gen.svg)

## redirect 分发

Ctrlblock 在生成出 Redirect 信号后，向流水级各个模块分发重定向信号。

* 对于 decode发送当前 redirect 或 redirectpending（即 decode 等待直到 Ctrlblock 发给前端的
  redirect 准备完成，使得前端有正确指令流到达之后才可继续流水）；
* 对于 rename，rat，rob，dispatch，snpt，mem 发送当前 redirect；
* 对于issueblock，datapath，exublock 发送打一拍后的 redirect。

其中比较特殊的是发送给前端的 redirect。发送给前端的重定向以及造成的影响，总共包括三部分：rob_commit,
redirect，ftqIdx(readAhead，seloh)。

![发向前端的 redirect](./figure/Redirect-ToFrontend.svg)

### 对于 rob commit

由于向前端传递的 flush 信号可能会延迟几个周期，并且如果在 flush 前继续提交，可能会导致提交后 flush 的错误。因此，我们将所有的 flush
视为异常，确保前端的处理行为一致，当 ROB 提交一条带 flush 信号的指令时，我们需要在 ctrlblock 直接刷掉带有 robflush 的
commit，告知前端进行 flush，但是不进行提交。

而对于 exuredirect，其对应的指令需要在写回 rob 等待 walk 完毕后才可以提交，因此这两类 redirect
不需要再特殊处理，其提交一定在其写回之后。

### 对于 redirect：

发送给前端的 redirect 信号还包括额外的 CFIupdate，而 ftq 信息通过额外的 readAhead 以及 seloh 更新。

对于 exuredirect，它们的 CFIupdate 和 ftqidx 等信息在从功能单元传递回来的时候已经包含在里面了，因此无需进行特殊处理。

对于 rob 发出的 flush，exception 对 CFI 更新的目的地址需要等待从 CSR 中得到：首先 rob 发出 flush 信号，产生
exception，向 CSR 发送 redirect 表示有 exception 产生，并从 CSR 得到 Trap Target 返回给
ctrlblock，最后再向前端发出 redirect。

其余的冲刷流水导致的目的地址更新，base pc 通过之前与 pcmem 交互得到，并在 ctrlblock 中根据是否刷自身加上偏移来生成目的地址。

其中比较特殊的是 CSR 发出的冲刷流水中 XRet，这种情况下目的地址更新也需要从 CSR 中得到，不过 CSR 生成 Xret 的通路不需要再依赖 rob
发回的 exception，可以直接与 Ctrlblock 通过 csrio 交互。

### 对于ftqIdx：

Ctrlblock 主要发送两组数据 ftqIdxAhead 以及 ftqIdxSelOH。

其中 ftqIdxAhead 用于前端提前一拍读取到重定向相关的 ftqidx。ftqIdxAhead 是一个大小为 3 的 FtqPtr
向量，其中第一个是执行的 redirect（jmp/brh），第二个是 load 的redirect，第三个是 robflush。

ftqIdxSelOH 用于选择有效的 ftqidx：前两个通过 redirectgen 输出的独热码选择，第三个通过发送到前端的 redirect
是否有效选择。

## 保证 redirect 发出的顺序

为了保证执行正确，较新的 redirect 不能先于较老的 redirect 分发。以下分四类情况说明：

（1）新的 exuredirect 在旧的 robflush 之后发出：

exuredirect 在写回时，会往前看是否已经有更老的 redirect。

在 robflush 到来时，对于较晚生成的 exuredirect，会直接在 exublock 中被刷掉；对于较早生成，还未来得及被 robflush 刷掉的
exuredirect，会检查是否有较老的 redirect，如果有则也会被刷掉。

（2）新的 exuredirect 在旧的 exuredirect 之后：

exuredirect 在写回时，会往前看是否已经有更老的 redirect。

在发生 redirect 时，对于较晚生成的 exuredirect，同样也会直接在 exublock 中被刷掉；对于较早生成，还未来得及被当前
redirect 刷掉的 exuredirect，会检查是否有较老的 redirect，如果有则也会被取消。

（3）新的 robflush 在旧的 redirect 之后

这种情况，rob 保证了不会出现，robflush 输出结果是当前 robdeq 的指令带有异常/中断标志，而 robdeq 即当前最老的
robidx，一定比现有的 redirect 更老。

（4）新的 robflush 在旧的 robflush 之后

这一部分主要在 rob 中保证，exceptionGen 获得最老 robflush，同时 robflush 发出时检查上一条 flushout，较新的
robflush 会被取消。

# 快照恢复

对于重命名恢复，目前昆明湖采用了快照恢复阶段：在重定向时不一定恢复到 arch
状态，而是可能会恢复到某一个快照状态。快照即根据一定规则，在重命名阶段保存的spec state，包括ROB enqptr；Vtypebuffer
enqptr；RAT spec table；freelist Headptr（出队指针）以及ctrlblock用于总体控制
robidx。目前上述模块均各自维护四份快照。

## SnapshotGenerator

SnapshotGenerator 模块主要用于生成快照，存储维护。其本质是一个循环队列，维护最多四份快照。

入队：在循环队列不满，且入队信号未被 redirect 取消的情况下，下一拍在 enqptr 入队，更新 enqptr。

出队：在出队信号未被 redirect 取消的情况下，下一拍在 deqptr 出队，更新 deqptr。

Flush：根据刷新向量在下一拍刷新掉对应的快照。

更新 enqptr：如果有空的快照，选择离deqptr最近的作为新的 enq 指针

Snapshots: snapshots 队列寄存器直出

![snapshots 总览](./figure/Snapshot-Overview.svg)

## 快照的创建

对于快照创建时机，目前在rename中进行管理。由于注意到对性能造成主要影响的重定向来源仍然是分支错误造成的重定向，因此选择在分支跳转指令处创建快照；同时为了在没有分支跳转的情况下其他的重定向也能用到快照恢复，因此固定每隔commitwidth\*4=32条uop打一份快照。

Rename模块会对输出的六条uop都打上snapshot标志，表示uop是否需要打上快照，在Ctrlblock中会把六条uop上的snapshot标志汇总到第一条uop。该操作为了解决快照机制在blockBackward下的正确性：即如果在六条uop中出现blockbackward，且在blockbackward之后需要打上snapshot，该snapshot会由于blockbackward而无法在rob中打上快照，将所有snapshot放到第一条就可以解决这个问题。

Rat，freelist，以及ctrlblock的快照创建均通过rename模块输出的snapshot标志控制。存储数据由各个模块自己管理。

Rob，vtype的快照创建除了rename输出流到rob的snapshot标志还需要考虑非blockbackward以及rab，rob，vtypebuffer没有满。rob，vtype的快照创建和前述模块的快照写入可能并不在一个周期，但通过snapshot标志随着rename输出流到rob我们可以保证写入的robidx相同即可同步。

## 快照的删除

快照删除主要包括两种情况，一种在commit的时候删除掉过期的快照；另一种是redirect的时候删除掉错误路径上的快照。

对于commit的时候删除快照：Ctrlblock通过控制deq信号删除快照：robcommit的八条uop有一条与当前deqptr指向的快照中第一条uop一致则删除过期快照。Ctrlblock将deq信号传递到上述各个模块中同步删除commit过期快照。

对于redirect的时候：Ctrlblock通过提供flushvec信号删除错误路径上的快照：判断快照的第一条uop是否比当前redirect要新（这里要注意套圈的情况），如果老则把这条快照刷掉，即flushvec相应位置1。Ctrlblock将flushvec传递到上述模块同步刷新错误路径上的快照。

## 快照的管理

Ctrlblock通过自身维护一个存储robidx的快照副本，在重定向到来时可以方便的向各个模块告知是否命中快照以及命中快照的编号。Ctrlblock遍历快照，在存在比当前redirect更老（或者不刷自己的情况下相等），允许使用快照恢复，并记录命中快照的编号，传递到上述模块中。

通过快照恢复spec state由各个模块自身控制。

上述部分整体框图：

![snapshot 的生成、删除和管理](./figure/Snapshot-Gen.svg)

# pcMem

pcMem 实质上是例化了一个 SyncDataModuleTemplate，并需要提供多个读口，1 个写口。大小为 64 项，每一项仅包括
startAddr。

pcMem 读出来的是 base PC，还需要再加上 Ftq Offset 得到完整的 PC。

当前配置下，需要提供 14 个读口，为 redirect，robFlush 各自提供 1 个读口，为 bjuPC 和 bjuTarget 各自提供 3
个读口，为 load 提供 3 个读口，以及为 trace 提供 3 个读口。

输入包括来自前端 Ftq 的写入使能，写入地址和写入数据，以及不同来源的读请求和读地址，分别输出读结果。

![PCMem 总览](./figure/PCMem-Overview.svg)

# GPAMem

GPAMem 模块类似于 pcMem，例化了一个 SyncDataModuleTemplate，但是只需要提供 1 个读口和 1 个写口，大小为 64
项。每一项主要包括一个 gpaddr，存储前端的 ftq 对应的 gpaddr 信息。

Rob 在 exception 输出的前一拍发出 gpaddr 读请求以读地址的 ftq 信息，第二拍得到返回的 gpaddr 信息。最终通过 robio 与
csr直接交互。

输入包括来自前端 IFU 的写入使能，写入地址和写入数据，以及来自 rob 的读请求和读地址，向 rob 输出读结果。

![GPAMem 总览](./figure/GPAMem-Overview.svg)

# Trace

ctrlBlock的trace子模块用来收集指令trace的信息，其接收来自rob指令提交时的信息，在rob压缩的基础上进行二次压缩（将不需要pc的指令和需要pc的指令压缩到一起存入trace
buffer），以减小对pcMem的读压力。

![trace 示意图](./figure/trace.svg)

## feature支持

当前KMH核内trace的实现只支持指令trace。核内收集的指令trace信息包括：priv，cause，tval，itype，iretire，ilastsize，iaddr；其中itype字段支持所有类型。

## trace 各级流水线功能：

在ctrlBlock里有三拍：

* Stage 0: 将 rob commitInfo 打一拍；
* Stage 1: commitInfo压缩，阻塞提交信号产生；
* Stage 2: 根据压缩后的ftqptr从pcmem中读出basePc，从csr获取当前提交的指令对应的priv，xcause，xtval；

memBlock

* Stage 3: 通过ftqOffest和从pcmem读到的basePc算出最终的iaddr；

## trace buffer 压缩机制

当每一组commitInfo进入trace buffer之前, 都需要做压缩，即把每一个需要pc的commitinfo项和其前面的项压缩成一项，送入trace
buffer，在进trace buffer之前，会计算当前拍进入trace buffer之后，在下一拍能不能全部出队，如果不能则去block
rob的提交，该block会一直block到产生该block信号的commitInfo从trace
buffer完全出队。产生blockCommit信号的commitInfo会无脑进trace buffer，但是其下一拍的commitinfo一定会被堵住。
