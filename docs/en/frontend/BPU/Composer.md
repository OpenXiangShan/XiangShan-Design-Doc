# BPU Submodule: Composer

## Functional Overview

Composer is a module designed to combine multiple predictors. In Nanhu, it
integrates five predictors—uFTB, FTB, TAGE-SC, ITTAGE, and RAS—and abstracts
them into a three-stage pipelined coverage predictor. Each predictor within
Composer can be enabled or disabled by writing to the custom register sbpctl,
allowing for on-demand usage. Upon detecting an external redirect, Composer
forwards the redirect request to each predictor to recover speculatively updated
elements. After all instructions in the prediction block are committed, the
predictors within Composer undergo training. Finally, Composer outputs the
three-stage prediction results to the Predictor.

During internal redirects in the three-stage BPU pipeline, only speculatively
updated states—such as branch history and RAS—are restored in case of prediction
errors. Other predictor updates are performed post-commit.

If the predictor is not flushed and only the pipeline is refreshed, wouldn't the
same location predict incorrectly again? Refreshing the pipeline starts
prediction from the corrected path. If the subsequent path revisits the same
location, it might predict the same result again. However, due to differing
branch histories, the predictors like TAGE could index different entries.

If a target address error is detected during execution, no redirect is initiated
immediately. Instead, the redirect is uniformly deferred until instruction
commit. One reason for this design is that misprediction redirects occur on
incorrect paths, where execution results may also be erroneous. Training under
such conditions could potentially corrupt the predictors.

### Configuration of the starting PC

Composer's IO interface io_reset_vector enables configuration of the starting
PC. The desired starting PC only needs to be passed to this IO.

### Connection with Predictors

Composer connects the five predictors—uFTB, FTB, TAGE-SC, ITTAGE, and RAS. Since
there are three branch predictor pipeline stages, and each predictor has a fixed
latency (completing prediction by its designated stage), Composer simply outputs
the corresponding predictor's result at the appropriate pipeline stage.

Meta refers to the data used by predictors during prediction, which is retrieved
during updates for training. They are all called meta because the Composer
integrates all predictors and interacts with the outside world through a common
meta interface.

### Predictor enable/disable

Through Zicsr instructions, we can read and write the custom CSR sbpctl to
control the enablement of various predictors in the Composer. sbpctl[6:0]
represents the enablement of seven predictors: {LOOP, RAS, SC, TAGE, BIM, BTB,
uFTB}. A high level indicates enablement, while a low level indicates
disablement. Specifically, the value of the spbctl CSR is passed to each
predictor through the Composer's IO interface io_ctrl_*, with each predictor
responsible for implementing the enablement.

### Redirection recovery

The Composer receives redirection requests through IO ports such as
io_s2_redirect, io_s3_redirect, and io_redirect_*. These requests are sent to
its predictors to recover speculatively updated elements, such as the top item
of the RAS stack.

### Predictor training

The Composer sends training signals to its predictors through the IO port
io_update_*. In general, to prevent contamination of predictor contents by
incorrect execution paths, each predictor is trained after all instructions in
the prediction block are committed. Their training content comes from their own
prediction information and the decoding and execution results of instructions in
the prediction block, which are read from the FTQ and sent back to the BPU. The
prediction information is packed and stored in the FTQ after prediction; the
decoding results of instructions come from the IFU's pre-decoding module and are
written back to the FTQ after fetching the instructions; and the execution
results come from various execution units.

## Overall Block Diagram

![Composer Module Overall Block Diagram](../figure/BPU/Composer/structure.png)

## Interface timing

### Control signal Ctrl interface timing

![Control Signal Ctrl Interface Timing](../figure/BPU/Composer/port1.png)

The above diagram illustrates a timing example of the Composer module's control
signal Ctrl interface. The io_ctrl signal is delayed by one cycle after entering
the Composer module before being passed to the internal components submodule.

### Redirection interface timing

![Redirection interface timing](../figure/BPU/Composer/port2.png)

The above diagram shows the redirection request interface of the Composer
module. After the BPU receives a redirection request from the backend, it is
delayed by one cycle before being sent to the Composer, so the predictors inside
the Composer receive the corresponding request one cycle later.

### Branch prediction block training interface timing

![Branch Prediction Block Training Interface
Timing](../figure/BPU/Composer/port3.png)

Similar to redirection, to optimize timing, the update interface for branch
prediction block training is also delayed by one cycle within the BPU before
being sent to the Composer and its internal predictors.

## Key circuits

The following diagrams illustrate the Composer meta concatenation and the
arbitration logic for redirection/branch history update sources.

![Composer meta concatenation](../figure/BPU/Composer/key_structure1.png)

![Redirect/Branch History Update Source Arbitration
Logic](../figure/BPU/Composer/key_structure2.png)
