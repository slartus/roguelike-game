"""Smoke-тест: HTML report собирается и содержит ожидаемые секции."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.analytics.dataset import build_dataset
from tools.analytics.importer import import_from_root
from tools.analytics.report import build_report_html
from tools.analytics.tests.fixtures.build_fixtures import write_fixture_files


class ReportSmokeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        write_fixture_files(self.tmp)
        self.events = import_from_root(self.tmp).events

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_report_has_all_sections(self) -> None:
        dataset = build_dataset(self.events)
        html = build_report_html(dataset, issues=[])
        for section in ("<h1>Roguelike analytics report</h1>",
                        "Overview", "Weapons", "Upgrades", "Enemies",
                        "Dungeon", "Economy", "Data quality"):
            self.assertIn(section, html, f"missing section '{section}' in report")
        # Caveats присутствуют явно.
        self.assertIn("Interpretation caveats", html)

    def test_report_handles_empty_dataset(self) -> None:
        from tools.analytics.dataset import Dataset
        html = build_report_html(Dataset(), issues=[])
        self.assertIn("Roguelike analytics report", html)


if __name__ == "__main__":
    unittest.main()
