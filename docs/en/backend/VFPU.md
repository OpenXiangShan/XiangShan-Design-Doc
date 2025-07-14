# VFPU

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Glossary of Terms

| Abbreviation | Full name                  | Descrption                            |
| ------------ | -------------------------- | ------------------------------------- |
| VFPU         | Vector Floating-Point Unit | Vector Floating-Point Functional Unit |
| IQ           | Issue Queue                | Issue Queue                           |

## Design specifications

1. Support Vector Floating-Point Mul Calculation
2. Support vector floating-point FMA computation
3. Support Vector Floating-Point Div Calculation
4. Support for vector floating-point Sqrt computation
5. Supports fp32, fp64, fp16 computation
6. Supports computation of RV-V1.0 version vector floating-point instructions

## Function

The VFPU module receives uop information issued from the Issue Queue and
performs vector floating-point instruction calculations based on fuType and
fuOpType information. It mainly consists of four modules: VFAlu, VFMA,
VFDivSqrt, and VFCvt.

VFAlu is primarily responsible for fadd-related instructions and some other
simple instructions, such as comparison instructions and sign injection
instructions. Notably, the reduction sum instruction is also computed in this
module by splitting into micro-operations (uops).

VFMA is primarily responsible for multiplication and multiply-add related
instructions.

VFDivSqrt is primarily responsible for instructions related to division and
square root.

VFCvt is primarily responsible for format conversion and reciprocal
estimation-related instructions.

## Algorithm design

The challenge of the vector floating-point unit lies in supporting multiple
single-precision format calculations (where the floating-point formats of
operands and results are the same) and mixed-precision calculations (where the
floating-point formats of operands and results differ). Taking common formats
such as half-precision ($f16$), single-precision ($f32$), and double-precision
($f64$) as examples, the differences between scalar and vector floating-point
units are compared.

Taking a typical floating-point addition as an example, for a scalar
floating-point unit, it only needs to support calculations in three
single-precision formats. The input operands and output results of this unit
should all be $64$-bit, meaning it must support calculations in three formats:

(1) One $f64 = f64 + f64$;

(2) $1$ $f32 = f32 + f32$;

(3) $1$ $f16 = f16 + f16$.

At first glance, three modules seem necessary to handle these three formats.
However, since floating-point numbers consist of a sign bit, exponent, and
mantissa, and higher-precision floating-point numbers have wider exponent and
mantissa bit widths than lower-precision ones, the hardware design for
higher-precision floating-point numbers can fully meet the requirements of
lower-precision floating-point calculations. With slight modifications, adding
$Mux$ (multiplexers) to the hardware can enable compatibility with multiple
single-precision formats, with only a marginal increase in area.

The vector floating-point unit needs to support vector operations, which are
characterized by high data bandwidth utilization. For example, although the
interface of a scalar arithmetic unit is 64-bit, when computing f32/f16, the
effective data is only 32/16 bits, reducing bandwidth utilization to 50%/25%.
The vector arithmetic unit also has a 64-bit interface, but when computing
single-precision formats f32/f16, it can perform 2/4 sets of operations
simultaneously, maintaining 100% bandwidth utilization. The supported
single-precision format computations are as follows:

(1) One $f64 = f64 + f64$;

(2) 2 $f32 = f32 + f32$;

(3) $4$ $f16 = f16 + f16$.

Performing multiple sets of floating-point additions with the same format
simultaneously makes hardware design more challenging than scalar operations,
but it also allows the reuse of high-precision format hardware for low-precision
formats. Additionally, a key feature that vector floating-point units must
support is mixed-precision computation. The $RISC-V$ vector instruction set
extension defines a series of $widening$ instructions requiring mixed-precision
computation, mandating that floating-point addition units also support the
following four computation formats:

(1) $1$ $f64 = f64 + f32$;

(2) One $f64 = f32 + f32$;

(3) Two $f32 = f32 + f16$;

(4) Two $f32 = f16 + f16$.

The design difficulty of mixed-precision computation is much greater than that
of multiple single-precision formats. On one hand, operands of different data
formats need to be converted to the same format as the result before
computation, increasing logical complexity. On the other hand, format conversion
imposes significant pressure on circuit timing, especially when converting
low-precision denormal numbers to high-precision floating-point numbers.
Therefore, this paper specifically designs a fast data format conversion
algorithm to address the timing issue.

In summary, the design challenges of the vector floating-point unit lie in the
implementation of multiple single-precision formats and mixed-precision formats.
This section will introduce the vector floating-point addition algorithm,
floating-point sequential accumulation algorithm, vector fused multiply-add
algorithm, and vector floating-point division algorithm to address these
challenges, achieving a high-performance vector floating-point unit with a
frequency of up to $3GHz$.

### Vector Floating-Point Addition

Floating-point addition is one of the most commonly used arithmetic operations
in scientific computing. Although conceptually simple, the traditional
single-path floating-point addition algorithm requires two to three signed
addition steps, which is a relatively time-consuming operation. The dual-path
floating-point addition algorithm has only one signed addition operation on the
critical path in the worst case, thus offering significant speed advantages over
the single-path algorithm. Based on the dual-path floating-point addition
algorithm, this paper designs an even faster improved dual-path floating-point
addition algorithm. This section first introduces the single-path floating-point
addition algorithm, the dual-path floating-point addition algorithm, and the
improved dual-path floating-point addition algorithm for single-precision
format, and finally presents the vector floating-point addition algorithm.

The floating-point addition formula is expressed as: $fp\_result = fp\_a +
fp\_b$. When $fp\_a$ and $fp\_b$ have the same sign, the significands are
aligned and added, which is referred to as equivalent addition. When $fp\_a$ and
$fp\_b$ have opposite signs, the significands are aligned and subtracted, which
is referred to as equivalent subtraction. For denormal numbers, the exponent is
$0$, and for normalized numbers, the exponent is $1$, but the corresponding
normalized exponent is the same. Therefore, when calculating the exponent
difference, an exponent of $0$ should be treated as $1$ (referred to as the
normalized exponent). The absolute difference between the normalized exponents
is the normalized exponent difference.

#### Single-path floating-point addition algorithm

The traditional single-path floating-point addition operation is illustrated as
follows, consisting of the following steps:

![Single-path floating-point addition
algorithm](./figure/SinglePassFloating-pointAddition.svg)

(1) Normalized exponent subtraction (ES): Calculate the difference between
normalized exponents, d = |Ea - Eb|, where Ea and Eb are both normalized
exponents.

(2) Alignment ($Align$): Shift the significand of the smaller operand right by
$d$ bits. The larger exponent is denoted as $Ef$.

(3) Significand addition ($SA$): Performs addition or subtraction based on the
effective operation $Eo$, which is the arithmetic operation executed by the
adder in the floating-point addition unit, determined by the sign bits of the
two floating-point operands.

(4) Conversion ($Conv$): If the significand addition result is negative, convert
the result to sign-magnitude representation. The conversion is completed through
an addition step, with the result denoted as $Sf$.

(5) Leading zero detection (LZD): Calculates the required left or right shift
amount, expressed as $En$, where right shift is positive and left shift is
negative.

(6) Normalization ($Norm$): Normalize the significand by shifting $En$ bits and
add $En$ to $Ef$.

(7) Rounding ($Round$): Round according to the $IEEE$-$754$ standard, adding $1$
to the $LSB$ of $Sf$ if necessary. This step may cause overflow, requiring the
mantissa result to be right-shifted by one bit while incrementing the exponent
$Ef$ by $1$.

#### Dual-path floating-point addition algorithm

The above single-path floating-point algorithm is slow because the steps in the
addition operation are essentially executed serially. This algorithm can be
improved in the following ways:

(1) In the single-path floating-point addition algorithm, the $Conv$ step is
only needed when the result is negative, and it can be avoided by swapping the
significands of the two operands. By checking the sign of the $ES$ step result,
the significands can be swapped ($Swap$) accordingly, always computing the
larger significand minus the smaller one. When exponents are equal, the result
may still be negative, requiring conversion, but no rounding is needed in this
case. Thus, the swap step makes rounding and conversion mutually exclusive,
allowing them to be parallelized. Note that another advantage of swapping is
that only one shifter is required.

(2) The leading zero detection step can be executed in parallel with the
significand addition step, removing it from the critical path. This optimization
is particularly important in cases where subtraction requires significant left
shifts.

(3) So far, the critical path steps have been reduced to: normalized exponent
subtraction, swapping, alignment, significand addition $||$ leading zero
detection, conversion $||$ rounding, normalization (where $||$ denotes steps
that can be executed in parallel). The alignment and normalization steps are
mutually exclusive and can be further optimized. Normalization requires a large
left shift only when $d≤1$ or during equivalent subtraction. Conversely,
alignment requires a large right shift only when $d > 1$. By distinguishing
these two cases, only one large shift—either alignment or normalization—remains
on the critical path.

The steps for single-path and dual-path floating-point addition algorithms are
shown in the table. In the dual-path algorithm, the preprocessing step ($Pred$)
in the $d ≤ 1$ path determines whether a right shift is needed to align
significands based on the value of $d$. The dual-path algorithm improves speed
by executing more steps in parallel, requiring additional hardware for
implementation.

Table: Steps for Two Floating-Point Addition Algorithms

+------------------+-----------------------------------------------------+ |
Single-Path Floating-Point Addition | Dual-Path Floating-Point Addition
Algorithm | | +-----------------------------+-----------------------+ | |
$d\leq1$ and Equivalent Subtraction | $d>1$ or Equivalent Addition |
+:================:+:===========================:+:=====================:+ |
Normalized Exponent Addition | Preprocessing + Swap | Normalized Exponent
Subtraction + Swap |
+------------------+-----------------------------+-----------------------+ |
Alignment | -- | Alignment |
+------------------+-----------------------------+-----------------------+ |
Significant Digit Addition | Significant Digit Addition or Leading Zero
Detection | Significant Digit Addition |
+------------------+-----------------------------+-----------------------+ |
Conversion | Conversion or Rounding | Rounding |
+------------------+-----------------------------+-----------------------+ |
Leading Zero Detection | -- | -- |
+------------------+-----------------------------+-----------------------+ |
Normalization | Normalization | -- |
+------------------+-----------------------------+-----------------------+ |
Rounding | Path Selection | Path Selection |
+------------------+-----------------------------+-----------------------+

In the dual-path floating-point addition algorithm, during the $SA$ step in the
case of equivalent subtraction, one of the significant digits is in 2's
complement form. The complementation step and the rounding step are mutually
exclusive, thus they can be performed in parallel. The optimized dual-path
floating-point addition algorithm is shown in the table.

Table: Optimized Dual-Path Floating-Point Addition Algorithm

|                     $d≤1$ and equivalent subtraction                      |       $d>1$ or equivalent addition        |
| :-----------------------------------------------------------------------: | :---------------------------------------: |
|                         Preprocessing + Exchange                          | Normalized Instruction Subtraction + Swap |
| Significant Digit Addition Conversion | Rounding | Leading Zero Detection |                 Alignment                 |
|                               Normalization                               |      Significand addition | Rounding      |
|                              Selection Path                               |              Selection Path               |

