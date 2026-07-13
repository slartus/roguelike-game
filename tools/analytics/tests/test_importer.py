"""Тесты importer: corrupt, dedup, unknown, future schema."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools.analytics.importer import import_from_root, import_paths
from tools.analytics.tests.fixtures.build_fixtures import write_fixture_files


class ImporterTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.baseline, self.candidate = write_fixture_files(self.tmp)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_baseline_import_surface(self) -> None:
        result = import_from_root(self.tmp)
        summary = result.summary()
        # Оба файла найдены.
        self.assertEqual(summary["files_scanned"], 2)
        # Corrupt строка не крашит импорт — лог как issue.
        self.assertTrue(
            any(i.code == "json_parse_error" for i in result.issues),
            "expected json_parse_error issue for corrupt final row",
        )
        # Unknown event попал в issues, не в events.
        self.assertTrue(
            any(i.code == "unknown_event" for i in result.issues),
        )
        # Duplicate event_id учтён.
        self.assertGreaterEqual(summary["duplicates_skipped"], 1)
        self.assertTrue(
            any(i.code == "duplicate_event_id" for i in result.issues),
        )
        # Future schema отфильтрована.
        self.assertGreaterEqual(summary["future_schema_skipped"], 1)
        self.assertTrue(
            any(i.code == "future_schema_version" for i in result.issues),
        )
        # Все оставшиеся события — известные.
        for event in result.events:
            self.assertIn(event["event_name"], {
                "session_started", "session_finished", "run_started",
                "run_finished", "floor_started", "floor_completed",
                "floor_weapon_summary", "floor_enemy_summary",
                "floor_economy_summary", "weapon_equipped",
                "upgrade_offer_shown", "upgrade_selected", "potion_used",
                "room_first_entered",
            })

    def test_import_single_file(self) -> None:
        result = import_from_root(self.candidate)
        self.assertEqual(result.files_scanned, 1)
        self.assertGreater(len(result.events), 0)

    def test_dedup_across_paths(self) -> None:
        # Import same file twice — все events второго прохода должны быть дублями.
        result = import_paths([self.candidate, self.candidate])
        # events_kept = уникальных event_id
        # duplicates_skipped = число дублей во втором файле
        self.assertEqual(result.duplicates_skipped, len(result.events))

    def test_events_track_source_metadata(self) -> None:
        result = import_from_root(self.candidate)
        first = result.events[0]
        self.assertTrue(first["_source_file"].endswith("candidate.jsonl"))
        self.assertGreater(first["_line_number"], 0)


if __name__ == "__main__":
    unittest.main()
