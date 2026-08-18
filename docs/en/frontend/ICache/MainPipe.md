# MainPipe {#sec:icache-mainpipe}

MainPipe is the main ICache pipeline. It has 2 stages and is responsible for reading data from DataArray, ECC checks, miss handling, and returning results to IFU.

## S0 Stage {#sec:icache-mainpipe-s0}

1. Accept fetch requests from FTQ.
2. Read metadata from the WayLookup queue head.
3. If hit, send DataArray read request based on fetch request and metadata.

## S1 Stage {#sec:icache-mainpipe-s1}

1. Decide whether fetch is needed based on hit result and exception information.
2. If hit, receive DataArray response.
3. If miss and no exception, send miss requests for up to four cachelines corresponding to at most two fetch blocks to MissUnit in order through Arbiter, then wait until refill completes.
4. Send data to IFU.

## S2 Stage {#sec:icache-mainpipe-s2}

1. Perform MetaArray and DataArray ECC checks.
2. If MetaArray or DataArray ECC check fails, report error information to BEU.
3. Send ECC check results to IFU.

In early V3 design, MainPipe was intended to be shortened to one stage, with DataArray ECC check also done in S1. However, because DataArray SRAM itself is relatively large and the check logic is wide combinational logic, timing could not converge, so the current two-stage design was adopted. ICache and IFU agree that the check result provided by ICache s2 becomes valid in the cycle after a successful handshake on the s1-stage interface. The s2 stage is updated only after the next successful handshake on the s1-stage interface. Therefore, MainPipe s2 does not need traditional ready-valid flow control, and the s2 interface between MainPipe and IFU does not need a handshake either, which simplifies the design.

### MetaArray ECC Check {#sec:icache-mainpipe-s2-meta-ecc}

After PrefetchPipe reads the metadata and check bits from MetaArray, it does not verify them in PrefetchPipe, but directly stores them in WayLookup and checks them in MainPipe.

Besides check-bit verification itself, MetaArray ECC check also checks whether there is a multi-way hit (that is, multiple ways with matching tags for the same `setIdx`). If a multi-way hit exists, MetaArray is considered erroneous even if the check bits pass.
