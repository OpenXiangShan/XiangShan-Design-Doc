# 目录 Directory

CoupledL2 采用基于目录的一致性实现方式，利用目录记录L2 Cache内数据块的元数据信息。如 [@fig:directory]
所示，Directory 会根据读请求的 tag 和 set，查找 L2 Cache
是否存储该数据块（是否命中）。如果命中，则返回该数据块的元数据信息。如果缺失，则挑选一个无效的路/被替换的路，返回该路数据的元数据信息。请求处理完成后，会将新的目录信息写入Directory进行更新。

![目录流水线框图](./figure/directory.svg){#fig:directory}
