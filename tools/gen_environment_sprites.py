#!/usr/bin/env python3
"""
Генератор pixel-art tile'ов подземелья: пол, стена, пустота.
Каждый 20×20 (совпадает с TILE_SIZE в floor.gd). Godot тайлит их
через Polygon2D.texture + texture_repeat=ENABLED.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "sprites" / "environment"


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


# --- FLOOR — светло-серый камень со швами -------------------------------
FLOOR_PALETTE = {
    "F": (70, 62, 78, 255),      # основной камень (тёплый серо-фиолетовый)
    "L": (95, 85, 105, 255),     # светлый блик
    "d": (45, 40, 55, 255),      # тень
    "S": (30, 25, 40, 255),      # шов между плитками
}

# 20×20, плитка 10×10 в шахматном порядке со швами по границам.
FLOOR = [
    "SSSSSSSSSSSSSSSSSSSS",
    "SFLLFFFFFFSFFFFFFFFS",
    "SLFFFFFFdFSFFFdFFFFS",
    "SFFFFFdFFFSFFFFFFLFS",
    "SFFdFFFFFFSFLFFFFFFS",
    "SFFFFFFFLFSFFFFFFdFS",
    "SFFFFLFFFFSFFFFFFFFS",
    "SFFFFFFFFFSFdFFFFFLS",
    "SLFFFFFdFFSFFFFdFFFS",
    "SFFFdFFFFFSFFFFFFFFS",
    "SSSSSSSSSSSSSSSSSSSS",
    "SFFFFLFFFFSFFFdFFFFS",
    "SFdFFFFFFFSFFFFFFFFS",
    "SFFFFFFdFFSLFFFFFFdS",
    "SFFFFFFFFLSFFFFFFFFS",
    "SFFdFFFFFFSFFFLFFFFS",
    "SFFFFFFLFFSFdFFFFFFS",
    "SFFFFFFFFFSFFFFdFFFS",
    "SLFFdFFFFFSFFFFFFFFS",
    "SSSSSSSSSSSSSSSSSSSS",
]


# --- WALL — тёмно-серый кирпич в кладку --------------------------------
WALL_PALETTE = {
    "B": (35, 28, 38, 255),      # тёмный кирпич
    "b": (22, 18, 26, 255),      # шов
    "L": (55, 45, 60, 255),      # верхний свет (грань)
    "d": (15, 12, 18, 255),      # тень
    "M": (30, 22, 30, 255),      # мох/пятна
}

# 20x20 — 2 ряда кирпичей 20x10, с смещением (running bond) для реалистичности.
WALL = [
    "LLLLLLLLLLLLLLLLLLLL",
    "BBBBBBBBBbBBBBBBBBBB",
    "BBBBBBBBBbBBBBBBBBBB",
    "BBBMBBBBBbBBBBBBBMBB",
    "BBBBBBBBBbBBBMBBBBBB",
    "BdBBBBBBBbBBBBBBBBBB",
    "BBBBBBBBBbBBBBBBBBBB",
    "BBBBBBBBBbBBBBBBdBBB",
    "BBBBBBBBBbBBBBBBBBBB",
    "bbbbbbbbbbbbbbbbbbbb",
    "LLLLLLLLLLLLLLLLLLLL",
    "BBBBBBbBBBBBBBBBBBBB",
    "BBBBBBbBBBBMBBBBBBBB",
    "BBBMBBbBBBBBBBBBBBBB",
    "BBBBBBbBBBBBBBBBBBBB",
    "BBBBBBbBBBBBBBBBBBBB",
    "BBBBBBbBBBBBBBBBBBBB",
    "BBdBBBbBBBBBBBBBBMBB",
    "BBBBBBbBBBBBBBBBBBBB",
    "bbbbbbbbbbbbbbbbbbbb",
]


SPRITES = [
    ("floor.png", FLOOR, FLOOR_PALETTE),
    ("wall.png", WALL, WALL_PALETTE),
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
