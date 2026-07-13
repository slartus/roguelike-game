"""Генератор synthetic JSONL fixture для тестов.

Не использует реальные пользовательские данные. Все id захардкожены —
детерминированный вывод для сравнения байт-в-байт.
"""

from __future__ import annotations

import json
from pathlib import Path


BASELINE_JSONL = "baseline.jsonl"
CANDIDATE_JSONL = "candidate.jsonl"


def _envelope(event_name: str, payload: dict, *, event_id: str,
        session_id: str, run_id: str | None = None, floor: int | None = None,
        balance_version: int = 1, timestamp_ms: int = 1_700_000_000_000) -> dict:
    envelope = {
        "schema_version": 1,
        "event_name": event_name,
        "event_id": event_id,
        "timestamp_ms": timestamp_ms,
        "installation_id": "inst-fixture",
        "session_id": session_id,
        "game_version": "0.0.0-fixture",
        "build_commit": "fixturecommit",
        "balance_version": balance_version,
        "platform": "macos",
        "locale": "en",
        "payload": payload,
    }
    if run_id:
        envelope["run_id"] = run_id
        envelope["tower_seed"] = 42
    if floor:
        envelope["floor"] = floor
    return envelope


def _baseline_events() -> list[dict]:
    session_id = "sess-1"
    run_id = "run-1"
    return [
        _envelope("session_started", {"debug_build": True},
            event_id="evt-1", session_id=session_id),
        _envelope("run_started", {
            "starting_weapon_id": "dagger",
            "starting_max_health": 10,
            "starting_level": 1,
        }, event_id="evt-2", session_id=session_id, run_id=run_id),
        _envelope("weapon_equipped", {
            "weapon_id": "dagger",
            "previous_weapon_id": "",
            "source": "starting",
        }, event_id="evt-3", session_id=session_id, run_id=run_id),
        _envelope("floor_started", {
            "layout_archetype": "wide_hub",
            "zone": "crypt",
            "room_count": 5,
            "enemy_count": 12,
            "chest_count": 1,
            "walkable_area_cells": 800,
            "critical_path_length_cells": 45,
            "floor_width": 40,
            "floor_height": 30,
        }, event_id="evt-4", session_id=session_id, run_id=run_id, floor=1),
        _envelope("upgrade_offer_shown", {
            "choice_level": 2,
            "current_weapon_id": "dagger",
            "current_weapon_style": "melee_arc",
            "current_attack_type": "melee_arc",
            "offered_ids": ["swift_edge", "iron_bulk", "vicious_strike"],
            "offered_positions": {"swift_edge": 0, "iron_bulk": 1, "vicious_strike": 2},
            "current_stacks": {"swift_edge": 0, "iron_bulk": 0, "vicious_strike": 0},
            "player_health": 10, "player_max_health": 10,
        }, event_id="evt-5", session_id=session_id, run_id=run_id, floor=1),
        _envelope("upgrade_selected", {
            "selected_id": "swift_edge",
            "offer_position": 0,
            "choice_time_seconds": 2.5,
            "stack_before": 0,
            "stack_after": 1,
        }, event_id="evt-6", session_id=session_id, run_id=run_id, floor=1),
        _envelope("room_first_entered", {
            "room_id": "room-3", "role": "combat",
            "critical_path": True, "optional": False,
            "seconds_since_floor_start": 12.4,
            "player_health": 10, "alive_enemies": 3,
            "reward_present": False,
        }, event_id="evt-7", session_id=session_id, run_id=run_id, floor=1),
        _envelope("floor_completed", {
            "duration_seconds": 60.0,
            "kills": 12, "gold_earned": 30,
            "damage_taken": 4, "damage_dealt": 55,
            "rooms_visited": 5,
        }, event_id="evt-8", session_id=session_id, run_id=run_id, floor=1),
        _envelope("floor_weapon_summary", {
            "weapon_id": "dagger",
            "equipped_seconds": 60.0,
            "combat_seconds": 40.0,
            "attacks": 20, "projectiles_fired": 0,
            "attacks_with_hit": 16, "projectiles_hit": 0,
            "targets_hit": 18, "damage_dealt": 55,
            "kills": 12, "overkill_damage": 3,
            "damage_taken_while_equipped": 4,
        }, event_id="evt-9", session_id=session_id, run_id=run_id, floor=1),
        _envelope("floor_enemy_summary", {
            "enemy_id": "goblin", "temperament": "aggressive", "elite_rank": 0,
            "spawned": 8, "killed": 8,
            "damage_to_player": 3, "hits_to_player": 3,
            "damage_received": 30, "time_alive_seconds": 22.0,
            "player_deaths": 0,
        }, event_id="evt-10", session_id=session_id, run_id=run_id, floor=1),
        _envelope("floor_economy_summary", {
            "gold_from_enemies": 25, "gold_from_chests": 5,
            "gold_from_props": 0, "gold_from_bosses": 0,
            "potions_received": 1, "potions_used": 0,
            "healing_received": 0, "overheal": 0,
            "chests_opened": 1, "weapons_offered": 0, "weapons_picked": 0,
        }, event_id="evt-11", session_id=session_id, run_id=run_id, floor=1),
        _envelope("run_finished", {
            "reason": "player_death",
            "duration_seconds": 60.0,
            "floor_reached": 1,
            "player_level": 2,
            "gold_earned": 30,
            "enemies_killed": 12,
            "damage_taken": 10,
            "damage_dealt": 55,
            "equipped_weapon_id": "dagger",
            "potions_remaining": 1,
            "upgrade_stacks": {"swift_edge": 1},
            "damage_history": [],
            "weapon_totals": [],
            "death_source_type": "enemy_projectile",
            "death_source_id": "goblin_archer",
            "death_attack_id": "projectile",
            "death_source_temperament": "aggressive",
            "death_source_elite_rank": 0,
        }, event_id="evt-12", session_id=session_id, run_id=run_id),
        _envelope("session_finished", {"reason": "normal_exit"},
            event_id="evt-13", session_id=session_id),
    ]


