"""CLI: сравнение baseline/candidate balance_version'ов."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .compare import build_comparison_html, compare_versions
from .dataset import build_dataset
from .importer import import_from_root


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Сравнить два balance version'а")
    parser.add_argument("--input", required=True)
    parser.add_argument("--baseline-balance-version", type=int, required=True)
    parser.add_argument("--candidate-balance-version", type=int, required=True)
    parser.add_argument("--output", required=True,
        help="Путь к output HTML файлу")
    parser.add_argument("--json-output", default=None,
        help="Дополнительно записать сравнение как JSON")
    args = parser.parse_args(argv)
    result = import_from_root(Path(args.input))
    dataset = build_dataset(result.events)
    comparison = compare_versions(
        dataset,
        args.baseline_balance_version,
        args.candidate_balance_version,
    )
    html_str = build_comparison_html(comparison)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html_str, encoding="utf-8")
    if args.json_output:
        json_out = Path(args.json_output)
        json_out.parent.mkdir(parents=True, exist_ok=True)
        json_out.write_text(json.dumps(comparison, indent=2), encoding="utf-8")
    print(f"comparison written: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
