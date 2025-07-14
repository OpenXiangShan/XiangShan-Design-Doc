# Atomics Execution Unit: AtomicsUnit

## Functional Description

The AtomicsUnit is used to execute atomic instructions, including the
A-extension (LR/SC and AMO instructions) and the Zacas extension (AMOCAS.W,
AMOCAS.D, and AMOCAS.Q). By default, the PMA supports all AMO and AMOCAS
instructions in the DDR address space.

The basic execution flow of atomic instructions is as follows:

1. **sta dispatch**: The AtomicsUnit shares the dispatch port with the
   StoreUnit, listening for sta uops from the reservation station.
2. **std dispatch**: Atomic instructions share the StdExeUnit execution unit
   with store instructions. The execution results of StdExeUnit are sent to the
   AtomicsUnit, which is responsible for collecting all the data required for
   the execution of atomic instructions.
3. **Address Translation**: The AtomicsUnit shares the DTLB port with LoadUnit_0
   for address translation, while also performing physical address checks such
   as PMA/PMP.
4. **Clear SBuffer**: Currently, atomic instructions are executed with aq/rl
   flags set, so the SBuffer must be cleared before execution.
5. **Access DCache**: Sends an atomic operation request to the DCache. After
   completion, the DCache returns the result to the AtomicsUnit.
6. **Writeback**: The AtomicsUnit writes the execution result back to the
   register file.

## Overall Block Diagram

The finite state machine of the AtomicsUnit is shown in the figure.

![AtomicsUnit State Machine Diagram](./figure/atomicsUnitFSM.svg)

- **s_invalid**: The AtomicsUnit is idle. Upon receiving a sta uop dispatched
  from the reservation station, it enters the s_tlb_and_flush_sb_req state.

- **s_tlb_and_flush_sb_req**: Accesses the TLB for address translation. If the
  TLB misses, it continues accessing the TLB until a hit occurs. Simultaneously,
  it requests the SBuffer to clear. After the TLB hits, if a debug trigger is
  activated or an address misalignment exception occurs, it directly transitions
  to the s_finish state to write back to the backend. Otherwise, it transitions
  to the s_pm state for physical address permission checks and further exception
  handling. During TLB access:
  - For LR instructions, read permission is required.
  - For SC instructions or other AMO instructions, write permission is required.

- **s_pm**: Physical address permission checks and exception handling. If any of
  the following exceptions occur, transition to the s_finish state to write back
  to the backend:
  - If an LR instruction accesses the TLB and returns an exception, report the
    corresponding LoadPageFault/LoadAccessFault/LoadGuestPageFault exception.
  - If atomic instructions other than LR encounter a TLB exception, raise the
    corresponding StorePageFault / StoreAccessFault / StoreGuestPageFault
    exception.
  - If the PBMT attribute is PMA and the PMA attribute is MMIO, report the
    corresponding LoadAccessFault / StoreAccessFault based on whether it is an
    LR instruction.
  - If the PBMT attribute is IO or NC, raise the corresponding LoadAccessFault /
    StoreAccessFault based on whether it is an LR instruction.
  - If the PMP attribute is MMIO, or if a read/write permission check exception
    is returned, report the corresponding LoadAccessFault/StoreAccessFault based
    on whether it is an LR instruction.

  If none of the above exceptions occur, begin clearing the SBuffer:
  - If the SBuffer is not empty, transition to the s_wait_flush_sbuffer_resp
    state to wait for the SBuffer to clear.
  - If the SBuffer is already cleared, transition to the s_cache_req state to
    access the DCache.

- **s_wait_flush_sbuffer_resp**: Waits for the SBuffer to be cleared, then
  enters the s_cache_req state to access the DCache.

- **s_cache_req**: After collecting all std uops, sends an access request to the
  DCache. Upon successful handshake, enters the s_cache_resp state to wait for
  the DCache to complete processing and respond.
  - Note that the AMOCAS instruction requires receiving multiple std uops from
    the backend. The AtomicsUnit must wait until all std uops are received in
    the s_cache_req state before sending a request to the DCache.

- **s_cache_resp**: Waits for the DCache to process the atomic operation and
  return the result.
  - If the DCache cannot process the request temporarily and requires the
    AtomicsUnit to resend, it returns to the s_cache_req state to resend the
    request.
  - Otherwise, no resend is needed, and it enters the s_cache_resp_latch state.

- **s_cache_resp_latch**: Shifts and performs signed/unsigned extension on the
  data returned by the DCache, with an additional cycle added due to timing
  reasons. The next cycle transitions to the s_finish state.
  - If the DCache returns an error, the corresponding LoadAccessFault /
    StoreAccessFault must be recorded.

- **s_finish**: Write back the execution result of the atomic instruction.
  - For LR instructions or AMO instructions, the old value read from memory is
    written back.
  - For SC instructions, write back whether the SC instruction executed
    successfully: 0 for success, 1 for failure.

  After a successful write-back handshake:
  - For the AMOCAS.Q instruction, a total of 16B of data needs to be written
    back. As mentioned earlier, the AMOCAS.Q instruction requires receiving 2
    sta uops and thus requires 2 cycles for writeback, with the pdest of each
    writeback corresponding to the pdest of the respective uop. The 2 sta uops
    of the AMOCAS.Q instruction do not have a fixed dispatch order, but the
    writeback must occur sequentially. Therefore, during the first writeback in
    the s_finish state, it must be ensured that the first sta uop has been
    received (to guarantee the correctness of the writeback pdest). After the
    first writeback succeeds, transition to the s_finish2 state for the second
    writeback.
  - If it is not an AMOCAS.Q instruction, after a successful write-back
    handshake, it enters the s_invalid state, and the state machine ends.

