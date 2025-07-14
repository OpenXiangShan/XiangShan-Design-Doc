# CtrlUnit Submodule Documentation

Currently, CtrlUnit mainly handles ECC check enable/error injection functions

## mmio-mapped CSR

CtrlUnit implements a set of mmio-mapped CSRs connected to the tilelink bus,
with the address configurable via parameter `cacheCtrlAddressOpt`, defaulting to
`0x38022080`. The total size is 128B.

When parameter `cacheCtrlAddressOpt` is `None`, CtrlUnit **will not be
instantiated**. In this case, ECC check enable**is enabled by default**, and
software cannot disable it; software cannot control error injection.

Currently implemented CSRs are as follows:

```plain
              64     10        7         4         2        1        0
0x00 eccctrl   | WARL | ierror | istatus | itarget | inject | enable |

              64 PAddrBits-1               0
0x08 ecciaddr  | WARL |       paddr        |
```

| CSR      | field   | desp                                                                                     |
| -------- | ------- | ---------------------------------------------------------------------------------------- |
| eccctrl  | enable  | ECC error check enable, originally `sfetchctl(0)`                                        |
| eccctrl  | inject  | ECC error injection enabled, write 1 to start injection, read always 0                   |
| eccctrl  | itarget | ECC error injection target, see table below                                              |
| eccctrl  | istatus | ECC error injection status (read-only), see table below                                  |
| eccctrl  | ierror  | ECC error reason (read-only), valid only when `eccctrl.istatus===error`, see table below |
| ecciaddr | paddr   | ECC error injection physical address                                                     |

`eccctrl.itarget`:

| value | target    |
| ----- | --------- |
| 0     | metaArray |
| 2     | dataArray |
| 1/3   | rsvd      |

`eccctrl.istatus`:

| value | status   |
| ----- | -------- |
| 0     | Idle     |
| 1     | working  |
| 2     | injected |
| 7     | error    |
| 3-6   | rsvd     |

`eccctrl.ierror`:

| value | error                                                                         |
| ----- | ----------------------------------------------------------------------------- |
| 0     | ECC not enabled (i.e., `!eccctrl.enable`)                                     |
| 1     | Inject target SRAM invalid (i.e. `eccctrl.itarget==rsvd`)                     |
| 2     | The target address for injection (i.e. `ecciaddr.paddr`) is not in the ICache |
| 3-7   | rsvd                                                                          |

## Error Check Enable

The `eccctrl.enable` bit of CtrlUnit is directly connected to MainPipe,
controlling ECC check enable. When this bit is 0, ICache will not perform ECC
checks. However, it still calculates and stores the check code during refill,
which may incur slight additional power consumption; if not calculated, flushing
ICache is required when switching from disabled to enabled (otherwise the read
parity code may be incorrect).

## Error Injection Enable

The CtrlUnit internally uses a state machine to control the error injection
process, with its status (note: different from `eccctrl.istatus`) as follows:

- idle: Injection controller idle
- readMetaReq: Send read request to metaArray
- readMetaResp: Receives read metaArray response
- writeMeta: Write to metaArray
- writeData: Writes to dataArray

When software writes 1 to `eccctrl.inject`, the following simple checks are
performed. If passed, the state machine transitions to the `readMetaReq` state:

- If `eccctrl.enable` is 0, report error `eccctrl.ierror=0`
- If `eccctrl.itarget` is rsvd(1/3), report error `eccctrl.ierror=1`

In the `readMetaReq` state, CtrlUnit sends a read request to MetaArray for the
set corresponding to address `ecciaddr.paddr`, waiting for handshake. After
handshake, it transitions to the `readMetaResp` state.

In the `readMetaResp` state, CtrlUnit receives the response from MetaArray and
checks whether the ptag corresponding to the `ecciaddr.paddr` address hits. If
not, it reports error `eccctrl.ierror=2`. Otherwise, based on `eccctrl.itarget`,
it transitions to either the `writeMeta` or `writeData` state.

In the `writeMeta` or `writeData` state, CtrlUnit writes arbitrary data to
MetaArray/DataArray while asserting the `poison` bit. After writing, the state
machine transitions to the `idle` state.

The ICache top level implements a Mux. When the CtrlUnit's state machine is not
in `idle`, it connects the read/write ports of MetaArray/DataArray to CtrlUnit
instead of MainPipe/IPrefetchPipe/MissUnit. When the state machine is in `idle`,
the opposite occurs.
