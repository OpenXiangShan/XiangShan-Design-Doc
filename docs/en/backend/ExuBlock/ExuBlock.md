# ExuBlock

- Version: V2R2
- Status: OK
- Date: 2025/01/20
- commit：[xxx](https://github.com/OpenXiangShan/XiangShan/tree/xxx)

## Input and Output

`flush` is a Redirect input with a valid signal.

`in` corresponds to the issueBlock and the ExuInput inputs associated with each
exu within the issueBlock. That is, in(i)(j) represents the input from the j-th
exu in the i-th issueBlock.

`out` corresponds to the issueBlock and the ExuOutput outputs associated with
each exu within the issueBlock. That is, out(i)(j) represents the output
corresponding to the j-th exu in the i-th issueBlock.

`csrio`, `csrin`, and `csrToDecode` exist only if there is a `CSR` in the
ExuBlock.

Similarly, `fenceio` exists only if there is a `fence` in the ExuBlock. `frm`
exists only if the ExuBlock requires `frm` as a source. `vxrm` exists only if
the ExuBlock requires `vxrm` as a source.

`vtype`, `vlIsZero`, and `vlIsVlmax` exist only if the ExuBlock requires writing
to Vconfig.

## Function

The ExuBlock is primarily responsible for connecting signals from external
modules to each exu according to configuration requirements and organizing the
outputs of the exus as the outputs of the ExuBlock.

![ExuBlock Overview](./figure/ExuBlock-Overview.svg)

## Design Specifications

There are a total of 3 ExuBlocks in the Backend: intExuBlock, fpExuBlock, and
vfExuBlock, which are the execution modules for integer, floating-point, and
vector operations, respectively. Each ExuBlock contains several ExeUnit units.

The intExuBlock contains 8 ExeUnits. Its I/O includes flush, in, out, csrio,
csrin, csrToDecode, fenceio, frm, vtype, vlIsZero, and vlIsVlmax, but excludes
vxrm.

The fpExuBlock contains 5 ExeUnits. Its I/O includes flush, in, out, and frm,
but excludes csrio, csrin, csrToDecode, fenceio, vxrm, vtype, vlIsZero, and
vlIsVlmax.

The vfExuBlock contains 5 ExeUnits. Its I/O includes flush, in, out, frm, vxrm,
vtype, vlIsZero, and vlIsVlmax, but excludes csrio, csrin, csrToDecode, and
fenceio.
