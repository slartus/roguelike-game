"""CLI: HTML report (report.html) поверх датасета."""

from __future__ import annotations

import argparse
from pathlib import Path

from .dataset import build_dataset
from .importer import import_from_root
from .report import build_report_html
from .validator import validate


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Собрать HTML-отчёт из JSONL")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True,
        help="Путь к output HTML файлу")
    args = parser.parse_args(argv)
    result = import_from_root(Path(args.input))
    dataset = build_dataset(result.events)
    issues = [i.to_dict() for i in result.issues]
    issues.extend(i.to_dict() for i in validate(result.events))
    html_str = build_report_html(dataset, issues)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html_str, encoding="utf-8")
    print(f"report written: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
