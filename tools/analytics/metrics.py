"""Агрегированные метрики над Dataset — используются в HTML report и version comparison."""

from __future__ import annotations

from collections import defaultdict
from statistics import median

from .dataset import Dataset


def _safe_div(numerator: float, denominator: float) -> float:
    if denominator <= 0:
        return 0.0
    return numerator / denominator


def _median_or_zero(values: list[float]) -> float:
    return float(median(values)) if values else 0.0


def overview(dataset: Dataset) -> dict:
    runs = dataset.runs
    completed = [r for r in runs if r["reason"] == "victory"]
    deaths = [r for r in runs if r["reason"] == "player_death"]
    total_runs = len(runs)
    return {
        "total_runs": total_runs,
        "completed_runs": len(completed),
        "deaths": len(deaths),
        "completion_rate": _safe_div(len(completed), total_runs),
        "median_floor_reached": _median_or_zero(
            [float(r["floor_reached"]) for r in runs if r["floor_reached"] > 0]
        ),
        "median_duration_seconds": _median_or_zero(
            [r["duration_seconds"] for r in runs if r["duration_seconds"] > 0]
        ),
        "reason_breakdown": _reason_breakdown(runs),
        "sample_size_note": _sample_note(total_runs),
    }


def _reason_breakdown(runs: list[dict]) -> dict[str, int]:
    counts: dict[str, int] = defaultdict(int)
    for run in runs:
        counts[run["reason"]] += 1
    return dict(sorted(counts.items()))


def _sample_note(n: int) -> str:
    if n < 10:
        return "very small sample (<10 runs) — treat all numbers as anecdotal"
    if n < 30:
        return "small sample (<30 runs) — trends only"
    if n < 100:
        return "moderate sample (<100 runs)"
    return "sample size ok (>=100 runs)"


def weapons_summary(dataset: Dataset) -> list[dict]:
    rows: dict[str, dict[str, float]] = defaultdict(lambda: {
        "runs": 0.0,
        "floors_used": 0.0,
        "equipped_seconds": 0.0,
        "combat_seconds": 0.0,
        "attacks": 0.0,
        "attacks_with_hit": 0.0,
        "projectiles_fired": 0.0,
        "projectiles_hit": 0.0,
        "damage_dealt": 0.0,
        "kills": 0.0,
        "damage_taken_while_equipped": 0.0,
    })
    runs_by_weapon: dict[str, set[str]] = defaultdict(set)
    for row in dataset.weapons:
        wid = row["weapon_id"]
        if not wid:
            continue
        agg = rows[wid]
        agg["floors_used"] += 1
        agg["equipped_seconds"] += float(row["equipped_seconds"])
        agg["combat_seconds"] += float(row["combat_seconds"])
        agg["attacks"] += float(row["attacks"])
        agg["attacks_with_hit"] += float(row["attacks_with_hit"])
        agg["projectiles_fired"] += float(row["projectiles_fired"])
        agg["projectiles_hit"] += float(row["projectiles_hit"])
        agg["damage_dealt"] += float(row["damage_dealt"])
        agg["kills"] += float(row["kills"])
        agg["damage_taken_while_equipped"] += float(row["damage_taken_while_equipped"])
        runs_by_weapon[wid].add(row["run_id"])
    result: list[dict] = []
    for wid in sorted(rows.keys()):
        agg = rows[wid]
        result.append({
            "weapon_id": wid,
            "runs_used_in": len(runs_by_weapon[wid]),
            "floors_used": int(agg["floors_used"]),
            "equipped_seconds": agg["equipped_seconds"],
            "combat_seconds": agg["combat_seconds"],
            "attacks": int(agg["attacks"]),
            "attacks_with_hit": int(agg["attacks_with_hit"]),
            "damage_dealt": int(agg["damage_dealt"]),
            "kills": int(agg["kills"]),
            "damage_taken_while_equipped": int(agg["damage_taken_while_equipped"]),
            "hit_rate": _safe_div(agg["attacks_with_hit"], agg["attacks"]),
            "projectile_hit_rate": _safe_div(agg["projectiles_hit"], agg["projectiles_fired"]),
            "damage_per_equipped_minute": _safe_div(agg["damage_dealt"], agg["equipped_seconds"] / 60.0),
            "damage_per_combat_minute": _safe_div(agg["damage_dealt"], agg["combat_seconds"] / 60.0),
            "kills_per_minute": _safe_div(agg["kills"], agg["equipped_seconds"] / 60.0),
        })
    return result


