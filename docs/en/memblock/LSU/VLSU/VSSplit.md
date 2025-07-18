# Vector Store Split Unit VSSplit

## Functional Description

Receive and process uops for Vector Store instructions. Split Uops, calculate
the offset of Uops relative to the base address, and generate control signals
for the scalar memory access Pipeline. VSSplit is broadly divided into two
implementation modules: VSSplitPipeline and VSSplitBuffer.

### Feature 1: VSSplitPipeline performs secondary decoding for uops

The splitting pipeline for Vector Store instructions. It accepts Vector Store
Uops dispatched from the Vector Store issue queue. After finer-grained decoding
and calculating the Mask and address offset in the pipeline, it sends them to
VSSplitBuffer. Simultaneously, VSSplitPipeline also requests entries in
VLMergeBuffer based on the decoding results. VSSplitPipeline consists of two
pipeline stages:

#### S0:

- Perform finer-grained decoding based on the incoming Uop information.
- Generate alignedType based on the instruction type, using alignedType to
  indicate the memory access width of the Store Pipeline.
- Generate the preIsSplit signal based on the instruction type. A high
  preIsSplit signal indicates that it is not a Unit-Stride instruction.
- Generate the Mask for this Uop based on the instruction type and information
  such as vm, emul, lmul, eew, and sew.
- Calculate the VdIdx of this Uop for subsequent backend data merging and
  writeback. Due to out-of-order execution, Uops from the same instruction may
  not execute consecutively, so this stage computes VdIdx based on instruction
  type, emul, lmul, and uopidx.

##### Mask calculation:

- First, we calculate and generate the SrcMask representing this Vector Store
  instruction based on vm, v0, vstart, and evl. Here, evl is the effective
  vector length, and different types of Vector Store instructions have different
  methods for calculating evl:
    - For Store Whole instructions, their evl = NFIELDS*VLEN/EEW.
    - For Store Unit-Stride Mask instructions, evl=ceil(vl/8).
    - For Vector Store instructions other than the two types mentioned above,
      their evl equals vl.

- Then, we use the [FlowNum of all Uops before the current Uop] and [FlowNum of
  all Uops including the current Uop] along with [FlowNum of all Vd before the
  current Uop] to calculate the actual FlowMask used. Here, due to the
  uniqueness of Store Indexed instructions, when $signed(emul) > $signed(lmul)
  for Indexed instructions, we need to ensure that the FlowNum of Uops with the
  same VdIdx is offset within VdIdx, as illustrated in the following example:
    - First, we assume the following configuration for the vector vluxei
      instruction:
        - vsetvli t1,t0,e8,m1,ta,ma lmul = 1
        - vsuxei16.v v2,(a0),v8 emul = 2
        - vl = 9, v0 = 0x1FF

    - Under this configuration, since $signed(emul) > $signed(lmul), it will
      actually generate two Uops, indicating that indexes need to be fetched
      from two vector registers, while the destination register for both Uops is
      the same Vd. That is, the VdIdx of the two Uops should be identical, as
      they are to be written into the same target register. Therefore, the
      following result will be produced here:
        - uopIdxInField = 0, vdIdxInField = 0, flowMask = 0x00FF,
          toMergeBuffMask = 0x01FF
        - uopIdxInField = 1, vdIdxInField = 0, flowMask = 0x0001,
          toMergeBuffMask = 0x01FF
        - uopIdxInField = 0, vdIdxInField = 0, flowMask = 0x0000,
          toMergeBuffMask = 0x0000
        - uopIdxInField = 0, vdIdxInField = 0, flowMask = 0x0000,
          toMergeBuffMask = 0x0000

    - The FlowNum calculated for each Uop is 8. For more details, refer to
      VSplit.scala.

#### S1:

- Calculate UopOffset and Stride.
- Calculate the FlowNum required for this Uop. Here, the FlowNum sent to the
  VMergeBuffer differs from the FlowNum sent to the VSplitBuffer. The FlowNum in
  the MergeBuffer is used to determine whether this Uop has completed all valid
  memory accesses, while the FlowNum used in the VSplitBuffer is needed for
  splitting.
- Request an entry in the VSMergeBuffer table. Each Uop requests one entry.
- Send information to the VSSplitBuffer.

### Feature 2: VSSplitBuffer splits based on the secondary decoding information generated by VSSplitPipeline

