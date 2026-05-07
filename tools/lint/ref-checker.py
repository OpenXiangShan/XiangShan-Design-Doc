"""Checker for references, also check out https://lierdakil.github.io/pandoc-crossref/"""

import argparse
from io import TextIOWrapper
import logging
from pathlib import Path
import re
import sys
from typing import List, Callable, Tuple


class BaseChecker:
    """Base class for checkers"""

    def __init__(self, name: str):
        self.logger = logging.getLogger(name)

    def get_checks(self) -> List[Callable[[TextIOWrapper], int]]:
        """Get the list of checks to perform on each file"""
        return []

    def check(self, path: Path) -> int:
        """Check all files in a directory or a single file"""
        self.logger.info("Checking %s in %s...", self.logger.name, path)
        err = 0
        for check in self.get_checks():
            if path.is_file():
                with path.open() as file:
                    err += check(file)
            elif path.is_dir():
                for filepath in path.rglob("*.md"):
                    with filepath.open() as file:
                        err += check(file)
            else:
                self.logger.critical("Path %s is not a file or directory", path)
        return err


class BaseDefRefChecker(BaseChecker):
    """Base class for checkers that check both definitions and references"""

    def __init__(
        self, name: str, prefix: str, def_pattern: re.Pattern, ref_pattern: re.Pattern
    ):
        super().__init__(name)
        self.prefix = prefix
        self.def_pattern = def_pattern
        self.ref_pattern = ref_pattern
        self.labels = {}

    def _parse_def(self, match: re.Match) -> Tuple[str, str]:
        """Parse a definition match and return the title and label"""
        raise NotImplementedError

    def _check_def(self, file: TextIOWrapper) -> int:
        """Check definitions in a file"""
        err = 0
        for line_num, line in enumerate(file, start=1):
            m = self.def_pattern.match(line)
            if m:
                title, label = self._parse_def(m)
                if label is None:
                    self.logger.warning(
                        "No label at %s:%d (%s)", file.name, line_num, title
                    )
                    err += 1
                elif not label.startswith(self.prefix):
                    self.logger.warning(
                        "Invalid label at %s:%d (%s), label should start with '%s'",
                        file.name,
                        line_num,
                        label,
                        self.prefix,
                    )
                    err += 1
                elif label in self.labels:
                    self.logger.warning(
                        "Duplicate label at %s:%d (%s), original at %s:%d",
                        file.name,
                        line_num,
                        label,
                        *self.labels[label],
                    )
                    err += 1
                else:
                    self.logger.debug(
                        "Found label at %s:%d (%s)", file.name, line_num, label
                    )
                    self.labels[label] = (file.name, line_num)
        return err

    def _parse_ref(self, match: re.Match) -> Tuple[str, str, str]:
        """Parse a reference match and return the cross-ref, file name and file-ref"""
        raise NotImplementedError

    def _check_ref(self, file: TextIOWrapper) -> int:
        """Check references in a file"""
        err = 0
        for line_num, line in enumerate(file, start=1):
            for m in self.ref_pattern.finditer(line):
                cross_ref, file_name, file_ref = self._parse_ref(m)
                if (
                    file_name.startswith("http://")
                    or file_name.startswith("https://")
                    or file_name.startswith("mailto:")
                    or file_name.startswith("base64:")
                ):
                    continue  # Skip external links
                if cross_ref is None:
                    self.logger.warning(
                        "Reference without cross-ref at %s:%d (%s#%s)",
                        file.name,
                        line_num,
                        file_name,
                        file_ref,
                    )
                    err += 1
                elif not cross_ref.startswith(self.prefix):
                    self.logger.warning(
                        "Invalid cross-ref at %s:%d (%s#%s), cross-ref should start with '%s'",
                        file.name,
                        line_num,
                        file_name,
                        cross_ref,
                        self.prefix,
                    )
                    err += 1
                elif file_ref != cross_ref:
                    self.logger.warning(
                        "File-ref mismatch at %s:%d (%s#%s), expected [%s]",
                        file.name,
                        line_num,
                        file_name,
                        file_ref,
                        cross_ref,
                    )
                    err += 1
                elif file_ref not in self.labels:
                    self.logger.warning(
                        "Undefined label at %s:%d (%s#%s)",
                        file.name,
                        line_num,
                        file_name,
                        file_ref,
                    )
                    err += 1
                else:
                    self.logger.debug(
                        "Valid reference at %s:%d (%s#%s -> %s:%d)",
                        file.name,
                        line_num,
                        file_name,
                        file_ref,
                        *self.labels[file_ref],
                    )
        return err

    def get_checks(self) -> List[Callable[[TextIOWrapper], int]]:
        return [self._check_def, self._check_ref]


