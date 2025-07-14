# GrantBuffer

## Basic Functions
GrantBuf receives tasks from MainPipe and forwards them based on the task type.
The main categories are:
-  Prefetch responses (opcode = HintAck) are arranged to enter the prefetch
   response queue pftRespQueue (size=10) and issued to the prefetcher in FIFO
   order.
-  Channel D responses (opcode = Grant/GrantData/ReleaseAck) are arranged to
   enter grantQueue (size=16) and issued to Channel D of the bus in FIFO order.
   For Grant/GrantAck, their information is also stored in the inflightGrant
   buffer (size=16) (indicating the Grant has been sent but not yet
   acknowledged), waiting for L1 to return GrantAck via Channel E before
   clearing the information.
-  Merged requests (task.mergeA = true) execute both of the above
   simultaneously.

### Feature 1: Blocking MainPipe Entry
GrantBuf also provides [request entry blocking information] to ReqArb based on:
[pipeline entry information + pipeline stage S1/S2/S3/S4/S5 status + internal
pftRespQueue, inflightGrant, grantQueue status].

Statistics for three types of resources:
-  GrantBuf resource shortage: Occupied GrantBuf count + potential GrantBuf
   count in pipeline stages S1/S2/S3/S4/S5 (from sinkA or sinkC) > 16
-  Channel E resource shortage: inflightGrant + potential GrantAck returns
   requiring Channel E in pipeline stages S1/S2/S3/S4/S5 (from sinkA) > 16
-  Prefetch RespQueue resource shortage: Occupied pftRespQueue count + potential
   preRespQueue usage in pipeline stages S1/S2/S3/S4/S5 (from sinkA) > 10

Conditions for blocking channel entry into MainPipe at S1
-  A-channel: Any of the above resource insufficiencies
-  Channel B: As long as the inflightGrant buffer contains an uncompleted
   operation with the same address as Channel B
-  Channel C: GrantBuf resource shortage

Three types of MSHR resource shortages (maximum resources -1):
-  GrantBuf resource shortage: Occupied GrantBuf count + potential GrantBuf
   count in pipeline stages S1/S2/S3/S4/S5 (from sinkA or sinkC) > 15
-  Insufficient E-channel resources: inflightGrant + the number of GrantAcks
   potentially required from the pipeline stages S1/S2/S3/S4/S5 (from sinkA) >
   15
-  Prefetch RespQueue resource shortage: Occupied pftRespQueue count + potential
   preRespQueue usage in pipeline stages S1/S2/S3/S4/S5 (from sinkA) > 9

The blocking condition for MSHR to enter Mainpipe is any one of the above three
scenarios


### Feature 2: Early Wake-up
The CustomL1Hint module in MainPipe issues the l1Hint signal 3 cycles before
GrantBuf to facilitate early wake-up of missq in L1D$. GrantBuffer provides
resource information to block the pipeline entry at S1, while MainPipe precisely
predicts when to issue the l1Hint signal based on scenarios already in the
pipeline.

### Feature 3: Handling of different data widths
For Grants/ReleaseAcks containing one beat, they are dequeued from grantQueue
and directly sent to the bus. For GrantData containing two beats, the first beat
is sent directly to the bus upon dequeuing, while the second beat is stored in
grantBuf. The data in grantBuf is then prioritized for sending. After grantBuf
is emptied, the next element in grantQueue can be dequeued.

## Overall Block Diagram
![GrantBuffer](./figure/GrantBuf.svg)




