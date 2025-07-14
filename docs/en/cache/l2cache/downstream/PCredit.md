# P-Credit Management Mechanism

## Functional Description
According to the description of Retry in CHI protocol 2.3.2, P-Credit management
follows the following rules:
1. When the RXRSP channel receives a PCrdGrant, a CAM records the PCrdType and
   SrcID of this operation.
2. At this point, if there is an MSHR in a certain Slice waiting for a PCredit
   of the same type {PCrdType, SrcID}, this PCredit is allocated to that Slice.
   - If multiple Slices hit simultaneously, this PCredit is allocated in a
   RoundRobin manner, and the corresponding record in the CAM is deleted. - If
   no Slice hits, the CAM saves the PCrdType and SrcID for future use (the
   protocol allows PCrdGrant to be issued before RetryAck).
4. For a hit Slice, if multiple MSHRs hit {PCrdType, SrcID}, it is allocated to
   one MSHR in a RoundRobin manner.
5. For each MSHR: - Upon receiving RetryAck, it saves PType and SrcID, while
   asserting the pValid signal to notify the CAM that it is waiting for PCredit.
   - If a matching PCredit is found in the CAM, the MSHR completes the operation
   by deasserting pValid and removing the matching entry from the CAM. - If no
   matching PCredit is found in the CAM, pValid remains asserted until the
   corresponding PCredit is received.

