"""Построение табличных датасетов из событий."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


def _pay(event: dict) -> dict:
    payload = event.get("payload", {})
    return payload if isinstance(payload, dict) else {}


def _num(value: Any, default: float = 0.0) -> float:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return default


def _safe_div(numerator: float, denominator: float) -> float:
    if denominator <= 0:
        return 0.0
    return numerator / denominator


@dataclass
class Dataset:
    sessions: list[dict] = field(default_factory=list)
    runs: list[dict] = field(default_factory=list)
    floors: list[dict] = field(default_factory=list)
    weapons: list[dict] = field(default_factory=list)
    upgrade_offers: list[dict] = field(default_factory=list)
    upgrade_selections: list[dict] = field(default_factory=list)
    enemies: list[dict] = field(default_factory=list)
    economy: list[dict] = field(default_factory=list)
    rooms: list[dict] = field(default_factory=list)


def _build_sessions(events: list[dict]) -> list[dict]:
    starts: dict[str, dict] = {}
    finishes: dict[str, dict] = {}
    for event in events:
        name = str(event.get("event_name", ""))
        session_id = str(event.get("session_id", ""))
        if not session_id:
            continue
        if name == "session_started":
            starts[session_id] = event
        elif name == "session_finished":
            finishes[session_id] = event
    rows: list[dict] = []
    for session_id in sorted(set(starts) | set(finishes)):
        start = starts.get(session_id, {})
        finish = finishes.get(session_id, {})
        source = start or finish
        rows.append({
            "session_id": session_id,
            "installation_id": str(source.get("installation_id", "")),
            "game_version": str(source.get("game_version", "")),
            "build_commit": str(source.get("build_commit", "")),
            "balance_version": int(_num(source.get("balance_version"))),
            "platform": str(source.get("platform", "")),
            "locale": str(source.get("locale", "")),
            "start_timestamp_ms": int(_num(start.get("timestamp_ms"))),
            "finish_timestamp_ms": int(_num(finish.get("timestamp_ms"))),
            "finish_reason": str(_pay(finish).get("reason", "") if finish else ""),
            "debug_build": bool(_pay(start).get("debug_build", False)),
        })
    return rows


def _build_runs(events: list[dict]) -> list[dict]:
    starts: dict[str, dict] = {}
    finishes: dict[str, dict] = {}
    for event in events:
        name = str(event.get("event_name", ""))
        run_id = str(event.get("run_id", ""))
        if not run_id:
            continue
        if name == "run_started":
            starts[run_id] = event
        elif name == "run_finished":
            finishes[run_id] = event
    rows: list[dict] = []
    for run_id in sorted(set(starts) | set(finishes)):
        start = starts.get(run_id, {})
        finish = finishes.get(run_id, {})
        source = start or finish
        pf = _pay(finish)
        ps = _pay(start)
        rows.append({
            "run_id": run_id,
            "session_id": str(source.get("session_id", "")),
            "game_version": str(source.get("game_version", "")),
            "build_commit": str(source.get("build_commit", "")),
            "balance_version": int(_num(source.get("balance_version"))),
            "tower_seed": int(_num(source.get("tower_seed"))),
            "starting_weapon_id": str(ps.get("starting_weapon_id", "")),
            "starting_max_health": int(_num(ps.get("starting_max_health"))),
            "starting_level": int(_num(ps.get("starting_level"))),
            "reason": str(pf.get("reason", "unknown")),
            "duration_seconds": _num(pf.get("duration_seconds")),
            "floor_reached": int(_num(pf.get("floor_reached"))),
            "player_level": int(_num(pf.get("player_level"))),
            "gold_earned": int(_num(pf.get("gold_earned"))),
            "enemies_killed": int(_num(pf.get("enemies_killed"))),
            "damage_taken": int(_num(pf.get("damage_taken"))),
            "damage_dealt": int(_num(pf.get("damage_dealt"))),
            "equipped_weapon_id": str(pf.get("equipped_weapon_id", "")),
            "potions_remaining": int(_num(pf.get("potions_remaining"))),
            "death_source_type": str(pf.get("death_source_type", "")),
            "death_source_id": str(pf.get("death_source_id", "")),
            "death_attack_id": str(pf.get("death_attack_id", "")),
        })
    return rows


def _build_floors(events: list[dict]) -> list[dict]:
    started: dict[tuple[str, int], dict] = {}
    completed: dict[tuple[str, int], dict] = {}
    for event in events:
        name = str(event.get("event_name", ""))
        if name not in ("floor_started", "floor_completed"):
            continue
        run_id = str(event.get("run_id", ""))
        floor = int(_num(event.get("floor")))
        if not run_id or floor <= 0:
            continue
        key = (run_id, floor)
        if name == "floor_started":
            started[key] = event
        else:
            completed[key] = event
    rows: list[dict] = []
    for key in sorted(set(started) | set(completed), key=lambda k: (k[0], k[1])):
        start = started.get(key, {})
        finish = completed.get(key, {})
        ps = _pay(start)
        pf = _pay(finish)
        rows.append({
            "run_id": key[0],
            "floor": key[1],
            "zone": str(ps.get("zone", "")),
            "layout_archetype": str(ps.get("layout_archetype", "")),
            "room_count": int(_num(ps.get("room_count"))),
            "corridor_count": int(_num(ps.get("corridor_count"))),
            "enemy_count": int(_num(ps.get("enemy_count"))),
            "chest_count": int(_num(ps.get("chest_count"))),
            "prop_count": int(_num(ps.get("prop_count"))),
            "walkable_area_cells": int(_num(ps.get("walkable_area_cells"))),
            "critical_path_length_cells": int(_num(ps.get("critical_path_length_cells"))),
            "branch_count": int(_num(ps.get("branch_count"))),
            "loop_count": int(_num(ps.get("loop_count"))),
            "dead_end_count": int(_num(ps.get("dead_end_count"))),
            "total_enemy_threat": _num(ps.get("total_enemy_threat")),
            "floor_width": int(_num(ps.get("floor_width"))),
            "floor_height": int(_num(ps.get("floor_height"))),
            "duration_seconds": _num(pf.get("duration_seconds")),
            "kills": int(_num(pf.get("kills"))),
            "gold_earned": int(_num(pf.get("gold_earned"))),
            "damage_taken": int(_num(pf.get("damage_taken"))),
            "damage_dealt": int(_num(pf.get("damage_dealt"))),
            "rooms_visited": int(_num(pf.get("rooms_visited"))),
        })
    return rows


def _build_weapons(events: list[dict]) -> list[dict]:
    rows: list[dict] = []
    for event in events:
        if str(event.get("event_name", "")) != "floor_weapon_summary":
            continue
        p = _pay(event)
        equipped = _num(p.get("equipped_seconds"))
        attacks = _num(p.get("attacks"))
        projectiles = _num(p.get("projectiles_fired"))
        attacks_with_hit = _num(p.get("attacks_with_hit"))
        projectile_hits = _num(p.get("projectiles_hit"))
        damage = _num(p.get("damage_dealt"))
        rows.append({
            "run_id": str(event.get("run_id", "")),
            "floor": int(_num(event.get("floor"))),
            "weapon_id": str(p.get("weapon_id", "")),
            "equipped_seconds": equipped,
            "combat_seconds": _num(p.get("combat_seconds")),
            "attacks": int(attacks),
            "projectiles_fired": int(projectiles),
            "attacks_with_hit": int(attacks_with_hit),
            "projectiles_hit": int(projectile_hits),
            "targets_hit": int(_num(p.get("targets_hit"))),
            "damage_dealt": int(damage),
            "kills": int(_num(p.get("kills"))),
            "overkill_damage": int(_num(p.get("overkill_damage"))),
            "damage_taken_while_equipped": int(_num(p.get("damage_taken_while_equipped"))),
            # Derived metrics — защита от деления на 0.
            "damage_per_equipped_second": _safe_div(damage, equipped),
            "damage_per_attack": _safe_div(damage, attacks),
            "hit_rate": _safe_div(attacks_with_hit, attacks),
            "projectile_hit_rate": _safe_div(projectile_hits, projectiles),
        })
    return rows


def _build_upgrades(events: list[dict]) -> tuple[list[dict], list[dict]]:
    """Возвращает (offers, selections)."""
    offer_rows: list[dict] = []
    selection_rows: list[dict] = []
    pending_run: str = ""
    for event in events:
        name = str(event.get("event_name", ""))
        if name == "upgrade_offer_shown":
            p = _pay(event)
            pending_run = str(event.get("run_id", ""))
            offered_ids_raw = p.get("offered_ids", [])
            if not isinstance(offered_ids_raw, list):
                offered_ids = []
            else:
                offered_ids = offered_ids_raw
            offered_positions = p.get("offered_positions", {})
            if not isinstance(offered_positions, dict):
                offered_positions = {}
            current_stacks = p.get("current_stacks", {})
            if not isinstance(current_stacks, dict):
                current_stacks = {}
            for card_id in offered_ids:
                card_key = str(card_id)
                position = int(_num(offered_positions.get(card_key, -1), default=-1))
                offer_rows.append({
                    "run_id": pending_run,
                    "floor": int(_num(event.get("floor"))),
                    "choice_level": int(_num(p.get("choice_level"))),
                    "card_id": card_key,
                    "position": position,
                    "current_weapon_id": str(p.get("current_weapon_id", "")),
                    "current_weapon_style": str(p.get("current_weapon_style", "")),
                    "current_attack_type": str(p.get("current_attack_type", "")),
                    "stack_before": int(_num(current_stacks.get(card_key, 0))),
                    "player_health": int(_num(p.get("player_health"))),
                    "player_max_health": int(_num(p.get("player_max_health"))),
                    "selected": False,
                    "selection_index": -1,
                })
        elif name == "upgrade_selected":
            p = _pay(event)
            selected_id = str(p.get("selected_id", ""))
            offer_position = int(_num(p.get("offer_position"), default=-1))
            selection_rows.append({
                "run_id": str(event.get("run_id", "")),
                "floor": int(_num(event.get("floor"))),
                "selected_id": selected_id,
                "offer_position": offer_position,
                "stack_before": int(_num(p.get("stack_before"))),
                "stack_after": int(_num(p.get("stack_after"))),
                "choice_time_seconds": _num(p.get("choice_time_seconds")),
            })
            # Помечаем последний матчинг offer как selected.
            if pending_run == str(event.get("run_id", "")):
                for row in reversed(offer_rows):
                    if row["run_id"] == pending_run and row["card_id"] == selected_id and not row["selected"]:
                        row["selected"] = True
                        row["selection_index"] = offer_position
                        break
    return offer_rows, selection_rows


def _build_enemies(events: list[dict]) -> list[dict]:
    rows: list[dict] = []
    for event in events:
        if str(event.get("event_name", "")) != "floor_enemy_summary":
            continue
        p = _pay(event)
        rows.append({
            "run_id": str(event.get("run_id", "")),
            "floor": int(_num(event.get("floor"))),
            "enemy_id": str(p.get("enemy_id", "")),
            "temperament": str(p.get("temperament", "")),
            "elite_rank": int(_num(p.get("elite_rank"))),
            "spawned": int(_num(p.get("spawned"))),
            "killed": int(_num(p.get("killed"))),
            "damage_to_player": int(_num(p.get("damage_to_player"))),
            "hits_to_player": int(_num(p.get("hits_to_player"))),
            "damage_received": int(_num(p.get("damage_received"))),
            "time_alive_seconds": _num(p.get("time_alive_seconds")),
            "player_deaths": int(_num(p.get("player_deaths"))),
        })
    return rows


def _build_economy(events: list[dict]) -> list[dict]:
    rows: list[dict] = []
    for event in events:
        if str(event.get("event_name", "")) != "floor_economy_summary":
            continue
        p = _pay(event)
        rows.append({
            "run_id": str(event.get("run_id", "")),
            "floor": int(_num(event.get("floor"))),
            "gold_from_enemies": int(_num(p.get("gold_from_enemies"))),
            "gold_from_chests": int(_num(p.get("gold_from_chests"))),
            "gold_from_props": int(_num(p.get("gold_from_props"))),
            "gold_from_bosses": int(_num(p.get("gold_from_bosses"))),
            "potions_received": int(_num(p.get("potions_received"))),
            "potions_used": int(_num(p.get("potions_used"))),
            "healing_received": int(_num(p.get("healing_received"))),
            "overheal": int(_num(p.get("overheal"))),
            "chests_opened": int(_num(p.get("chests_opened"))),
            "weapons_offered": int(_num(p.get("weapons_offered"))),
            "weapons_picked": int(_num(p.get("weapons_picked"))),
        })
    return rows


def _build_rooms(events: list[dict]) -> list[dict]:
    rows: list[dict] = []
    for event in events:
        if str(event.get("event_name", "")) != "room_first_entered":
            continue
        p = _pay(event)
        rows.append({
            "run_id": str(event.get("run_id", "")),
            "floor": int(_num(event.get("floor"))),
            "room_id": str(p.get("room_id", "")),
            "role": str(p.get("role", "")),
            "critical_path": bool(p.get("critical_path", False)),
            "optional": bool(p.get("optional", False)),
            "seconds_since_floor_start": _num(p.get("seconds_since_floor_start")),
            "player_health": int(_num(p.get("player_health"))),
            "alive_enemies": int(_num(p.get("alive_enemies"))),
            "reward_present": bool(p.get("reward_present", False)),
        })
    return rows


def build_dataset(events: list[dict]) -> Dataset:
    offers, selections = _build_upgrades(events)
    return Dataset(
        sessions=_build_sessions(events),
        runs=_build_runs(events),
        floors=_build_floors(events),
        weapons=_build_weapons(events),
        upgrade_offers=offers,
        upgrade_selections=selections,
        enemies=_build_enemies(events),
        economy=_build_economy(events),
        rooms=_build_rooms(events),
    )
