#!/usr/bin/env python3
"""
Генератор pixel-art спрайтов предметов: dagger, сундуки, портал.

- weapons/dagger.png — 16×16 иконка для WeaponPickup (на полу) и HUD.
  Остальные fantasy оружия (short_sword, spear, short_bow, crossbow,
  wand, apprentice_staff) генерируются `tools/gen_weapon_sprites.py`.
- pickups/chest_closed.png, chest_open.png — 20×16, сундук в двух
  состояниях. Открытие меняет текстуру Sprite2D.
- pickups/portal.png — 24×32, магический портал (дверь на след. этаж).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "assets" / "sprites"


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


# ============================================================================
# DAGGER 16×16 — простой стальной кинжал
# ============================================================================
DAGGER_PALETTE = {
    ".": (0, 0, 0, 0),
    "B": (200, 205, 220, 255),   # клинок — светлая сталь
    "b": (130, 140, 155, 255),   # тень клинка
    "D": (60, 65, 80, 255),      # контур
    "H": (110, 60, 30, 255),     # рукоять — коричневая
    "h": (70, 35, 15, 255),      # тень рукояти
    "G": (200, 165, 60, 255),    # эфес — золото
    "g": (140, 105, 30, 255),
}
DAGGER = [
    "................",
    ".......D........",
    "......DBD.......",
    ".....DBBBD......",
    ".....DBbBD......",
    ".....DBBBD......",
    ".....DBbBD......",
    ".....DBBBD......",
    ".....DBbBD......",
    "....DGGGGGGD....",   # эфес
    "....DggggggD....",
    ".....DHHHHD.....",
    ".....DHhhHD.....",
    ".....DHhhHD.....",
    "......DHHD......",
    "................",
]


# ============================================================================
# CHEST CLOSED 20×16 — деревянный сундук
# ============================================================================
CHEST_CLOSED_PALETTE = {
    ".": (0, 0, 0, 0),
    "W": (140, 90, 45, 255),     # дерево
    "w": (90, 55, 25, 255),      # тень дерева
    "D": (55, 30, 10, 255),      # контур
    "M": (110, 100, 90, 255),    # железные полосы
    "m": (65, 55, 45, 255),
    "G": (220, 180, 60, 255),    # золотой замок
    "g": (150, 110, 30, 255),
}
CHEST_CLOSED = [
    "....................",
    "....................",
    "....DDDDDDDDDDDDD...",
    "...DWwWwWwWwWwWwWD..",   # верх крышки
    "..DWWWWMMMMWWWWWWWD.",
    "..DWWwWMWWMWWwWWWWD.",
    "..DDDDDMGGMDDDDDDDD.",   # замочная скважина
    "..DWWWWMggMWWWWWWWD.",
    "..DWWwWMMMMWWwWWWWD.",   # нижняя часть — тело
    "..DWWWWWWWWWWWWWWWD.",
    "..DWMMMMMMMMMMMMWWD.",   # железная полоса внизу
    "..DWWWmmmmmmmmmmWWD.",
    "..DWWWWWWWWWWWWWWWD.",
    "..DDDDDDDDDDDDDDDDD.",
    "....................",
    "....................",
]


# ============================================================================
# CHEST OPEN 20×16 — тот же сундук, крышка откинута, внутри золото
# ============================================================================
CHEST_OPEN_PALETTE = {
    ".": (0, 0, 0, 0),
    "W": (140, 90, 45, 255),
    "w": (90, 55, 25, 255),
    "D": (55, 30, 10, 255),
    "M": (110, 100, 90, 255),
    "m": (65, 55, 45, 255),
    "G": (250, 210, 70, 255),    # золото — ярче
    "g": (200, 160, 50, 255),
    "S": (255, 240, 150, 255),   # блик на золоте
    "K": (25, 15, 8, 255),       # внутренняя тьма
}
CHEST_OPEN = [
    "....................",
    "..DDDDDDDDDDDDDDDD..",   # откинутая крышка сверху
    "..DWwWwWwWwWwWwWWD..",
    "..DWWWWWWWWWWWWWWD..",
    "..DDDDDDDDDDDDDDDD..",
    "....................",
    "..DDDDDDDDDDDDDDDDD.",
    "..DKKKKKKKKKKKKKKKD.",   # внутренность (тёмная)
    "..DKGGGGGGGGGGGGGKD.",   # золото
    "..DKGSGGGGGSGGGSGKD.",   # блики
    "..DKGgGGgGGGgGgGGKD.",
    "..DWMMMMMMMMMMMMWWD.",   # железная полоса
    "..DWWWmmmmmmmmmmWWD.",
    "..DWWWWWWWWWWWWWWWD.",
    "..DDDDDDDDDDDDDDDDD.",
    "....................",
]


# ============================================================================
# PORTAL 24×32 — вертикальный магический портал (дверь на след. этаж)
# ============================================================================
PORTAL_PALETTE = {
    ".": (0, 0, 0, 0),
    "F": (95, 60, 30, 255),      # каменная рама
    "f": (55, 35, 15, 255),      # тень камня
    "D": (25, 15, 8, 255),
    "P": (140, 60, 180, 255),    # магическое свечение — фиолетовый
    "p": (80, 30, 120, 255),
    "L": (200, 130, 240, 255),   # яркий блик
    "B": (240, 210, 255, 255),   # белые искры
    "R": (60, 220, 90, 255),     # зелёная руна
    "S": (30, 5, 40, 255),       # внутренняя тьма портала
}
PORTAL = [
    "........................",
    "........................",
    "........DDDDDDDD........",   # верх рамы
    ".......DfFFFFFFfD.......",
    "......DfFFFFFFFFfD......",
    ".....DfFFDDDDDDFFfD.....",
    ".....DfFDPPPPPPDFfD.....",
    ".....DfFDPPLPPPDFfD.....",
    ".....DfFDPPPPPPDFfD.....",
    ".....DfFDpBpPPPDFfD.....",
    ".....DfFDPPPBPPDFfD.....",
    ".....DfFDPLPPPPDFfD.....",
    ".....DfFDpPRPPpDFfD.....",   # руна внутри
    ".....DfFDPPRRPpDFfD.....",
    ".....DfFDpPRRPPDFfD.....",
    ".....DfFDPPRPPPDFfD.....",
    ".....DfFDpPPBPPDFfD.....",
    ".....DfFDPPPPLPDFfD.....",
    ".....DfFDPBPPPPDFfD.....",
    ".....DfFDpPPPPpDFfD.....",
    ".....DfFDPPPBPPDFfD.....",
    ".....DfFDPPPPPPDFfD.....",
    ".....DfFDpPPPPPDFfD.....",
    ".....DfFDDDDDDDDFfD.....",
    ".....DfFFFSSSSFFFfD.....",   # порог с тёмной пастью
    "......DfFFSSSSFFfD......",
    ".......DfFFFFFFfD.......",
    "........DFFFFFFDD.......",
    ".........DDDDDDD........",
    "........................",
    "........................",
    "........................",
]


SPRITES: list[tuple[str, list[str], dict[str, tuple[int, int, int, int]]]] = [
    ("weapons/dagger.png", DAGGER, DAGGER_PALETTE),
    ("pickups/chest_closed.png", CHEST_CLOSED, CHEST_CLOSED_PALETTE),
    ("pickups/chest_open.png", CHEST_OPEN, CHEST_OPEN_PALETTE),
    ("pickups/portal.png", PORTAL, PORTAL_PALETTE),
]


def main() -> None:
    for filename, rows, palette in SPRITES:
        out = ROOT / filename
        out.parent.mkdir(parents=True, exist_ok=True)
        img = render(rows, palette)
        img.save(out)
        print(f"wrote {out} ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
