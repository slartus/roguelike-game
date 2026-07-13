"""CLI: вывести content_balance_hash проекта."""

from __future__ import annotations

import argparse
from pathlib import Path

from .content_hash import DEFAULT_INCLUDE_GLOBS, compute_content_balance_hash


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Вычислить content_balance_hash")
    parser.add_argument("--project-root", default=".",
        help="Путь к корню проекта (по умолчанию текущий каталог)")
    parser.add_argument("--glob", action="append", default=None,
        help="Дополнительный include-glob (можно указать несколько раз)")
    args = parser.parse_args(argv)
    globs = tuple(args.glob) if args.glob else DEFAULT_INCLUDE_GLOBS
    result = compute_content_balance_hash(Path(args.project_root), globs)
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
