# 饱和计数器 {#sec:bpu-saturate-counter}

从功能上讲，就是普通的饱和计数器（加到最大值后继续加仍然保持最大值，减到最小值后继续减仍然保持最小值），但是使用了非常面向对象的实现方法来简化使用。

有符号和无符号饱和计数器的实现是相似的，下面以无符号版本进行说明。

## `class SaturateCounter` {#sec:bpu-saturate-counter-class}

饱和计数器类实现，提供各种类方法。

- 比较
    - 重载了常见比较运算符（`===`、`=/=`、`<`、`>`、`<=`、`>=`），和普通的 UInt 比较方法一致
- 获取状态
    - 饱和程度
        - 饱和：`.isSaturate()`
        - 临界（再加减 1 就会切换方向）：`.isWeak()`
        - 非饱和非临界：`.isMid()`
    - 方向：
        - 正向：`.isPositive()`
        - 负向：`.isNegative()`
    - 以及它们的组合，如是否为正向饱和：`.isSaturatePositive()`
- 获取更新后的饱和计数器（返回更新后的新实例，可用于 wire）
    - 更新±1：`.getUpdate(increase, en)`，若 `en` 为 False 则不更新，否则，若 `increase` 为 True 则加 1，否则减 1。
    - 正向更新：`.getIncrease(step, en)`，当 `step` 为 1 时等价于 `.getUpdate(True, en)`，`step` 可以大于 1 来一次性增加多个级别的饱和程度，但需要注意会在选择端引入额外的 `width+1` bit 位宽的比较器。
    - 负向更新：`.getDecrease(step, en)`，类似
- 自更新（在当前实例上更新，仅可用于 reg，无返回值）
    - 更新±1：`.selfUpdate(increase, en)`，类似于 `.getUpdate(increase, en)`
    - 正/负向更新：`.selfIncrease(step, en)` 和 `.selfDecrease(step, en)`，同理
- 复位（在当前实例上更新，仅可用于 reg，无返回值）
    - 归零：`.resetZero()`
    - 复位正向饱和：`.resetSaturatePositive()`
    - 复位正向临界：`.resetWeakPositive()`
    - 复位负向同理
    - 需要注意的是，对无符号饱和计数器来讲，`.resetZero()` 和 `.resetSaturateNegative()` 是等价的；而对有符号的饱和计数器来讲，`.resetZero()` 和 `.resetWeakPositive()` 是等价的。由于这点模糊性，不建议使用 `.resetZero()` 来复位饱和计数器。

## `object SaturateCounter` {#sec:bpu-saturate-counter-object}

计算给定位宽的饱和计数器的饱和/临界常量值，返回 Int 或饱和计数器实例。

- 获取 Int：`SaturateCounter.Value.AAABBB(width)`
- 获取饱和计数器实例：`SaturateCounter.AAABBB(width)`

其中 `AAA` 为饱和程度（`Saturate`，`Weak`），`BBB` 为方向（`Positive`、`Negative`），和类方法的 `isAAABBB()` 依次对应

## `object SaturateCounterInit` {#sec:bpu-saturate-counter-init-object}

快速实例化一个饱和计数器并为其赋值。

```scala
val counter = SaturateCounterInit(width, value)
// 等价于
val counter = new SaturateCounter(width)
counter.value := value   // 如果 value 是 Int，或者
counter.value := value.U // 如果 value 是 UInt
```

## `trait SaturateCounterFactory` {#sec:bpu-saturate-counter-factory-trait}

针对 XiangShan 的参数传递体系设计的工厂方法，用于快速创建特定名字的饱和计数器 object，从而简化 width 的传递，减少多个不同位宽的饱和计数器之间容易笔误的问题。

可以创建 `object XxxCounter extends SaturateCounterFactory`，并在其中定义 `def width(implicit p: Parameters): Int` 来指定位宽，然后在代码中直接使用 `XxxCounter()` 来实例化对应位宽的饱和计数器，以及使用 `XxxCounter.AAABBB` 来获取对应的常量值。

```scala
object TageTakenCounter extends SaturateCounterFactory {
    def width(implicit p: Parameters): Int = p(XSCoreParamsKey).frontendParameters.bpuParameters.tageParameters.TakenCntWidth
}
class TageIO(implicit p: Parameters) extends Bundle {
    val takenCnt = Output(TageTakenCounter())
}
class Tage(implicit p: Parameters) extends Module {
    val takenCnt = TageTakenCounter()
    takenCnt := Mux(
        needReset,
        if (resetPositive) TageTakenCounter.WeakPositive else TageTakenCounter.WeakNegative,
        takenCnt.getUpdate(increase, en)
    )
}
// 等价于
// 每次实例化 taken counter / 使用常量都要手动传递 width
trait TageParameters {
    implicit val p: Parameters
    def TakenCntWidth: Int = p(XSCoreParamsKey).frontendParameters.bpuParameters.tageParameters.TakenCntWidth
}
class TageIO(implicit p: Parameters) extends Bundle with TageParameters {
    val takenCnt = Output(new SaturateCounter(TakenCntWidth))
}
class Tage(implicit p: Parameters) extends Module with TageParameters {
    val takenCnt = new SaturateCounter(TakenCntWidth)
    takenCnt := Mux(
        needReset,
        if (resetPositive) SaturateCounter.WeakPositive(TakenCntWidth) else SaturateCounter.WeakNegative(TakenCntWidth),
        takenCnt.getUpdate(increase, en)
    )
}
```
