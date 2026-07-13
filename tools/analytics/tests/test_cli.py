"""Тесты CLI entry-points: import_jsonl, validate_events, build_dataset,
generate_report, compare_versions, hash_content."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.analytics.tests.fixtures.build_fixtures import write_fixture_files


def _run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


class CliTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.fixture_dir = self.tmp / "jsonl"
        write_fixture_files(self.fixture_dir)
        self.out = self.tmp / "out"
        self.out.mkdir()
        self.repo_root = Path(__file__).resolve().parents[3]

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _py(self, module: str, *args: str) -> subprocess.CompletedProcess:
        return _run([sys.executable, "-m", module, *args])

    def test_import_jsonl_prints_summary(self) -> None:
        proc = self._py("tools.analytics.import_jsonl",
            "--input", str(self.fixture_dir))
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        summary = json.loads(proc.stdout)
        self.assertGreater(summary["events_kept"], 0)
        self.assertGreater(summary["files_scanned"], 0)

    def test_validate_events_exits_zero_on_only_warnings(self) -> None:
        proc = self._py("tools.analytics.validate_events",
            "--input", str(self.fixture_dir))
        # Fixture содержит warnings, но не errors.
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)

    def test_build_dataset_creates_all_csvs(self) -> None:
        proc = self._py("tools.analytics.build_dataset",
            "--input", str(self.fixture_dir),
            "--output", str(self.out))
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        for name in ("sessions.csv", "runs.csv", "floors.csv", "weapons.csv",
                     "upgrade_offers.csv", "upgrade_selections.csv",
                     "enemies.csv", "economy.csv", "rooms.csv",
                     "data_quality.json"):
            self.assertTrue((self.out / name).exists(), f"missing {name}")

    def test_generate_report_writes_html(self) -> None:
        html_path = self.out / "report.html"
        proc = self._py("tools.analytics.generate_report",
            "--input", str(self.fixture_dir),
            "--output", str(html_path))
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertTrue(html_path.exists())
        text = html_path.read_text(encoding="utf-8")
        self.assertIn("<html", text)
        self.assertIn("Weapons", text)

    def test_compare_versions_writes_html(self) -> None:
        html_path = self.out / "compare.html"
        proc = self._py("tools.analytics.compare_versions",
            "--input", str(self.fixture_dir),
            "--baseline-balance-version", "1",
            "--candidate-balance-version", "2",
            "--output", str(html_path))
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertTrue(html_path.exists())

    def test_hash_content_prints_hex(self) -> None:
        proc = self._py("tools.analytics.hash_content",
            "--project-root", str(self.repo_root))
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        result = proc.stdout.strip()
        self.assertEqual(len(result), 64)  # SHA256 hex
        # Repeatable
        proc2 = self._py("tools.analytics.hash_content",
            "--project-root", str(self.repo_root))
        self.assertEqual(result, proc2.stdout.strip())


if __name__ == "__main__":
    unittest.main()
