---
name: xiangshan-doc-alignment
description: Translate or incrementally align XiangShan design documentation from docs/zh to docs/en, including chapter navigation and shared assets. Use for Chinese-to-English document synchronization in XiangShan-Design-Doc.
---

# XiangShan Documentation Alignment

Use the repository's [documentation alignment agent](../../../.github/agents/doc-alignment.agent.md) as the workflow. Read it before editing. Chinese documents are the source of truth; retain existing equivalent English and preserve the source's line structure, references, and shared assets.

Run commands from the `XiangShan-Design-Doc` root, identified by `mkdocs-zh.yml` and `mkdocs-en.yml`. The helper paths in the agent are relative to this root. Keep the task's existing Git permissions and publication scope.

Use [ref-checker.py](../../../tools/lint/ref-checker.py) for the Chinese pre-check and English post-check. On Windows, use `python -X utf8 tools/lint/ref-checker.py <path>` and inspect both stdout and stderr. Check the two language trees separately. Verify reported missing references against their definitions, especially compound references such as `[@fig:a;@fig:b]`.

The English and shared `.index.md` and figure files use relative symbolic links. A Windows checkout with `core.symlinks=false` may expose a tracked link as a small file containing its target path. Inspect its Git mode with read-only `git ls-files --stage` and resolve the relative target chain to read the asset. Preserve these link-target files when editing prose. For local build previews, materialize assets in a generated build directory; maintain the repository's shared-link structure for source files. For recursive reference checks on such checkouts, use the materialized language tree, or pass real Markdown content files as explicit arguments so the checker reads document content.

The [lint runner](../../../tools/lint/run-lint.sh) supports `TARGET` and `AUTOFIX`. For a read-only check, use `AUTOFIX=false` and set `TARGET` to the intended document scope. Its default enables automatic fixes, so choose the mode explicitly before running it.
