# VecRotate 工具类 {#sec:utils-vecrotate}

`VecRotate` 用于对 `Vec` 类型的信号做循环移位，目前主要应用于 Bpu 的 half-align 设计中。

```plaintext
Vec(0, 1, 2, 3) -- rotate(1) --> Vec(3, 0, 1, 2)
Vec(0, 1, 2, 3) -- rotate(2) --> Vec(2, 3, 0, 1)
Vec(0, 1, 2, 3) -- rotate(3) --> Vec(1, 2, 3, 0)
...
Vec(0, 1, 2, 3) -- rotate(1, left) --> Vec(1, 2, 3, 0)
...
```

该类继承自 `Bundle`，并将移位的位数作为成员，意味着可以直接将其实例寄存，从而实现无感的移位和还原。

```scala
val s1_offset  = Wire(UInt(2.W))
val s1_rotator = VecRotate(s1_offset)
val s1_index   = VecInit(Seq(0, 1, 2, 3))

val s1_indexToSram = s1_rotator.rotate(s1_index)
// read sram request logic
val s2_resultFromSram = ... // read sram response logic

val s2_rotator = RegEnable(s1_rotator, s1_fire)
val s2_result  = s2_rotator.revert(s2_resultFromSram)

// equivalent to:
val s2_offset  = RegEnable(s1_offset, s1_fire)
val s2_rotator = VecRotate(s2_offset)
val s2_result  = s2_rotator.revert(s2_resultFromSram)

// also equivalent to:
val s2_offset  = RegEnable(s1_offset, s1_fire)
val s2_rotator = VecRotate(s2_offset, direction = VecRotate.Direction.Left)
val s2_result  = s2_rotator.rotate(s2_resultFromSram)
```

需要注意这里的方向和 scala 中 `Seq` 或 chisel 中 `Vec` 在代码中的行为是一致的，和 `UInt` 是相反的，即向右移位是向下标递增的方向移位，向左移位是向下标递减的方向移位。默认为向右移位。
