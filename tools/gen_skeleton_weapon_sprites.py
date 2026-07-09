#!/usr/bin/env python3
"""
Оружие скелетов — дочерний спрайт, накладывающийся на базового
скелета (см. scenes/enemies/skeleton.tscn::Weapon).

Раньше варианты «безоружный / кинжал wood / кинжал iron / меч wood /
меч iron» отличались только subtle tint'ом всего скелета — практически
неразличимо. Теперь у каждого вооружённого варианта свой видимый
спрайт клинка + рукояти.

Пиксельная сетка:
- Кинжалы: 3×6 (короткий клинок).
- Мечи:    3×10 (в 1.7× длиннее).
- Столбец X=0/2 — окантовка тени, X=1 — центр клинка/рукояти.

Материалы:
- WOOD — тёплая коричневая рукоять + светлое деревянное «лезвие» (для
  тренировочного оружия / прошедшего лёгкой обработки дерева).
- IRON — тёмная кожаная рукоять + стальное лезвие с холодным бликом.

Использование:
    python3 tools/gen_skeleton_weapon_sprites.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "sprites" / "enemies" / "weapons"


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


# --- Общие сетки: hilt/grip/guard/blade/tip -----------------------
# H = pommel/hilt-top, G = grip, R = guard/cross-piece, B = blade,
# M = highlighted tip / edge.
DAGGER = [
    ".H.",
    ".G.",
    "RRR",
    ".B.",
    ".B.",
    ".M.",
]

SWORD = [
    ".H.",
    ".G.",
    "RRR",
    ".B.",
    ".B.",
    ".B.",
    ".B.",
    ".B.",
    ".B.",
    ".M.",
]


WOOD_PALETTE = {
    ".": (0, 0, 0, 0),
    "H": (120, 75, 35, 255),      # тёмный набалдашник
    "G": (150, 100, 55, 255),     # средне-коричневая рукоять
    "R": (95, 60, 25, 255),       # тёмная гарда
    "B": (185, 145, 90, 255),     # светлое деревянное лезвие
    "M": (215, 180, 130, 255),    # осветлённый край
}

IRON_PALETTE = {
    ".": (0, 0, 0, 0),
    "H": (75, 55, 30, 255),       # тёмный кожаный набалдашник
    "G": (100, 70, 40, 255),      # коричневая обмотка
    "R": (65, 65, 75, 255),       # серо-стальная гарда
    "B": (200, 205, 220, 255),    # стальное лезвие
    "M": (240, 245, 250, 255),    # блик на кромке
}


SPRITES = [
    ("dagger_wood.png", DAGGER, WOOD_PALETTE),
    ("dagger_iron.png", DAGGER, IRON_PALETTE),
    ("sword_wood.png", SWORD, WOOD_PALETTE),
    ("sword_iron.png", SWORD, IRON_PALETTE),
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
