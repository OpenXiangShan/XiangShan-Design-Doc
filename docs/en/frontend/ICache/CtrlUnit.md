# CtrlUnit {#sec:icache-ctrlunit}

Currently, CtrlUnit is mainly responsible for ECC check enable/error injection features.

## Parameter List

See `case class ICacheCtrlUnitParameters` in `Parameters.scala`. Selected parameters are listed below:

| Parameter | Default | Description | Requirement |
| --- | ------ | --------- | ------ |
| Address | AddressSet(0x38022080, 0x7f) | MMIO-mapped CSR address range of CtrlUnit | See below |
| BeatBytes | 8 | Bus width of CtrlUnit | Power of 2 and <= 8 |

## MMIO-mapped CSR

CtrlUnit implements a set of MMIO-mapped CSRs connected on TileLink bus. Address is configurable by parameter `Address`, with default `0x38022080`. Total size is 128B.

Implemented CSRs are:

```plain
              64     10        7         4         2        1        0
0x00 eccctrl   | WARL | ierror | istatus | itarget | inject | enable |

              64 PAddrBits-1               0
0x08 ecciaddr  | WARL |       paddr        |
```

| CSR | field | desp |
| --- | --- | ------------ |
| eccctrl | enable | ECC check enable, originally `sfetchctl(0)` |
| eccctrl | inject | ECC injection enable, write 1 to start injection, always reads 0 |
| eccctrl | itarget | ECC injection target, see table below |
| eccctrl | istatus | ECC injection status (read-only), see table below |
| eccctrl | ierror | ECC error reason (read-only), valid only when `eccctrl.istatus===error`, see table below |
| ecciaddr | paddr | ECC injection physical address |

`eccctrl.itarget`:

| value | target |
| --- | --- |
| 0 | metaArray |
| 2 | dataArray |
| 1/3 | rsvd |

`eccctrl.istatus`:

| value | status |
| --- | --- |
| 0 | idle |
| 1 | working |
| 2 | injected |
| 7 | error |
| 3-6 | rsvd |

`eccctrl.ierror`:

| value | error |
| --- | --- |
| 0 | ECC is not enabled (i.e. `!eccctrl.enable`) |
| 1 | Invalid inject target SRAM (i.e. `eccctrl.itarget==rsvd`) |
| 2 | Inject target address (i.e. `ecciaddr.paddr`) is not in ICache |
| 3-7 | rsvd |

## ECC Check Enable

`eccctrl.enable` in CtrlUnit is directly connected to MainPipe and controls ECC check enable. When this bit is 0, ICache does not perform ECC checking. But check bits are still calculated and stored during refill, which may add a small amount of power overhead. If check bits are not calculated, then switching from disabled to enabled requires flushing ICache (otherwise read parity code may be incorrect).

## ECC Injection Enable

CtrlUnit uses an internal state machine to control injection process. Its internal status (note: different from `eccctrl.istatus`) is:

- idle: injection controller is idle
- readMetaReq: send MetaArray read request
- readMetaResp: receive MetaArray read response
- writeMeta: write MetaArray
- writeData: write DataArray

When software writes 1 to `eccctrl.inject`, the following checks are performed. If checks pass, state machine enters `readMetaReq`:

- If `eccctrl.enable` is 0, report error `eccctrl.ierror=0`
- If `eccctrl.itarget` is rsvd (1/3), report error `eccctrl.ierror=1`

In `readMetaReq`, CtrlUnit sends a set-read request to MetaArray using set from `ecciaddr.paddr`, then waits for handshake. After handshake, it enters `readMetaResp`.

In `readMetaResp`, CtrlUnit receives MetaArray response and checks whether ptag from `ecciaddr.paddr` hits. If no hit, report error `eccctrl.ierror=2`. Otherwise, enter `writeMeta` or `writeData` based on `eccctrl.itarget`.

In `writeMeta` or `writeData`, CtrlUnit writes arbitrary data into MetaArray/DataArray while asserting `poison`. After write completes, state machine enters `idle`.

At ICache top level, a Mux is implemented: when CtrlUnit state machine is not `idle`, MetaArray/DataArray read/write ports are connected to CtrlUnit instead of MainPipe/PrefetchPipe/MissUnit. When state machine is `idle`, the opposite applies.