- **s_finish2**: For the AMOCAS.Q instruction, the AtomicsUnit needs to perform
  a second write-back to write the upper 8B of the 16B data. The condition for
  write-back is to ensure that the second sta uop has been received. After a
  successful write-back handshake, it enters the s_invalid state, and the state
  machine ends.

## Zacas extension

1. The AMOCAS.W instruction loads 4B of data from the memory address pointed to
   by rs1 and compares it with the lower 4B of the rd register. If they are
   equal, it writes the lower 4B of rs2 to the memory address pointed to by rs1.
   Finally, the old value loaded from memory is written back to the rd register.
2. The AMOCAS.D instruction loads 8B of data from the memory address pointed to
   by rs1, compares it with rd, and if equal, writes rs2 to the memory address
   pointed to by rs1; the old value loaded from memory is finally written back
   to the rd register.
3. The AMOCAS.Q instruction loads 16B of data from the memory address pointed to
   by rs1 and compares it with the concatenated data of rd and rd+1. If they are
   equal, it writes the concatenated 16B data of rs2 and rs2+1 to the memory
   address pointed to by rs1. Finally, the lower 8B of the old value loaded from
   memory is written back to the rd register, and the upper 8B is written back
   to the rd+1 register.
  - It should be noted that regarding the register pairs for rs2 and rd, if the
    source operand is the x0 register, the read result of the register pair will
    be all zeros; if the destination register is the x0 register, none of the
    registers in the register pair will be written.

## Uop splitting for atomic instructions.

Each instruction in the A extension is split into one sta uop and one std uop,
performing one writeback (the number of writebacks matches the number of sta
uops; std uops do not require writeback).

AMOCAS differs from other A-extension instructions in terms of uop splitting,
issuing, and write-back. When issuing an AMOCAS instruction, in addition to
providing the data to be written to memory, comparison data is also required.
Therefore, an AMOCAS instruction is split into multiple std uops, or even
multiple sta uops.

The AMOCAS instruction reuses fuOpType to distinguish between multiple std uops
or multiple sta uops. fuOpType has a total of 9 bits, with atomic instructions
using only 6 bits, so the upper 3 bits are used to mark uopIdx.

The specific uop splitting rules are as follows:

1. **A-extension instructions (including LR/SC and regular AMO instructions)**:
   Both sta and std uopIdx are 0, carrying rs1 and rs2 data respectively, and
   stored in the rs1 and rs2_l registers in the AtomicsUnit. The AtomicsUnit
   performs one write-back operation with uopIdx 0, and the write-back pdest
   equals the pdest of the sta uop.

![Schematic diagram of Uop splitting for A-extension atomic
instructions](./figure/atomicsUnitAMOUop.svg)

2. **AMOCAS.W and AMOCAS.D instructions**: The backend dispatches 1 sta uop and
   2 std uops:

  - The uopIdx for a single sta uop is 0.
  - The uopIdx of the two std uops are 0 and 1, storing rd (data for comparison)
    and rs2 (data to be stored if the comparison succeeds) respectively, and
    writing them into the rd_l and rs2_l registers in the AtomicsUnit.
  - Finally, perform one writeback with uopIdx 0, where the pdest for writeback
    equals the pdest of the sta uop.

![Schematic diagram of Uop splitting for AMOCAS.W and AMOCAS.D
instructions](./figure/atomicsUnitAMOCASWUop.svg)

3. **AMOCAS.Q instruction**: The backend dispatches 2 sta uops and 4 std uops:

  - The uopIdx for the two sta uops are 0 and 2, with their pdest recorded as
    pdest1 and pdest2.
  - The four std uops have uopIdx 0-3, where uops 0 and 2 store the lower and
    upper bits of rd, writing to the rd_l and rd_h registers, respectively; uops
    1 and 3 store the lower and upper bits of rs2, writing to the rs2_l and
    rs2_h registers, respectively.
  - Finally, perform two write-backs. The write-back uopIdx values are 0 and 2,
    with pdest being pdest1 and pdest2 respectively, and the write-back data
    being the lower and higher bits of the old value loaded from memory.

![Schematic diagram of Uop splitting for AMOCAS.Q
instruction](./figure/atomicsUnitAMOCASQUop.svg)

## Exception summary.

Possible exceptions for atomic instructions include:

- **Address misalignment exception**: The address for atomic operations must be
  aligned according to the operation type (word/doubleword/quadword) (4B / 8B /
  16B), otherwise an address misalignment exception is raised.
- **Illegal instruction exception** (checked at the backend decode stage,
  unrelated to memory access): The AMOCAS.Q instruction requires the register
  numbers for rs2 and rd to be even; if odd, an illegal instruction exception
  must be raised.
- **Breakpoint exception**: If the trigger comparison hits, a breakpoint
  exception must be reported.
- **Exceptions related to address translation and permission checks**
  - If the TLB address translation returns an exception, report the
    corresponding Load or Store PageFault/AccessFault/GuestPageFault exception
    based on whether it is an LR instruction.
  - If the PMP attribute is MMIO, or if the PMP lacks the corresponding
    read/write permissions, report LoadAccessFault/StoreAccessFault.
  - If the PMA + PBMT attributes are IO or NC (including the following 3 cases),
    a LoadAccessFault/StoreAccessFault is reported.
    - PBMT = IO
    - PBMT = NC
    - PBMT = PMA and PMA = MMIO.
