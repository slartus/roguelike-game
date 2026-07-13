"""CLI: полная сборка CSV-датасета + issues.json + data_quality.json."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .csv_writer import write_dataset
from .dataset import build_dataset
from .importer import import_from_root
from .validator import validate
from . import metrics


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Собрать CSV-датасет из JSONL")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True,
        help="Каталог для CSV-файлов + data_quality.json")
    args = parser.parse_args(argv)
    result = import_from_root(Path(args.input))
    dataset = build_dataset(result.events)
    issues = [i.to_dict() for i in result.issues]
    issues.extend(i.to_dict() for i in validate(result.events))
    output_dir = Path(args.output)
    files = write_dataset(dataset, output_dir)
    dq_path = output_dir / "data_quality.json"
    dq_path.write_text(json.dumps({
        "quality": metrics.data_quality(dataset, issues),
        "issues": issues,
    }, indent=2), encoding="utf-8")
    summary = {
        "input_summary": result.summary(),
        "csv_files": {name: str(p) for name, p in files.items()},
        "data_quality_json": str(dq_path),
    }
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
