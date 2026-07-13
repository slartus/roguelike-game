"""HTML report generator — самодостаточный (без сервера, без CDN)."""

from __future__ import annotations

import html
from datetime import datetime, timezone
from typing import Any, Iterable

from .dataset import Dataset
from . import metrics


INTERPRETATION_CAVEATS: list[str] = [
    "Correlation is not causation.",
    "Rare weapons/upgrades нельзя оценивать по raw floor reached — pick-rate искажён контекстом offer.",
    "Position offer влияет на выбор карты, не только качество карты.",
    "Strong players создают selection bias по всем метрикам.",
    "Маленький N (<30) — только тенденции, не выводы.",
    "Builds с разным balance_version нельзя смешивать без явного фильтра.",
    "Content-balance-hash mismatch означает различающийся набор ресурсов — сравнение может быть невалидным.",
]


_CSS = """
body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 1100px; margin: 24px auto; padding: 0 16px; color: #222; }
h1 { border-bottom: 2px solid #333; padding-bottom: 8px; }
h2 { margin-top: 32px; border-bottom: 1px solid #ccc; padding-bottom: 4px; }
h3 { margin-top: 20px; color: #555; }
table { border-collapse: collapse; width: 100%; margin: 8px 0; }
th, td { border: 1px solid #ddd; padding: 6px 10px; text-align: left; font-size: 13px; }
th { background: #f4f4f4; }
tr:nth-child(even) { background: #fafafa; }
.small { font-size: 12px; color: #666; }
.warn { background: #fff3cd; border-left: 4px solid #f0ad4e; padding: 8px 12px; margin: 12px 0; }
.warn ul { margin: 4px 0 0 20px; }
.metric { display: inline-block; margin: 4px 12px 4px 0; padding: 6px 10px; background: #f4f8ff; border-radius: 3px; font-size: 13px; }
.metric b { font-family: monospace; font-size: 14px; }
"""


def _fmt(value: Any) -> str:
    if isinstance(value, float):
        return f"{value:.3f}"
    return html.escape(str(value))


def _table(rows: Iterable[dict], columns: list[str] | None = None) -> str:
    rows_list = list(rows)
    if not rows_list:
        return "<p class='small'>Нет данных.</p>"
    if columns is None:
        columns = list(rows_list[0].keys())
    header = "".join(f"<th>{html.escape(c)}</th>" for c in columns)
    body = ""
    for row in rows_list:
        cells = "".join(f"<td>{_fmt(row.get(c, ''))}</td>" for c in columns)
        body += f"<tr>{cells}</tr>"
    return f"<table><thead><tr>{header}</tr></thead><tbody>{body}</tbody></table>"


def _metric_pill(label: str, value: Any) -> str:
    return f"<span class='metric'>{html.escape(label)}: <b>{_fmt(value)}</b></span>"


def _section_overview(dataset: Dataset) -> str:
    ov = metrics.overview(dataset)
    pills = "".join([
        _metric_pill("runs", ov["total_runs"]),
        _metric_pill("completed", ov["completed_runs"]),
        _metric_pill("completion rate", ov["completion_rate"]),
        _metric_pill("median floor", ov["median_floor_reached"]),
        _metric_pill("median duration (s)", ov["median_duration_seconds"]),
    ])
    breakdown_rows = [{"reason": r, "count": c} for r, c in ov["reason_breakdown"].items()]
    return (
        "<h2>Overview</h2>"
        + f"<p class='small'>Sample: {html.escape(ov['sample_size_note'])}</p>"
        + pills
        + "<h3>Death / exit reasons</h3>"
        + _table(breakdown_rows, ["reason", "count"])
    )


def _section_weapons(dataset: Dataset) -> str:
    rows = metrics.weapons_summary(dataset)
    columns = [
        "weapon_id", "runs_used_in", "floors_used", "equipped_seconds",
        "attacks", "hit_rate", "projectile_hit_rate",
        "damage_dealt", "damage_per_equipped_minute", "kills", "kills_per_minute",
        "damage_taken_while_equipped",
    ]
    return "<h2>Weapons</h2>" + _table(rows, columns)


