# 数据 SRAM DataStorage

DataStorage 模块负责 CoupledL2 数据 SRAM 的读写，采用单端口 SRAM 搭建。请求只会在 MainPipe s3 流水级与
DataStorage 交互。DataStorage 每拍只能处理一个读请求或写请求。