def upgrades_summary(dataset: Dataset) -> list[dict]:
    offers_by_card: dict[str, int] = defaultdict(int)
    selections_by_card: dict[str, int] = defaultdict(int)
    position_offers: dict[int, int] = defaultdict(int)
    position_selects: dict[int, int] = defaultdict(int)
    choice_time_seconds: list[float] = []
    for offer in dataset.upgrade_offers:
        offers_by_card[offer["card_id"]] += 1
        if offer["position"] >= 0:
            position_offers[offer["position"]] += 1
            if offer["selected"]:
                position_selects[offer["position"]] += 1
    for sel in dataset.upgrade_selections:
        selections_by_card[sel["selected_id"]] += 1
        if sel["choice_time_seconds"] > 0:
            choice_time_seconds.append(sel["choice_time_seconds"])
    cards: list[dict] = []
    for card_id in sorted(set(offers_by_card) | set(selections_by_card)):
        offered = offers_by_card.get(card_id, 0)
        selected = selections_by_card.get(card_id, 0)
        cards.append({
            "card_id": card_id,
            "offered": offered,
            "selected": selected,
            "pick_rate": _safe_div(selected, offered),
        })
    positions: list[dict] = []
    for position in sorted(position_offers):
        offered = position_offers[position]
        selected = position_selects.get(position, 0)
        positions.append({
            "position": position,
            "offered": offered,
            "selected": selected,
            "pick_rate": _safe_div(selected, offered),
        })
    return [
        {"section": "cards", "rows": cards},
        {"section": "positions", "rows": positions},
        {"section": "choice_time", "rows": [
            {"median_choice_time_seconds": _median_or_zero(choice_time_seconds),
             "samples": len(choice_time_seconds)}
        ]},
    ]


def enemies_summary(dataset: Dataset) -> list[dict]:
    agg: dict[tuple[str, str, int], dict[str, float]] = defaultdict(lambda: {
        "spawned": 0.0,
        "killed": 0.0,
        "damage_to_player": 0.0,
        "hits_to_player": 0.0,
        "damage_received": 0.0,
        "time_alive_seconds": 0.0,
        "player_deaths": 0.0,
        "floors_seen": 0.0,
    })
    for row in dataset.enemies:
        key = (row["enemy_id"], row["temperament"], row["elite_rank"])
        bucket = agg[key]
        bucket["floors_seen"] += 1
        for field_name in ("spawned", "killed", "damage_to_player", "hits_to_player",
                           "damage_received", "time_alive_seconds", "player_deaths"):
            bucket[field_name] += float(row[field_name])
    rows: list[dict] = []
    for key in sorted(agg.keys()):
        enemy_id, temperament, rank = key
        b = agg[key]
        rows.append({
            "enemy_id": enemy_id,
            "temperament": temperament,
            "elite_rank": rank,
            "floors_seen": int(b["floors_seen"]),
            "spawned": int(b["spawned"]),
            "killed": int(b["killed"]),
            "damage_to_player": int(b["damage_to_player"]),
            "hits_to_player": int(b["hits_to_player"]),
            "damage_received": int(b["damage_received"]),
            "time_alive_seconds": b["time_alive_seconds"],
            "player_deaths": int(b["player_deaths"]),
            "damage_per_spawn": _safe_div(b["damage_to_player"], b["spawned"]),
            "kill_rate": _safe_div(b["killed"], b["spawned"]),
            "avg_time_to_kill_seconds": _safe_div(b["time_alive_seconds"], b["killed"]),
        })
    return rows


