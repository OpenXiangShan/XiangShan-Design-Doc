# 前言 {.unnumbered .unlisted}

本文档为《香山开源处理器设计文档》，详细介绍了 {{processor_name}} 的微架构设计实现细节。

您可从以下渠道获取最新版的本文档：

* 网页版：[https://docs.xiangshan.cc/projects/design/](https://docs.xiangshan.cc/projects/design/)
* PDF 文件：[https://github.com/OpenXiangShan/XiangShan-Design-Doc/releases](https://github.com/OpenXiangShan/XiangShan-Design-Doc/releases)

您可访问香山文档网站 [docs.xiangshan.cc](https://docs.xiangshan.cc/) 获取更多文档。

本文档源语言为中文，托管于 GitHub，采用 Weblate 平台进行协作翻译。欢迎您参与校对、纠错与翻译工作，共同完善文档内容！

## 声明 {.unnumbered .unlisted}

版权所有 © 2024 - 2025 香山开源处理器团队·北京开源芯片研究院

本文档采用“[知识共享 署名 4.0](https://creativecommons.org/licenses/by/4.0/deed.zh-hans)”协议公开发布。您可以根据该协议的规定，自由地使用、修改、分发本文档，但必须给出恰当的署名、表明原始许可协议、标注是否对原始文档作了修改。具体许可条款以知识共享组织公布的完整法律文本为准。

本文档仅提供阶段性信息，可能不定期根据实际情况更新。除非另有约定，本文档中的所有陈述、信息和建议不构成任何明示或暗示的担保。

## 版本信息 {.unnumbered .unlisted}

XSAI 基于昆明湖 V2 控制核，集成 CUTE 矩阵计算单元，并扩展指令译码、矩阵配置、任务调度和访存通路。本文所述 XSAI 设计对应以下源码版本：

| 仓库 | 分支或集成来源 | 源码提交 |
| --- | --- | --- |
| [XSAI](https://github.com/OpenXiangShan/XSAI) | `master` | `e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f` |
| [CUTE](https://github.com/OpenXiangShan/CUTE) | XSAI 固定提交 | `d27b93d61c359478f4202f8f42cbfe82c830912a` |
| [XSAICache](https://github.com/OpenXiangShan/XSAICache) | XSAI 固定提交 | `1186ab336ad130767f6e86fd6afc7cd1d24d1098` |

本文采用 `DefaultMatrixConfig`：每个 AB 矩阵寄存器容量为 8 KiB，每个 C 累加寄存器容量为 64 KiB，AB 行宽为 64 B，L2 配置为 8 个 bank，CUTE 采用 `CUTE_8Tops_128SCP` 的计算阵列参数，并按控制核的矩阵参数设置张量维度。该配置关闭矩阵预取；启用矩阵预取的配置、独立 CUTE 预设和其他加载器的参数与接口见相应章节。

| 日期       | 版本            | 说明                                         |
| ---------- | --------------- | -------------------------------------------- |
| 2026-10-13 | kunminghu-v2r2a | XSAI 控制核、矩阵访存、HBL2 与 CUTE 设计说明 |
