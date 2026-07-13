"""Регрессионные тесты для находок code-review PR 3.

Каждый тест — one-to-one map на конкретную MAJOR/MINOR issue, чтобы
регрессия сразу называла своё имя в failure output.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.analytics.compare import _percent_delta
from tools.analytics.content_hash import hash_content_from_bytes
from tools.analytics.dataset import build_dataset
from tools.analytics.importer import import_from_root, iter_jsonl_paths
from tools.analytics.validator import validate


def _envelope(event_name: str, payload: dict, **kwargs) -> dict:
    envelope = {
        "schema_version": 1,
        "event_name": event_name,
        "event_id": kwargs.get("event_id", "evt-x"),
        "timestamp_ms": kwargs.get("timestamp_ms", 1_700_000_000_000),
        "installation_id": "inst",
        "session_id": kwargs.get("session_id", "sess-1"),
        "game_version": "0.0.0",
        "build_commit": "abc",
        "balance_version": 1,
        "platform": "macos",
        "locale": "en",
        "payload": payload,
    }
    if "run_id" in kwargs:
        envelope["run_id"] = kwargs["run_id"]
        envelope["tower_seed"] = 42
    if "floor" in kwargs:
        envelope["floor"] = kwargs["floor"]
    return envelope


class ReviewFixesTests(unittest.TestCase):
    # ------------------------------------------------------------------
    # M1: dataset — offered_ids не-list не должен ломать построение.
    # ------------------------------------------------------------------
    def test_offered_ids_non_list_yields_no_offer_rows(self) -> None:
        events = [
            _envelope("upgrade_offer_shown", {
                "choice_level": 1,
                "current_weapon_id": "dagger",
                "offered_ids": "malformed_string_not_list",
            }, run_id="run-1", floor=1),
        ]
        dataset = build_dataset(events)
        # Не должно быть 20+ offer rows «по символам».
        self.assertEqual(len(dataset.upgrade_offers), 0)

    # ------------------------------------------------------------------
    # M2: content_hash CRLF/LF normalization.
    # ------------------------------------------------------------------
    def test_content_hash_normalizes_line_endings(self) -> None:
        crlf = [("resources/weapons/dagger.tres", b"stats: 5\r\ndamage: 3\r\n")]
        lf = [("resources/weapons/dagger.tres", b"stats: 5\ndamage: 3\n")]
        self.assertEqual(hash_content_from_bytes(crlf), hash_content_from_bytes(lf))

    # ------------------------------------------------------------------
    # M3: validator — orphan floor_completed после reorder перестаёт
    # быть false-positive когда timestamp расставляет всё по местам.
    # ------------------------------------------------------------------
    def test_multifile_reorder_by_timestamp_removes_orphan_false_positives(self) -> None:
        floor_started = _envelope("floor_started",
            {"layout_archetype": "wide", "zone": "crypt"},
            run_id="run-1", floor=1,
            event_id="evt-start", timestamp_ms=1)
        floor_started["_source_file"] = "b_file.jsonl"
        floor_started["_line_number"] = 1

        floor_completed = _envelope("floor_completed", {
            "duration_seconds": 1.0, "kills": 0, "gold_earned": 0,
            "damage_taken": 0, "damage_dealt": 0, "rooms_visited": 0,
        }, run_id="run-1", floor=1,
            event_id="evt-complete", timestamp_ms=2)
        floor_completed["_source_file"] = "a_file.jsonl"
        floor_completed["_line_number"] = 1

        # completed раньше в списке (alphabetical file order),
        # но timestamp_ms правильный.
        issues = validate([floor_completed, floor_started])
        codes = {i.code for i in issues}
        self.assertNotIn("floor_event_without_started", codes,
            "validator должен упорядочивать events по timestamp внутри run")

    # ------------------------------------------------------------------
    # N7: iter_jsonl_paths принимает любой файл при явном указании.
    # ------------------------------------------------------------------
    def test_iter_paths_accepts_non_jsonl_file(self) -> None:
        with tempfile.NamedTemporaryFile(suffix=".log", delete=False) as fh:
            fh.write(b"{\"schema_version\":1}\n")
            path = Path(fh.name)
        try:
            self.assertEqual(list(iter_jsonl_paths(path)), [path])
        finally:
            path.unlink()

    # ------------------------------------------------------------------
    # N8: bool schema_version не должен пройти как int.
    # ------------------------------------------------------------------
    def test_bool_schema_version_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "sess.jsonl"
            row = json.dumps({
                "schema_version": True,  # bool masquerading as int
                "event_name": "session_started",
                "event_id": "evt-bool",
                "timestamp_ms": 1,
                "installation_id": "i", "session_id": "s",
                "game_version": "v", "build_commit": "c",
                "balance_version": 1, "platform": "macos", "locale": "en",
                "payload": {"debug_build": True},
            })
            path.write_text(row + "\n", encoding="utf-8")
            result = import_from_root(path)
            codes = {i.code for i in result.issues}
            self.assertIn("missing_schema_version", codes)
            self.assertEqual(result.events, [])

    # ------------------------------------------------------------------
    # N10: import_jsonl CLI --output не пишет _source_file / _line_number.
    # ------------------------------------------------------------------
    def test_import_output_strips_internal_fields(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_str:
            tmp = Path(tmp_str)
            src = tmp / "sess.jsonl"
            src.write_text(json.dumps({
                "schema_version": 1,
                "event_name": "session_started",
                "event_id": "evt-out",
                "timestamp_ms": 1,
                "installation_id": "i", "session_id": "s",
                "game_version": "v", "build_commit": "c",
                "balance_version": 1, "platform": "macos", "locale": "en",
                "payload": {"debug_build": True},
            }) + "\n", encoding="utf-8")
            out = tmp / "events.jsonl"
            proc = subprocess.run(
                [sys.executable, "-m", "tools.analytics.import_jsonl",
                    "--input", str(src), "--output", str(out)],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(proc.returncode, 0, msg=proc.stderr)
            written = out.read_text(encoding="utf-8").strip()
            parsed = json.loads(written)
            self.assertNotIn("_source_file", parsed)
            self.assertNotIn("_line_number", parsed)
            self.assertEqual(parsed["event_name"], "session_started")

    # ------------------------------------------------------------------
    # N5: percent_delta baseline=0 candidate≠0 → None, не 0.0.
    # ------------------------------------------------------------------
    def test_percent_delta_none_when_baseline_zero_candidate_nonzero(self) -> None:
        self.assertIsNone(_percent_delta(0.0, 1.0))
        self.assertEqual(_percent_delta(0.0, 0.0), 0.0)
        self.assertAlmostEqual(_percent_delta(1.0, 2.0), 1.0)


if __name__ == "__main__":
    unittest.main()
