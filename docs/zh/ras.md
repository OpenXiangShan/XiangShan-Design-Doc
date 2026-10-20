# ECC、总线错误与 RNMI {#sec:ras}

本章说明当前实现中的 ECC 检查、总线错误传播、BEU 事件和可恢复 NMI（RNMI）处理。

## 本地 ECC 检查

| 模块 | 默认保护方式 | 检出错误后的主要处理 |
| --- | --- | --- |
| L1 ICache | Meta 和各 64 bit Data 单元使用 1 bit parity | 向 BEU 报告、使错误项失效并从 L2 重取；下级返回 TL corrupt 时产生 Instruction Access Fault（1） |
| L1 DCache | Tag/Data 使用 SECDED | 根据 Load、Store、Probe、替换和原子操作路径报告或传播；普通 Load 的精确本地错误路径由 `EnableAccurateLoadError` 控制且默认关闭 |
| L2 Cache | Tag/Data 使用 SECDED，128 bit Data 使用 9 bit 校验 | 本地错误可上报 BEU，也可通过返回的 denied/corrupt 传播；错误来源和访问类型共同决定同步异常 |
| L2 TLB Page Cache | l0/l1 SRAM 项支持可选 SECDED | `enablePTWECC` 默认关闭；开启后错误项失效、返回 miss 并重新 Page Walk |

parity 可以检测奇数个比特错误，但无法检出偶数个比特错误，也不能直接纠错。SECDED 编码具有单比特纠错能力，但当前 DCache/L2 数据读路径返回原始数据并使用错误信号，没有将纠正后的数据接回输出。

L1 ICache 本地错误通过失效和重取恢复。L1 DCache 的本地精确错误还受编译参数和 `cache_error_enable` 控制，部分非 miss Store 和非 LR 原子操作会抑制 MainPipe 的错误报告。

## CHI 与 TL 错误传播

Poison、DataCheck 和 RespErr 属于不同字段或机制，可以同时出现。DataCheck 是链路数据校验，与缓存 SRAM 的本地 ECC 不同。对于单独出现的 CHI 读数据错误，当前映射如下：

| CHI 读数据错误 | TL denied | TL corrupt | 普通数据 Load 的同步异常 |
| --- | --- | --- | --- |
| Poison 非零 | 0 | 1 | Hardware Error（19） |
| DataCheck 校验失败 | 0 | 1 | 当前代码对有效错误响应设有断言 |
| RespErr=DERR | 0 | 1 | Hardware Error（19） |
| RespErr=NDERR | 1 | 1 | Load Access Fault（5） |

对于普通数据 Load，硬件按 `denied` 优先、`corrupt && !denied` 次之的顺序分类。NC 和 MMIO Load 均使用这一规则。取指收到下级 corrupt 时产生 Instruction Access Fault，而不是 Hardware Error。预取、已取消或冲刷的请求不保证对应一条架构同步异常。

这些读返回错误通过 TL denied/corrupt 影响请求。接入 BEU 的后级路径会形成对应事件，例如 Uncache Store 将写完成失败形成 U_ECC。

CHI 读数据中的 DataCheck 错误会并入 corrupt。当前代码对有效响应带有 DataCheck 错误的情况设有断言；L2 本地 BEU 上报条件由 Directory/DataStorage 的检查结果形成。

MMIO Store 的 CHI 写完成响应与读数据不同：DERR 和 NDERR 均转换为 TL denied，返回的 `AccessAck` 将 corrupt 固定为 0，最终产生 Store Access Fault（7）。NC Store 在提交后发送，失败不能追溯为原 Store 的普通精确异常，但会形成 U_ECC 事件。

无数据写完成响应没有与读数据 DAT 对称的 Poison/DataCheck 字段。MMIOBridge 自身不直接上报 BEU，后级 Uncache Store 将 denied/corrupt 形成 U_ECC 事件。MMIO Store 的写完成错误可同时形成 Store Access Fault 和 U_ECC 事件。

## BEU 事件与软件可见状态

BEU 默认基址为 `0x38010000`，各寄存器间隔 8 字节。

| 偏移 | 寄存器 | 作用 |
| --- | --- | --- |
| `0x00` | `cause` | 一份事件源编号记录 |
| `0x08` | `value` | 一份错误地址记录 |
| `0x10` | `enable` | 事件更新 `cause`/`value` 的资格掩码 |
| `0x18` | `global_interrupt` | 与 `accrued` 相与后输出到 PLIC |
| `0x20` | `accrued` | 按事件源累积的事件位 |
| `0x28` | `local_interrupt` | 与 `accrued` 相与后输出本地 NMI31 |

| 编号 | 名称 | 来源 |
| --- | --- | --- |
| 0 | I_ECC | ICache 本地检查错误 |
| 1 | D_ECC | DCache 选中的本地错误报告 |
| 2 | U_ECC | Uncache Store 返回的 denied/corrupt |
| 3 | L2_ECC | L2 本地检查错误 |

`enable` 复位时四个有效源位均为 1，即低四位为 `0xF`；它只影响 `cause`/`value` 的捕获，不直接门控 `accrued`。`local_interrupt` 和 `global_interrupt` 复位值均为 0，本地和全局中断条件分别为 `(accrued & local_interrupt) != 0` 与 `(accrued & global_interrupt) != 0`。

`cause` 和 `value` 不是错误队列，只保留一份记录；同周期多个源可以分别更新 `accrued`，并按实现中的源处理顺序依次获得捕获机会，后处理的记录会覆盖先处理的记录。I_ECC 的编号也是 0，而硬件仅在 `cause == 0` 时接受新的记录，因此 `cause == 0` 不能独立表示“没有错误”，首个 I_ECC 地址也不保证一直保持。软件应结合 `accrued` 判断，并保存 `cause`、`value` 后再处理错误。`accrued` 当前是普通读写寄存器，不能按 W1C 处理。

DCache 和 Uncache 的错误报告还受 `smblockctl[6]` 控制。BEU 记录事件后，NMI 的产生还要求 `local_interrupt` 对应位和 RNMI 接收条件成立。

## RNMI

当前 NMI31 输入是外部 NMI31 与 BEU 本地中断的按位或结果，NMI43 来自另一条外部输入。两者同时待处理时，NMI43 的优先级高于 NMI31。NMI 的接收不依赖普通 `mstatus.MIE` 和 `mie` 使能路径，但受 `mnstatus.NMIE` 以及调试和单步状态约束。

RNMI 进入时切换到 M 模式，保存 `mnepc`、`mncause`、`mnstatus.MNPP/MNPV`，并清零 `NMIE`。当前入口复用 `mtvec`：Direct 模式从 BASE 进入，Vectored 模式从 BASE + 4 × cause 进入。返回使用 `mnret`，恢复保存状态并重新置位 `NMIE`。`NMIE` 复位值为 0，软件初始化 RNMI 时应按需开启。RNMI 处理期间再次发生非调试陷入会进入 critical-error 处理，不能按普通可嵌套异常处理。

`mnepc` 是被中断位置，不是 ECC 错误访问的精确地址。软件应通过 `mncause`、BEU 的事件记录和源寄存器共同定位原因，并在返回前处理持续错误源和已累积事件。

## 错误注入

ICache 和 DCache 提供用于测试检错路径的 MMIO 错误注入接口，其控制字段、地址和限制分别见[ICache 控制单元](frontend/ICache/CtrlUnit.md)和[DCache 错误处理](memblock/DCache/Error.md)。
