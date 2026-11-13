# XiangShan Design Document

![build via pandoc](https://github.com/OpenXiangShan/XiangShan-Design-Doc/actions/workflows/build-pandoc.yml/badge.svg)

Documentation for XiangShan Design

## Translation

Your contributions are welcome — come and help us improve it!

The original language of this document is Chinese. An English translation is currently in progress.

## Build

We use Pandoc and MkDocs to build the document.

### Pandoc

Pandoc is used to build PDF and single-page HTML documents.

With Docker installed, use the [docs-utils](https://github.com/OpenXiangShan/docs-utils) build environment:

```bash
docker run --rm -it -v "$(pwd):/work" ghcr.io/openxiangshan/docs-utils:latest
```

Run the commands below inside the container, or locally with the Pandoc/TeX dependencies installed:

```bash
# Build PDF
make pdf

# Build PDF for print
make pdf TWOSIDE=1

# Build HTML
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
pip install -r requirements.txt

# Preview the website
mkdocs serve -f mkdocs-zh.yml

# Build the website
mkdocs build -f mkdocs-zh.yml
```

## Template updates

Commit `.copier-answers.yml` to record the template source and version. A scheduled workflow opens draft PRs for updates; from a clean working tree, update manually with:

```bash
copier update --vcs-ref=master --defaults --conflict rej
```

## LICENSE

This document is licensed under CC BY 4.0. Files under `tools/` use the licenses and notices recorded there.

Copyright © 2024 The XiangShan Team, Beijing Institute of Open Source Chip
