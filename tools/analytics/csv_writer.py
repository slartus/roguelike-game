"""Утилиты для записи датасета в CSV с детерминированным порядком колонок."""

from __future__ import annotations

import csv
from pathlib import Path

from .dataset import Dataset


def _write_csv(path: Path, rows: list[dict], columns: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    if columns is None:
        # Union всех ключей из всех rows — защита на случай, если row-словари
        # разошлись по составу колонок. Сначала берём порядок первой строки,
        # затем добавляем недостающие колонки из остальных строк в порядке
        # обнаружения.
        seen: dict[str, None] = {}
        for row in rows:
            for key in row.keys():
                seen.setdefault(key, None)
        columns = list(seen.keys())
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_dataset(dataset: Dataset, output_dir: Path) -> dict[str, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    files: dict[str, Path] = {}
    mapping = {
        "sessions.csv": dataset.sessions,
        "runs.csv": dataset.runs,
        "floors.csv": dataset.floors,
        "weapons.csv": dataset.weapons,
        "upgrade_offers.csv": dataset.upgrade_offers,
        "upgrade_selections.csv": dataset.upgrade_selections,
        "enemies.csv": dataset.enemies,
        "economy.csv": dataset.economy,
        "rooms.csv": dataset.rooms,
    }
    for filename, rows in mapping.items():
        path = output_dir / filename
        _write_csv(path, rows)
        files[filename] = path
    return files
