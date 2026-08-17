# Saturate Counter {#sec:bpu-saturate-counter}

Functionally, it is an ordinary saturate counter (after reaching the maximum value, further increments keep it at the maximum; after reaching the minimum value, further decrements keep it at the minimum), but it uses a very object-oriented implementation to simplify usage.

The implementations of signed and unsigned saturate counters are similar; the unsigned version is used below for illustration.

## `class SaturateCounter` {#sec:bpu-saturate-counter-class}

Saturate counter class implementation, providing various class methods.

- Comparison
    - Overloads common comparison operators (`===`, `=/=`, `<`, `>`, `<=`, `>=`), consistent with ordinary UInt comparison methods
- Getting state
    - Saturation level
        - Saturated: `.isSaturate()`
        - Weak (one more increment or decrement will flip the direction): `.isWeak()`
        - Neither saturated nor weak: `.isMid()`
    - Direction:
        - Positive: `.isPositive()`
        - Negative: `.isNegative()`
    - And their combinations, e.g., whether it is positively saturated: `.isSaturatePositive()`
- Getting the updated saturate counter (returns a new updated instance, usable for wires)
    - Update by ±1: `.getUpdate(increase, en)`. If `en` is False, no update occurs; otherwise, if `increase` is True, increment by 1, otherwise decrement by 1.
    - Positive update: `.getIncrease(step, en)`. When `step` is 1, it is equivalent to `.getUpdate(True, en)`. `step` can be greater than 1 to increase the saturation level by multiple steps at once, but note that this introduces an extra comparator of `width+1` bits at the select side.
    - Negative update: `.getDecrease(step, en)`, similar to above
- Self-update (updates the current instance, only usable for regs, no return value)
    - Update by ±1: `.selfUpdate(increase, en)`, similar to `.getUpdate(increase, en)`
    - Positive/negative update: `.selfIncrease(step, en)` and `.selfDecrease(step, en)`, same principle
- Reset (updates the current instance, only usable for regs, no return value)
    - Reset to zero: `.resetZero()`
    - Reset to positive saturation: `.resetSaturatePositive()`
    - Reset to positive weak: `.resetWeakPositive()`
    - Negative direction counterparts are analogous
    - Note that for unsigned saturate counters, `.resetZero()` and `.resetSaturateNegative()` are equivalent; for signed saturate counters, `.resetZero()` and `.resetWeakPositive()` are equivalent. Due to this ambiguity, it is not recommended to use `.resetZero()` to reset the saturate counter.

## `object SaturateCounter` {#sec:bpu-saturate-counter-object}

Computes the saturate/weak constant values for a saturate counter of a given width, returning an Int or a saturate counter instance.

- Get Int: `SaturateCounter.Value.AAABBB(width)`
- Get saturate counter instance: `SaturateCounter.AAABBB(width)`

Here `AAA` is the saturation level (`Saturate`, `Weak`), `BBB` is the direction (`Positive`, `Negative`), corresponding in order to the class methods `isAAABBB()`.

## `object SaturateCounterInit` {#sec:bpu-saturate-counter-init-object}

Quickly instantiate a saturate counter and assign it a value.

```scala
val counter = SaturateCounterInit(width, value)
// Equivalent to
val counter = new SaturateCounter(width)
counter.value := value   // if value is Int, or
counter.value := value.U // if value is UInt
```

## `trait SaturateCounterFactory` {#sec:bpu-saturate-counter-factory-trait}

A factory method designed for XiangShan's parameter-passing system, used to quickly create a named saturate counter object, thereby simplifying width passing and reducing the chance of typos among multiple saturate counters of different widths.

You can create `object XxxCounter extends SaturateCounterFactory`, define `def width(implicit p: Parameters): Int` inside it to specify the width, and then directly use `XxxCounter()` in the code to instantiate a saturate counter of the corresponding width, and use `XxxCounter.AAABBB` to obtain the corresponding constant value.

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
// Equivalent to
// Manually passing width every time you instantiate a taken counter / use a constant
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
