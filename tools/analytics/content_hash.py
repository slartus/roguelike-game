"""Content balance hash — детерминированный хеш значимых balance ресурсов.

Инклюдит файлы, попавшие под указанные include-globs; всё остальное
(textures, docs, translations, .import, timestamps) вне scope.

Хеш детерминирован и cross-platform:
- порядок файлов в результате sort'ится по relative path;
- содержимое нормализуется CRLF → LF, чтобы Windows checkout с
  `core.autocrlf=true` давал тот же hash, что macOS/Linux checkout.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Iterable


DEFAULT_INCLUDE_GLOBS: tuple[str, ...] = (
    "resources/weapons/*.tres",
    "resources/upgrades/*.tres",
    "resources/enemies/**/*.tres",
    "autoloads/balance.gd",
)


def _iter_files(project_root: Path, globs: Iterable[str]) -> list[Path]:
    seen: set[Path] = set()
    for pattern in globs:
        for path in project_root.glob(pattern):
            if path.is_file():
                seen.add(path.resolve())
    return sorted(seen)


def _normalize_content(raw: bytes) -> bytes:
    return raw.replace(b"\r\n", b"\n")


def compute_content_balance_hash(project_root: Path,
        globs: Iterable[str] = DEFAULT_INCLUDE_GLOBS) -> str:
    """Возвращает hex-SHA256 всего балансирующего контента.

    Реализация: сортируем файлы по относительному пути, хешируем каждый
    (path + normalized content), затем собираем финальный SHA256.
    """
    hasher = hashlib.sha256()
    project_root = project_root.resolve()
    for path in _iter_files(project_root, globs):
        rel = path.relative_to(project_root).as_posix()
        content = _normalize_content(path.read_bytes())
        hasher.update(rel.encode("utf-8"))
        hasher.update(b"\x00")
        hasher.update(hashlib.sha256(content).digest())
        hasher.update(b"\x00")
    return hasher.hexdigest()


def hash_content_from_bytes(pairs: list[tuple[str, bytes]]) -> str:
    """Тестовая версия: принимает [(path, content), ...] напрямую.

    Порядок в списке НЕ должен влиять на результат — сортируем по path.
    Содержимое также нормализуется CRLF → LF.
    """
    hasher = hashlib.sha256()
    for rel, content in sorted(pairs, key=lambda kv: kv[0]):
        hasher.update(rel.encode("utf-8"))
        hasher.update(b"\x00")
        hasher.update(hashlib.sha256(_normalize_content(content)).digest())
        hasher.update(b"\x00")
    return hasher.hexdigest()
