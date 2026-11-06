"""Heading-anchor rules the documentation link check relies on."""

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "check_repository", Path(__file__).with_name("check-repository.py"))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class AnchorTests(unittest.TestCase):
    def test_matches_github_heading_anchors(self):
        markdown = "\n".join([
            "# Changelog",
            "## 0.6.0-alpha.1 (unreleased)",
            "### Added",
            "### Added",
            "## [Setup](docs/HELP.md) and `check.sh`",
            "```sh",
            "# not a heading",
            "```",
            "~~~",
            "## Also not a heading",
            "~~~",
        ])
        self.assertEqual(checker.anchors(markdown), {
            "changelog", "060-alpha1-unreleased", "added", "added-1", "setup-and-checksh",
        })


if __name__ == "__main__":
    unittest.main()
