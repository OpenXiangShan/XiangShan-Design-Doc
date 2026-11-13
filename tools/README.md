# Managed documentation tooling

This directory is generated and updated by Copier.

- `mkdocs_theme/` contains MkDocs Material overrides.
- `pandoc/` contains the LaTeX template, Lua filters, and common figures.
- `lint/` contains repository-local documentation checks.

The Python-Markdown extensions and the executable Pandoc/TeX toolchain are provided by [`OpenXiangShan/docs-utils`](https://github.com/OpenXiangShan/docs-utils).

Files in this directory are licensed under Mulan PSL v2 unless a more specific notice is present. In particular, `pandoc/filters/include-files.lua` is vendored under the MIT license recorded next to that file, and the logos in `pandoc/figs/` remain all rights reserved.
