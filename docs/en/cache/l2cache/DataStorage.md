# Data SRAM DataStorage

The DataStorage module is responsible for reading and writing the CoupledL2 data
SRAM, constructed using single-port SRAM. Requests only interact with
DataStorage during the MainPipe s3 pipeline stage. DataStorage can handle only
one read or write request per clock cycle.
