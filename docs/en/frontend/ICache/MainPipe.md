# MainPipe Submodule Documentation

MainPipe is the main ICache pipeline. It has 2 stages and is responsible for reading data from DataArray, ECC checks, miss handling, and returning results to IFU.

## S0 Stage

1. Accept fetch requests from FTQ.
2. Read metadata from the WayLookup queue head.
3. If hit, send DataArray read request based on fetch request and metadata.

## S1 Stage

1. Perform MetaArray ECC check.
2. Decide whether fetch is needed based on hit result, exception metadata, and MetaArray ECC result.
3. If hit, receive DataArray response.
4. If miss and no exception, send miss requests for up to two cachelines to MissUnit through Arbiter in order, then wait until refill completes.
5. Send data to IFU.

### MetaArray ECC Check

After PrefetchPipe reads MetaArray metadata and check bits, it does not verify them in PrefetchPipe. Instead, they are directly stored in WayLookup and checked in MainPipe.

Besides check-bit verification itself, MetaArray ECC check also detects multi-way hit (that is, multiple ways with matching tags in the same `setIdx`). If multi-way hit exists, it is treated as a MetaArray error even when check bits pass.

## S2 Stage

1. Perform DataArray ECC check.
2. If MetaArray or DataArray ECC check fails, report error information to BEU.
3. Send ECC check results to IFU.

In early V3 design, MainPipe was intended to be shortened to one stage, with DataArray ECC check also done in S1. But timing could not converge because DataArray SRAM is large and ECC check logic is wide combinational logic. So the current two-stage design is used. Therefore, ICache-to-IFU has two ports at S1 and S2, each with handshake.
