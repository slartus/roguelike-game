"""Проверка envelope + payload + run/floor consistency."""

from __future__ import annotations

from collections import defaultdict
from typing import Iterable

from .importer import Issue
from . import schemas


def _add(issues: list[Issue], level: str, code: str, msg: str,
        event: dict | None = None) -> None:
    if event is None:
        issues.append(Issue(level=level, code=code, message=msg))
        return
    issues.append(Issue(
        level=level,
        code=code,
        message=msg,
        source_file=str(event.get("_source_file", "")),
        line_number=int(event.get("_line_number", 0)),
        event_name=str(event.get("event_name", "")),
    ))


def _validate_envelope(event: dict, issues: list[Issue]) -> bool:
    ok = True
    for field_name in schemas.ENVELOPE_REQUIRED:
        if field_name not in event:
            _add(issues, "error", "envelope_missing_field",
                f"envelope missing required field '{field_name}'", event)
            ok = False
    if not isinstance(event.get("payload", {}), dict):
        _add(issues, "error", "payload_not_object",
            "payload is not a JSON object", event)
        ok = False
    return ok


def _validate_payload(event: dict, issues: list[Issue]) -> None:
    spec = schemas.event_spec_or_none(str(event.get("event_name", "")))
    if spec is None:
        return
    payload = event.get("payload", {})
    if not isinstance(payload, dict):
        return
    for field_name in spec.required_payload:
        if field_name not in payload:
            _add(issues, "error", "payload_missing_field",
                f"payload missing required field '{field_name}'", event)
    for field_name in spec.numeric_payload:
        if field_name in payload:
            value = payload[field_name]
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                _add(issues, "warning", "payload_non_numeric",
                    f"field '{field_name}' expected number, got {type(value).__name__}",
                    event)
                continue
            if value < 0:
                _add(issues, "warning", "payload_negative_value",
                    f"field '{field_name}' negative: {value}", event)


def _validate_enums(event: dict, issues: list[Issue]) -> None:
    name = str(event.get("event_name", ""))
    payload = event.get("payload", {})
    if not isinstance(payload, dict):
        return
    if name == "session_finished":
        reason = str(payload.get("reason", ""))
        if reason and reason not in schemas.SESSION_END_REASONS:
            _add(issues, "warning", "unknown_session_reason",
                f"unknown session_finished reason '{reason}'", event)
    elif name == "run_finished":
        reason = str(payload.get("reason", ""))
        if reason and reason not in schemas.RUN_END_REASONS:
            _add(issues, "warning", "unknown_run_reason",
                f"unknown run_finished reason '{reason}'", event)
    elif name == "weapon_equipped":
        source = str(payload.get("source", ""))
        if source and source not in schemas.WEAPON_EQUIP_SOURCES:
            _add(issues, "warning", "unknown_weapon_source",
                f"unknown weapon_equipped source '{source}'", event)


def _sort_key(event: dict) -> tuple:
    """Стабильный порядок для проверок consistency: run_id, timestamp, line.

    JSONL из разных файлов после `iter_jsonl_paths` идёт в порядке имён
    файлов + строк — timestamp'ы могут перемешаться при мульти-сессионных
    прогонах. Для validation мы восстанавливаем логический порядок
    внутри run'а по timestamp'у, а внутри timestamp'а — по номеру строки.
    """
    return (
        str(event.get("run_id", "")),
        int(event.get("timestamp_ms", 0) or 0),
        str(event.get("_source_file", "")),
        int(event.get("_line_number", 0) or 0),
    )


def _validate_run_consistency(events: list[dict], issues: list[Issue]) -> None:
    """Проверки на уровне run: run_id consistency, monotonic floor,
    duplicate run_finished, floor_completed без floor_started, impossible HP."""
    run_started_ids: set[str] = set()
    run_finished_ids: set[str] = set()
    max_floor_by_run: dict[str, int] = defaultdict(int)
    started_floors: dict[tuple[str, int], bool] = {}

    ordered = sorted(events, key=_sort_key)
    for event in ordered:
        name = str(event.get("event_name", ""))
        run_id = event.get("run_id", "")
        if name == "run_started":
            if isinstance(run_id, str) and run_id:
                if run_id in run_started_ids:
                    _add(issues, "warning", "duplicate_run_started",
                        f"run_started emitted twice for run_id={run_id}", event)
                run_started_ids.add(run_id)
        elif name == "run_finished":
            if isinstance(run_id, str) and run_id:
                if run_id in run_finished_ids:
                    _add(issues, "warning", "duplicate_run_finished",
                        f"run_finished emitted twice for run_id={run_id}", event)
                run_finished_ids.add(run_id)
                if run_id not in run_started_ids:
                    _add(issues, "warning", "run_finished_without_started",
                        f"run_finished without matching run_started for {run_id}",
                        event)
        elif name in schemas.FLOOR_SCOPED_EVENTS and name != "floor_started":
            if isinstance(run_id, str) and run_id:
                floor_num = int(event.get("floor", 0))
                key = (run_id, floor_num)
                if key not in started_floors and floor_num > 0:
                    _add(issues, "warning", "floor_event_without_started",
                        f"'{name}' at floor={floor_num} without floor_started",
                        event)
        if name == "floor_started":
            floor_num = int(event.get("floor", 0))
            if isinstance(run_id, str) and run_id and floor_num > 0:
                if floor_num < max_floor_by_run[run_id]:
                    _add(issues, "warning", "non_monotonic_floor",
                        f"floor={floor_num} lower than previous "
                        f"{max_floor_by_run[run_id]} for run {run_id}", event)
                max_floor_by_run[run_id] = max(max_floor_by_run[run_id], floor_num)
                started_floors[(run_id, floor_num)] = True
        payload = event.get("payload", {}) if isinstance(event.get("payload"), dict) else {}
        max_hp = payload.get("max_health")
        cur_hp = payload.get("health_before")
        if isinstance(max_hp, (int, float)) and isinstance(cur_hp, (int, float)):
            if cur_hp > max_hp and max_hp >= 0:
                _add(issues, "warning", "impossible_health",
                    f"health_before={cur_hp} exceeds max_health={max_hp}", event)


def validate(events: list[dict]) -> list[Issue]:
    issues: list[Issue] = []
    for event in events:
        if not _validate_envelope(event, issues):
            continue
        _validate_payload(event, issues)
        _validate_enums(event, issues)
    _validate_run_consistency(events, issues)
    return issues


def partition_by_level(issues: Iterable[Issue]) -> dict[str, list[Issue]]:
    buckets: dict[str, list[Issue]] = {"error": [], "warning": [], "info": []}
    for issue in issues:
        buckets.setdefault(issue.level, []).append(issue)
    return buckets
