# VecRotate Utility Class {#sec:utils-vecrotate}

`VecRotate` is used to rotate `Vec`-typed signals. It is mainly applied in the Bpu half-align design.

```plaintext
Vec(0, 1, 2, 3) -- rotate(1) --> Vec(3, 0, 1, 2)
Vec(0, 1, 2, 3) -- rotate(2) --> Vec(2, 3, 0, 1)
Vec(0, 1, 2, 3) -- rotate(3) --> Vec(1, 2, 3, 0)
...
Vec(0, 1, 2, 3) -- rotate(1, left) --> Vec(1, 2, 3, 0)
...
```

The class extends `Bundle` and keeps the rotation amount as a member, which means instances can be registered directly to perform rotation and restoration transparently.

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

Note that the rotation direction here matches the behavior of `Seq` in Scala and `Vec` in Chisel, and is the opposite of `UInt`: rotating right means moving toward increasing indices, while rotating left means moving toward decreasing indices. The default direction is right rotation.
