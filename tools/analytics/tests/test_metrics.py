"""Тесты metrics: overview, weapons, upgrades, enemies, dungeon, economy, safe_div."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.analytics import metrics
from tools.analytics.dataset import Dataset, build_dataset
from tools.analytics.importer import import_from_root
from tools.analytics.tests.fixtures.build_fixtures import write_fixture_files


def _load_dataset() -> Dataset:
    tmp = Path(tempfile.mkdtemp())
    write_fixture_files(tmp)
    events = import_from_root(tmp).events
    return build_dataset(events)


class MetricsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.dataset = _load_dataset()

    def test_overview_counts(self) -> None:
        ov = metrics.overview(self.dataset)
        self.assertEqual(ov["total_runs"], 2)
        self.assertEqual(ov["completed_runs"], 1)
        self.assertEqual(ov["deaths"], 1)
        self.assertAlmostEqual(ov["completion_rate"], 0.5)
        self.assertIn("sample", ov["sample_size_note"])

    def test_weapons_kills_per_minute(self) -> None:
        rows = metrics.weapons_summary(self.dataset)
        dagger = next(r for r in rows if r["weapon_id"] == "dagger")
        # 12 + 12 kills over 60 + 60 equipped_seconds → 12 per minute.
        self.assertAlmostEqual(dagger["kills_per_minute"], 12.0)

    def test_safe_division_no_crash_when_empty(self) -> None:
        empty = Dataset()
        ov = metrics.overview(empty)
        self.assertEqual(ov["completion_rate"], 0.0)
        self.assertEqual(ov["median_floor_reached"], 0.0)
        weapons = metrics.weapons_summary(empty)
        self.assertEqual(weapons, [])
        eco = metrics.economy_summary(empty)
        self.assertEqual(eco["total_gold"], 0)
        self.assertEqual(eco["potion_use_rate"], 0.0)

    def test_upgrades_selections_by_card(self) -> None:
        section = metrics.upgrades_summary(self.dataset)[0]
        rows = section["rows"]
        swift = next(r for r in rows if r["card_id"] == "swift_edge")
        self.assertEqual(swift["offered"], 1)
        self.assertEqual(swift["selected"], 1)
        self.assertEqual(swift["pick_rate"], 1.0)

    def test_dungeon_summary_aggregates(self) -> None:
        rows = metrics.dungeon_summary(self.dataset)
        floor_1 = next(r for r in rows if r["floor"] == 1)
        self.assertEqual(floor_1["samples"], 2)
        # Average duration = (60 + 55) / 2 = 57.5.
        self.assertAlmostEqual(floor_1["avg_duration_seconds"], 57.5)
        # rooms_visited_ratio = 10 / 10 = 1.0.
        self.assertAlmostEqual(floor_1["rooms_visited_ratio"], 1.0)


if __name__ == "__main__":
    unittest.main()
