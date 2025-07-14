# Store Execution Unit: StdExeUnit

## Functional Description

Scalar store instruction data pipeline, used to write store data to the
corresponding position in the StoreQueue.

## Overall Block Diagram
![Overall block diagram of
stdExeUnit](./figure/LSU-StdExeUnit.svg){#fig:LSU-StdExeUnit}

## Interface timing

### Interface timing example

![Timing diagram of stdExeUnit valid request
interface](./figure/LSU-StdExeUnit-Timing.svg){#fig:LSU-StdExeUnit-Timing}

As shown in Figure \ref{fig:LSU-StdExeUnit-Timing}, after the handshake where
both io_ooo_to_mem_issueStd_0_ready and io_ooo_to_mem_issueStd_0_valid are high,
a valid write request is received with the data being
io_ooo_to_mem_issueStd_0_bits_src_0. The example above illustrates that at the
third clock cycle, the data is written to the sqIdx0 entry of the StoreQueue,
with the data being src0. At the fourth clock cycle,
io_ooo_to_mem_issueStd_0_ready goes low, at which point the data is not written
to the StoreQueue. This situation typically occurs when a vector store
instruction attempts to write data to the StoreQueue.
