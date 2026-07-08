#!/usr/bin/env python3
"""
Генератор pixel-art спрайтов снарядов.

- player_bullet.png (8×8) — универсальный магический снаряд игрока.
  Bullet.apply_weapon() всё равно перекрашивает через modulate, но
  сам спрайт даёт форму «горящей звёздочки», а не квадрата.
- enemy_bullet.png (8×8) — оранжево-красный шар с ореолом для
  дальнобойных врагов (Skeleton Archer, Lich) и залпов босса.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "sprites" / "bullets"


def render(rows: list[str], palette: dict[str, tuple[int, int, int, int]]) -> Image.Image:
    height = len(rows)
    width = max(len(row) for row in rows)
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    pixels = img.load()
    for y, row in enumerate(rows):
        padded = row.ljust(width, ".")
        for x, ch in enumerate(padded):
            color = palette.get(ch)
            if color is not None:
                pixels[x, y] = color
    return img


# --- PLAYER BULLET — белый горящий сгусток с жёлтой сердцевиной ---------
PLAYER_BULLET_PALETTE = {
    ".": (0, 0, 0, 0),
    "O": (255, 240, 200, 200),  # мягкая жёлтая аура
    "C": (255, 220, 120, 255),  # средний слой
    "H": (255, 255, 255, 255),  # ядро — белый
}

PLAYER_BULLET = [
    "........",
    "...OO...",
    "..OCCO..",
    ".OCHHCO.",
    ".OCHHCO.",
    "..OCCO..",
    "...OO...",
    "........",
]


# --- ENEMY BULLET — оранжево-красный шар с ореолом ----------------------
ENEMY_BULLET_PALETTE = {
    ".": (0, 0, 0, 0),
    "O": (255, 150, 50, 180),   # оранжевая аура
    "R": (240, 90, 30, 255),    # красно-оранжевое ядро
    "H": (255, 220, 100, 255),  # горячая точка
    "d": (140, 40, 15, 255),    # тень
}

ENEMY_BULLET = [
    "........",
    "...OO...",
    "..OdRO..",
    ".ORHHRO.",
    ".ORHHRO.",
    "..ORRO..",
    "...OO...",
    "........",
]


SPRITES = [
    ("player_bullet.png", PLAYER_BULLET, PLAYER_BULLET_PALETTE),
    ("enemy_bullet.png", ENEMY_BULLET, ENEMY_BULLET_PALETTE),
]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for filename, rows, palette in SPRITES:
        img = render(rows, palette)
        out = OUT_DIR / filename
        img.save(out)
        print(f"wrote {out} ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