In the IEEE round-to-nearest ($RTN$) mode, computing $A+B$ and $A+B+1$ suffices
to address all normalization possibilities (additional computation of $A+B+2$ is
required for rounding toward positive or negative infinity). By utilizing $Cin$
to select the final rounded mantissa result from multiple sets of significand
adder outputs, both two's complement conversion and rounding can be completed
simultaneously, saving an addition step. Since floating-point addition may
require normalization through a right shift by one bit, no shift, or a left
shift (potentially as extensive as the significand's length), $Cin$ must account
for all these normalization possibilities to ensure the selected result is the
rounded one.

#### Improved dual-path floating-point addition algorithm

This section details the improved dual-path floating-point addition algorithm
proposed in this paper. The path for equivalent addition or equivalent
subtraction with d > 1 is called the far path, while the path for equivalent
subtraction with d ≤ 1 is called the close path. Cases involving infinity or NaN
operands are handled separately and do not belong to the far or close paths.

##### $far$ path

The $far$ path algorithm is illustrated in the figure, with the main steps as
follows:

![far Path Algorithm Diagram](./figure/FarPath.svg)

Step 1: In the $far$ path, when the exponent difference $d$ is greater than $1$,
the smaller significand is shifted right by $d$ bits to align with the larger
significand. First, calculate the normalized exponent difference. To accelerate
computation, two adders are used to compute the normalized exponent difference
while comparing the magnitudes of $Efp\_a$ and $Efp\_b$. The correct normalized
exponent difference is selected based on the comparison result of the exponent
magnitudes.

In the second step, based on the exponent comparison from the first step, the
significand of the operand with the larger exponent and the significand of the
operand with the smaller exponent can be selected in parallel while also
selecting the larger exponent $EA$. For equivalent subtraction, $EA$ is
decremented by $1$ (in this case, $EA$ cannot be $0$, as that would fall under
the $close$ path). This adjustment aims to align the value range of the
significand after subtraction with that of equivalent addition, facilitating the
selection of the final result. The adjusted significand addition or subtraction
result falls within the range $[1$-$4)$, divided into two cases: $[1$-$2)$ and
$[2$-$4)$.

Step three involves right-shifting the smaller significand, which is divided
into two scenarios: during equivalent subtraction, the smaller significand is
first inverted and then arithmetically right-shifted, saving some time compared
to right-shifting first and then inverting; during equivalent addition, a
logical right shift is directly applied. To reduce the number of shifter stages,
when the high-order bits of the normalized exponent difference are all $0$, the
lower bits (the specific number depends on the significand width) are used for
the right shift. If the high-order bits are not all $0$, the right-shift result
is $0$. Here, the adder result from the first step, which calculates the
normalized exponent difference between the two, is used, with the least
significant bit applied first (since the adder result's least significant bit is
obtained earliest). Specifically: if $fp\_a$'s exponent is larger, only
$fp\_b$'s significand is right-shifted by the value of $fp\_a$'s normalized
exponent minus $fp\_b$'s normalized exponent; if $fp\_b$'s exponent is larger,
only $fp\_a$'s significand is right-shifted by the value of $fp\_b$'s normalized
exponent minus $fp\_a$'s normalized exponent. The final right-shifted
significand is then selected based on the exponent magnitude relationship and
the normalized exponent difference, and the $grs$ ($guard$, $round$, $sticky$)
bits after the shift are calculated. To ensure correct rounding for the two
scenarios in step two, two sets of $grs$ need to be computed for the significand
addition/subtraction results within $[1$-$2)$ and $[2$-$4)$.

Step 4: Perform significand addition. For equivalent subtraction, the smaller
significand is inverted before right-shifting. Denote the larger significand as
$A$ and the right-shifted smaller significand as $B$. Two adders compute $A+B$
and $A+B+2$, and the final rounded result is selected from these two adder
outputs.

Step five: generate the final result. Depending on whether the significant
digits $A+B$ result falls within $[1$-$2)$ (case one) or $[2$-$4)$ (case two),
and based on the two sets of $grs$ and rounding modes calculated during the
previous right shift, determine the conditions for selecting the two significant
digit adders in case one and case two, respectively. Finally, use a one-hot
four-way selection to choose the mantissa result. The exponent result is either
$EA$ (case one and mantissa rounded to $<1$) or $EA+1$ (case two or case one
rounded to $=2$). Note whether the exponent overflows after rounding, and the
final result is selected between the overflow result and the normal computation
result based on $overflow$. The exception flags in the $far$ path only produce
overflow and inexact results.

##### $close$ path

In the $close$ path, it must be an effective subtraction with $d \leq 1$,
specifically categorized as $d=0$ or $d=1$. The algorithm is illustrated in the
figure, with the following detailed steps:

![Schematic diagram of the close path algorithm](./figure/ClosePath.svg)

Step 1: Perform four sets of significand subtractions in parallel. Based on
$d=0$ ($fp\_a$ significand is larger, $fp\_b$ significand is larger) and $d=1$
($fp\_a$ normalized exponent is larger, $fp\_b$ normalized exponent is larger),
combine the four scenarios for effective subtraction. The first subtractor:
$fp\_a$ significand $-$ $fp\_b$ significand; the second subtractor: $fp\_b$
significand $-$ $fp\_a$ significand; the third subtractor: $fp\_a$ significand
$×2$ $-$ $fp\_b$ significand; the fourth subtractor: $fp\_b$ significand $×2$
$-$ $fp\_a$ significand. Simultaneously, calculate the $grs$ bits based on the
exponent magnitude relationship. When $d=0$, all $grs$ bits are $0$; when $d=1$,
only $g$ may be non-zero. These four sets of adders cannot produce all rounding
results, so a fifth slower adder is added: the significand with the larger
exponent $–$ the significand with the smaller exponent shifted right by one bit.

Step two: Determine the four conditions for selecting the four sets of
significand subtractions, based on the value of $d$, the most significant bit of
the adder result, $grs$, and the rounding mode. After selecting the subtraction
result from the four sets of adders, perform $LZD$ $+$ left shift on the
subtraction result. Here, attention must be paid to the value of the larger
exponent $EA$. The left shift is controlled jointly by $LZD$ and $EA$,
generating a $mask$ value (with the same bit width as the subtraction result but
with at most one bit set to $1$) based on the value of $EA$. This $mask$ is ORed
with the subtraction result before performing $LZD+$ left shift.

Step 3: Determine the condition for selecting the fifth subtractor. When
selecting the result of the fifth subtractor, no left shift is required, so a
slower adder is used, and the final mantissa result can then be selected.

Step four: exponent and sign bit results. The exponent result requires
subtracting the $LZD$ value from step two from $EA$. If the fifth subtractor is
selected as the mantissa result, the exponent remains unchanged. When $d=1$, the
sign bit is the sign of the operand with the larger exponent. When $d=0$, the
sign bit is selected based on the mantissa size. Note that when the result is
$0$ and rounded down, the sign bit is $1$.

#### Vector floating-point addition algorithm

The vector floating-point adder's output signal width is $64$ bits, supporting
mixed precision and widening instructions. It must support calculations for the
following data formats:

(1) $1$ $f64$ $= f64 + f64$;

(2) $1$ $f64$ $= f64 + f32$;

(3) 1 $f64$ = $f32$ + $f32$;

(4) $2$ $f32$ values $= f32 + f32$;

(5) $2$ $f32$ $= f32 + f16$;

(6) Two $f32$ $= f16 + f16$;

(7) Four $f16$ = $f16 + f16$.

##### Module partitioning

The computation approach uses one module for the first three formats, all
outputting 64-bit results. The single-precision floating-point adder for $f64 =
f64 + f64$ is reused to compute $f64 = f64 + f32$ and $f64 = f32 + f32$. This
paper proposes a fast data format conversion algorithm to convert $f32$ operands
to $f64$, enabling $f64 = f64 + f64$ computation and yielding results in $f64$
format.

The same approach is applied to computation formats where the output is $f32$.
Since $f32$ has less timing pressure, integrating a $f16 = f16 + f16$ operation
into the module that computes $f32$ results saves area while supporting:

(1) One $f32 = f32 + f32$;

(2) One $f32 = f32 + f16$;

(3) One $f32 = f16 + f16$;

(4) One $f16 = f16 + f16$.

Clearly, this module needs to be instantiated twice, and there are still two
$f16 = f16 + f16$ operations missing. Two single-precision floating-point adders
dedicated to computing $f16 = f16 + f16$ are instantiated separately, totaling
four modules, to implement all vector addition calculation formats.

##### Fast format conversion algorithm

Taking the conversion from $f16$ to $f32$ as an example, a fast format
conversion algorithm is introduced.

When $f16$ is a normalized number, converting it to $f32$ will also result in a
normalized number. For $f16$ exponents, they are biased to match $f32$
exponents. Since $f32$ has a larger exponent range, there is no concern about
exponent overflow after conversion. Additionally, the $f16$ significand is $10$
bits, while the $f32$ significand is $23$ bits. Simply appending $13$ zeros to
the $f16$ significand yields the $f32$ significand. This is a conversion from
lower to higher precision, ensuring the result is exact.

For a normalized $f16$ exponent (5-bit width), the actual exponent $Ereal = Ef16
– 15$. For a normalized $f32$ exponent (8-bit width), $Ereal = Ef32 – 127$.
Thus, converting $Ef16$ to $Ef32$ via $Ereal$: $Ef16 – 15 = Ef32 – 127$, $Ef32 =
Ef16 – 15 + 127$, $Ef32 = Ef16 + 112$. The 8-bit binary representation of $112$
is $01110000$. Computing $Ef16 + 112$ requires an adder for a variable plus a
constant, but this adder can be avoided by identifying the following pattern:

When the highest bit of $Ef16$ is $0$, $Ef16 + 112 = (0111, Ef16(3, 0))$

When the most significant bit of $Ef16$ is $1$, $Ef16 + 112 = (1000, Ef16(3,
0))$.

Using this pattern, an $Mux$ can quickly convert $Ef16$ to $Ef32$. Thus, for
normalized $f16$ to $f32$ conversion, the exponent bits use an $Mux$, the
significand bits are padded with 0, and the sign bit remains unchanged. The
challenge arises when $f16$ is denormal. In this case, all exponent bits of
$f16$ are 0, and the number of leading zeros in the significand determines the
exponent after conversion to $f32$. When all exponent bits of $f16$ are zero and
only the $lsb$ of the significand is 1, the converted $f32$ exponent is
minimized at $-15-9=-24$, which still falls within the range of $f32$ normalized
numbers. Therefore, for denormal $f16$, leading zero detection ($lzd$) and left
shifting of the significand are required.

Chisel's built-in priority encoder can implement the $lzd$ function. Tests show
it synthesizes better than traditional $lzd$ implementations using binary
search. The syntax is: $PriorityEncoder(Reverse(Cat(in,1.U)))$. For a $5$-bit
$in$, the generated Verilog code is as follows:

```verilog
module LZDPriorityEncoder(
  input        clock,
  input        reset,
  input  [4:0] in,
  output [2:0] out
);
  wire [5:0] _out_T = {in,1'h1};
  wire [5:0] _out_T_15 = {_out_T[0],_out_T[1],_out_T[2],_out_T[3],_out_T[4],_out_T[5]};
  wire [2:0] _out_T_22 = _out_T_15[4] ? 3'h4 : 3'h5;
  wire [2:0] _out_T_23 = _out_T_15[3] ? 3'h3 : _out_T_22;
  wire [2:0] _out_T_24 = _out_T_15[2] ? 3'h2 : _out_T_23;
  wire [2:0] _out_T_25 = _out_T_15[1] ? 3'h1 : _out_T_24;
  assign out = _out_T_15[0] ? 3'h0 : _out_T_25;
endmodule
```

Although this code appears to use many cascaded $Mux$es, the synthesizer
produces good timing results for such code. Inspired by this, this paper designs
a novel priority-based left-shift algorithm to accelerate $lzd+$ left-shift,
with the $Chisel$ code as follows:

```scala
def shiftLeftPriorityWithF32EXPResult(srcValue: UInt, priorityShiftValue: UInt): UInt = {
  val width = srcValue.getWidth
  val lzdWidth = srcValue.getWidth.U.getWidth
  def do_shiftLeftPriority(srcValue: UInt, priorityShiftValue: UInt, i:Int): UInt = {
    if (i==0) Cat(
      Mux(
        priorityShiftValue(i),
        Cat(srcValue(0),0.U((width-1).W)),
        0.U(width.W)
      ),
      Mux(
        priorityShiftValue(i),
        "b01110000".U-(width-i-1).U(8.W),
        "b01110000".U-(width-i).U(8.W)
      )
    )
    else Mux(
      priorityShiftValue(i),
      if (i==width-1) Cat(srcValue(i,0),"b01110000".U-(width-i-1).U(8.W)) 
      else Cat(Cat(srcValue(i,0),0.U((width-1-i).W)), "b01110000".U-(width-i-1).U(8.W)),
      do_shiftLeftPriority(srcValue = srcValue, priorityShiftValue = priorityShiftValue, i = i - 1)
      )
    }
    do_shiftLeftPriority(srcValue = srcValue, priorityShiftValue = priorityShiftValue, i = width-1)
  }
```

Both $srcValue$ and $priorityShiftValue$ pass the mantissa of $f16$, starting
from the most significant bit (MSB) of the mantissa. If the MSB is $1$, the
original value of $srcValue$ is returned along with the corresponding exponent
(the exponent is selected from multiple constants and depends on the position of
the first $1$ in the mantissa). If the MSB is $0$, the next bit is checked for
$1$. If it is $1$, $srcValue$ is left-shifted by one bit and returned (no actual
left shift is needed here since the high bits after shifting are not retained;
truncation and zero-padding suffice), along with the corresponding exponent.
This process continues iteratively. Thus, a priority left shifter simultaneously
performs the $lzd$ and left shift operations while also generating the
corresponding $Ef32$, eliminating the need to calculate the $Ef32$ exponent
based on $lzd$. This enables a fast algorithm for converting $f16$ denormal
numbers to $f32$. A similar algorithm is used for converting $f32$ to $f64$,
which is not elaborated here.

### Vector Floating-Point Fused Multiply-Add Algorithm

Floating-point fused multiply-add computation $fpa × fp\_b + fp\_c$, where the
intermediate multiplication $fpa × fp\_b$ is performed as if without range and
precision limitations, without rounding, and only rounded once to the target
format at the end. FMA is typically implemented using a pipeline, with steps
including multiplication, addition, normalization shift, and rounding. This
chapter introduces the vector floating-point fused multiply-add algorithm, whose
functionalities include:

(1) 1 $fp64 = fp64 × fp64 + fp64$;

(2) $2$ $fp32 = fp32 × fp32 + fp32$;

(3) Four $fp16 = fp16 × fp16 + fp16$;

(4) $2$ $fp32 = fp16 × fp16 + fp32$;

(5) $1$ $fp64 = fp32 × fp32 + fp64$.

($1$) ($2$) ($3$) The source and destination operands are in the same
floating-point format, while in ($4$) ($5$), the two multipliers have the same
width, and the other addend and the result share the same width, which is twice
that of the multipliers.

#### Scalar single-precision format algorithm

The computation flow first calculates the unrounded result of multiplying two
floating-point numbers, then adds this unrounded product to a third number. The
algorithm flowchart is illustrated, expressed by the formula $fp\_result = fp\_a
× fp\_b + fp\_c$, where $Sa$, $Sb$, and $Sc$ are the significands of $fp\_a$,
$fp\_b$, and $fp\_c$ respectively, and $Ea$, $Eb$, and $Ec$ are their exponents:

![FMA algorithm flowchart](./figure/FMA.svg)

For ease of description below, some parameters are defined, with their meanings
and values listed in the table:

Table: Parameter meanings and values under different precisions

|     Parameters     | $f16$ | $f32$ | $f64$ |                                                Meaning                                                 |
| :----------------: | :---: | :---: | :---: | :----------------------------------------------------------------------------------------------------: |
| $significandWidth$ | $11$  | $24$  | $53$  |                                        Significant Digit Width                                         |
|  $exponentWidth$   |  $5$  |  $8$  | $11$  |                                             Exponent width                                             |
|   $rshiftBasic$    | $14$  | $27$  | $56$  |      Number of right shifts required to align $fp\_c$'s significand with the product significand       |
|    $rshiftMax$     | $37$  | $76$  | $163$ | $fp\_c$ maximum right shift count for significant digits (beyond this value, $g$ and $r$ are both $0$) |

##### Unsigned Integer Multiplication

The rule for multiplying two floating-point numbers is to multiply the sign
bits, add the exponent bits (not simply added, as bias must be considered), and
multiply the significands (including the implicit bit and mantissa bits). The
significand multiplication is essentially fixed-point multiplication, which
follows the same principle as unsigned integer multiplication.

Binary vertical multiplication is the original multiplication algorithm, where
an $n$-bit $C=A×B$ vertical method is illustrated. This process generates $n$
partial products, which are then added with staggered alignment.

![Binary vertical method for multiplication](./figure/BinaryVerticalMul.svg)

The multiplication algorithm using the vertical method has significant latency.
Optimization efforts for multiplication operations primarily focus on two
aspects: reducing the number of partial products (e.g., $Booth$ encoding) and
minimizing the latency introduced by adders (e.g., $CSA$ compression).

When computing the multiplication of two floating-point numbers, their
significands are multiplied. Since significands are unsigned, unsigned integer
multiplication suffices for this computation. There are many algorithms for
implementing unsigned integer multiplication, and three of them are compared
below.

Method 1: Directly use the multiplication symbol $×$, letting the synthesis tool
decide.

Method two: Use a vertical multiplication method similar to manual decimal
multiplication. Multiplying two $n$-bit numbers generates $n$ partial products,
which are then compressed using $CSA$ (to be introduced later) into two numbers
for addition.

Method 3: Use $Booth$ encoding to generate $(n+1)/2$ rounded-up partial
products, then compress them into two numbers for addition using $CSA$.

The data in the table are the results of multiplying two 53-bit unsigned
integers (for f64) using the TSMC 7nm process library. The target frequency is
3GHz, with a theoretical cycle time of 333.33ps. However, considering clock
uncertainty and process corner variations, a design margin is reserved for the
backend, leaving approximately 280ps per cycle. Therefore, it is evident that
multiplication cannot be completed within one cycle. In practice, additional
time is required to determine the implicit bit, making it even more impossible
to achieve 53-bit multiplication in a single cycle. Although Method 1 has a
smaller area and shorter latency, it cannot be pipelined, leaving only Methods 2
or 3 as viable options. Method 3 offers shorter latency and a smaller area
compared to Method 2, making it the chosen implementation for unsigned integer
multiplication.

Table: Comparison of Three Algorithms for Unsigned Integer Multiplication

|  Algorithm   | Delay ($ps$) | Area ($um²$) | Pipelining feasibility |
| :----------: | :----------: | :----------: | :--------------------: |
|  Method one  |   $285.15$   |  $1458.95$   |           No           |
|  Method two  |   $320.41$   |  $2426.34$   |          Yes           |
| Method three |   $302.19$   |  $2042.46$   |          Yes           |

##### $Booth$ encoding

The purpose of Booth encoding is to reduce the number of partial products in a
multiplier. Taking the binary unsigned integer multiplication C=A*B as an
example, the Booth encoding algorithm is derived.

The following expression is a general form of unsigned binary integers. To
facilitate subsequent transformations, a $0$ is added at both the beginning and
the end, leaving its value unchanged.

$$ B = 2^{n-1}B_{n-1} + 2^{n-2}B_{n-2} + \ldots + 2B_1 + B_0 + B_{-1}, \quad
B_{-1}=0 $$

After equivalent transformation, adjacent two bits of $1$ cancel out to $0$. For
consecutive $1$s, the least significant $1$ becomes $-1$, and the bit above the
most significant $1$ changes from $0$ to $1$, with all $1$s turning to $0$. This
transformation is known as Booth transformation. It simplifies sequences of
three or more consecutive $1$s, with greater simplification for longer
sequences. However, this transformation does not optimize hardware circuits
because it does not guarantee any partial product will always be $0$. Therefore,
modified Booth encoding is typically used in circuit design to effectively
reduce the number of partial products.

$$ \begin{split} B &= 2^{n-1}B_{n-1} + 2^{n-2}B_{n-2} + \ldots + 2B_1 + B_0 +
B_{-1} \\
&= 2^{n-1}B_{n-1} + 2^{n-2}B_{n-2} + 2^{n-2}B_{n-2} - 2^{n-2}B_{n-2} + \ldots +
2B_1 + 2B_1 - 2B_1 + B_0 + B_0 - B_0 + B_{-1} \\
&= 2^{n-1}(B_{n-1}+B_{n-2}) + 2^{n-2}(-B_{n-2} + B_{n-3}) + \ldots + 2(-B_1 +
B_0) + (-B_0 + B_{-1}) \end{split} $$

Perform an equivalent transformation again, but this time with additional
constraints on $n$. Assuming $n$ is odd, a zero is still appended at the end,
increasing the length to an even number. Then, a zero is prepended at the
highest bit, making the total length $n+2$. This is done to facilitate
subsequent derivations.

$$ \begin{split} B &= 2^nB_n + 2^{n-1}B_{n-1} + 2^{n-2}B_{n-2} + \ldots + 2B_1 +
B_0 + B_{-1} \\
&= -2 × 2^{n-1}B_n + 2^{n-1}B_{n-1} + 2^{n-2}B_{n-2} + 2^{n-2}B_{n-2} -
2^{n-2}B_{n-2} + \ldots \\
&\quad + 2^3B_3 + 2^3B_3 - 2^3B_3 + 2^2B_2 + 2B_1 + 2B_1 - 2B_1 + B_0 + B_{-1}
\\
&= 2^{n-1}(-2B_n + B_{n-1} + B_{n-2}) + 2^{n-2}(-2B_{n-1} + B_{n-2} + B_{n-3}) +
\ldots \\
&\quad + 2^2(-2B_3 + B_2 + B_1) + (-2B_1 + B_0 + B_{-1}) \end{split} $$

After equivalent transformation, it can be observed that the number of terms in
the polynomial expression becomes $(n+1)/2$ (when $n$ is odd). If $n$ is even, a
zero needs to be appended at the end, and two zeros are prepended before the
most significant bit, making the number of terms $n/2+1$ (when $n$ is even).
Combining both odd and even cases, the number of terms in the polynomial
expression is the ceiling of $(n+1)/2$. Starting from the LSB of the original
binary number, groups of three bits are formed (the first group's least
significant bit requires an additional appended bit $0$, and the most
significant bit is padded with one $0$ if $n$ is odd or two $0$s if $n$ is even,
ensuring the padded length is odd). Adjacent groups overlap by one bit (the
highest bit of the lower group overlaps with the lowest bit of the higher
group), forming new polynomial factors. This is the improved Booth encoding
method.

When multiplying two binary numbers, modified Booth encoding of the multiplier
can halve the number of partial products. Let the multiplicand be $A$ and the
multiplier be $B$, with $B_{2i+1}$, $B_{2i}$, and $B_{2i-1}$ representing three
consecutive bits of $X$, where $i$ is a natural number $N$. $PP_i$ denotes the
partial product for each $i$. After applying modified Booth transformation to
$B$ and multiplying by $A$, the Booth encoding and $PP$ truth table are as
shown.

Table: $Booth$ encoding and $PP$ truth table

| $B_{2i+1}$ | $B_{2i}$ | $B_{2i-1}$ | $PP_i$ |
| :--------: | :------: | :--------: | :----: |
|    $0$     |   $0$    |    $0$     |  $0$   |
|    $0$     |   $0$    |    $1$     |  $A$   |
|    $0$     |   $1$    |    $0$     |  $A$   |
|    $0$     |   $1$    |    $1$     |  $2A$  |
|    $1$     |   $0$    |    $0$     | $-2A$  |
|    $1$     |   $0$    |    $1$     |  $-A$  |
|    $1$     |   $1$    |    $0$     |  $-A$  |
|    $1$     |   $1$    |    $1$     |  $0$   |

By evaluating each consecutive three-bit segment of the multiplier, the
corresponding partial product is derived, halving the number of partial
products. This approach treats the multiplier as a quaternary number, hence
termed radix-4 Booth encoding. Multiplication using radix-4 Booth encoding
offers significant optimization over traditional methods, is straightforward to
implement, and meets most application requirements.

In $Booth$ encoding, five types of partial products need to be calculated: $0$,
$A$, $2A$, $-A$, $-2A$. $0$ and $A$ require no computation, $2A$ is obtained by
a one-bit left shift, while $-A$ and $-2A$ require the operation of inversion
plus one. This paper introduces a fast algorithm for handling inversion plus
one.

To simplify the explanation of the principle, we assume computing $f16$ with 11
significant bits, generating 6 partial products. Each partial product is 22 bits
wide, as shown in the figure. The colored positions in the figure are 12 bits
wide, representing $A$ possibly multiplied by $0$, $1$, or $2$. Since the last
partial product's three-bit encoding is $0$xx, its value cannot be negative.
Assuming all other partial products are negative, we invert and add one to each
of them. The colored parts represent the results after inversion only. We place
the added one for the current partial product into the corresponding position of
the next partial product, ensuring the sum of partial products remains unchanged
and avoiding the issue of a carry chain from adding one to the current partial
product. The last partial product is non-negative and does not require this
adjustment.

![Diagram of assuming all partial products are negative and inverted plus
one](./figure/PartialProduct1.svg)

The $1$ in the above figure can first be simplified through summation to obtain
the result shown in the following figure.

![Result after simplifying assuming all partial products are
negative](./figure/PartialProduct2.svg)

If the actual partial product value is positive, the above result needs to be
corrected by adding one to the bit position immediately to the left of the
colored bit and setting the next partial product's tail addition to zero. As
shown in the figure, $Si$ (where $i$ starts from $0$) represents the sign bit of
the $i$-th partial product, transforming it into a general form where the
colored position only computes $0$, $A$, $2A$, $\sim A$, or $\sim 2A$, speeding
up partial product generation.

![Correcting the result when the partial product is
positive](./figure/PartialProduct3.svg)

One additional point to note is that the sum of partial products yields the
multiplication result, but the summation of partial products may also generate
carries. These carries are meaningless for multiplication, but they can cause
erroneous carries when the product is added to a wider number. The correction
method involves adding an extra bit to the most significant bit of the partial
product, as illustrated.

![Partial Product Carry Correction](./figure/PartialProduct4.svg)

This ensures that the carry is correct after summing all partial products. This
concludes the introduction to Booth encoding. Note that the example uses an
11-bit multiplication. While $f16$ and $f64$ have an odd number of significant
digits, $f32$ has an even number, requiring slight differences in zero-padding
the most significant bit. Other steps are similar and thus omitted.

##### $CSA$ Compression

$Carry$-$Save$-$Adder$ is a carry-save adder that compresses $n$ addends into
$m$ addends ($m

Assuming the calculation of adding two binary numbers $A+B$, the truth table for
their sum and carry, where $A[i]+B[i]$ is the decimal result and also the count
of $1$s in $A[i]$ and $B[i]$:

Table: Truth Table for Sum and Carry of $A+B$

| $A[i]$ | $B[i]$ | $A[i] + B[i]$ | $Sum[i]$ | $Car[i]$ |
| :----: | :----: | :-----------: | :------: | :------: |
|  $0$   |  $0$   |      $0$      |   $0$    |   $0$    |
|  $0$   |  $1$   |      $1$      |   $1$    |   $0$    |
|  $1$   |  $0$   |      $1$      |   $1$    |   $0$    |
|  $1$   |  $1$   |      $2$      |   $0$    |   $1$    |

Simplified into the following logical expression:

$Sum = A$ ^ $B$

$Car = A$ & $B$

$Result = A+B = Sum + (Car << 1)$

For three-number addition, the sum is the XOR of two numbers, and the carry
occurs when both numbers are $1$. $(Car << 1)$ reflects that the current bit's
carry propagates to the next bit. This derivation is for clarity; in practice,
generating sum and carry from two addends does not accelerate addition.

Suppose we want to calculate the sum of three numbers $A+B+C$, where the $CSA$
key is to generate the sum and carry, as shown in the truth table:

Table: Truth Table for Sum and Carry of $A+B+C$

| $A[i]$ | $B[i]$ | $C[i]$ | $A[i] + B[i] + C[i]$ | $Sum[i]$ | $Car[i]$ |
| :----: | :----: | :----: | :------------------: | :------: | :------: |
|  $0$   |  $0$   |  $0$   |         $0$          |   $0$    |   $0$    |
|  $0$   |  $0$   |  $1$   |         $1$          |   $1$    |   $0$    |
|  $0$   |  $1$   |  $0$   |         $1$          |   $1$    |   $0$    |
|  $0$   |  $1$   |  $1$   |         $2$          |   $0$    |   $1$    |
|  $1$   |  $0$   |  $0$   |         $1$          |   $1$    |   $0$    |
|  $1$   |  $0$   |  $1$   |         $2$          |   $0$    |   $1$    |
|  $1$   |  $1$   |  $0$   |         $2$          |   $0$    |   $1$    |
|  $1$   |  $1$   |  $1$   |         $3$          |   $1$    |   $1$    |

From the above table, some patterns can be observed. The generation of $Sum[i]$
and $Car[i]$ actually depends only on the sum of $A[i]+B[i]+C[i]$, i.e., the
number of $1$s in $A[i]$, $B[i]$, and $C[i]$. The simplified expression is as
follows:

$Sum = A$ ^ $B$ ^ $C$

$Car = (A$ & $B) \quad | \quad (A$ & $C) \quad | \quad (B$ & $C)$

$Result = A+B+C = Sum + (Car << 1)$

For three-number addition, the sum is the XOR of the three numbers, and the
carry occurs when at least two numbers are $1$. $(Car << 1)$ accounts for the
current bit's carry propagating to the next bit. This method converts
three-number addition into two-number addition with just two XOR gate delays,
significantly saving time, especially for longer bit widths.

Adding four numbers is slightly more complex because when all four are $1$, the
sum is $4$, requiring a carry of $2$. We designate one carry as $Cout$ and the
other as $Car$. The $Cout$ generated from the current four-bit addition is
passed to the next stage as $Cin$. With $Cin$ and the four numbers, the
operation now involves five inputs: $A[i]$, $B[i]$, $C[i]$, $D[i]$, and
$Cin[i]$, producing three outputs: $Sum[i]$, $Cout[i]$, and $Car[i]$. The least
significant bit's $Cin[0]$ is $0$, while other bits' $Cin[i]$ is the $Cout[i-1]$
from the previous bit, as shown in the table.

Table: Truth Table for Sum and Carry of $A+B+C+D$

| $A[i]+B[i]+C[i]+D[i]+Cin[i]$ | $Sum[i]$ | $Cout[i]$ | $Car[i]$ |
| :--------------------------: | :------: | :-------: | :------: |
|             $0$              |   $0$    |    $0$    |   $0$    |
|             $1$              |   $1$    |    $0$    |   $0$    |
|             $2$              |   $0$    |   $1/0$   |  $0/1$   |
|             $3$              |   $1$    |   $1/0$   |  $0/1$   |
|             $4$              |   $0$    |    $1$    |   $1$    |
|             $5$              |   $1$    |    $1$    |   $1$    |

There are many ways to simplify this truth table. One feasible method is
described below. The value of $Sum[i]$ can be easily derived as the XOR of the
five inputs: $Sum[i] = A[i]$^$B[i]$^$C[i]$^$D[i]$^$Cin[i]$. $Car[i]$ and
$Cout[i]$ are more complex. We define $Cout[i]$ to be generated only by the
first three numbers, i.e., when the sum of the first three numbers is greater
than $1$, $Cout[i] = 1$. The table shows the truth table for $Cout[i]$:

Table: Truth Table for $Cout$ Generation of $A+B+C$

| $A[i]+B[i]+C[i]$ | $Cout[i]$ |
| :--------------: | :-------: |
|       $0$        |    $0$    |
|       $1$        |    $0$    |
|       $2$        |    $1$    |
|       $3$        |    $1$    |

$Cout[i]$ can be expressed as: $Cout[i] = (A[i]$^$B[i])?C[i]:A[i]$, while
$Car[i]$ is generated by $D[i]$ and $Cin[i]$, with the table showing the truth
table for $Car[i]$.

Table: Truth table for $Car$ generation from $A+B+C$

| $A[i]+B[i]+C[i]+D[i]$ | $Car[i]$ |
| :-------------------: | :------: |
|          $0$          |  $D[i]$  |
|          $1$          | $Cin[i]$ |
|          $2$          |  $D[i]$  |
|          $3$          | $Cin[i]$ |

$Car[i]$ can be expressed as: $Car[i] = (A[i]$ ^ $B[i]$ ^ $C[i]$ ^ $D[i]) ?
Cin[i] : D[i]$. Specifically, when $(A[i]$ ^ $B[i]$ ^ $C[i]$ ^ $D[i]) = 1$,
$A[i]+B[i]+C[i]+D[i] = 1/3$, and $Cin[i] = 1$ will generate a carry. When
$(A[i]$ ^ $B[i]$ ^ $C[i]$ ^ $D[i]) = 0$, $A[i]+B[i]+C[i]+D[i] = 0/4$. Here,
$D[i] = 0$ indicates $A[i]+B[i]+C[i]+D[i] = 0$, and adding $Cin$ will not
produce a carry, while $D[i] = 1$ indicates $A[i]+B[i]+C[i]+D[i] = 4$, and
adding $Cin$ will generate a carry. Based on the above derivation, the
expression for $CSA4\_2$ is as follows:

Sum[i] = A[i] ^ B[i] ^ C[i] ^ D[i] ^ Cin[i], Cin[i] = Cout[i-1], Cin[0] = 0

$Cout[i] = (A[i]$ ^ $B[i])?C[i]:A[i]$

$Car[i] = (A[i]$ ^ $B[i]$ ^ $C[i]$ ^ $D[i])?Cin[i]:D[i]$

$Result = A+B+C+D = Sum + (Car << 1)$

Using the $TSMC7nm$ process library, a comprehensive comparison of delay and
area was conducted for different input XOR gates, $CSA3\_2$, and $CSA4\_2$. The
synthesis results for different input XOR gates are shown in the table.

Table: Synthesis Results of Different Input XOR Gates

|     $106$ bits      | Delay ($ps$) | Area ($um²$) |
| :-----------------: | :----------: | :----------: |
|       $A$^$B$       |   $13.74$    |  $38.66880$  |
|     $A$^$B$^$C$     |   $23.01$    |  $63.09120$  |
|   $A$^$B$^$C$^$D$   |   $24.69$    |  $87.51360$  |
| $A$^$B$^$C$^$D$^$E$ |   $37.21$    |  $99.72480$  |

The synthesis results of $CSA3\_2$ and $CSA4\_2$ are shown in the table.

Table: Synthesis Results of $CSA3\_2$ and $CSA4\_2$

| $106$ bits | Delay ($ps$) | Area ($um²$) |
| :--------: | :----------: | :----------: |
| $CSA3\_2$  |   $23.23$    | $104.42880$  |
| $CSA4\_2$  |   $40.63$    | $237.86881$  |

It can be seen that although $CSA4\_2$ theoretically has a delay of three XOR
gates and $CSA3\_2$ theoretically has a delay of two XOR gates, in actual
physical implementation, $CSA4\_2$ is only slightly faster than two levels of
$CSA3\_2$. Therefore, $CSA3\_2$ should be used whenever possible, unless one
level of $CSA4\_2$ can replace two levels of $CSA3\_2$, such as in $4->2$
compression or $8->2$ compression.

##### CSAn_2

For two unsigned integer multiplications using Booth encoding, the number of
partial products is ceil((n+1)/2). To ensure correct carry propagation, the
partial product bit width is extended by one bit. The number and bit width of
partial products for each data format are listed in the table.

Table: Partial Product Count and Bit Width for Different Data Formats

| Data Format | Number of significant digits | Number of partial products | Partial product bit width |
| :---------: | :--------------------------: | :------------------------: | :-----------------------: |
|   $fp16$    |             $11$             |            $6$             |           $12$            |
|   $fp32$    |             $24$             |            $13$            |           $25$            |
|   $fp64$    |             $53$             |            $27$            |            54             |

Following the principle of prioritizing $CSA3\_2$ unless one level of $CSA4\_2$
can replace two levels of $CSA3\_2$, the number of $CSA3\_2$ and $CSA4\_2$
stages used for each data format is listed in the table.

Table: Partial Product $CSA$ Compression Process for Different Data Formats

| Data Format | Number of $CSA3\_2$ Stages | $CSA4\_2$ Stages | Process ($->$ denotes $CSA3\_2$, $-->$ denotes $CSA4\_2$) |
| :---------: | :------------------------: | :--------------: | :-------------------------------------------------------: |
|   $fp16$    |            $1$             |       $1$        |                        $6->4-->2$                         |
|   $fp32$    |            $3$             |       $1$        |                     $13->9->6->4-->2$                     |
|   $fp64$    |            $3$             |       $2$        |                  $27->18->12->8-->4-->2$                  |

##### Exponent processing and right shift

Following conventional methods, if the exponent relationship between the product
of $fp\_a$ and $fp\_b$ and the exponent of $fp\_c$ is unknown, the smaller
exponent must be right-shifted, similar to floating-point addition. This would
require both the significand of the $fp\_a$ and $fp\_b$ product and the
significand of $fp\_c$ to potentially shift right, necessitating two shifters
and increasing area. Additionally, waiting for the $fp\_a$ and $fp\_b$ product
to be computed before right-shifting its significand increases circuit latency.
An alternative algorithm avoids using two shifters and reduces latency by
parallelizing the computation with the $fp\_a$ and $fp\_b$ product.

The exponent bits are treated as unsigned numbers, but there is an exponent bias
between them and the actual exponent. Additionally, the $denormal$ case must be
considered. Let $E\_fix$ denote the exponent bits after handling the $denormal$
case, and $E\_bit$ denote the original exponent bits. When all bits of $E\_bit$
are 0, $E\_fix = 1$; otherwise, $E\_fix = E\_bit$.

$$ E\_real = E\_fix - bias, \quad bias = (1 << (exponentWidth - 1)) - 1 $$

In the above equation, the true exponent $E\_real$ equals $E\_fix$ minus a bias
value $bias$, where $exponentWidth$ is the width of $E\_bit$, and $bias$ equals
the value where the highest bit of $E\_bit$ is $0$ and all other bits are $1$.
Without considering the carry or borrow of the significand product, the true
exponent result $Eab\_real$ of multiplying $fp\_a$ and $fp\_b$ is given by:

$$ Ea\_real = Ea\_fix + Eb\_fix - 2 × bias $$

The calculation formula for the binary exponent result $Eab\_bit$ of the
multiplication of $fp\_a$ and $fp\_b$ is shown below:

$$ Eab\_bit = Cat(0.U, Ea\_fix + \&amp;Eb\_fix).asSInt - bias.S $$

The operation of $+$& extends the result of $Ea\_fix + Eb\_fix$ by one bit to
retain the carry. The carry is preserved because a bias value will be subtracted
later, and without retaining the carry, the result would be incorrect.
Additionally, subtracting the bias might result in a negative value, so another
bit is extended by appending a 0 at the highest bit. Finally, the bias $bias$ is
subtracted, yielding the binary exponent result $Eab\_bit$ for the
multiplication of $fp\_a$ and $fp\_b$ without considering the carry or borrow
from the significand product. Then, we construct an exponent $Eab$ with the
following value:

$$ Eab = Eab\_bit + rshiftBasic.S $$

Assuming the binary exponent result of multiplying $fp\_a$ and $fp\_b$ is $Eab$,
to ensure lossless precision when adding the significant digits of $fp\_a \times
fp\_b$ and $fp\_c$, both addends are extended in width. The significant digits
of $fp\_c$ are extended to $3 \times significandWidth + 4$, with the bit
distribution shown in the figure. Here, $g0$, $r0$, $g1$, and $r1$ are used to
preserve the $guard$ and $round$ bits during right-shifting:

![fp_c significant digit extension bit
distribution](./figure/fp_c_Significand.svg)

As shown above, the significand of $fp\_c$ is $significandWidth+2$ bits wider
than the product of the significands of $fp\_a$ and $fp\_b$. Since the product
result has two digits before the decimal point, aligning it as $1$.xxx requires
$significandWidth+3$ bits, which explains why $rshiftBasic =
significandWidth+3$.

Let $fp\_c\_significand\_cat0 = Cat(fp\_c\_significand, 0.U(2 \times
significandWidth + 4))$, where $fp\_c\_significand$ is the significand of
$fp\_c$. If $Ec\_fix = Eab = Eab\_bit + rshiftBasic.S$,
$fp\_c\_significand\_cat0$ is exactly $significandWidth + 3$ larger than
$Eab\_bit$, so no right shift is needed for alignment. If $Ec\_fix > Eab$,
theoretically $fp\_c\_significand\_cat0$ would require a left shift, but due to
the presence of $g0$ and $g1$ as buffers and the fact that lower bits cannot
generate carry (only affecting rounding), no actual left shift is needed. If
$Ec\_fix < Eab$, $fp\_c\_significand\_cat0$ must be right-shifted by
$rshift\_value = Eab - Cat(0.U, Ec\_fix).asSInt$. Since $rshift\_value$ is
derived from the addition of multiple numbers, its LSB is computed first. Thus,
during right-shifting, the LSB of $rshift\_value$ is first used as the Mux
select signal, followed by higher bits. The shifting process must compute
$guard$, $round$, and $sticky$ (collectively $grs$). For $guard$ and $round$,
these positions are already preserved during bit-width extension, requiring no
additional computation. For $sticky$, two methods exist: (1) Extend the
bit-width further to store shifted-out bits and compute $sticky$ after all
shifts, or (2) Compute $sticky$ during shifting based on Mux select signals.
Method 2 offers lower latency than Method 1. Below is the design code for Method
2:

```scala
/**
 * 使用Mux进行移位，先用最低位，输出位宽为srcValue + 1(Sticky)
 */
def shiftRightWithMuxSticky(srcValue: UInt, shiftValue: UInt): UInt = {
  val vecLength  = shiftValue.getWidth + 1
  val res_vec    = Wire(Vec(vecLength,UInt(srcValue.getWidth.W)))
  val sticky_vec = Wire(Vec(vecLength,UInt(1.W)))
  res_vec(0)    := srcValue
  sticky_vec(0) := 0.U
  for (i <- 0 until shiftValue.getWidth) {
    res_vec(i+1) := Mux(shiftValue(i), res_vec(i) >> (1<<i), res_vec(i))
    sticky_vec(i+1) := Mux(shiftValue(i), sticky_vec(i) | res_vec(i)((1<<i)-1,0).orR,
    sticky_vec(i))
  }
  Cat(res_vec(vecLength-1),sticky_vec(vecLength-1))
}
```

There is another method to speed up the right shift. The bit width of
$rshift\_value$ is $exponentWidth+1$, while the width of
$fp\_c\_significand\_cat0$ is $3*significandWidth+4$. There may be overflow bits
in $rshift\_value$. For example, using a 5-bit number to right-shift a 7-bit
number, $a(6,0) >> b(4,0)$, the maximum value of the third bit in $b$ is $7$,
which is sufficient for the bit width of $a$. Therefore, if the upper two bits
of $b$ contain any non-zero value, the right-shift result of $a$ will be zero.
The right-shift result can be simplified to $Mux(b(4,3).orR,0.U, a(6,0) >>
b(2,0))$. The table below lists the bit widths of $rshift\_value$ used for three
floating-point data formats.

Table: Bit Width of $rshift\_value$ Used for Different Floating-Point Formats

| Data Format | $fp\_c\_significand\_cat0$ bit width | Bit Width of $rshift\_value$ | Bit width used |
| :---------: | :----------------------------------: | :--------------------------: | :------------: |
|    $f16$    |                 $37$                 |             $6$              |      $6$       |
|    $f32$    |                 $76$                 |             $9$              |      $7$       |
|    $f64$    |                $163$                 |             $12$             |      $8$       |

There are three cases based on the value of $rshift\_value$: $rshift\_value <=
0$ means no right shift is needed, and the $sticky$ result is $0$;
$rshift\_value > rshiftMax$ means the right shift result is $0$, and the
$sticky$ result is $fp\_c\_significand\_cat0$ or reduced; $0 < rshift\_value <=
rshiftMax$ means the right shift result and $sticky$ are calculated by
$shiftRightWithMuxSticky$.

Thus, this section has covered the methods for exponent processing, the design
of the right shifter, and the handling of $grs$ during the right-shift
operation.

##### Significand addition

The $rshift\_result$ of the significand of $fp\_c$ after right-shifting must be
added to the two results compressed by $CSAn\_2$. Since the signs of $fp\_c$ and
$fp\_a \times fp\_b$ may differ, subtraction is performed when they are
opposite, and the result may be negative. To determine the sign, an additional
sign bit is appended. $fp\_c\_rshiftValue\_inv$ selects either $rshift\_result$
(with a $0$ sign bit) or its negation (with a $1$ sign bit) based on whether the
signs differ. Thus, $fp\_c\_rshiftValue\_inv$ is added to the two results
compressed by $CSAn\_2$. However, during subtraction, $fp\_c\_rshiftValue\_inv$
only negates $rshift\_result$, and a $+1$ is required at the least significant
bit when all right-shifted $grs$ bits are $0$. This $+1$ is placed in the
$carry$ bit of the two results compressed by $CSAn\_2$, as the $carry$ bit is
always $0$, saving adder usage and area. The three numbers have different bit
widths: the right-shifted significand of $fp\_c$ has a width of $3 \times
significandWidth + 4$, while the two results compressed by $CSAn\_2$ have a
width of $2 \times significandWidth + 1$ (the $+1$ accounts for the partial
product extension to ensure correct carry). The strategy for summing these three
numbers involves first compressing the lower $2 \times significandWidth + 1$
bits of the $CSAn\_2$ results and the lower $2 \times significandWidth$ bits of
$rshift\_result$ (with a $0$ appended to form $2 \times significandWidth + 1$
bits) using $CSA3\_2$ compression. The two compressed results are then summed,
denoted as $adder\_low\_bits$. Simultaneously, the higher $significandWidth + 4$
bits of $rshift\_result$ are incremented by $1$. The final result selects either
the higher $significandWidth + 4$ bits of $fp\_c\_rshiftValue\_inv$ or its
incremented version based on whether the highest bit of the lower $2 \times
significandWidth + 1$ sum is $1$, denoted as $adder\_high\_bits$.

Additionally, consider the inversion and increment by one of the right-shifted
$grs$ during subtraction. The final significand addition result $adder$
(including the right-shifted $grs$) consists of: $adder\_high\_bits$,
$adder\_low\_bits$, and the right-shifted $grs$ (inverted and incremented by one
for subtraction). Since $adder$ may be negative, an extra $1$-bit is extended
solely for sign determination of $adder$, which is later discarded. $adder\_inv$
inverts $adder$ when it is negative and removes this sign bit.

##### $LZD$, left shift, rounded and unrounded mantissa results

After computing $adder\_inv$, a leading-zero detection must be performed on
$adder\_inv$ to determine the number of left shifts required, thereby
normalizing and rounding the mantissa result.

When performing LZD on $adder\_inv$, there is an issue of exponent limitation.
Let $E\_greater$ be $Eab$ (the exponent result from multiplying $fp\_a$ and
$fp\_b$). The left shift amount cannot exceed $E\_greater$ because the exponent
result would already be all zeros at that point. To address this, similar to the
floating-point adder, a $mask$ is used during left shift to limit the shift
amount.

For cases where $adder$ is negative, $-adder$ should be the inversion of $adder$
plus $1$. Since adding $1$ would create a long carry chain, only the inversion
is performed, and then the $LZD$ of $adder\_inv$ is calculated. This may result
in a one-bit deviation. When the inversion of $adder$ ends with consecutive
$1$s, adding $1$ would cause a carry at the highest bit. To resolve this one-bit
deviation, a trailing zero detection ($TZD$) is performed on $adder$. If $LZD +
TZD$ equals the width of $adder$, the inversion of $adder$ ends with consecutive
$1$s, requiring a correction to the left-shift result. After the left-shift
correction, the unrounded result is obtained, and adding $1$ to it yields the
rounded result.

##### Final result

The sign bit result is determined based on the sign of $adder$, while the
calculation of $grs$ requires combining both the right-shift process in step
five and the left-shift process in step seven. The rounding strategy employs
$after \quad rounding$. To detect $underflow$, an additional set of $grs$
specifically for $underflow$ checking is used. Based on the rounding mode and
$grs$, the necessity of rounding is determined, selecting the final mantissa
result. The exponent result is derived according to the rounding outcome.

When input operands contain special values such as $NaN$, infinity, or zero, the
result is calculated separately. Depending on the actual input values, either
the special result or the normal result is selected. Except for the
divide-by-zero flag, all four other flag results can be generated.

#### Vector single-precision format algorithm

The main design principle for vector operations is to share hardware where
timing requirements are met.

During Booth encoding, $f16$ generates 6 partial products (pp), $f32$ generates
13 pp, and $f64$ generates 27 pp. Thus, the 27 pp positions generated by $f64$
during Booth encoding can accommodate two sets of 13 pp from $f32$, and
similarly, the 13 pp positions from $f32$ can hold two sets of 6 pp from $f16$.
This allows continued sharing of a single $CSA\_27to2$ compression unit. The
vector shared Booth encoding is illustrated in the figure.

![Vector Shared Booth Encoding Diagram](./figure/VectorBooth.svg)

During the right shift of the $fp\_c$ mantissa, one of the right shifts for the
mantissas in $f64$ and $f32$ can share a single shifter, while the other
shifters remain independent.

The $CSA\_3to2$ is also shared, with the third operand derived from the
right-shifted result of the $fp\_c$ mantissa. The right-shifted results of two
$f32$ or four $f16$ mantissas are concatenated and then compressed with the two
operands from the shared $Booth$ encoding for $3\_2$ compression.

The adder after compression is also shared. Different formats are assigned
different bits, and the bits are separated to prevent low-bit carries from
affecting high-bit results.

The shared logic for $LZD$, $TZD$, and the left shifter is similar to the right
shifter, with $f64$ and $f32$ sharing one unit while others remain independent.

#### Vector Mixed-Precision Format Algorithm

There are two types of vector mixed-precision format calculations:

(1) $2$ instances of $fp32 = fp16 × fp16 + fp32$;

(2) One $fp64 = fp32 × fp32 + fp64$.

For two multipliers of the same width, the essence is still adding exponents and
multiplying significant bits. Unlike floating-point addition, there's no need to
first convert their formats to match the result's format. Simply extending the
bit width suffices—padding the exponent's high bits with zeros and the
mantissa's low bits with zeros to align with high-precision floating-point
operands. After alignment, computation proceeds according to the
single-precision format.

### Vector floating-point division algorithm

Division is one of the most representative floating-point functions in modern
processors. There are two main algorithms for computing division in hardware:
digit iteration algorithms based on subtraction with linear convergence, and
multiplicative algorithms based on multiplication with quadratic convergence.
The subtraction-based digit iteration algorithms are more energy-efficient and
require less area. Subsequent references to digit iteration in this paper refer
to subtraction-based digit iteration. For common floating-point
precisions—double, single, and half—digit iteration methods are significantly
faster. In digit iteration division, the most critical aspect is the selection
of quotient bits, where each iteration yields one bit of the quotient. To
implement a simple $Radix-4$ selection function independent of the divisor, the
divisor must be adjusted to a value sufficiently close to 1. This scaling is
performed before digit iteration.

Digital iterative algorithms are widely used in high-performance processors due
to their excellent trade-offs in performance, area, and power consumption. This
paper is based on the $SRT$ division ($Sweeney-Robertson-Tocher Division$),
employing a $Radix-64$ floating-point division algorithm that computes $6$
quotient bits per cycle. To reduce overhead, each $Radix-64$ iteration consists
of three $Radix-4$ iterations. Speculative algorithms are used between
consecutive $Radix-4$ iterations to reduce latency.

#### Scalar floating-point division algorithm

The $Radix-64$ scalar floating-point division algorithm implemented in this
paper has low latency for double-precision, single-precision, and half-precision
floating-point division when both input operands and results are normalized
numbers, with latencies of $11$, $6$, and $4$ cycles, respectively, including
scaling and rounding cycles. In cases where input operands or results include
denormalized numbers, one or two additional normalization cycles are required.

The exponent result can be easily derived, with the focus being on the division
of significands. The significand divider performs floating-point division of the
dividend significand $x$ by the divisor significand $d$ to obtain the
significand quotient $q = x/d$. Both operands need to be normalized numbers, $x,
d ∈ [1, 2)$. Denormalized operands are also permitted, with normalization
applied before the digital iteration. If both operands are normalized within
$[1, 2)$, the result lies within $[0.5, 2)$. Thus, two bits to the right of the
least significant bit ($LSB$) of the quotient are required for rounding, namely
the guard bit and the rounding bit.

When the result is normalized, the guard bit is used for rounding, with $q ∈ [1,
2)$. When the result is unnormalized, the rounding bit is used for rounding,
with $q ∈ [0.5, 1)$. In the latter case, the result is left-shifted by $1$ bit,
and the guard and rounding bits become the $LSB$ and guard bit of the normalized
result, respectively. To simplify rounding, the result is forced to $q ∈ [1,
2)$. Note that $q < 1$ only occurs when $x < d$. This condition is detected
early, and the dividend is left-shifted by $1$ bit, making $q = 2 × x/d$ and $q
∈ [1, 2)$. Note that the exponent result must be adjusted accordingly.

The algorithm used for division is the $Radix-4$ digit iteration algorithm, with
three iterations per cycle. The quotient's signed-digit representation uses the
digit set {$−2, −1, 0, +1, +2$}, meaning the radix $r = 4$ and the digit set $a
= 2$. In each iteration, a digit of the quotient is obtained through a selection
function. To have a quotient digit selection function independent of the
divisor, the divisor must be scaled to be close to $1$. Naturally, to maintain
result correctness, the dividend must be scaled by the same factor as the
divisor.

Using the radix$-4$ algorithm, each iteration yields 2 bits of the quotient.
Since three radix$-4$ iterations are performed per clock cycle, 6 quotient bits
are obtained per cycle, equivalent to a $Radix-64$ divider. Additionally, note
that the first quotient bit of the integer result can only take values {$+1,
+2$}, and its computation is much simpler than that of the remaining bits. By
computing it in parallel with operand prescaling, one single-precision
floating-point iteration is saved. On the other hand, there is an early
termination mode for exceptional operands. Early termination is triggered when
any operand is $NaN$, infinity, or zero, or when dividing by a power of 2 with
both operands normalized. In the latter case, the result is obtained simply by
reducing the exponent of the dividend. The main features of the $Radix-64$
divider are as follows:

(1) Pre-scaling of divisor and dividend.

(2) The first quotient digit is executed in parallel with pre-scaling.

(3) Compare the scaled dividend and divisor, and left-shift the dividend to
obtain a result in the range $[1, 2)$.

(4) Three $Radix-4$ iterations per cycle, processing $6$ bits each cycle.

(5) Supports half-precision, single-precision, and double-precision.

(6) Denormal number support requires an additional cycle for normalization
before iteration.

(7) Early termination for exceptional operands.

##### Digit-Recurrence Division Algorithm

Digit-recurrence division is an iterative algorithm where each iteration
computes a $radix-r$ quotient digit $q_{i+1}$ and a remainder. The remainder
$rem[i]$ is used to obtain the next $radix-r$ digit. For fast iteration, the
remainder is stored in a carry-save adder using a signed-digit redundant
representation. This paper selects a $radix-2$ signed-digit representation for
the remainder, consisting of a positive and a negative number. For radix $r =4$,
the following expression represents the partial quotient before the $i$-th
iteration:

$$ Q[i] = \sum_{j=0}^i q_j × 4^{-j} $$

After scaling the divisor to around 1, the $radix-4$ algorithm describes the
quotient and remainder as follows:

$$ q_{i+1} = SEL(\widehat{rem}[i]) $$

$$ rem[i + 1] = 4 × rem[i] - d × q_{i+1} $$

Here, $\widehat{rem}[i]$ is an estimate of the remainder $rem[i]$, which
consists of only a few bits. For this algorithm, it has been determined that
only the 6 most significant bits (MSB) of the remainder are needed, i.e., 3
integer bits and 3 fractional bits. Then, each iteration extracts a quotient bit
from the current remainder and computes a new remainder for the next iteration.
The formula below calculates the number of iterations $it$:

$$ it = [n/log_2(4)] $$

Here, $n$ is the number of bits in the result, including those needed for
rounding. The division latency, i.e., the number of cycles, is directly related
to the number of iterations. It also depends on the number of iterations
performed per cycle. Three iterations per cycle have been implemented to achieve
$6$ bits per cycle, equivalent to $Radix-64$ division. The cycles ($cycles$)
required for normalized floating-point numbers are determined by the following
formula. In addition to the ($it/3$) cycles needed for iterations, there are two
extra cycles for operand pre-scaling and rounding.

$$ cycles = [it/3] + 2 $$

Some examples of digital iterative division, including the $Radix-4$ algorithm,
can be found in [$38$]. A simple implementation is shown in the figure. Note
that only the most significant bit of the remainder is used to select the
quotient bit. The remainder is updated using a carry-save adder ($CSA$) and
stored in a redundant representation. The quotient bit selection then requires
the $t$ most significant bits of the remainder to be summed in a carry-propagate
adder ($CPA$) to obtain its non-redundant representation. However, this
implementation is too slow. To accelerate the iteration loop, speculative
algorithms must be employed for both the remainder computation between
iterations and the quotient bit selection.

![Simple Implementation of Radix-64 Composed of Three Radix-4
Stages](./figure/Radix-64.svg)

##### Operand pre-scaling

During prescaling, the divisor is scaled to a value close to 1, making the
selection of quotient digits independent of the divisor. For the $radix-4$
algorithm, scaling the divisor to the range $[1 − 1/64, 1+1/8]$ is sufficient.
As shown in the prescaling factor truth table, only three bits determine the
scaling factor. Note that during prescaling, the divisor should be scaled by a
factor of $1-2$. The dividend should also be scaled by the same factor.

Table: Truth Table of Pre-Scaling Factor

| $0.1$xxx | Pre-scaling factor |
| :------: | :----------------: |
|  $000$   |    $1+1/2+1/2$     |
|  $001$   |    $1+1/4+1/2$     |
|   010    |    $1+1/2+1/8$     |
|  $011$   |     $1+1/2+0$      |
|  $100$   |    $1+1/4+1/8$     |
|  $101$   |     $1+1/4+0$      |
|  $110$   |     $1+0+1/8$      |
|  $111$   |     $1+0+1/8$      |

##### Integer Quotient Calculation

While computing the integer quotient, the following data is provided for the
digit iteration steps (each digit iteration performs three $radix-4$ operations,
corresponding to the $s0$, $s1$, and $s2$ stages):

(1) Redundant remainder in carry-save representation: $f\_r\_s$, $f\_r\_c$.

(2) Pre-scaled divisor: $divisor$.

(3) Provides a 6-bit remainder result for the quotient selection in the $s0$
stage of the first digital iteration.

(4) Provides a 7-bit remainder result for the quotient selection in the $s1$
stage of the first digit iteration.

###### Digital iteration

The actual implementation of the floating-point divider requires executing three
$radix-4$ iterations per cycle. Conventional sequential iteration three times is
too slow to meet timing requirements, so the logic has been optimized. The
figure illustrates the block diagram of the digit-recurrence loop.

![Digit Iteration Optimization
Algorithm](./figure/DigitalIterativeOptimizationAlgorithm.svg)

(1) Process the divisor to obtain five possible quotient selection results,
requiring the use of divisor multiples (only negate when the quotient is
negative).

(2) In the $s0$ stage, four $CSA$ modules are used (not required when the
quotient is $0$) to predictively compute the five remainder redundant
representations needed for the $s1$ stage in parallel during $s0$.

(3) In the $s0$ stage, using the five remainder redundant representations
calculated in the second step, predictively compute five 7-bit remainder results
for the $s2$ stage.

(4) In the $s0$ stage, the quotient for the $s0$ stage is selected based on the
6-bit remainder result in the input signal. The quotient is represented using a
5-bit one-hot code.

(5) Based on the quotient from stage $s0$, select the redundant remainder
representation needed for stage $s1$, and predictively choose one of the five
7-bit remainder results calculated in step three for stage $s2$.

(6) In the $s1$ stage, four $CSA$ modules are used (not required when the
quotient is $0$), and the five remainder redundant representations needed for
the $s2$ stage are predictively calculated in parallel.

(7) In the $s1$ stage, predictively perform the quotient selection for the $s1$
stage based on the $7$-bit remainder result from the input signal, the divisor
multiples used for the five quotient selection results, and the quotient from
the $s0$ stage.

(8) Based on the quotient from stage $s1$, select the redundant remainder
representation required for stage $s2$.

(9) In the $s2$ stage, four $CSA$ modules are used (not required when the
quotient is $0$) to predictively compute the five redundant remainder
representations needed for the next digit iteration in the $s0$ stage in
parallel.

(10) In the s2 stage, predictively compute five possible results for the 6-bit
remainder required in the s0 stage and the 7-bit remainder required in the s1
stage of the next digit iteration.

(11) In the $s2$ stage, based on the $7$-bit remainder result selected for the
$s2$ stage in the fifth step, the divisor multiples used for the five quotient
selection results, and the quotient from the $s1$ stage, the quotient for the
$s2$ stage is predictively selected.

(12) Based on the quotient selection result from the $s2$ stage, the following
are selected for the next digit iteration: the carry-save representation of the
redundant remainder, the 6-bit remainder result required for the $s0$ stage, and
the 7-bit remainder result required for the $s1$ stage.

Since the divisor's multiple is only inverted in the first step without $+1$,
there will be a deviation in the remainder calculation. Correction logic is
added during the quotient selection process to rectify this. The table below
shows the standard quotient selection function, and the subsequent table
presents the quotient selection function after logical correction.

Table: Standard Quotient Selection Function

|  $4 × rem[i]$   | $q_{i+1}$ |
| :-------------: | :-------: |
|  $[13/8,31/8]$  |   $+2$    |
|  $[4/8,12/8]$   |   $+1$    |
|  $[-3/8,3/8]$   |    $0$    |
| $[-12/8,-4/8]$  |   $-1$    |
| $[-32/8,-13/8]$ |   $-2$    |

Table: Quotient Selection Function After Logical Correction

|  $4 × rem[i]$   | $carry$ | $q_{i+1}$ |
| :-------------: | :-----: | :-------: |
|     $31/8$      |   $1$   |   $+2$    |
|  $[13/8,30/8]$  |    -    |   $+2$    |
|     $12/8$      |   $0$   |   $+2$    |
|     $12/8$      |   $1$   |   $+1$    |
|  $[4/8,11/8]$   |    -    |   $+1$    |
|      $3/8$      |   $0$   |   $+1$    |
|      $3/8$      |   $1$   |    $0$    |
|  $[-3/8,2/8]$   |    -    |    $0$    |
|     $-4/8$      |   $0$   |    $0$    |
|     $-4/8$      |   $1$   |   $-1$    |
| $[-12/8, -5/8]$ |    -    |   $-1$    |
|     $-13/8$     |   $0$   |   $-1$    |
|     $-13/8$     |   $1$   |   $-2$    |
| $[-32/8,14/8]$  |    -    |   $-2$    |

Convert the redundant remainder representation of the iteratively output digits
back to a standard remainder. Use $On$ $the$ $Fly$ $Conversion$ to compute both
the quotient and quotient minus one, calculate two sets of $grs$ and the signal
for whether rounding up is needed, determine the selection signal for choosing
between the quotient or quotient minus one, and finally select the correct
quotient result. Perform rounding using the correct quotient result and its
corresponding rounding-up signal.

###### Denormal numbers and early termination

(1) The input contains denormal numbers. The significand of a denormal number is
less than $1$ and cannot be pre-scaled together with normal numbers. Therefore,
an additional cycle is added to normalize the significand of denormal numbers
while simultaneously adjusting their exponents.

(2) The result is a denormal number. The quotient result after digit iteration
is greater than 1, which does not meet the denormal significand range. An
additional cycle is required to right-shift the quotient result for
normalization.

(3) Early termination occurs in two scenarios: when the result is $NaN$,
infinity, or exact $0$, computation can terminate early and output the result
since this information is available in the first cycle, allowing the division
result to be output in the second cycle; when the divisor is a power of $2$, its
significand $=1$, and division only requires processing the exponent of the
dividend, skipping the digit iteration phase, enabling the division result to be
output as early as the second cycle. However, additional cycles are still needed
if the dividend or result is a denormal number.

#### Vector floating-point division algorithm

For vector floating-point division, the RISC-V vector instruction set extension
does not support mixed-precision floating-point division, thus only the
following needs to be supported:

(1) 1 f64 = f64 + f64;

(2) $2$ $f32 = f32 + f32$;

(3) $4$ $f16 = f16 + f16$.

Considering that vector division involves multiple division computations
simultaneously, and early termination can cause asynchronous output of results
unless all cases terminate early under the same conditions, the early
termination mechanism is disabled for vector division. If early termination
occurs, the result is temporarily stored internally and output simultaneously
with other division results.

To unify timing, the divider's cycle count is standardized to the worst-case
scenario, i.e., when the input contains denormal numbers and the output also
contains denormal numbers. Other cases that could produce results faster are
internally buffered until the standardized cycle count is reached before
outputting the result.

The main design employs resource reuse, with the following data reuse in the
non-numeric iteration module:

(1) $1$ $f64/f32/f16 = f64/f32/f16 + f64/f32/f16$;

(2) 1 $f32/f16 = f32/f16 + f32/f16$;

(3) $2$ $f16$ values $= f16 + f16$.

A total of 4 signal groups are used to achieve the functionality of 7 division
groups.

Since the digital iteration module is a critical path with significant timing
pressure, achieving high reuse with non-digital iteration modules is not
feasible without compromising timing requirements. Therefore, a partial reuse
design is implemented for the digital iteration module:

(1) The interface consists of four sets of quotients and redundant remainders.

(2) The $s0$ stage uses $7$ sets of $CSA$ and $7$ sets of prediction, with $4$
sets of quotient selection.

(3) Stages $s1$ and $s2$ utilize $4$ sets of $CSA$, $4$ sets of prediction, and
$4$ sets of quotient selection.

Registers also adopt resource reuse. For divisor, redundant remainder, quotient,
and other registers, the bit width is allocated based on the maximum required by
$4$ $f16$, $2$ $f32$, or $1$ $f64$.

## Hardware Design

### Vector Floating-Point Adder

#### Scalar single-precision floating-point adder

A scalar single-precision floating-point adder is designed based on the improved
dual-path floating-point addition algorithm, with its hardware implementation
architecture shown in the figure.

![Scalar Single-Precision Floating-Point Adder Architecture
Diagram](./figure/ScalarSinglePrecisionFloating-pointAdder.svg)

The two input operands on the left are $fp\_a$ and $fp\_b$, while $fp\_c$ on the
right represents the addition result. $fflags$ is a 5-bit exception flag, and
$rm$ is the rounding mode, with five modes represented by 3 bits. When $is\_sub$
is 0, $fp\_c = fp\_a + fp\_b$ is computed; when $is\_sub$ is 1, $fp\_c = fp\_a -
fp\_b$ is computed. The difference between floating-point addition and
subtraction lies only in the sign bit of $fp\_b$, so minor adjustments to
$fp\_b$'s sign bit enable the floating-point adder to support both operations.
The overall design consists of three parts: the $far$ path, the $close$ path,
and the exception path.

The far path first performs two parallel normalized exponent subtractions with
significand right shifts, handling the cases where Efp_a ≥ Efp_b and Efp_b ≥
Efp_a separately. The correct right-shift result is selected based on the
magnitude relationship between Efp_a and Efp_b and sent to the FS0 and FS1
significand adders. For subtraction, the far path sets EA as the larger exponent
minus one, while for addition, EA is the larger exponent. This ensures the
significand addition result falls within the range [1,4). During the right
shift, two sets of grs are computed: grs_normal for rounding when the value is
in [1,2), and grs_overflow for rounding when the value is in [2,4). Finally,
based on the FS0 result and rounding mode, either FS0 or FS1 is selected as the
significand result, and either EA or EA+1 is chosen as the exponent result. The
sign bit result is determined by the exponent magnitude. The flag results
indicate overflow if EA+1 is all ones and inexactness based on grs. The far path
does not generate divide-by-zero, invalid operation, or underflow flags.

The $close$ path uses four significant-digit adders, $CS0$, $CS1$, $CS2$, and
$CS3$, to handle significant-digit subtraction for the cases where $Efp\_a =
Efp\_b$, $Efp\_a = Efp\_b + 1$, and $Efp\_a = Efp\_b – 1$. Based on the $CS0$
result and $grs$, four one-hot selection signals, $sel\_CS0$, $sel\_CS1$,
$sel\_CS2$, and $sel\_CS3$, are generated. A four-input one-hot multiplexer
($Mux1H$) selects one result, which is ORed with the left-shifted $mask$. A
priority left shifter then normalizes the mantissa, outputting the $lzd$ value
during the shift. The exponent result is $EA – lzd$, and the mantissa result is
chosen between the normalized mantissa and $CS4$, where $CS4$ is a supplementary
rounding result that does not require left-shift normalization. The sign result
is derived from the exponent difference and the $CS0$ result. The flag result
only indicates imprecision; no other exception flags are generated.

The exception path is used to determine whether the operation is invalid,
whether the result is $NaN$, or whether the result is infinite. When none of
these conditions are met, normal computation proceeds, generating a selection
signal to choose the result and flags from either the $far$ path or the $close$
path as output.

#### Scalar mixed-precision floating-point adder

Building upon the scalar single-precision floating-point adder, a
mixed-precision hardware design is implemented. The main difference lies in
supporting mixed-precision computation. Taking the result as $f32$ as an
example, the table below shows the truth table for the operations corresponding
to $res\_widen$ and $opb\_widen$.

Table: Mixed-precision format table for $f32$ results

| $res\_widen$ | $opb\_widen$ |       $f32$       |
| :----------: | :----------: | :---------------: |
|     $0$      |     $0$      | $f32 = f32 + f32$ |
|     $1$      |     $0$      | $f32 = f16 + f16$ |
|     $1$      |     $1$      | $f32 = f16 + f32$ |
|     $0$      |     $1$      |    Not allowed    |

The figure below shows the architecture of a scalar mixed-precision
floating-point adder. The main difference is the addition of a fast format
conversion module at the data input. Based on the operation type, this module
converts the operands into the result's data format before processing, after
which the computation flow is identical to that of a single-precision
floating-point adder.

![Scalar Mixed-Precision Floating-Point Adder Architecture
Diagram](./figure/ScalarMixedPrecisionFloating-pointAdder.svg)

#### Vector Floating-Point Adder

The diagram below shows the architecture of the vector floating-point adder. To
meet timing requirements, it is composed of four modules: $FloatAdderF64Widen$
handles all operations with 64-bit output results, $FloatAdderF32WidenF16$
handles all operations with 16-bit or 32-bit output results, and $FloatAdderF16$
handles only operations with 16-bit output results.

Here, $fp\_format$ is a 2-bit result format control signal: $00$ indicates the
result format is $f16$, $01$ indicates $f32$, and $10$ indicates $f64$. The
output flags are 20 bits, arranged with lower bits being significant. When the
result format is $f16$, all 20 bits are valid; for $f32$, the lower 10 bits are
valid; and for $f64$, the lower 5 bits are valid.

![Vector Floating-Point Adder Architecture
Diagram](./figure/VectorFloating-pointAdder.svg)

The vector floating-point adder employs a two-stage pipeline design. To achieve
rapid wake-up, the addition result is computed in approximately 1.5 cycles.
Pipeline partitioning is performed within each submodule, requiring only the
insertion of a single register level. Below is an explanation of the pipeline
partitioning for the three modules shown in the diagram.

The diagram below illustrates the pipeline partitioning of the
$FloatAdderF64Widen$ module. The $far$ path inserts registers after the
significand right shift, while the $close$ path inserts registers after the
$Mux1H$.

![FloatAdderF64Widen Pipeline Stages](./figure/FloatAdderF64WidenPipeline.svg)

The figure below shows the pipeline division of the $FloatAdderF32WidenF16$
module, which includes calculations for two different output formats. The
selection logic in the second cycle is complex, so registers are inserted within
the adder in the $far$ path. The first cycle performs the addition of the lower
$18$ bits and the higher bits, while the second cycle combines the carry from
the lower $18$-bit addition of the first cycle with the higher bits to obtain
the final result. The $close$ path also inserts registers after $Mux1H$.

![Pipeline Division of
FloatAdderF32WidenF16](./figure/FloatAdderF32WidenF16Pipeline.svg)

The following diagram shows the pipeline partitioning of the $FloatAdderF16$
module. This module has minimal timing pressure and adopts a partitioning method
where the $far$ path inserts registers after the right shift of significant
bits, and the $close$ path inserts registers after $Mux1H$.

![FloatAdderF16 Pipeline Partitioning](./figure/FloatAdderF16Pipeline.svg)

#### Interface Description

The previously introduced vector floating-point adder has a width of $64$ bits,
requiring both operands to be in vector form. However, $RVV$ not only specifies
that both operands are in vector form ($vector-vector$, abbreviated as $vv$) but
also allows one operand to be a vector and the other a scalar ($vector-scalar$,
abbreviated as $vf$). Additionally, under $widening$ instructions, the
arrangement of source operands is not limited to the lower significant part.
When the source register width is half of the destination register width, the
data source may come from either the lower or upper half.

To implement all floating-point instruction calculations in $RVV$ and support
$VLEN$ extension, simple instruction computations are added to the vector
floating-point adder, transforming it into a vector floating-point "$ALU$",
referred to as $VFALU$.

Therefore, the vector floating-point adder needs to be modified to adapt to the
features of $RVV$. The modifications consist of two parts: functional
modifications and interface modifications.

The table below lists the opcodes supported by $VFALU$, totaling $16$
operations, where ($w$) indicates operations involving $widen$. The operand
formats for $vfmerge$, $vfmove$, and $vfclass$ are special: $vfmerge.vfm$ has
three source operands—a vector register, a floating-point register, and a $mask$
register; $vfmove.v.f$ has only one floating-point register as the source
operand; $vfclass$ has only one vector register as the source operand.

Table: $VFALU$ Opcode

| $op\_code$ | Corresponding instruction | Operand format |           Meaning           |
| :--------: | :-----------------------: | :------------: | :-------------------------: |
|    $0$     |        $vf(w)add$         |    $vv,vf$     |          Addition           |
|    $1$     |        $vf(w)sub$         |    $vv,vf$     |         Subtraction         |
|    $2$     |          $vfmin$          |    $vv,vf$     |   Find the minimum value    |
|    $3$     |          $vfmax$          |    $vv,vf$     |        Find Maximum         |
|    $4$     |         $vfmerge$         |     $vfm$      |        Data merging         |
|    $5$     |         $vfmove$          |     $v.f$      |        Data movement        |
|    $6$     |         $vfsgnj$          |    $vv,vf$     |       Sign Injection        |
|    $7$     |         $vfsgnjn$         |    $vv,vf$     |  Sign inversion injection   |
|    $8$     |         $vfsgnjx$         |    $vv,vf$     |     XOR sign injection      |
|    $9$     |          $vmfeq$          |    $vv,vf$     |        Whether equal        |
|    $10$    |          $vmfnq$          |    $vv,vf$     |          Not Equal          |
|    $11$    |          $vmflt$          |    $vv,vf$     |   Whether it is less than   |
|    $12$    |          $vmfle$          |    $vv,vf$     |    Less than or equal to    |
|    $13$    |          $vmfgt$          |      $vf$      |    Whether greater than     |
|    $14$    |          $vmfge$          |      $vf$      | Is greater than or equal to |
|     15     |         $vfclass$         |      $v$       |       Classification        |

The table below defines the $VFALU$ interface. Compared to the vector
floating-point adder, it adds two mixed-precision data sources, $widen\_a$ and
$widen\_b$. When the source and destination operand formats are the same, the
data comes from $fp\_a$ and $fp\_b$; otherwise, it comes from $widen\_a$ and
$widen\_b$. When $uop\_idx=0$, the lower half is taken, and when $uop\_idx=1$,
the upper half is taken. When $is\_frs1=1$, the source operand $vs1$ comes from
the floating-point register $frs1$, which needs to be replicated into a vector
register for computation. $mask$ participates in the calculation of the $merge$
instruction, and $op\_code$ is the operation code indicating the operation to be
performed.

Table: $VFALU$ interface and meanings

|    Interface    | Direction | Bit Width |                            Meaning                            |
| :-------------: | :-------: | :-------: | :-----------------------------------------------------------: |
|      fp_a       |  $input$  |   $64$    |                     Source operand $vs2$                      |
|     $fp\_b$     |  $input$  |   $64$    |                     Source operand $vs1$                      |
|   $widen\_a$    |  $input$  |   $64$    |                         $widen\_vs2$                          |
|   $widen\_b$    |  $input$  |   $64$    |                         $widen\_vs1$                          |
|     $frs1$      |  $input$  |   $64$    |                 Floating-Point Register Data                  |
|   $is\_frs1$    |  $input$  |   $64$    |       Addend sourced from floating-point register data        |
|     $mask$      |  $input$  |    $4$    |        Participate in $merge$ instruction computation         |
|   $uop\_idx$    |  $input$  |    $1$    |             Select upper/lower half when $widen$              |
|  $round\_mode$  |  $input$  |    $3$    |                         Rounding mode                         |
|  $fp\_format$   |  $input$  |    $2$    |                     Floating-point format                     |
| $res\_widening$ |  $input$  |    $1$    |                      $widen$ instruction                      |
| $opb\_widening$ |  $input$  |    $1$    | Is the source operand $vs1$ in the same format as the result? |
|   $op\_code$    |  $input$  |    $5$    |                            Opcode                             |
|    fp_result    | $output$  |   $64$    |                      Computation result                       |
|    $fflags$     | $output$  |   $20$    |                           Flag bits                           |

### Vector Floating-Point Fused Multiply-Add Unit

#### Pipeline Partitioning

The vector floating-point fused multiply-adder adopts a four-stage pipeline
design to achieve rapid wake-up, ensuring the multiply-add result is computed in
approximately $3.5$ cycles. The vector unit's latency is $3.5$ cycles. The
diagram below illustrates the architecture of the vector floating-point fused
multiply-adder, where $reg\_0$ denotes the first-stage register, $reg\_1$ the
second-stage, and $reg\_2$ the third-stage. The vector floating-point fused
multiply-adder also supports $widen$ functionality, limited to $f32 = f16 × f16
+ f32$ and $f64 = f32 × f32 + f64$ cases. Thus, only a single-bit $widen$ signal
is needed for control when the output format is fixed. The output $fflags$ is
also $20$ bits, consistent with the representation in the vector floating-point
adder.

![Vector Floating-Point Fused Multiply-Add Architecture
Diagram](./figure/VFMA.svg)

To save area while meeting timing constraints, a resource-sharing implementation
is adopted. Calculations for all data formats use the same vector Booth encoder
and CSA compression. By interleaving the layout, the 107-bit adder also achieves
resource sharing.

In the first cycle, seven sets of exponent processing are performed to obtain
seven right-shift values. The corresponding right-shift value is selected based
on the computation format. For the right shifters, the $f64$ right shifter is
shared with one $f32$, while a separate $f32$ and four $f16$ right shifters are
dedicated. If subtraction is performed, the right-shifted result of $fp\_c$'s
mantissa is inverted before being fed into the first-stage register.
Simultaneously, vector $Booth$ encoding is performed in the first cycle,
generating 27 partial products, which are compressed into 4 partial products
using $CSA$ and then registered.

In the second cycle, compress the remaining 4 partial products using $CSA4\_2$,
then compress the result with the first cycle's right-shifted significand using
$CSA3\_2$. Perform a 107-bit addition and register the result in the
second-stage register.

In the third cycle, the sum result from the second cycle undergoes $lzd$ and
$tzd$, followed by a left shift with $mask$ limitation. The shifted result is
stored in the third-stage register.

In the fourth cycle, rounding is performed to obtain the mantissa result. The
exponent result is calculated based on the left shift condition in the third
cycle. The sign bit can be obtained from the $107$-bit adder in the second
cycle. The flag results can generate four types of flags: overflow, underflow,
invalid operation, and inexact. Note the method for detecting underflow.
$IEEE-754$ specifies two methods for detecting underflow: $before \quad
rounding$ and $after \quad rounding$. This design uses the $after \quad
rounding$ method selected by $RISC-V$ to detect underflow.

#### Interface Description

According to the $RVV$ instruction definitions, vector floating-point fused
multiply-add units can be reused for multiplication calculations, controlled by
$op\_code$. When performing multiplication, the internal adder is set to zero.
Additionally, $RVV$ defines a series of floating-point fused multiply-add
instructions, primarily differing in sign bits and operand order. The vector
floating-point fused multiply-add unit is modified to support all related
instructions as $VFMA$, with added $op\_code$ and interfaces. The following
table lists the $VFMA$ opcodes, totaling $9$ operations, all supporting $vv$ and
$vf$ operand forms. For $vf$, $vs1[i]$ is replaced by the floating-point
register $frs1$.

Table: $VFMA$ Opcode

| $op\_code$ | Corresponding instruction | Operand format | Meaning                              |
| ---------- | ------------------------- | -------------- | ------------------------------------ |
| $0$        | $vf(w)mul$                | $vv,vf$        | $vd[i] = vs[2] × vs1[i]$             |
| $1$        | $vf(w)macc$               | $vv,vf$        | $vd[i] = +(vs1[i] × vs2[i]) + vd[i]$ |
| $2$        | $vf(w)nmacc$              | $vv,vf$        | $vd[i] = -(vs1[i] × vs2[i]) - vd[i]$ |
| $3$        | $vf(w)msac$               | $vv,vf$        | $vd[i] = +(vs1[i] × vs2[i]) - vd[i]$ |
| $4$        | $vf(w)nmsac$              | $vv,vf$        | $vd[i] = -(vs1[i] × vs2[i]) + vd[i]$ |
| $5$        | $vfmadd$                  | $vv,vf$        | $vd[i] = +(vs1[i] × vd[i]) + vs2[i]$ |
| $6$        | $vfnamdd$                 | $vv,vf$        | $vd[i] = -(vs1[i] × vd[i]) - vs2[i]$ |
| $7$        | $vfmsub$                  | $vv,vf$        | $vd[i] = +(vs1[i] × vd[i]) - vs2[i]$ |
| $8$        | $vfnmsub$                 | $vv,vf$        | $vd[i] = -(vs1[i] × vd[i]) + vs2[i]$ |

The table below shows the $VFMA$ interface. To simplify control logic
complexity, the three operands sent to $VFMA$ are fixed in the order $vs2$,
$vs1$, $vd$. The functional unit internally adjusts the order based on
$op\_code$. Since the $fma$ instruction uses a fixed target format for the
addend during $widen$, only $widen\_a$ and $widen\_b$ need to be added.
$uop\_idx$ is similarly used to select the upper or lower half of $widen\_a$ and
$widen\_b$. $frs1$ and $is\_frs1$ are used to support $vf$ instructions.

Table: $VFMA$ Interface and Meanings

|    Interface    | Direction | Bit Width |                     Meaning                      |
| :-------------: | :-------: | :-------: | :----------------------------------------------: |
|      fp_a       |  $input$  |   $64$    |               Source operand $vs2$               |
|     $fp\_b$     |  $input$  |   $64$    |               Source operand $vs1$               |
|     $fp\_c$     |  $input$  |   $64$    |               Source operand $vd$                |
|   $widen\_a$    |  $input$  |   $64$    |                   $widen\_vs2$                   |
|   $widen\_b$    |  $input$  |   $64$    |                   $widen\_vs1$                   |
|     $frs1$      |  $input$  |   $64$    |           Floating-Point Register Data           |
|   $is\_frs1$    |  $input$  |   $64$    | Addend sourced from floating-point register data |
|   $uop\_idx$    |  $input$  |    $1$    |       Select upper/lower half when $widen$       |
|  $round\_mode$  |  $input$  |    $3$    |                  Rounding mode                   |
|  $fp\_format$   |  $input$  |    $2$    |              Floating-point format               |
| $res\_widening$ |  $input$  |    $1$    |               $widen$ instruction                |
|   $op\_code$    |  $input$  |    $5$    |                      Opcode                      |
|    fp_result    | $output$  |   $64$    |                Computation result                |
|    $fflags$     | $output$  |   $20$    |                    Flag bits                     |

### Vector floating-point divider

#### Scalar Floating-Point Divider

The scalar floating-point divider supports computations in three formats: $1$
$f16 = f16 / f16$, $1$ $f32 = f32 / f32$, and $1$ $f64 = f64 / f64$. The divider
employs a $Radix-64$ algorithm, where the iterative module performs three
$Radix-4$ iterations per cycle to achieve $Radix-64$. The figure below shows the
architecture of the scalar floating-point divider. The divider operates in a
blocking manner and cannot accept the next division operation during
computation, requiring handshake signals for control. This design uses
$start-valid$ handshake signals. Since the $CPU$ may encounter branch prediction
failures that flush pipeline states, a dedicated $flush$ signal is included to
clear the divider's internal state, allowing it to immediately start a new
division operation in the next cycle.

![Scalar Floating-Point Divider Architecture Diagram](./figure/FDiv.svg)

Input data falls into three categories: both are normalized numbers (excluding
divisors that are powers of $2$), at least one is a denormal number, and early
termination (input contains $NaN$, infinity, zero, or the divisor is a power of
$2$). Results fall into two categories: the result is a normalized number, or
the result is a denormal number.

When the inputs are all normalized numbers (excluding divisors that are powers
of 2), the mantissas are normalized, and the process directly proceeds to the
pre-scaling stage. When at least one input is a denormalized number, compared to
the case where all inputs are normalized, an additional cycle is required for
mantissa normalization before pre-scaling.

The prescaling stage takes one cycle, followed by integer quotient selection,
where the two-bit integer quotient result is selected, and the prescaled
divisor, dividend, and remainder's carry-save redundant representation are
provided for the $Radix-4$ iteration. The $Radix-4$ iteration module calculates
6 bits of the quotient per cycle. $f16$ division requires 2 cycles of $Radix-4$
iteration, $f32$ division requires 6 cycles, and $f64$ division requires 9
cycles. After $Radix-4$ iteration, the resulting mantissa quotient ranges
between $(1, 2)$. When the result is a normalized number, only one cycle is
needed for rounding and exponent result calculation to obtain the final division
result. When the result is a denormal number, an additional cycle is required to
denormalize the quotient before rounding.

Early termination is divided into two scenarios: (1) When the input operands
contain NaN, infinity, or zero, division computation is unnecessary, and the
result can be output in the second cycle. (2) When the divisor is a power of 2,
the exponent result can be obtained in the first cycle. If the result does not
require denormalization steps, it can be output in the second cycle; if
denormalization is needed, an additional cycle is required, and the result is
output in the third cycle.

The table below shows the required computation cycles for scalar dividers under
different data formats, where $+1$ indicates an additional cycle for
post-processing when the division result is denormalized. In early termination
cases, division operations for all data formats can be completed in just $1$ to
$2$ cycles. Without early termination, $f16$ division requires $5$ to $7$
cycles, $f32$ division requires $7$ to $9$ cycles, and $f64$ division requires
$12$ to $14$ cycles.

Table: Scalar Divider Calculation Cycles

| Data Format | Normalized Number | Denormal number | Early termination |
| :---------: | :---------------: | :-------------: | :---------------: |
|    $f16$    |       $5+1$       |      $6+1$      |       $1+1$       |
|    $f32$    |       $7+1$       |      $8+1$      |       $1+1$       |
|    $f64$    |      $12+1$       |     $13+1$      |       $1+1$       |

#### Vector floating-point divider

The figure below shows the architecture of the vector floating-point divider.
Compared to the scalar floating-point divider, since vector division computes
multiple divisions simultaneously and all results must be written back to the
register file together, early termination of a single division offers little
benefit for vector division acceleration. Thus, the feature of variable output
latency is removed. In all cases, the latency of the vector floating-point
divider is fixed based on the input data format, as shown in the table below.

![Vector Floating-Point Divider Architecture Diagram](./figure/VFDiv.svg)

Table: Vector Divider Calculation Cycles

| Data Format | Calculation Cycle |
| :---------: | :---------------: |
|    $f16$    |        $7$        |
|    $f32$    |       $11$        |
|    $f64$    |       $14$        |

In hardware design, aside from the $Radix-64$ iteration module, the vector
floating-point divider employs logic reuse, utilizing four signal groups for
computation and control: the first group computes $f64\_0$, $f32\_0$, or
$f16\_0$; the second computes $f32\_1$ or $f16\_1$; the third computes $f16\_2$;
and the fourth computes $f16\_3$. Registers are also reused to store
intermediate results, with widths sized to $max$ (1 $f64$, 2 $f32$, or 4 $f16$)
to meet maximum requirements. The $Radix-64$ iteration module is the critical
path, optimized for timing while minimizing area. The first $Radix-4$ iteration
uses 7 independent $CSA$ and quotient selection units, while the second and
third iterations reuse 4 $CSA$ and quotient selection units.

#### Interface Description

The $RVV$ specification defines three vector floating-point division
instructions:

① $vfdiv.vv \quad vd[i] = vs2[i]/vs1[i]$

② $vfdiv.vf \quad vd[i] = vs2[i]/f[rs1]$

③ $vfrdiv.vf \quad vd[i] = f[rs1]/vs2[i]$

Case ③ is special as the operand order differs from cases ① and ②. For the
vector division unit, the first operand is passed by the control logic as
$vs2[i]/f[rs1]$, and the second operand is passed as $vs1[i]/f[rs1]/vs2[i]$.
Thus, the functional unit sees the dividend in either vector or scalar form, and
the divisor is also in vector or scalar form. Therefore, two additional scalar
data interfaces are required. After adding these interfaces, the module is named
$VFDIV$, with the interfaces as shown in the table below.

Table: $VFDIV$ Interface and Meanings

| Interface          | Direction | Bit Width | Meaning                                            |
| ------------------ | --------- | --------- | -------------------------------------------------- |
| $start\_valid\_i$  | $input$   | $1$       | Handshake signal                                   |
| $finish\_ready\_i$ | $input$   | $1$       | Handshake signal                                   |
| $flush\_i$         | $input$   | $1$       | Flush signal                                       |
| $fp\_format\_i$    | $input$   | $2$       | Floating-point format                              |
| $opa\_i$           | $input$   | $64$      | Dividend                                           |
| $opb\_i$           | $input$   | $64$      | Divisor                                            |
| $frs2\_i$          | $input$   | $64$      | Dividend comes from floating-point register data   |
| $frs1\_i$          | $input$   | $64$      | Divisor sourced from floating-point register data  |
| $is\_frs2\_i$      | $input$   | $1$       | Dividend sourced from floating-point register      |
| $is\_frs1\_i$      | $input$   | $1$       | The divisor comes from the floating-point register |
| $rm\_i$            | $input$   | $3$       | Rounding mode                                      |
| $start\_ready\_o$  | $output$  | $1$       | Handshake signal                                   |
| $finish\_valid\_o$ | $output$  | $1$       | Handshake signal                                   |
| $fpdiv\_res\_o$    | $output$  | $64$      | Computation result                                 |
| $fflags\_o$        | $output$  | $20$      | Flag bits                                          |

### Vector format conversion module $VCVT$

The $VCVT$ module is a three-stage pipelined vector floating-point format
conversion module. It instantiates two $VectorCvt$ submodules capable of
processing $64$-bit data. Each $VectorCvt$ contains one $cvt64$, one $cvt32$,
and two $cvt16$ modules. The $cvt64$ supports processing floating-point/integer
formats of $64$, $32$, $16$, and $8$ bits. The $cvt32$ supports $32$, $16$, and
$8$-bit floating-point/integer formats, while the $cvt16$ supports $16$ and
$8$-bit floating-point/integer formats. Thus, $VectorCvt$ can simultaneously
process one $64$-bit (or two $32$-bit, or four $16$-bit, or four $8$-bit)
floating-point/integer format input data for conversion.

#### Overall design

![VCVT Overall Design](./figure/VCVT.svg)

#### Module Design

The $CVT$ module includes single-width floating-point/integer type conversion
instructions, widening floating-point/integer type conversion instructions,
narrowing floating-point/integer type conversion instructions, vector
floating-point reciprocal square root estimation instructions, and vector
floating-point reciprocal estimation instructions.

Select different $cvt$ module calls based on $width$. The design approach for
the $cvt$ module is divided into four types based on instruction type: $fp2int$,
$int2fp$, $fp2fp$, and $vfr$. The overall design approach for $fcvt64$ is to
unify the format of the input $64bit$ data:

different width unsigned/signed int -> 65 signed int

$f16/f32/f64 -> 65bit (f64 \#\# false.B)$

After standardizing the format, there is no longer a need to distinguish between
different types of data, their bit widths, or field positions during the
conversion process to a certain extent.

Building on this, $VFCVT64$ is divided into 5 categories: $int -> fp$, $fp ->
fp$ widen, $fp -> fp$ narrow, estimate7 ($rsqrt7$ & $rec7$), and $fp -> int$.

#### $FuopType$ decoding logic

For the $cvt$ instruction: its $fuopType$ consists of $9$ bits, with each bit
representing the following information:

Here, $[5:0]$ is obtained from the manual, and $[8:6]$ is additionally added
during the design of control signal generation for convenience.

$[8]:1$ indicates it is a $move$ instruction, $0$ represents $cvt$ instruction
or the two estimation instructions $vfrsqrt7$ and $vfrec7$.

$[7]: 1$ indicates the input is $fp$, $0$ indicates the input is $int$.

$[6]$: $1$ indicates the output is $fp$, $0$ indicates the output is $int$.

$[5]:1$ indicates it is one of the two estimation instructions, $vfrsqrt7$ or
$vfrec7$; otherwise, it is a $cvt$ instruction. When it is $1$, $[0]$
distinguishes between $vfrsqrt7$ and $vfrec7$.

$[4:3]: 00$ denotes $single$ type, $01$ denotes $widen$, $10$ denotes $narrow$.

$[2:0]$: For different instructions, it serves different purposes: For
conversions between floating-point and integer, $[0]$ distinguishes whether the
integer is signed or unsigned; in other cases, $[2:1]=11$ indicates it is an
$rtz$ type instruction, and $[2:0]=101$ indicates it is $rod$ (vfncvt_rod_ffw).
