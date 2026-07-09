#!/usr/bin/env python3
"""
UI-иконки для HUD (инвентарь и т.п.).

- potion_icon.png (12×12) — иконка зелья лечения для слота инвентаря.
  Совпадает по стилю с health_pickup.tscn (красная жидкость, коричневая
  пробка), но нарисована как pixel-art texture, а не Polygon2D.

Использование:
    python3 tools/gen_ui_icons.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "sprites" / "ui"


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


# --- POTION ICON 12×12 --------------------------------------------
# Круглая колба на короткой шейке с пробкой + блик слева.
POTION_PALETTE = {
    ".": (0, 0, 0, 0),
    "C": (85, 55, 25, 255),       # тёмная пробка
    "c": (140, 90, 45, 255),      # светлая пробка
    "R": (155, 40, 55, 255),      # тёмный контур жидкости
    "F": (220, 55, 75, 255),      # красная жидкость
    "L": (255, 180, 190, 255),    # блик
    "S": (110, 25, 40, 255),      # глубокая тень
}
POTION_ICON = [
    "............",
    "....cCCc....",
    "....cCCc....",
    "....RFFR....",
    "...RFLFFR...",
    "..RFLFFFFR..",
    ".RFFLFFFFFR.",
    ".RFFFFFFFFR.",
    ".RFFFFFFFFR.",
    ".RSFFFFFFSR.",
    "..RSSFFSSR..",
    "...RRRRRR...",
]


SPRITES = [
    ("potion_icon.png", POTION_ICON, POTION_PALETTE),
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
