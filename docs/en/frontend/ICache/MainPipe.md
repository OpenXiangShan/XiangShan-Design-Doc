# MainPipe submodule documentation.

MainPipe is the main pipeline of ICache, designed as a 2-stage pipeline. It is
responsible for reading data from DataArray, performing PMP checks, ECC checks,
handling misses, and returning results to IFU.

![MainPipe structure](../figure/ICache/MainPipe/mainpipe_structure.png)

## S0 pipeline stage

In the S0 pipeline stage, retrieves metadata from WayLookup, including way hit
information and ITLB query results, and accesses a single way of DataArray. The
pipeline stalls if DataArray is being written or if WayLookup has no valid
entries. After each redirect, the same request from FTQ is sent simultaneously
to MainPipe and IPrefetchPipe. MainPipe always waits for IPrefetchPipe to write
the query information into WayLookup before proceeding, resulting in a 1-cycle
redirect latency. This latency is hidden when prefetching outpaces instruction
fetching.

## S1 pipeline stage

1. Updates the replacer by sending a touch request to it.
2. PMP check: sends a PMP request and receives the response in the same cycle,
   then registers the result for processing in the next pipeline stage.
   - It should be noted that the IPrefetchPipe s1 pipeline stage also performs
     PMP checks, which are identical to those performed here. Separate checks
     are conducted to optimize timing (avoiding the excessively long
     combinational logic path: `ITLB(reg) -&gt; ITLB.resp -&gt; PMP.req -&gt;
     PMP.resp -&gt; WayLookup.write -&gt; bypass -&gt; WayLookup.read -&gt;
     MainPipe s1(reg)`).
3. Receives and registers the data and code returned by DataArray while
   monitoring MSHR responses. When both DataArray and MSHR responses are valid,
   the latter has higher priority.

## S2 pipeline stage

1. DataArray ECC verification: checks the code registered in the S1 pipeline
   stage. Reports errors to BEU if verification fails.
2. MetaArray ECC verification. After IPrefetchPipe reads data from MetaArray, it
   directly performs verification and enqueues the verification result along
   with hit information into WayLookup. This then flows through the MainPipe to
   the S2 stage, where it is reported to BEU together with the ECC verification
   result from DataArray.
3. Tilelink error handling: when monitoring a MissUnit response with the corrupt
   signal high (indicating L2 cache response data error), reports the error to
   BEU.
4. Miss handling: sends requests to MissUnit upon a miss while monitoring MSHR
   responses. On a hit, registers the MSHR response data and sends it to IFU in
   the next cycle for timing optimization.
