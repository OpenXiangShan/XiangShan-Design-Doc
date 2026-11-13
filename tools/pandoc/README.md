# Pandoc resources

These files are managed by the XiangShan documentation Copier template.

Lua filter sources are maintained in the docs-utils root `pandoc_filters/` directory. The template references that directory through a repository-local symlink; Copier expands it into ordinary files under `filters/` in each documentation repository. Shared changes should be made in docs-utils and distributed through a Copier update.

The vendored `include-files.lua` filter's upstream revision and checksum are recorded in [include-files.version](filters/include-files.version), with its MIT license in [include-files.LICENSE](filters/include-files.LICENSE). `template.tex` is licensed under Mulan PSL v2 as recorded in `../LICENSE`.
