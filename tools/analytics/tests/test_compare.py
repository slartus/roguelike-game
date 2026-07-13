"""Тесты сравнения balance_version."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.analytics.compare import build_comparison_html, compare_versions
from tools.analytics.dataset import build_dataset
from tools.analytics.importer import import_from_root
from tools.analytics.tests.fixtures.build_fixtures import write_fixture_files


class CompareTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        write_fixture_files(self.tmp)
        events = import_from_root(self.tmp).events
        self.dataset = build_dataset(events)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_baseline_and_candidate_produce_deltas(self) -> None:
        result = compare_versions(self.dataset, baseline_version=1,
            candidate_version=2)
        self.assertEqual(result["baseline_runs"], 1)
        self.assertEqual(result["candidate_runs"], 1)
        # Completion rate baseline=0 (death), candidate=1 (victory) → +1.0.
        completion = next(d for d in result["overview_deltas"]
            if d["metric"] == "completion_rate")
        self.assertAlmostEqual(completion["baseline"], 0.0)
        self.assertAlmostEqual(completion["candidate"], 1.0)
        self.assertAlmostEqual(completion["absolute_delta"], 1.0)
        # Small N warning присутствует.
        self.assertIn("N", completion["sample_warning"])

    def test_weapon_delta_present_for_dagger(self) -> None:
        result = compare_versions(self.dataset, 1, 2)
        dagger = next(w for w in result["weapon_deltas"] if w["weapon_id"] == "dagger")
        # Candidate damage 70 > baseline 55 → damage_per_equipped_minute вырос.
        dpm = dagger["damage_per_equipped_minute"]
        self.assertGreater(dpm["candidate"], dpm["baseline"])

    def test_comparison_html_smoke(self) -> None:
        result = compare_versions(self.dataset, 1, 2)
        html = build_comparison_html(result)
        self.assertIn("Balance version comparison", html)
        self.assertIn("baseline", html.lower())
        self.assertIn("candidate", html.lower())


if __name__ == "__main__":
    unittest.main()
