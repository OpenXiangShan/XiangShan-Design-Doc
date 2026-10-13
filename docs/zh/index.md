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

本分支介绍在昆明湖 V2 控制核基础上集成 CUTE 的 XSAI 实现。XSAI 专有部分按以下固定源码基线编写；配置、接口和实现范围与通用昆明湖 V2R2 说明有差异时，以相应章节的 XSAI 说明为准。

| 仓库 | 分支或集成来源 | 源码提交 |
| --- | --- | --- |
| [XSAI](https://github.com/OpenXiangShan/XSAI) | `master` | `e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f` |
| [CUTE](https://github.com/OpenXiangShan/CUTE) | XSAI 记录的版本，与本次核查的 `master` 一致 | `d27b93d61c359478f4202f8f42cbfe82c830912a` |
| [XSAICache](https://github.com/OpenXiangShan/XSAICache) | XSAI 记录的版本，与本次核查的 `master` 一致 | `1186ab336ad130767f6e86fd6afc7cd1d24d1098` |

本文默认矩阵配置为 `DefaultMatrixConfig`。独立 CUTE 预设、可选加载器及矩阵预取实验配置在相关章节中分别说明，不作为默认配置的能力。

| 日期       | 版本            | 说明                                         |
| ---------- | --------------- | -------------------------------------------- |
| 2026-10-13 | kunminghu-v2r2a | XSAI 控制核、矩阵访存、HBL2 与 CUTE 设计说明 |
