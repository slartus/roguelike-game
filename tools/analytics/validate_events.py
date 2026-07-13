"""CLI: валидация JSONL, exit code = 1 если есть errors."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .importer import import_from_root
from .validator import validate, partition_by_level


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Валидация JSONL-событий")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", default=None,
        help="Куда писать issues (JSON). По умолчанию только stdout summary.")
    args = parser.parse_args(argv)
    result = import_from_root(Path(args.input))
    issues = list(result.issues)
    issues.extend(validate(result.events))
    buckets = partition_by_level(issues)
    summary = {
        "files_scanned": result.files_scanned,
        "events_kept": len(result.events),
        "errors": len(buckets.get("error", [])),
        "warnings": len(buckets.get("warning", [])),
        "infos": len(buckets.get("info", [])),
    }
    print(json.dumps(summary, indent=2))
    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps([i.to_dict() for i in issues], indent=2),
            encoding="utf-8")
    return 1 if summary["errors"] > 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
