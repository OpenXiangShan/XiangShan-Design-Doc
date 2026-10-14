# Write Data Buffer: PutBuffer

## Design Specifications

- Each Slice has 4 entries, each holding one 64 B cache line.
- Each write request consists of two 32 B beats on channel A.
- Supports a beat write from SinkA concurrently with a full-line read from RequestArb.
- The first beat locks the buffer entry; the final beat marks the full line valid.
- Accepts the read request in s2, supplies registered full-line data in s3, and releases the entry read.

## Functional Description

PutBuffer holds the write data carried by matrix PutFullData requests. Request control information enters the main pipeline through RequestBuffer. The `bufIdx` in TaskBundle points to the PutBuffer entry holding the full-line data.

### Feature 1: Allocation and Writing

When SinkA receives the first beat, PutBuffer selects an invalid entry by priority, writes the current beat, and saves the entry number in `sel_r`. Subsequent beats of the same Put use `sel_r`, ensuring that both beats are written to the same buffer entry.

Each write handshake updates the corresponding 32 B data according to the beat number. The entry's valid bit is set only after the final beat is written, indicating that collection of the full line is complete. SinkA also places the selected entry number in the Put task's `bufIdx`; RequestBuffer then retains this index until the task enters the main pipeline.

When all valid PutBuffer entries are occupied, write ready is deasserted, blocking the first beat of a new Put.

### Feature 2: Reading and Releasing

RequestArb identifies a regular channel A PutFullData task in s2 and uses `bufIdx` to issue one full-line read. PutBuffer concatenates the entry's two beats into a DSBlock, registers it for MainPipe in the next cycle, and clears the entry's valid bit.

The PutBuffer entry is released when the full-line data is handed to the main pipeline. MainPipe schedules the data write in s3 according to the directory result:

- Hit in a writable state without an upper-level client: write directly to DataStorage.
- Miss, insufficient permission, or an upper-level client exists: write the data to the RefillBuffer entry for the newly allocated MSHR, awaiting coherence operations and a later refill task.

After transfer to RefillBuffer, the data is managed by MSHR index, and the original PutBuffer entry can serve other requests. See [Request arbiter and main pipeline](ReqArb_MainPipe.md) for the detailed conditions.

## Interface List

Table: Main PutBuffer interfaces

| Interface      | Direction              | Content                                                |
| -------------- | ---------------------- | ------------------------------------------------------ |
| w              | SinkA → PutBuffer      | Decoupled write containing data, beat, first, and last |
| state.entryIdx | PutBuffer → SinkA      | Entry number selected and saved on the first beat      |
| r              | RequestArb → PutBuffer | Valid read request containing buffer entry number id   |
| resp.data      | PutBuffer → MainPipe   | Registered full-line DSBlock                           |

The read interface uses the Valid protocol. A valid read request registers the full-line data and releases the buffer entry. For writes awaiting coherence operations, RefillBuffer holds the data and the MSHR tracks the control state.
