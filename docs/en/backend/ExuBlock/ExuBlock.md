# ExuBlock

- Version: V2R2A
- Status: OK
- Date: 2026/10/13
- commit: [XSAI ee268923](https://github.com/OpenXiangShan/XSAI/tree/ee268923b7175d79a9d0183a0181a684ccec9487)

## Input and Output

`flush` is a Redirect input with a valid signal.

`in` corresponds to the issueBlock and the ExuInput inputs associated with each exu within the issueBlock. That is, in(i)(j) represents the input from the j-th exu in the i-th issueBlock.

`out` corresponds to the issueBlock and the ExuOutput outputs associated with each exu within the issueBlock. That is, out(i)(j) represents the output corresponding to the j-th exu in the i-th issueBlock.

`csrio`, `csrin`, and `csrToDecode` exist only if there is a `CSR` in the ExuBlock.

Similarly, `fenceio` exists only if there is a `fence` in the ExuBlock. `frm` exists only if the ExuBlock requires `frm` as a source. `vxrm` exists only if the ExuBlock requires `vxrm` as a source.

`vtype`, `vlIsZero`, and `vlIsVlmax` exist only if the ExuBlock requires writing to Vconfig.

## Function

The ExuBlock is primarily responsible for connecting signals from external modules to each exu according to configuration requirements and organizing the outputs of the exus as the outputs of the ExuBlock.

![ExuBlock Overview](./figure/ExuBlock-Overview.svg)

## Design Specifications

With the matrix extension enabled, the Backend contains four execution blocks: intExuBlock, fpExuBlock, vfExuBlock, and mfExuBlock. Matrix memory execution resources remain in MemBlock. Each ExuBlock contains several ExeUnits according to its IssueBlock configuration.

The intExuBlock in DefaultMatrixConfig contains 10 ExeUnits. Its I/O includes flush, in, out, csrio, csrin, csrToDecode, fenceio, frm, vtype, vlIsZero, and vlIsVlmax, but excludes vxrm.

The fpExuBlock contains 5 ExeUnits. Its I/O includes flush, in, out, and frm, but excludes csrio, csrin, csrToDecode, fenceio, vxrm, vtype, vlIsZero, and vlIsVlmax.

The vfExuBlock contains 5 ExeUnits. Its I/O includes flush, in, out, frm, vxrm, vtype, vlIsZero, and vlIsVlmax, but excludes csrio, csrin, csrToDecode, and fenceio.

MfExuBlock contains three execution resources: MSET1, MEX0, and MEX1, for dimension reads, MMA control generation, and mzero control generation, respectively. Its mxrm, mfrm, and msaten inputs are forwarded according to needSrcMcsr to FUs requiring matrix CSR control. Its outputs contain normal ROB writeback control and optional amuCtrl.
