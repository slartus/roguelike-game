#!/usr/bin/env python3
"""
Генератор pixel-art спрайта игрока. 16×16, детерминированный.

Классический RPG-приключенец: каштановые волосы, кожаная куртка,
синий плащ, кожаные сапоги. Универсальный образ, подходит и к
кинжалу, и к пистолету, и к дробовику.

Использование:
    python3 tools/gen_player_sprite.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "sprites" / "player"


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


# --- PLAYER — приключенец в кожаной куртке и синем плаще -----------------

PLAYER_PALETTE = {
    ".": (0, 0, 0, 0),
    "H": (105, 65, 35, 255),        # тёмно-каштановые волосы
    "h": (65, 40, 20, 255),         # тень волос
    "F": (240, 205, 165, 255),      # кожа лица
    "f": (200, 155, 120, 255),      # тень кожи
    "W": (245, 245, 245, 255),      # белки глаз
    "B": (15, 10, 10, 255),         # зрачки
    "M": (150, 60, 55, 255),        # рот
    "C": (60, 105, 195, 255),       # синий плащ
    "c": (30, 60, 130, 255),        # тень плаща
    "L": (150, 100, 55, 255),       # кожаная куртка
    "l": (90, 55, 25, 255),         # тень кожи
    "P": (65, 45, 30, 255),         # штаны
    "T": (30, 20, 15, 255),         # ботинки
    "G": (230, 200, 60, 255),       # пояс/пряжка (золото)
}

PLAYER = [
    "................",
    "....hhHHHHhh....",   # 1 верх волос
    "...hHHHHHHHHh...",   # 2 волосы
    "...hHFFFFFFHh...",   # 3 лоб под чёлкой
    "...hHFfffffHh...",   # 4 лицо + тень
    "...hHFWBFBWFh...",   # 5 глаза
    "...hHFffffffh...",   # 6 щёки
    "....FFFMMFFF....",   # 7 рот, подбородок
    "...LLLLLLLLLL...",   # 8 плечи (куртка)
    "..LLCCCCCCCCLL..",   # 9 плащ + куртка по бокам
    "..LcCCGGGGCCcL..",   # 10 пояс
    "..LcCCCCCCCCcL..",   # 11 туловище
    "..LcCCCCCCCCcL..",   # 12 туловище
    "...cCCCCCCCC....",   # 13 подол плаща
    "....PPPPPPPP....",   # 14 бёдра/штаны
    "....TT....TT....",   # 15 сапоги
]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    img = render(PLAYER, PLAYER_PALETTE)
    out = OUT_DIR / "player.png"
    img.save(out)
    print(f"wrote {out} ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