class SecLabelChecker(BaseDefRefChecker):
    """Checker for section label definitions"""

    def __init__(self):
        super().__init__(
            "sec-label",
            "sec:",
            # definition: # Title {#sec:label}
            re.compile(r"^#+\s+(.+?)(\s*\{#(.+?)\})?\s*$"),
            # reference: [@sec:label] [Title](file.md#sec:label)
            re.compile(r"(\[@(.+?)\] )?\[([^\[\]]+?)\]\((.*?)#(.+?)\)"),
        )

    def _parse_def(self, match: re.Match) -> Tuple[str, str]:
        title, _, label = match.groups()
        return title, label

    def _parse_ref(self, match: re.Match) -> Tuple[str, str, str]:
        _, cross_ref, _, file_name, file_ref = match.groups()
        return cross_ref, file_name, file_ref


class FigLabelChecker(BaseDefRefChecker):
    """Checker for figure label definitions and references"""

    def __init__(self):
        super().__init__(
            "fig-label",
            "fig:",
            # definition: ![Caption](file.png){#fig:label}
            re.compile(r"^!\[(.+?)\]\((.+?)\)(\s*\{#(.+?)\})?\s*$"),
            # reference: [@fig:label]
            re.compile(r"\[@fig:(.+?)\]"),
        )

    def _parse_def(self, match: re.Match) -> Tuple[str, str]:
        title, _, _, label = match.groups()
        return title, label

    def _parse_ref(self, match: re.Match) -> Tuple[str, str, str]:
        cross_ref = f"fig:{match.group(1)}"
        return cross_ref, "", cross_ref


class TblLabelChecker(BaseDefRefChecker):
    """Checker for table label definitions and references"""

    def __init__(self):
        super().__init__(
            "tbl-label",
            "tbl:",
            # definition: Table: Title {#tbl:label}
            re.compile(r"^Table:\s+(.+?)(\s*\{#(.+?)\})?\s*$"),
            # reference: [@tbl:label], also match [@tab:label] to check common mistakes
            re.compile(r"\[@(t(?:bl|ab):.+?)\]"),
        )

    def _parse_def(self, match: re.Match) -> Tuple[str, str]:
        title, _, label = match.groups()
        return title, label

    def _parse_ref(self, match: re.Match) -> Tuple[str, str, str]:
        cross_ref = match.group(1)
        return cross_ref, "", cross_ref


def main():
    """Entry point"""
    parser = argparse.ArgumentParser(
        description="Check section labels in markdown files"
    )
    parser.add_argument(
        "path",
        type=Path,
        help="Path to a markdown file or a directory containing markdown files",
    )
    parser.add_argument(
        "--log-level",
        type=str,
        default="INFO",
        help="Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)",
    )
    args = parser.parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level), format="%(name)s: %(message)s"
    )

    err = 0
    for checker in [
        SecLabelChecker(),
        FigLabelChecker(),
        TblLabelChecker(),
    ]:
        err += checker.check(args.path)

    if err > 0:
        logging.error("Found %d issues", err)
    else:
        logging.info("No issues found")

    return 0 if err == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
