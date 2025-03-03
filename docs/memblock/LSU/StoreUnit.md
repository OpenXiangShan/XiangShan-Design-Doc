\newpage
# Store 地址执行单元 StoreUnit

## 功能描述

Store指令地址流水线分为S0/S1/S2/S3/S4五级, 如图\ref{fig:LSU-StoreUnit-Pipeline}所示。接收store地址发射队列发来的请求，处理完成之后需要给后端和向量部分响应，处理过程中需要给发射队列反馈信息，给StoreQueue反馈信息，最后写回, 如果中间出现异常则从发射队列重新发射。

### 特性 1：StoreUnit支持标量Store指令

* stage 0:

    * 计算VA地址(向量store指令的vaddr是在vssplit中计算的)

    * 地址非对齐检查更新到uop.cf.exceptionVec(storeAddrMisaligned)

    * 发出DTLB读请求到tlb（如果是来自发射队列的标量store或者向量store指令，需要检查完整的虚拟地址）

    * 更新指令的mask信息到s0_mask_out发送到StoreQueue

    * 判断是否为数据宽度为128bits的store指令。

* stage 1:

    * 将DTLB查询结果更新到storeQueue

    * 向LoadQueue发出store-load违例检查请求

    * 如果DTLB hit，将store issue信息发送到后端

* stage 2:

    * mmio/PMP检查并更新storeQueue

    * 更新DTLB结果通过feedback_slow更新到后端

* stage 3

    * 为了和RAW违例检查同步发送给后端，需要增加一拍

* stage 4

    * 标量store发起Writeback，通过stout发送给后端

### 特性 3: StoreUnit支持向量Store指令

StoreUnit处理非对齐Store指令流程和标量类似，特别的:

* stage 0:

    * 接受vsSplit的执行请求，优先级高于标量请求,并且不需要计算虚拟地址

* stage 1:

    * 计算vecVaddrOffset和vecTriggerMask

* stage 2:

    * 不需要向后端发送feedback_slow响应

* stage 4:

    * 向量store发起Writeback，通过vecstout发送给后端

### 特性 2: StoreUnit支持非对齐Store指令

StoreUnit处理非对齐Store指令流程和标量类似，特别的:

* stage 0:

    * 接受来自StoreMisalignBuffer的勤求，优先级高于向量和标量请求,并且不需要计算虚拟地址

* stage 2:

    * 不需要向后端发送feedback响应,

    * 如果不是来自于StoreMisalignBuffer的请求并且没有跨越16字节边界的非对齐请求，那么需要进入StoreMisalignBuffer处理

        * 通过io_misalign_buf接口，向StoreMisalignBuffer发送入队请求

        * 不进入stage 3

    * 如果是来自与StoreMisalignBuffer的请求并且没有跨越16字节边界请求，则需要向StoreMisliagnBuffer发送重发或者写回响应

        * 通过io_misalign_sout接口，向StoreMisalignBuffer发送响应

        * 如果出现TLB miss，则需要重发，否则写回

        * 不进入stage 3


\newpage

## 整体框图

![StoreUnit整体框图](./figure/LSU-StoreUnit.svg){#fig:LSU-StoreUnit}

\newpage

## 接口时序

### 接口时序实例

如图\ref{fig:LSU-StoreUnit-Timing}所示, store指令进入StoreUnit后，在stage 0 请求TLB，stage 1得到TLB返回的paddr。在stage 0将mask写入StoreQueue，stage 1向 RAW发送请求，并通过io_lsq将store指令的其他信息更新到LoadStoreQueue。在stage 2得到feedback相关信息，stage 4 通过stout写回。

![StoreUnit接口时序](./figure/LSU-StoreUnit-Timing.svg){#fig:LSU-StoreUnit-Timing}
