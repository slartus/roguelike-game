"""Сравнение baseline и candidate balance_version'ов."""

from __future__ import annotations

import html
from datetime import datetime, timezone

from .dataset import Dataset
from . import metrics


def _filter_dataset(dataset: Dataset, balance_version: int) -> Dataset:
    """Возвращает Dataset, содержащий только записи с указанной balance_version.

    Полагаемся на runs.balance_version как источник правды — каскадно отфильтровываем
    зависимые таблицы по run_id.
    """
    keep_run_ids = {r["run_id"] for r in dataset.runs if r["balance_version"] == balance_version}
    keep_session_ids = {r["session_id"] for r in dataset.runs if r["balance_version"] == balance_version}
    return Dataset(
        sessions=[s for s in dataset.sessions if s["session_id"] in keep_session_ids],
        runs=[r for r in dataset.runs if r["run_id"] in keep_run_ids],
        floors=[f for f in dataset.floors if f["run_id"] in keep_run_ids],
        weapons=[w for w in dataset.weapons if w["run_id"] in keep_run_ids],
        upgrade_offers=[u for u in dataset.upgrade_offers if u["run_id"] in keep_run_ids],
        upgrade_selections=[u for u in dataset.upgrade_selections if u["run_id"] in keep_run_ids],
        enemies=[e for e in dataset.enemies if e["run_id"] in keep_run_ids],
        economy=[e for e in dataset.economy if e["run_id"] in keep_run_ids],
        rooms=[r for r in dataset.rooms if r["run_id"] in keep_run_ids],
    )


def _percent_delta(baseline: float, candidate: float) -> float | None:
    # Возвращаем None при baseline=0 и candidate≠0 — HTML/JSON форматируют
    # это как "N/A", чтобы не показывать вводящий в заблуждение 0.0%.
    if baseline == 0:
        return 0.0 if candidate == 0 else None
    return (candidate - baseline) / abs(baseline)


def _sample_warning(n: int) -> str:
    if n < 10:
        return "very small N — anecdotal"
    if n < 30:
        return "small N — trend only"
    return ""


def _compare_scalar(label: str, baseline: float, candidate: float,
        baseline_n: int, candidate_n: int) -> dict:
    return {
        "metric": label,
        "baseline": baseline,
        "candidate": candidate,
        "absolute_delta": candidate - baseline,
        "percent_delta": _percent_delta(baseline, candidate),
        "baseline_samples": baseline_n,
        "candidate_samples": candidate_n,
        "sample_warning": _sample_warning(min(baseline_n, candidate_n)),
    }


def _weapon_index(rows: list[dict]) -> dict[str, dict]:
    return {row["weapon_id"]: row for row in rows}


def _enemy_key(row: dict) -> tuple[str, str, int]:
    return (row["enemy_id"], row["temperament"], row["elite_rank"])


