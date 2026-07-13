"""Тесты content_balance_hash: deterministic, file-order-invariant."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.analytics.content_hash import (
    compute_content_balance_hash,
    hash_content_from_bytes,
)


class ContentHashTests(unittest.TestCase):
    def test_hash_deterministic(self) -> None:
        pairs = [
            ("resources/weapons/dagger.tres", b"stats: dagger"),
            ("resources/weapons/bow.tres", b"stats: bow"),
        ]
        h1 = hash_content_from_bytes(pairs)
        h2 = hash_content_from_bytes(pairs)
        self.assertEqual(h1, h2)

    def test_hash_ignores_input_order(self) -> None:
        pairs_a = [
            ("resources/weapons/dagger.tres", b"stats: dagger"),
            ("resources/weapons/bow.tres", b"stats: bow"),
        ]
        pairs_b = list(reversed(pairs_a))
        self.assertEqual(hash_content_from_bytes(pairs_a),
            hash_content_from_bytes(pairs_b))

    def test_hash_changes_on_content_change(self) -> None:
        pairs = [("resources/weapons/dagger.tres", b"stats: dagger")]
        modified = [("resources/weapons/dagger.tres", b"stats: dagger++")]
        self.assertNotEqual(hash_content_from_bytes(pairs),
            hash_content_from_bytes(modified))

    def test_hash_from_filesystem(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "resources" / "weapons").mkdir(parents=True)
            (root / "resources" / "weapons" / "dagger.tres").write_bytes(b"stats: dagger")
            (root / "autoloads").mkdir(parents=True)
            (root / "autoloads" / "balance.gd").write_bytes(b"const BALANCE_VERSION = 1")
            h1 = compute_content_balance_hash(root)
            # Изменение файла меняет hash.
            (root / "resources" / "weapons" / "dagger.tres").write_bytes(b"stats: modified")
            h2 = compute_content_balance_hash(root)
            self.assertNotEqual(h1, h2)


if __name__ == "__main__":
    unittest.main()
