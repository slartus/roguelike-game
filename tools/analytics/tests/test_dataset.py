"""Тесты dataset: построение таблиц, upgrade selection matching, derived metrics."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.analytics.dataset import build_dataset
from tools.analytics.importer import import_from_root
from tools.analytics.tests.fixtures.build_fixtures import write_fixture_files


class DatasetTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        write_fixture_files(self.tmp)
        self.events = import_from_root(self.tmp).events

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_runs_include_death_source(self) -> None:
        dataset = build_dataset(self.events)
        run = next(r for r in dataset.runs if r["run_id"] == "run-1")
        self.assertEqual(run["reason"], "player_death")
        self.assertEqual(run["death_source_type"], "enemy_projectile")
        self.assertEqual(run["death_source_id"], "goblin_archer")
        self.assertEqual(run["death_attack_id"], "projectile")

    def test_floors_join_start_and_complete(self) -> None:
        dataset = build_dataset(self.events)
        floor = next(f for f in dataset.floors if f["run_id"] == "run-1" and f["floor"] == 1)
        self.assertEqual(floor["zone"], "crypt")
        self.assertEqual(floor["room_count"], 5)
        self.assertEqual(floor["duration_seconds"], 60.0)
        self.assertEqual(floor["rooms_visited"], 5)

    def test_weapon_derived_metrics_safe_div(self) -> None:
        dataset = build_dataset(self.events)
        weapon = next(w for w in dataset.weapons if w["run_id"] == "run-1")
        self.assertGreater(weapon["hit_rate"], 0)
        self.assertLess(weapon["hit_rate"], 1)
        # projectile_fired = 0 → hit_rate = 0, не деление на 0
        self.assertEqual(weapon["projectile_hit_rate"], 0.0)

    def test_upgrade_offer_selection_matches(self) -> None:
        dataset = build_dataset(self.events)
        selected_rows = [o for o in dataset.upgrade_offers if o["selected"]]
        self.assertEqual(len(selected_rows), 1)
        self.assertEqual(selected_rows[0]["card_id"], "swift_edge")
        self.assertEqual(selected_rows[0]["selection_index"], 0)
        # Selections таблица тоже содержит selected_id.
        self.assertEqual(len(dataset.upgrade_selections), 1)
        self.assertEqual(dataset.upgrade_selections[0]["selected_id"], "swift_edge")

    def test_enemies_grouped_by_key(self) -> None:
        dataset = build_dataset(self.events)
        goblin = next(e for e in dataset.enemies if e["enemy_id"] == "goblin")
        self.assertEqual(goblin["spawned"], 8)
        self.assertEqual(goblin["killed"], 8)

    def test_rooms_first_entered_row(self) -> None:
        dataset = build_dataset(self.events)
        room = next(r for r in dataset.rooms if r["run_id"] == "run-1")
        self.assertEqual(room["room_id"], "room-3")
        self.assertTrue(room["critical_path"])


if __name__ == "__main__":
    unittest.main()
