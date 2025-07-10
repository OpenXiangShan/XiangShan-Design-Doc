# XiangShan Design Document

![build via pandoc](https://github.com/OpenXiangShan/XiangShan-User-Guide/actions/workflows/build-pandoc.yml/badge.svg)

Documentation for XiangShan Design

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