def dungeon_summary(dataset: Dataset) -> list[dict]:
    """Одна строка на floor number с усреднением по всем прогонам."""
    agg: dict[int, dict[str, float]] = defaultdict(lambda: {
        "duration_seconds": 0.0,
        "rooms_visited": 0.0,
        "room_count": 0.0,
        "damage_taken": 0.0,
        "kills": 0.0,
        "gold_earned": 0.0,
        "walkable_area_cells": 0.0,
        "critical_path_length_cells": 0.0,
        "samples": 0.0,
    })
    for row in dataset.floors:
        b = agg[row["floor"]]
        b["samples"] += 1
        for field_name in ("duration_seconds", "rooms_visited", "room_count",
                           "damage_taken", "kills", "gold_earned",
                           "walkable_area_cells", "critical_path_length_cells"):
            b[field_name] += float(row[field_name])
    rows: list[dict] = []
    for floor in sorted(agg.keys()):
        b = agg[floor]
        n = b["samples"]
        rows.append({
            "floor": floor,
            "samples": int(n),
            "avg_duration_seconds": _safe_div(b["duration_seconds"], n),
            "avg_rooms_visited": _safe_div(b["rooms_visited"], n),
            "avg_room_count": _safe_div(b["room_count"], n),
            "avg_damage_taken": _safe_div(b["damage_taken"], n),
            "avg_kills": _safe_div(b["kills"], n),
            "avg_gold_earned": _safe_div(b["gold_earned"], n),
            "avg_walkable_area_cells": _safe_div(b["walkable_area_cells"], n),
            "avg_critical_path_length": _safe_div(b["critical_path_length_cells"], n),
            "rooms_visited_ratio": _safe_div(b["rooms_visited"], b["room_count"]),
        })
    return rows


def economy_summary(dataset: Dataset) -> dict:
    total: dict[str, float] = defaultdict(float)
    for row in dataset.economy:
        for field_name in ("gold_from_enemies", "gold_from_chests", "gold_from_props",
                           "gold_from_bosses", "potions_received", "potions_used",
                           "healing_received", "overheal", "chests_opened"):
            total[field_name] += float(row[field_name])
    total_gold = sum(total[k] for k in ("gold_from_enemies", "gold_from_chests",
                                        "gold_from_props", "gold_from_bosses"))
    return {
        "total_gold": int(total_gold),
        "gold_split": {
            "enemies": _safe_div(total["gold_from_enemies"], total_gold),
            "chests": _safe_div(total["gold_from_chests"], total_gold),
            "props": _safe_div(total["gold_from_props"], total_gold),
            "bosses": _safe_div(total["gold_from_bosses"], total_gold),
        },
        "potions_received": int(total["potions_received"]),
        "potions_used": int(total["potions_used"]),
        "potion_use_rate": _safe_div(total["potions_used"], total["potions_received"]),
        "overheal_ratio": _safe_div(total["overheal"], total["healing_received"]),
        "chests_opened": int(total["chests_opened"]),
        "floor_samples": len(dataset.economy),
    }


def data_quality(dataset: Dataset, issues: list[dict]) -> dict:
    errors = sum(1 for i in issues if i.get("level") == "error")
    warnings_ = sum(1 for i in issues if i.get("level") == "warning")
    infos = sum(1 for i in issues if i.get("level") == "info")
    unfinished_runs = [r["run_id"] for r in dataset.runs if r["duration_seconds"] == 0.0]
    return {
        "errors": errors,
        "warnings": warnings_,
        "infos": infos,
        "runs_total": len(dataset.runs),
        "runs_unfinished": len(unfinished_runs),
        "floors_total": len(dataset.floors),
        "weapons_rows": len(dataset.weapons),
        "enemies_rows": len(dataset.enemies),
        "top_issue_codes": _top_issue_codes(issues),
    }


def _top_issue_codes(issues: list[dict]) -> list[dict]:
    counts: dict[str, int] = defaultdict(int)
    for issue in issues:
        counts[issue.get("code", "unknown")] += 1
    return [
        {"code": code, "count": count}
        for code, count in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    ][:10]
