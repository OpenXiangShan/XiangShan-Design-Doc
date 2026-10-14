# WbFuBusyTable

- Version: V2R2A
- Status: OK
- Date: 2026/10/13
- commit: [XSAI e8fb1a14](https://github.com/OpenXiangShan/XSAI/tree/e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f)

## Function

The primary function of the WbFuBusyTable module is to manage and synchronize the interaction between the busy tables of different execution units and write-back ports.

The main process is as follows:

1. Busy table information from integer, floating-point, vector, and memory schedulers is merged by type into a global busy table.
2. Bind the global busy table with execution unit parameters, obtaining the maximum latency and deterministic flags (whether the execution latency of functional units is deterministic) for each write-back port from the parameters, and generate hardware busy tables based on the latency configuration.
3. Determine whether the execution unit is connected to the specified write-back port based on the type of write-back physical register.
4. Merge the busy status of each execution unit into the busy table of the write-back port.
5. Distribute the busy table of write-back ports to the dispatch queues of each scheduler.

### Matrix writeback ports

XSAI adds the MxWB latency mapping, writeback-port busy tables, and conflict flags. The IQ's mx busy reservation is gated by mxWen; failed OG0/OG1 responses can cancel the reservation. Results are distributed back to the corresponding IQs to prevent deterministic-latency dimension writes from colliding at the same physical write port.

Writes to the global busy/deqResp aggregation come from the four input classes Int/Fp/Vf/Mem; the MfScheduler input does not participate in this aggregation. Busy-table read responses are distributed to the five scheduler classes Int, Fp, Vf, Mf, and Mem. WbDataPath independently arbitrates actual MxRF writeback.

### Functional Unit Busy Table FuBusyTable

The functional unit busy table records the busy status of each functional unit at different time points. Only functional units with deterministic latency have a functional unit busy table, with a bit width equal to the execution latency of the functional unit. Each bit corresponds to a specific time point, where "1" indicates the functional unit is busy at that time point, and "0" indicates it is idle.

### Functional Unit Busy Table Write FuBusyTableWrite

The primary function of the functional unit busy table write is to update the status of the functional unit busy table. It receives various response signals, such as the dequeue signal from the dispatch queue (deqResp), the response signal returned after processing in the og0 stage (og0Resp), and the response signal returned after processing in the og1 stage (og1Resp). Based on the validity of these signals and the functional unit type, the busy table is updated. When an instruction is successfully dispatched, the corresponding bit in the busy table is set to "1" based on the functional unit type and latency information in the response signal, indicating the functional unit is busy. When instruction dispatch fails in the og0 or og1 stage, the corresponding time point in the busy table is cleared based on the functional unit type and latency information in the response signal, indicating the functional unit is idle.

### Functional Unit Busy Table Read FuBusyTableRead

The functional unit busy table read generates a mask by processing the busy table and functional unit type, indicating which instructions can use the corresponding functional unit.