def compare_versions(dataset: Dataset, baseline_version: int,
        candidate_version: int) -> dict:
    baseline_ds = _filter_dataset(dataset, baseline_version)
    candidate_ds = _filter_dataset(dataset, candidate_version)
    baseline_ov = metrics.overview(baseline_ds)
    candidate_ov = metrics.overview(candidate_ds)
    overview_delta = [
        _compare_scalar(
            "completion_rate",
            baseline_ov["completion_rate"], candidate_ov["completion_rate"],
            baseline_ov["total_runs"], candidate_ov["total_runs"],
        ),
        _compare_scalar(
            "median_floor_reached",
            baseline_ov["median_floor_reached"], candidate_ov["median_floor_reached"],
            baseline_ov["total_runs"], candidate_ov["total_runs"],
        ),
        _compare_scalar(
            "median_duration_seconds",
            baseline_ov["median_duration_seconds"], candidate_ov["median_duration_seconds"],
            baseline_ov["total_runs"], candidate_ov["total_runs"],
        ),
    ]
    baseline_weapons = _weapon_index(metrics.weapons_summary(baseline_ds))
    candidate_weapons = _weapon_index(metrics.weapons_summary(candidate_ds))
    weapon_deltas: list[dict] = []
    for wid in sorted(set(baseline_weapons) | set(candidate_weapons)):
        b = baseline_weapons.get(wid, {})
        c = candidate_weapons.get(wid, {})
        weapon_deltas.append({
            "weapon_id": wid,
            "hit_rate": _compare_scalar(
                "hit_rate",
                float(b.get("hit_rate", 0.0)), float(c.get("hit_rate", 0.0)),
                int(b.get("runs_used_in", 0)), int(c.get("runs_used_in", 0)),
            ),
            "damage_per_equipped_minute": _compare_scalar(
                "damage_per_equipped_minute",
                float(b.get("damage_per_equipped_minute", 0.0)),
                float(c.get("damage_per_equipped_minute", 0.0)),
                int(b.get("runs_used_in", 0)), int(c.get("runs_used_in", 0)),
            ),
        })
    baseline_enemies = {_enemy_key(r): r for r in metrics.enemies_summary(baseline_ds)}
    candidate_enemies = {_enemy_key(r): r for r in metrics.enemies_summary(candidate_ds)}
    enemy_deltas: list[dict] = []
    for key in sorted(set(baseline_enemies) | set(candidate_enemies)):
        b = baseline_enemies.get(key, {})
        c = candidate_enemies.get(key, {})
        enemy_deltas.append({
            "enemy_id": key[0],
            "temperament": key[1],
            "elite_rank": key[2],
            "damage_per_spawn": _compare_scalar(
                "damage_per_spawn",
                float(b.get("damage_per_spawn", 0.0)), float(c.get("damage_per_spawn", 0.0)),
                int(b.get("spawned", 0)), int(c.get("spawned", 0)),
            ),
            "kill_rate": _compare_scalar(
                "kill_rate",
                float(b.get("kill_rate", 0.0)), float(c.get("kill_rate", 0.0)),
                int(b.get("spawned", 0)), int(c.get("spawned", 0)),
            ),
        })
    return {
        "baseline_balance_version": baseline_version,
        "candidate_balance_version": candidate_version,
        "baseline_runs": baseline_ov["total_runs"],
        "candidate_runs": candidate_ov["total_runs"],
        "overview_deltas": overview_delta,
        "weapon_deltas": weapon_deltas,
        "enemy_deltas": enemy_deltas,
    }


def build_comparison_html(comparison: dict) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    def fmt_delta(d: dict) -> str:
        pct = d["percent_delta"]
        pct_str = "N/A" if pct is None else f"{pct * 100.0:+.1f}%"
        warning = f" ({d['sample_warning']})" if d["sample_warning"] else ""
        return (
            f"{d['metric']}: baseline={d['baseline']:.3f}, "
            f"candidate={d['candidate']:.3f}, "
            f"Δ={d['absolute_delta']:+.3f} ({pct_str}){warning}"
        )

    parts: list[str] = [
        "<!DOCTYPE html><html><head><meta charset='utf-8'>",
        "<title>Balance version comparison</title></head><body>",
        "<h1>Balance version comparison</h1>",
        f"<p>Generated at {html.escape(now)}</p>",
        f"<p>Baseline: balance_version={comparison['baseline_balance_version']} "
        f"({comparison['baseline_runs']} runs)</p>",
        f"<p>Candidate: balance_version={comparison['candidate_balance_version']} "
        f"({comparison['candidate_runs']} runs)</p>",
        "<h2>Overview deltas</h2><ul>",
    ]
    for d in comparison["overview_deltas"]:
        parts.append(f"<li>{html.escape(fmt_delta(d))}</li>")
    parts.append("</ul><h2>Weapon deltas</h2><ul>")
    for w in comparison["weapon_deltas"]:
        parts.append(
            f"<li><b>{html.escape(w['weapon_id'])}</b>: "
            f"{html.escape(fmt_delta(w['hit_rate']))}; "
            f"{html.escape(fmt_delta(w['damage_per_equipped_minute']))}</li>"
        )
    parts.append("</ul><h2>Enemy deltas</h2><ul>")
    for e in comparison["enemy_deltas"]:
        parts.append(
            f"<li><b>{html.escape(e['enemy_id'])}</b> "
            f"({html.escape(e['temperament'])}, rank={e['elite_rank']}): "
            f"{html.escape(fmt_delta(e['damage_per_spawn']))}; "
            f"{html.escape(fmt_delta(e['kill_rate']))}</li>"
        )
    parts.append(
        "</ul><p><b>Note:</b> statistical significance NOT computed. "
        "Small N warnings shown next to each metric.</p>"
    )
    parts.append("</body></html>")
    return "\n".join(parts)
