# Preface {.unnumbered .unlisted}

This document is _XiangShan Open-Source Processor Design Document_, providing a detailed introduction to the microarchitecture design and implementation of {{processor_name}}.

You can obtain the latest version of this document from:

* Website: [https://docs.xiangshan.cc/projects/design/](https://docs.xiangshan.cc/projects/design/)
* PDF file: [https://github.com/OpenXiangShan/XiangShan-Design-Doc/releases](https://github.com/OpenXiangShan/XiangShan-Design-Doc/releases)

You can visit the XiangShan Documentation website [docs.xiangshan.cc](https://docs.xiangshan.cc/) for more documents.

The original language of this document is Chinese. It is hosted on GitHub and collaboratively translated using the Weblate platform. You are welcome to join us in proofreading, correcting errors, and contributing to the translation to help improve the documentation!

## Notice {.unnumbered .unlisted}

Copyright © 2024–2025 The XiangShan Team · Beijing Institute of Open Source Chip

This document is publicly released under the “[Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/deed.zh-hans)” license. You are free to use, modify, and distribute this document under the terms of the license, provided that you give appropriate credit, indicate the original license, and note if any changes were made. For full details, please refer to the complete legal text published by Creative Commons.

This document provides interim information and may be updated periodically as needed. Unless otherwise specified, all statements, information, and recommendations contained herein do not constitute any express or implied warranties.

## Version Information {.unnumbered .unlisted}

XSAI builds on the Kunminghu V2 control core, integrates the CUTE matrix compute unit, and extends instruction decode, matrix configuration, task scheduling, and memory paths. The XSAI design described here corresponds to the following source versions:

| Repository                                              | Branch or Integration Source | Source Commit                              |
| ------------------------------------------------------- | ---------------------------- | ------------------------------------------ |
| [XSAI](https://github.com/OpenXiangShan/XSAI)           | `master`                     | `e8fb1a14fc85e05696e8b69a4ebfd2ca7cd1672f` |
| [CUTE](https://github.com/OpenXiangShan/CUTE)           | XSAI-pinned commit           | `d27b93d61c359478f4202f8f42cbfe82c830912a` |
| [XSAICache](https://github.com/OpenXiangShan/XSAICache) | XSAI-pinned commit           | `1186ab336ad130767f6e86fd6afc7cd1d24d1098` |

This document uses `DefaultMatrixConfig`: each AB matrix register holds 8 KiB, each C accumulator register holds 64 KiB, AB rows are 64 B wide, and L2 has 8 banks. CUTE uses the compute array parameters of `CUTE_8Tops_128SCP`, with tensor dimensions set from the control core's matrix parameters. Matrix prefetching is disabled in this configuration; the relevant chapters describe configurations with matrix prefetching, standalone CUTE presets, and the parameters and interfaces of other loaders.

| Date       | Version         | Description                                                   |
| ---------- | --------------- | ------------------------------------------------------------- |
| 2026-10-13 | kunminghu-v2r2a | XSAI control core, matrix memory paths, HBL2, and CUTE design |
