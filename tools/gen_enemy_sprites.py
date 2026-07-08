#!/usr/bin/env python3
"""
Генератор pixel-art спрайтов монстров. Детерминированный: каждый запуск
даёт идентичный PNG. Полотна — 16×16 (обычные враги) и 32×32 (босс).

Спрайты рисуются построчно через матрицу символов + палитру. Никаких
внешних ассетов и рандома.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "sprites" / "enemies"


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


# --- MELEE — красный демон-слизь ------------------------------------------------
MELEE_PALETTE = {
    ".": (0, 0, 0, 0),
    "R": (200, 40, 40, 255),      # основной красный
    "d": (110, 20, 20, 255),      # тёмный контур
    "W": (245, 245, 245, 255),    # белок глаза
    "B": (10, 10, 10, 255),       # зрачок
    "M": (60, 10, 10, 255),       # рот
    "F": (240, 240, 240, 255),    # клыки
}

MELEE = [
    "................",
    "................",
    "....dddddd......",
    "...dRRRRRRd.....",
    "..dRRRRRRRRd....",
    "..dRRRRRRRRd....",
    ".dRRWWRRWWRRd...",
    ".dRRWBRRWBRRd...",
    ".dRRRRRRRRRRd...",
    ".dRRRMMMMRRRd...",
    ".dRRMFFFFMRRd...",
    "..dRRRRRRRRd....",
    "..dRRRRRRRRd....",
    "...ddddddddd....",
    "................",
    "................",
]


# --- RANGED — синий волшебник ---------------------------------------------------
RANGED_PALETTE = {
    ".": (0, 0, 0, 0),
    "H": (35, 30, 90, 255),       # шляпа (тёмно-синяя)
    "h": (20, 15, 60, 255),       # тень на шляпе
    "T": (240, 220, 60, 255),     # звезда на шляпе
    "B": (70, 110, 210, 255),     # мантия
    "b": (30, 55, 130, 255),      # контур мантии
    "F": (240, 210, 170, 255),    # лицо
    "E": (240, 220, 60, 255),     # горящие жёлтые глаза
}

RANGED = [
    "................",
    ".......HH.......",
    "......HHTH......",
    ".....HHHHH......",
    "....HHhhHHH.....",
    "...HHHHHHHHH....",
    "..hHHHHHHHHHh...",
    "...FFFFFFFF.....",
    "..FEEFFFFEEF....",
    "..FFFFFFFFFF....",
    "..bBBBBBBBBb....",
    "..bBBBBBBBBb....",
    "..bBBBBBBBBb....",
    "..bBBBBBBBBb....",
    "...bbbbbbbb.....",
    "................",
]


# --- CHARGER — оранжевый шипастый ---------------------------------------------
CHARGER_PALETTE = {
    ".": (0, 0, 0, 0),
    "O": (240, 140, 30, 255),     # основной оранжевый
    "o": (170, 80, 15, 255),      # тень / контур
    "S": (230, 120, 20, 255),     # шипы (чуть темнее тела)
    "E": (240, 60, 40, 255),      # красный горящий глаз
    "e": (110, 20, 10, 255),      # тёмная точка в глазу
    "M": (60, 20, 5, 255),        # рот
}

CHARGER = [
    ".......SS.......",
    "......SSSS......",
    "S.....SSSS.....S",
    "SS...oooooo...SS",
    ".SS.oOOOOOOo.SS.",
    "..SoOOOOOOOOoS..",
    "...oOOEeeEOOo...",
    "...oOOEeeEOOo...",
    "...oOOOOOOOOo...",
    "...oOOMMMMOOo...",
    "...oOOOOOOOOo...",
    "..SoOOOOOOOOoS..",
    ".SS.oOOOOOOo.SS.",
    "SS...oooooo...SS",
    "S.....SSSS.....S",
    "......SSSS......",
]


# --- BOSS — фиолетовый рогатый демон (32×32) ---------------------------------
BOSS_PALETTE = {
    ".": (0, 0, 0, 0),
    "P": (140, 60, 180, 255),     # основной фиолетовый
    "p": (80, 30, 110, 255),      # контур / тень
    "H": (30, 15, 40, 255),       # рога / контур рогов
    "W": (245, 245, 245, 255),    # белки глаз
    "E": (255, 200, 40, 255),     # горящие жёлтые радужки
    "B": (20, 5, 25, 255),        # зрачок
    "M": (30, 5, 10, 255),        # пасть
    "F": (240, 240, 240, 255),    # клыки
}

BOSS = [
    "................................",
    "................................",
    "..HH........................HH..",
    "..HHH......................HHH..",
    "...HHH.....pppppp......HHHH.....",
    "....HHH..ppPPPPPPpp..HHHH.......",
    ".....HHHpPPPPPPPPPPpHHH.........",
    "......pPPPPPPPPPPPPPPp..........",
    ".....pPPPPPPPPPPPPPPPPp.........",
    "....pPPPPPPPPPPPPPPPPPPp........",
    "...pPPPPPPPPPPPPPPPPPPPPp.......",
    "...pPPPWWWPPPPPPPPWWWPPPp.......",
    "...pPPPWEWPPPPPPPPWEWPPPp.......",
    "...pPPPWBWPPPPPPPPWBWPPPp.......",
    "...pPPPWWWPPPPPPPPWWWPPPp.......",
    "...pPPPPPPPPPPPPPPPPPPPPp.......",
    "...pPPPPPPPPPPPPPPPPPPPPp.......",
    "...pPPPPPPMMMMMMMMPPPPPPp.......",
    "...pPPPPMMFFFFFFFFMMPPPPp.......",
    "...pPPPPMFFFFFFFFFFMPPPPp.......",
    "...pPPPPMMMMMMMMMMMMPPPPp.......",
    "....pPPPPPPPPPPPPPPPPPPp........",
    ".....pPPPPPPPPPPPPPPPPp.........",
    "......pPPPPPPPPPPPPPPp..........",
    ".......ppPPPPPPPPPPpp...........",
    "........ppppppppppp.............",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
]


SPRITES: list[tuple[str, list[str], dict[str, tuple[int, int, int, int]]]] = [
    ("melee.png", MELEE, MELEE_PALETTE),
    ("ranged.png", RANGED, RANGED_PALETTE),
    ("charger.png", CHARGER, CHARGER_PALETTE),
    ("boss.png", BOSS, BOSS_PALETTE),
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
