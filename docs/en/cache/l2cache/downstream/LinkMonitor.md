# Link Layer Controller LinkMonitor

## Functional Description
The LinkMonitor module converts messages based on Valid-Ready handshakes into
L-Credit-based handshakes while maintaining the power states of the TX and RX
links. For details, refer to the CHI Spec Link Handshake chapter.

### Feature 1: Decoupled Handshake to L-Credit Handshake
The Decoupled handshake from the three TX channels is converted into an LCredit
handshake via the Decoupled2LCredit module. The Decoupled2LCredit module records
the number of LCredits received by the downstream ICN (lcreditPool). Only when
lcreditPool is greater than 0 can it accept upstream Decoupled requests; upon
successful Decoupled handshake, the lcreditPool count decreases by one.

Impact of TX Link State: When the TX link state is STOP or ACTIVATE, the
reception of Decoupled messages should be halted. If the TX link state is STOP,
the reception of LCredit should also be stopped, and the lcreditPool should
remain unchanged even if the downstream lcrdv signal pulls the lcreditPool high.

### Feature 2: L-Credit Handshake to Decoupled Handshake
The LCredit handshake received from the three RX channels is converted into a
Decoupled handshake via the LCredit2Decoupled module. The LCredit2Decoupled
module maintains a default 4-entry queue (configurable as lcreditNum, with
lcreditNum ≤ 15) to temporarily store messages, meaning an RX channel can send
up to lcreditNum outstanding LCredits downstream. It also maintains a counter
(lcreditPool) initialized to lcreditNum, tracking the maximum number of LCredits
the channel can currently send. When lcreditPool > the number of valid queue
entries (queueCnt), it indicates the channel has sent fewer outstanding LCredits
than the queue can receive, allowing the channel to send LCredits downstream.
When lcreditPool < lcreditNum, the channel should unconditionally accept valid
downstream requests, i.e., those with flitv high and flitpending high in the
previous cycle.

Impact of RX Link State: If the RX link state is not RUN, the channel should not
send LCredits downstream, even if lcreditPool > the number of valid queue
entries.

### Feature 3: TXSACTIVE and RXSACTIVE
TXSACTIVE is always held high. RXSACTIVE is currently unused.

### Feature 4: Interface activation and deactivation
TXLINKACTIVEREQ remains high after reset. RXLINKACTIVEACK is set to true in the
next cycle after RXLINKACTIVEREQ is set to true; starting from the cycle after
RXLINKACTIVEREQ is set to false, it monitors the states of the three RX
channels. Once all outstanding LCredits are reclaimed (i.e., lcreditPool equals
lcreditNum), RXLINKACTIVEACK can be set to false.

## Overall Block Diagram
![LinkMonitor](./figure/LinkMonitor.svg)
