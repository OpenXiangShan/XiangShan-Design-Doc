# 昆明湖 BPU 模块文档

## 术语说明

## 设计规格

## 功能描述

## 总体设计

## 寄存器配置

Table: BPU 相关 CSR 列表

+---------+-------+----------+------+----------------------------------------------------------------------+
| 寄存器  | 地址  | 复位值   | 属性 | 描述                                                                 |
+=========+=======+==========+======+======================================================================+
| sbpctl  | 0x5C0 | 64'd0    | RW   | bit0: ubtb 使能信号                                                  |
|         |       |          |      |                                                                      |
|         |       |          |      | bit1: abtb 使能信号                                                  |
|         |       |          |      |                                                                      |
|         |       |          |      | bit2: mbtb 使能信号                                                  |
|         |       |          |      |                                                                      |
|         |       |          |      | bit3: Tage 使能信号                                                  |
|         |       |          |      |                                                                      |
|         |       |          |      | bit4: Sc 使能信号                                                    |
|         |       |          |      |                                                                      |
|         |       |          |      | bit5: Ittage 使能信号                                                |
|         |       |          |      |                                                                      |
|         |       |          |      | bit6: Ras 使能信号                                                   |
|         |       |          |      |                                                                      |
|         |       |          |      | 需要注意：虽然这个寄存器可以任意配置，但预测器间存在依赖关系，例如： |
|         |       |          |      |                                                                      |
|         |       |          |      | - Tage、Sc、Ittage、Ras 依赖 mbtb；                                  |
|         |       |          |      |                                                                      |
|         |       |          |      | - Sc 依赖 Tage。                                                     |
|         |       |          |      |                                                                      |
|         |       |          |      | 当预测器依赖的预测器被禁用时，其自身也会被禁用，                     |
|         |       |          |      |                                                                      |
|         |       |          |      | 这**不会**反映在该 CSR 的值上。                                      |
+---------+-------+----------+------+----------------------------------------------------------------------+

注：RO——只读寄存器；RW——可读可写寄存器。

## 参考文档

1. Reinman G, Austin T, Calder B. A scalable front-end architecture for fast instruction delivery[J]. ACM SIGARCH Computer Architecture News, 1999, 27(2): 234-245.
2. Perais A, Sheikh R, Yen L, et al. Elastic instruction fetching[C]//2019 IEEE International Symposium on High Performance Computer Architecture (HPCA). IEEE, 2019: 478-490.
3. Software Optimization Guide for AMD Family 19h Processors (PUB), Chap. 2.8.1.5, <https://www.amd.com/system/files/TechDocs/56665.zip>
4. Seznec A, Michaud P. A case for (partially) TAgged GEometric history length branch prediction[J]. The Journal of Instruction-Level Parallelism, 2006, 8: 23.
5. Seznec A. A 256 kbits l-tage branch predictor[J]. Journal of Instruction-Level Parallelism (JILP) Special Issue: The Second Championship Branch Prediction Competition (CBP-2), 2007, 9: 1-6.
6. Seznec A. A new case for the tage branch predictor[C]//Proceedings of the 44th Annual IEEE/ACM International Symposium on Microarchitecture. 2011: 117-127.
7. Seznec A. The O-GEHL branch predictor[J]. The 1st JILP Championship Branch Prediction Competition (CBP-1), 2004.
8. Jiménez D A, Lin C. Dynamic branch prediction with perceptrons[C]//Proceedings HPCA Seventh International Symposium on High-Performance Computer Architecture. IEEE, 2001: 197-206.
9. Seznec A. A 64-Kbytes ITTAGE indirect branch predictor[C]//JWAC-2: Championship Branch Prediction. 2011.
