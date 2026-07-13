"""CLI: импорт JSONL-файлов, вывод summary в stdout."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .importer import import_from_root


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Импорт JSONL-событий roguelike-game")
    parser.add_argument("--input", required=True,
        help="Путь к каталогу с *.jsonl или к одному .jsonl файлу")
    parser.add_argument("--output", default=None,
        help="Если указан — записать все распарсенные события одним events.jsonl")
    parser.add_argument("--issues-output", default=None,
        help="Если указан — записать список issues одним issues.json")
    args = parser.parse_args(argv)
    result = import_from_root(Path(args.input))
    print(json.dumps(result.summary(), indent=2))
    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", encoding="utf-8") as fh:
            for event in result.events:
                # Не утечём внутренние поля (_source_file, _line_number) в
                # экспортируемый JSONL — это локальные пути пользователя.
                public = {k: v for k, v in event.items() if not k.startswith("_")}
                fh.write(json.dumps(public, sort_keys=True) + "\n")
    if args.issues_output:
        out = Path(args.issues_output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps([i.to_dict() for i in result.issues], indent=2),
            encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
