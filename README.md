# XiangShan Design Document

![build via pandoc](https://github.com/OpenXiangShan/XiangShan-User-Guide/actions/workflows/build-pandoc.yml/badge.svg)
[![translation status](https://hosted.weblate.org/widget/openxiangshan/-/en/svg-badge.svg)](https://hosted.weblate.org/engage/openxiangshan/)

Documentation for XiangShan Design

## Translation

We are using [Weblate](https://hosted.weblate.org/projects/openxiangshan/design-doc/) to translate this documentation into English and other languages. Your contributions are welcome — come and help us improve it!

The original language of this document is Chinese. An English translation is currently in progress.

## Build

We use Pandoc and MkDocs to build the document.

### Pandoc

Pandoc is used to build PDF and single-page HTML documents.

```bash
# Install dependencies
bash ./utils/dependency.sh

# Build PDF
make pdf

# Build PDF for print
make pdf TWOSIDE=1

# Build HTML (not ready)
make html

# Build default format (PDF)
make
```

### MkDocs

MkDocs is used to build and deploy a static website on the internet

```bash
# Create and Activate Python Virtual Environments (Recommended)
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r ./utils/requirements.txt

# Preview the website
mkdocs serve -f mkdocs-zh.yml

# Build the website
mkdocs build -f mkdocs-zh.yml
```

## LICENSE

This document is licensed under CC BY 4.0.

Copyright © 2024 The XiangShan Team, Beijing Institute of Open Source Chip