def _candidate_events() -> list[dict]:
    session_id = "sess-2"
    run_id = "run-2"
    return [
        _envelope("session_started", {"debug_build": True},
            event_id="evt-101", session_id=session_id, balance_version=2),
        _envelope("run_started", {
            "starting_weapon_id": "dagger",
            "starting_max_health": 10,
            "starting_level": 1,
        }, event_id="evt-102", session_id=session_id, run_id=run_id, balance_version=2),
        _envelope("floor_started", {
            "layout_archetype": "wide_hub", "zone": "crypt",
            "room_count": 5, "enemy_count": 12, "chest_count": 1,
        }, event_id="evt-103", session_id=session_id, run_id=run_id,
            floor=1, balance_version=2),
        _envelope("floor_weapon_summary", {
            "weapon_id": "dagger",
            "equipped_seconds": 60.0,
            "combat_seconds": 40.0,
            "attacks": 20, "projectiles_fired": 0,
            "attacks_with_hit": 18, "projectiles_hit": 0,
            "targets_hit": 20, "damage_dealt": 70,
            "kills": 12, "overkill_damage": 3,
            "damage_taken_while_equipped": 4,
        }, event_id="evt-104", session_id=session_id, run_id=run_id,
            floor=1, balance_version=2),
        _envelope("floor_enemy_summary", {
            "enemy_id": "goblin", "temperament": "aggressive", "elite_rank": 0,
            "spawned": 8, "killed": 8,
            "damage_to_player": 2, "hits_to_player": 2,
            "damage_received": 40, "time_alive_seconds": 20.0,
            "player_deaths": 0,
        }, event_id="evt-105", session_id=session_id, run_id=run_id,
            floor=1, balance_version=2),
        _envelope("floor_completed", {
            "duration_seconds": 55.0,
            "kills": 12, "gold_earned": 30,
            "damage_taken": 2, "damage_dealt": 70,
            "rooms_visited": 5,
        }, event_id="evt-106", session_id=session_id, run_id=run_id,
            floor=1, balance_version=2),
        _envelope("floor_economy_summary", {
            "gold_from_enemies": 25, "gold_from_chests": 5,
            "gold_from_props": 0, "gold_from_bosses": 0,
            "potions_received": 1, "potions_used": 1,
            "healing_received": 5, "overheal": 0,
            "chests_opened": 1, "weapons_offered": 0, "weapons_picked": 0,
        }, event_id="evt-107", session_id=session_id, run_id=run_id,
            floor=1, balance_version=2),
        _envelope("run_finished", {
            "reason": "victory",
            "duration_seconds": 55.0,
            "floor_reached": 1,
            "player_level": 2,
            "gold_earned": 30,
            "enemies_killed": 12,
            "damage_taken": 2,
            "damage_dealt": 70,
            "equipped_weapon_id": "dagger",
            "potions_remaining": 0,
        }, event_id="evt-108", session_id=session_id, run_id=run_id,
            balance_version=2),
        _envelope("session_finished", {"reason": "normal_exit"},
            event_id="evt-109", session_id=session_id, balance_version=2),
    ]


def write_fixture_files(target_dir: Path) -> tuple[Path, Path]:
    """Пишет два JSONL-файла + добавляет мусорную последнюю строку в baseline
    + дубли + unknown event + future schema."""
    target_dir.mkdir(parents=True, exist_ok=True)
    baseline_path = target_dir / BASELINE_JSONL
    with baseline_path.open("w", encoding="utf-8") as fh:
        events = _baseline_events()
        # Плюс: unknown event (пропускается импортом с warning).
        unknown_event = _envelope(
            "unknown_probe", {"foo": 1},
            event_id="evt-unknown", session_id="sess-1",
        )
        events.insert(2, unknown_event)
        # Плюс: future schema_version (schema 99).
        future_event = _envelope("session_started", {"debug_build": True},
            event_id="evt-future", session_id="sess-1")
        future_event["schema_version"] = 99
        events.insert(3, future_event)
        for event in events:
            fh.write(json.dumps(event, sort_keys=True) + "\n")
        # Дубль (второе появление evt-4).
        fh.write(json.dumps(next(e for e in events if e["event_id"] == "evt-4"),
            sort_keys=True) + "\n")
        # Corrupt final row (обрезан JSON).
        fh.write("{\"schema_version\": 1, \"event_name\": \"session_started\"")
    candidate_path = target_dir / CANDIDATE_JSONL
    with candidate_path.open("w", encoding="utf-8") as fh:
        for event in _candidate_events():
            fh.write(json.dumps(event, sort_keys=True) + "\n")
    return baseline_path, candidate_path


if __name__ == "__main__":
    import sys
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent
    write_fixture_files(target)
