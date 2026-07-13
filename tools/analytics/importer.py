"""JSONL importer — устойчивый к порче последней строки и дублям.

Гарантии:
- corrupt / non-JSON строки пропускаются с записью в issues (не крашат импорт);
- дубли по event_id откидываются (сохраняется первый встреченный);
- unknown event_name сохраняется как SkippedEvent (в issues), не в датасете;
- future schema_version отбрасывается с warning.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Iterator

from . import schemas


@dataclass(frozen=True)
class Issue:
    level: str
    code: str
    message: str
    source_file: str = ""
    line_number: int = 0
    event_name: str = ""

    def to_dict(self) -> dict:
        return {
            "level": self.level,
            "code": self.code,
            "message": self.message,
            "source_file": self.source_file,
            "line_number": self.line_number,
            "event_name": self.event_name,
        }


@dataclass
class ImportResult:
    events: list[dict] = field(default_factory=list)
    issues: list[Issue] = field(default_factory=list)
    lines_read: int = 0
    lines_parsed: int = 0
    duplicates_skipped: int = 0
    unknown_events_skipped: int = 0
    future_schema_skipped: int = 0
    files_scanned: int = 0

    def summary(self) -> dict:
        return {
            "files_scanned": self.files_scanned,
            "lines_read": self.lines_read,
            "lines_parsed": self.lines_parsed,
            "events_kept": len(self.events),
            "duplicates_skipped": self.duplicates_skipped,
            "unknown_events_skipped": self.unknown_events_skipped,
            "future_schema_skipped": self.future_schema_skipped,
            "issues": len(self.issues),
        }


def iter_jsonl_paths(root: Path) -> Iterator[Path]:
    if root.is_file():
        # Явно указанный файл принимаем независимо от суффикса —
        # позволяет читать test fixture'ы, отладочные snapshot'ы,
        # переименованные экспорты. Каталоги строже: там ищем только *.jsonl.
        yield root
        return
    if not root.is_dir():
        return
    yield from sorted(p for p in root.rglob("*.jsonl") if p.is_file())


def import_paths(paths: Iterable[Path]) -> ImportResult:
    result = ImportResult()
    seen_event_ids: set[str] = set()
    for path in paths:
        result.files_scanned += 1
        with path.open("r", encoding="utf-8") as fh:
            for lineno, raw_line in enumerate(fh, start=1):
                result.lines_read += 1
                stripped = raw_line.rstrip("\n").rstrip("\r")
                if not stripped:
                    continue
                try:
                    event = json.loads(stripped)
                except json.JSONDecodeError as exc:
                    result.issues.append(Issue(
                        level="warning",
                        code="json_parse_error",
                        message=f"invalid JSON: {exc.msg}",
                        source_file=str(path),
                        line_number=lineno,
                    ))
                    continue
                if not isinstance(event, dict):
                    result.issues.append(Issue(
                        level="warning",
                        code="non_object_row",
                        message=f"expected JSON object, got {type(event).__name__}",
                        source_file=str(path),
                        line_number=lineno,
                    ))
                    continue
                result.lines_parsed += 1
                schema_version = event.get("schema_version")
                # bool — subclass of int в Python, отфильтровываем явно.
                if isinstance(schema_version, bool) or not isinstance(schema_version, int):
                    result.issues.append(Issue(
                        level="warning",
                        code="missing_schema_version",
                        message="schema_version missing or non-int",
                        source_file=str(path),
                        line_number=lineno,
                        event_name=str(event.get("event_name", "")),
                    ))
                    continue
                if schema_version > schemas.SUPPORTED_SCHEMA_VERSION:
                    result.future_schema_skipped += 1
                    result.issues.append(Issue(
                        level="warning",
                        code="future_schema_version",
                        message=(
                            f"schema_version={schema_version} exceeds supported "
                            f"{schemas.SUPPORTED_SCHEMA_VERSION}"
                        ),
                        source_file=str(path),
                        line_number=lineno,
                        event_name=str(event.get("event_name", "")),
                    ))
                    continue
                event_id_raw = event.get("event_id")
                event_id = str(event_id_raw) if event_id_raw is not None else ""
                if event_id and event_id in seen_event_ids:
                    result.duplicates_skipped += 1
                    result.issues.append(Issue(
                        level="info",
                        code="duplicate_event_id",
                        message=f"event_id already seen: {event_id}",
                        source_file=str(path),
                        line_number=lineno,
                        event_name=str(event.get("event_name", "")),
                    ))
                    continue
                if event_id:
                    seen_event_ids.add(event_id)
                event_name = event.get("event_name", "")
                if not schemas.is_known_event(str(event_name)):
                    result.unknown_events_skipped += 1
                    result.issues.append(Issue(
                        level="warning",
                        code="unknown_event",
                        message=f"unknown event_name '{event_name}'",
                        source_file=str(path),
                        line_number=lineno,
                        event_name=str(event_name),
                    ))
                    continue
                event["_source_file"] = str(path)
                event["_line_number"] = lineno
                result.events.append(event)
    return result


def import_from_root(root: Path) -> ImportResult:
    return import_paths(list(iter_jsonl_paths(root)))