VSplitBuffer is a single-entry Buffer that receives relevant information from
VSSplitPipeline, caching the Vector Store Uop that needs to be split.

The VSSplitBuffer splits a Uop into multiple segments that can be dispatched to
the scalar Store Pipeline based on the Uop's information, then sends them to the
scalar Store Pipeline for actual memory access.


** enqueue logic: **

The VSSplitBuffer accepts entry requests and related information from the
VSSplitPipeline. When there are free entries in the VSSplitBuffer, it allocates
a VSSplitBuffer entry for each request and sets the Valid bit of the
corresponding entry to high.

**Dequeue logic：**

The VSSplitBuffer accepts entry requests and related information from the
VSSplitPipeline. When there are free entries in the VSSplitBuffer, it allocates
a VSSplitBuffer entry for each request and sets the Valid bit of the
corresponding entry to high.


**Split：**

- The VsSplitBuffer performs splitting according to the instruction type.
- For Unit-Stride instructions:
- When the base address is aligned (not crossing CacheLine), it accesses 128 Bit
  at once.
- When the base address is unaligned (crossing CacheLine boundaries), we perform
  splitting and initiate two 128-bit memory accesses.
- For other Vector Store instructions, we split them according to the
  instruction semantics on an element-by-element basis and perform memory access
  accordingly.
- Each split operation sends the generated relevant information to the scalar
  Store Pipeline for actual memory access.
- The splitting decision is based on the splitIdx counter, where splitIdx
  indicates the number of splits already performed for the current table entry.
  When splitIdx is less than the required number of splits and the entry can be
  sent to the scalar Store Pipeline, a split occurs, incrementing the splitIdx
  counter. Once splitIdx meets or exceeds the required split count, the
  splitting process concludes, the entry is dequeued, and the splitIdx counter
  resets to zero.

**Address calculation: **

- During splitting, it is also necessary to calculate the relevant information
  to be sent to the scalar Store Pipeline, primarily determining the virtual
  address for memory access after each split.
- The virtual address calculation varies based on the instruction type's
  splitting method.

- For Unit-Stride instructions:
    - When the base address is aligned (not crossing a CacheLine), a single
      128-bit aligned access is sufficient.
    - When the base address is unaligned (crossing CacheLine), we split it and
      use two consecutive 128-bit aligned addresses for access.

- For other Vector Store instructions, we split them element-wise as required by
  their semantics, with virtual addresses calculated based on elements and
  instruction semantics.

** data calculation: **

- During splitting, it is also necessary to calculate the relevant information
  to be sent to the Store Queue, mainly determining the data to be stored after
  each split.
- The data to be stored is calculated differently based on the instruction type
  and splitting method. For specifics, refer to the address calculation
  requirements mentioned above; it only needs to align with the granularity of
  the address.

** Redirection and Exception Handling: **

When a redirect signal arrives, the relevant entries in the VSSplitBuffer will
be flushed based on the redirect information.

## Overall Block Diagram

No block diagram for a single module.

## Main ports

Only the external interfaces of VSSplit are listed, excluding the internal
interfaces of VSSplitPipe and VSSplitBuffer.

|                    | Direction | Description                                                                                           |
| -----------------: | --------- | ----------------------------------------------------------------------------------------------------- |
|           redirect | In        | Redirect port                                                                                         |
|                 in | In        | Receive uop dispatch from the Issue Queue.                                                            |
|  toMergeBuffer.req | Out       | Request MergeBuffer entry                                                                             |
| toMergeBuffer.resp | In        | MergeBuffer response                                                                                  |
|                out | Out       | Send memory access requests to the Store Unit                                                         |
|               vstd | Out       | When a completed uop writes back to the backend, it updates the status of entries in the Store queue. |
|       vstdMisalign | In        | Receive misalignment-related signals from the Store Unit and Store Misalign Buffer.                   |

## Interface timing

The interface timing is relatively simple, described only in text.

|                    | Description                                                                                                                   |
| -----------------: | ----------------------------------------------------------------------------------------------------------------------------- |
|           redirect | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|                 in | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|  toMergeBuffer.req | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
| toMergeBuffer.resp | Has Valid status. Data is valid when Valid is asserted.                                                                       |
|                out | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|               vstd | Includes Valid and Ready signals. Data is valid when Valid && Ready.                                                          |
|       vstdMisalign | No Valid signal; data is always considered valid, and responses are generated as soon as the corresponding signal is present. |
