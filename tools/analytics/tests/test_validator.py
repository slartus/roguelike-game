"""Тесты validator: envelope, payload, enums, run consistency."""

from __future__ import annotations

import unittest

from tools.analytics.validator import validate, partition_by_level


def _envelope(event_name: str, payload: dict, **kwargs) -> dict:
    envelope = {
        "schema_version": 1,
        "event_name": event_name,
        "event_id": kwargs.get("event_id", "evt-1"),
        "timestamp_ms": 1_700_000_000_000,
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


class ValidatorTests(unittest.TestCase):
    def test_missing_envelope_field_flagged_as_error(self) -> None:
        event = _envelope("session_started", {"debug_build": True})
        del event["installation_id"]
        issues = validate([event])
        self.assertTrue(any(i.code == "envelope_missing_field" for i in issues))
        self.assertEqual(partition_by_level(issues)["error"][0].code,
            "envelope_missing_field")

    def test_missing_payload_field_flagged(self) -> None:
        event = _envelope("run_started", {"starting_weapon_id": "dagger"})
        issues = validate([event])
        codes = [i.code for i in issues]
        self.assertIn("payload_missing_field", codes)

    def test_negative_numeric_warned(self) -> None:
        event = _envelope("floor_completed", {
            "duration_seconds": -1.0,
            "kills": 0, "gold_earned": 0,
            "damage_taken": 0, "damage_dealt": 0,
            "rooms_visited": 0,
        }, run_id="run-1", floor=1)
        issues = validate([event])
        self.assertTrue(any(i.code == "payload_negative_value" for i in issues))

    def test_unknown_session_reason_warned(self) -> None:
        event = _envelope("session_finished", {"reason": "totally_bogus"})
        issues = validate([event])
        self.assertTrue(any(i.code == "unknown_session_reason" for i in issues))

    def test_run_finished_without_started_warns(self) -> None:
        finished = _envelope("run_finished", {
            "reason": "player_death",
            "duration_seconds": 10, "floor_reached": 1,
            "player_level": 1, "gold_earned": 0,
            "enemies_killed": 0, "damage_taken": 0,
            "damage_dealt": 0,
        }, run_id="run-orphan")
        issues = validate([finished])
        self.assertTrue(any(i.code == "run_finished_without_started" for i in issues))

    def test_duplicate_run_started_warns(self) -> None:
        payload = {"starting_weapon_id": "dagger",
            "starting_max_health": 10, "starting_level": 1}
        first = _envelope("run_started", payload, run_id="run-1", event_id="evt-1")
        second = _envelope("run_started", payload, run_id="run-1", event_id="evt-2")
        issues = validate([first, second])
        self.assertTrue(any(i.code == "duplicate_run_started" for i in issues))

    def test_non_monotonic_floor_warns(self) -> None:
        payload = {"layout_archetype": "wide", "zone": "crypt"}
        first = _envelope("floor_started", payload, run_id="run-1",
            floor=2, event_id="evt-1")
        second = _envelope("floor_started", payload, run_id="run-1",
            floor=1, event_id="evt-2")
        issues = validate([first, second])
        self.assertTrue(any(i.code == "non_monotonic_floor" for i in issues))

    def test_floor_event_without_started_warns(self) -> None:
        summary = _envelope("floor_weapon_summary", {
            "weapon_id": "dagger", "equipped_seconds": 10.0,
            "attacks": 5, "damage_dealt": 10,
        }, run_id="run-orphan", floor=1)
        issues = validate([summary])
        self.assertTrue(any(i.code == "floor_event_without_started" for i in issues))

    def test_impossible_health_warns(self) -> None:
        event = _envelope("potion_used", {
            "health_before": 20, "max_health": 10,
            "heal_amount": 5, "actual_healed": 0, "overheal": 5,
        }, run_id="run-1", floor=1)
        issues = validate([event])
        self.assertTrue(any(i.code == "impossible_health" for i in issues))


if __name__ == "__main__":
    unittest.main()