def _section_upgrades(dataset: Dataset) -> str:
    sections = metrics.upgrades_summary(dataset)
    html_parts: list[str] = ["<h2>Upgrades</h2>"]
    for section in sections:
        html_parts.append(f"<h3>{html.escape(section['section'])}</h3>")
        html_parts.append(_table(section["rows"]))
    return "\n".join(html_parts)


def _section_enemies(dataset: Dataset) -> str:
    rows = metrics.enemies_summary(dataset)
    columns = [
        "enemy_id", "temperament", "elite_rank", "floors_seen",
        "spawned", "killed", "kill_rate",
        "damage_to_player", "damage_per_spawn",
        "avg_time_to_kill_seconds", "player_deaths",
    ]
    return "<h2>Enemies</h2>" + _table(rows, columns)


def _section_dungeon(dataset: Dataset) -> str:
    rows = metrics.dungeon_summary(dataset)
    columns = [
        "floor", "samples",
        "avg_duration_seconds", "avg_room_count", "avg_rooms_visited",
        "rooms_visited_ratio", "avg_walkable_area_cells",
        "avg_critical_path_length", "avg_damage_taken", "avg_kills", "avg_gold_earned",
    ]
    return "<h2>Dungeon</h2>" + _table(rows, columns)


def _section_economy(dataset: Dataset) -> str:
    e = metrics.economy_summary(dataset)
    split = e["gold_split"]
    return (
        "<h2>Economy</h2>"
        + _metric_pill("total gold", e["total_gold"])
        + _metric_pill("floor samples", e["floor_samples"])
        + _metric_pill("gold: enemies", split["enemies"])
        + _metric_pill("gold: chests", split["chests"])
        + _metric_pill("gold: props", split["props"])
        + _metric_pill("gold: bosses", split["bosses"])
        + _metric_pill("potions received", e["potions_received"])
        + _metric_pill("potions used", e["potions_used"])
        + _metric_pill("potion use rate", e["potion_use_rate"])
        + _metric_pill("overheal ratio", e["overheal_ratio"])
        + _metric_pill("chests opened", e["chests_opened"])
    )


def _section_data_quality(dataset: Dataset, issues: list[dict]) -> str:
    dq = metrics.data_quality(dataset, issues)
    pills = "".join([
        _metric_pill("errors", dq["errors"]),
        _metric_pill("warnings", dq["warnings"]),
        _metric_pill("infos", dq["infos"]),
        _metric_pill("runs total", dq["runs_total"]),
        _metric_pill("runs unfinished", dq["runs_unfinished"]),
        _metric_pill("floors total", dq["floors_total"]),
    ])
    return (
        "<h2>Data quality</h2>"
        + pills
        + "<h3>Top issue codes</h3>"
        + _table(dq["top_issue_codes"], ["code", "count"])
    )


def _section_caveats() -> str:
    items = "".join(f"<li>{html.escape(c)}</li>" for c in INTERPRETATION_CAVEATS)
    return (
        "<div class='warn'><b>Interpretation caveats:</b>"
        f"<ul>{items}</ul></div>"
    )


def build_report_html(dataset: Dataset, issues: list[dict]) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    parts: list[str] = [
        "<!DOCTYPE html><html><head><meta charset='utf-8'>",
        "<title>Analytics report</title>",
        f"<style>{_CSS}</style>",
        "</head><body>",
        "<h1>Roguelike analytics report</h1>",
        f"<p class='small'>Generated at {html.escape(now)}</p>",
        _section_caveats(),
        _section_overview(dataset),
        _section_weapons(dataset),
        _section_upgrades(dataset),
        _section_enemies(dataset),
        _section_dungeon(dataset),
        _section_economy(dataset),
        _section_data_quality(dataset, issues),
        "</body></html>",
    ]
    return "\n".join(parts)
