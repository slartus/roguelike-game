#!/usr/bin/env python3
"""
Спрайты снарядов врагов — по типу стрелка:

- arrow.png      (16×5)  — стрела с оперением, для Skeleton Archer.
- magic_bolt.png (10×10) — зелёный магический сгусток, для Lich.
- dark_orb.png   (10×10) — тёмно-фиолетовый шар, для boss volley.

Общий enemy_bullet.png (старый оранжевый шар) остаётся как fallback,
но новыми сценами не используется.
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


# --- ARROW 16×5 — горизонтальная стрела с оперением ------------------
ARROW_PALETTE = {
    ".": (0, 0, 0, 0),
    "F": (200, 50, 50, 255),      # красное оперение
    "f": (140, 30, 30, 255),      # тень оперения
    "S": (140, 90, 45, 255),      # деревянное древко
    "s": (85, 55, 25, 255),       # тень древка
    "A": (200, 205, 220, 255),    # стальной наконечник
    "a": (120, 130, 145, 255),    # тень наконечника
    "D": (30, 25, 15, 255),       # контур
}
ARROW = [
    "................",
    "Ff...SsSsSsSs.Aa",
    "fFFFsSSSSSSSSaAA",
    "Ff...SsSsSsSs.Aa",
    "................",
]


# --- MAGIC BOLT 10×10 — зелёный магический сгусток --------------------
MAGIC_BOLT_PALETTE = {
    ".": (0, 0, 0, 0),
    "G": (60, 210, 90, 255),      # ярко-зелёный
    "g": (30, 140, 55, 255),      # тень
    "L": (150, 255, 170, 255),    # свет
    "W": (240, 255, 240, 255),    # ядро — белое свечение
    "B": (200, 255, 210, 255),    # переход
}
MAGIC_BOLT = [
    "....G.....",
    "...gLg....",
    "..gLGGLg..",
    ".gLGBWBGLg",
    "GLGBWWWBGL",
    "GLGBWWWBGL",
    ".gLGBWBGLg",
    "..gLGGLg..",
    "...gLg....",
    "....G.....",
]


# --- DARK ORB 10×10 — тёмно-фиолетовый шар для boss volley ---------------
DARK_ORB_PALETTE = {
    ".": (0, 0, 0, 0),
    "P": (140, 60, 180, 255),
    "p": (80, 30, 110, 255),
    "d": (40, 15, 55, 255),
    "L": (200, 130, 235, 255),
    "W": (240, 220, 255, 255),
    "S": (170, 90, 200, 255),
}
DARK_ORB = [
    "...PPPP...",
    "..PSPPSp..",
    ".PSLPPLSPd",
    "PSLWPPWLSP",
    "PSLWWWWWLP",
    "PSLWWWWWLP",
    "PSLWPPWLSP",
    ".PSLPPLSPd",
    "..PSPPSp..",
    "...PPPP...",
]


SPRITES = [
    ("arrow.png", ARROW, ARROW_PALETTE),
    ("magic_bolt.png", MAGIC_BOLT, MAGIC_BOLT_PALETTE),
    ("dark_orb.png", DARK_ORB, DARK_ORB_PALETTE),
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
