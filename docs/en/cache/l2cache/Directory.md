# Directory

CoupledL2 adopts a directory-based coherence implementation, utilizing the
directory to record metadata information of data blocks within the L2 Cache. As
shown in [@fig:directory], the Directory checks whether the L2 Cache stores the
requested data block (hit or miss) based on the tag and set of the read request.
If it hits, the metadata information of that data block is returned. If it
misses, an invalid way or a way to be replaced is selected, and the metadata
information of that way's data is returned. After processing the request, the
new directory information is written back to the Directory for updates.

![Directory Pipeline Block Diagram](./figure/directory.svg){#fig:directory}
