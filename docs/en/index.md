# Preface {.unnumbered .unlisted}

XiangShan's native AI processor, XiangShan AI (XSAI), is an AICPU that integrates high-performance general-purpose computing and AI inference.

This document, _XiangShan Native AI Processor Design Document_, describes the microarchitecture and implementation of the XSAI processor IP.

XSAI builds on the Kunminghu V2 microarchitecture. Its main components are the control core, the CUTE matrix compute unit, and the high-bandwidth L2 cache (HBL2). The control core handles general-purpose computing, vector operations, and matrix task control. CUTE performs matrix computation, and HBL2 provides coherent memory access for the control core and CUTE. See [Architecture Overview](overview.md) for the main modules and their relationships.

The online documentation and PDF releases are available at:

* Website: [Kunminghu V2R2A (XSAI) Design Document](https://docs.xiangshan.cc/projects/design/en/kunminghu-v2r2a/)
* PDF releases: [XiangShan-Design-Doc Releases](https://github.com/OpenXiangShan/XiangShan-Design-Doc/releases)

You can visit the XiangShan Documentation website [docs.xiangshan.cc](https://docs.xiangshan.cc/) for more documents.

Chinese is the source language of this document. The source files are hosted on GitHub, and the English version is updated alongside the Chinese content. You are welcome to help improve the documentation through proofreading, corrections, and translation.

## Notice {.unnumbered .unlisted}

Copyright © 2024–2025 The XiangShan Team · Beijing Institute of Open Source Chip

This document is publicly released under the “[Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/deed.zh-hans)” license. You are free to use, modify, and distribute this document under the terms of the license, provided that you give appropriate credit, indicate the original license, and note if any changes were made. For full details, please refer to the complete legal text published by Creative Commons.

This document provides interim information and may be updated periodically as needed. Unless otherwise specified, all statements, information, and recommendations contained herein do not constitute any express or implied warranties.

## Version Information {.unnumbered .unlisted}

The {{processor_name}} design described here corresponds to the following source versions. XSAI uses the remote `origin/master` commit verified on 2026-10-16; CUTE and XSAICache use the submodule pointers recorded by that commit:

| Repository                                              | Branch or Integration Source | Source Commit                              |
| ------------------------------------------------------- | ---------------------------- | ------------------------------------------ |
| [XSAI](https://github.com/OpenXiangShan/XSAI) | `origin/master` | [`ee268923b717`](https://github.com/OpenXiangShan/XSAI/commit/ee268923b7175d79a9d0183a0181a684ccec9487) |
| [CUTE](https://github.com/OpenXiangShan/CUTE) | XSAI submodule pointer | [`d27b93d61c35`](https://github.com/OpenXiangShan/CUTE/commit/d27b93d61c359478f4202f8f42cbfe82c830912a) |
| [XSAICache](https://github.com/OpenXiangShan/XSAICache) | XSAI submodule pointer | [`1186ab336ad1`](https://github.com/OpenXiangShan/XSAICache/commit/1186ab336ad130767f6e86fd6afc7cd1d24d1098) |

This document uses `DefaultMatrixConfig`: each AB matrix register holds 8 KiB, each C accumulator register holds 64 KiB, AB rows are 64 B wide, and L2 has 8 banks. CUTE uses the compute array parameters of `CUTE_8Tops_128SCP`, with tensor dimensions set from the control core's matrix parameters. Matrix prefetching is disabled in this configuration; the relevant chapters describe configurations with matrix prefetching, standalone CUTE presets, and the parameters and interfaces of other loaders.

| Date       | Version         | Description                                                   |
| ---------- | --------------- | ------------------------------------------------------------- |
| 2026-10-16 | kunminghu-v2r2a | XSAI control core, matrix memory paths, HBL2, and CUTE design |
