# 前言 {.unnumbered .unlisted}

香山原生AI处理器，简称香山AI（XSAI），是一款兼顾高性能通用计算和AI推理的“通推一体” AICPU。

本文档为《香山原生AI处理器设计文档》，详细介绍了 XSAI 处理器 IP 的微架构设计实现细节。

XSAI 基于昆明湖 V2 微架构，主要包括控制核、CUTE 矩阵计算单元和高带宽二级缓存 HBL2。控制核承担通用计算、向量运算和矩阵任务控制，CUTE 执行矩阵计算，HBL2 为控制核与 CUTE 提供一致性存储访问。主要模块及协作关系见[总体架构](overview.md)。

本文档的在线版本与 PDF 发布页如下：

* 网页版：[昆明湖 V2R2A（XSAI）设计文档](https://docs.xiangshan.cc/projects/design/zh-cn/kunminghu-v2r2a/)
* PDF 发布页：[XiangShan-Design-Doc Releases](https://github.com/OpenXiangShan/XiangShan-Design-Doc/releases)

您可访问香山文档网站 [docs.xiangshan.cc](https://docs.xiangshan.cc/) 获取更多文档。

本文档以中文为源文档，源文件托管于 GitHub，英文版随中文内容同步更新。欢迎您参与校对、纠错与翻译工作，共同完善文档内容！

## 声明 {.unnumbered .unlisted}

版权所有 © 2024 - 2025 香山开源处理器团队·北京开源芯片研究院

本文档采用“[知识共享 署名 4.0](https://creativecommons.org/licenses/by/4.0/deed.zh-hans)”协议公开发布。您可以根据该协议的规定，自由地使用、修改、分发本文档，但必须给出恰当的署名、表明原始许可协议、标注是否对原始文档作了修改。具体许可条款以知识共享组织公布的完整法律文本为准。

本文档仅提供阶段性信息，可能不定期根据实际情况更新。除非另有约定，本文档中的所有陈述、信息和建议不构成任何明示或暗示的担保。

## 版本信息 {.unnumbered .unlisted}

本文所述 {{processor_name}} 设计对应以下源码版本。XSAI 采用 2026-10-16 核对的远程 `origin/master` 提交，CUTE 和 XSAICache 采用该提交记录的子模块指针：

| 仓库 | 分支或集成来源 | 源码提交 |
| --- | --- | --- |
| [XSAI](https://github.com/OpenXiangShan/XSAI) | `origin/master` | [`ee268923b717`](https://github.com/OpenXiangShan/XSAI/commit/ee268923b7175d79a9d0183a0181a684ccec9487) |
| [CUTE](https://github.com/OpenXiangShan/CUTE) | XSAI 子模块指针 | [`d27b93d61c35`](https://github.com/OpenXiangShan/CUTE/commit/d27b93d61c359478f4202f8f42cbfe82c830912a) |
| [XSAICache](https://github.com/OpenXiangShan/XSAICache) | XSAI 子模块指针 | [`1186ab336ad1`](https://github.com/OpenXiangShan/XSAICache/commit/1186ab336ad130767f6e86fd6afc7cd1d24d1098) |

本文采用 `DefaultMatrixConfig`：每个 AB 矩阵寄存器容量为 8 KiB，每个 C 累加寄存器容量为 64 KiB，AB 行宽为 64 B，L2 配置为 8 个 bank，CUTE 采用 `CUTE_8Tops_128SCP` 的计算阵列参数，并按控制核的矩阵参数设置张量维度。该配置关闭矩阵预取；启用矩阵预取的配置、独立 CUTE 预设和其他加载器的参数与接口见相应章节。

| 日期       | 版本            | 说明                                         |
| ---------- | --------------- | -------------------------------------------- |
| 2026-10-16 | kunminghu-v2r2a | XSAI 控制核、矩阵访存、HBL2 与 CUTE 设计说明 |
