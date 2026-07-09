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


# --- POTION ICON 12×12 (Diablo-стиль) -----------------------------
# Круглая колба-сфера на короткой пробке. Стеклянный ободок вокруг
# всей колбы читается как «толстое стекло», яркий блик в верхнем-
# левом квадранте — как отражение источника света. Referens: red
# health potion из Diablo 2 (сферическая, коротышка, cork на макушке).
POTION_PALETTE = {
    ".": (0, 0, 0, 0),
    "C": (85, 55, 25, 255),        # тёмная пробка
    "c": (140, 90, 45, 255),       # светлая пробка / шов
    "O": (60, 60, 65, 255),        # тёмное стеклянное горлышко
    "R": (140, 30, 45, 255),       # стеклянный ободок колбы (тёмно-красный)
    "F": (220, 55, 75, 255),       # красная жидкость
    "L": (255, 200, 210, 255),     # яркий блик
    "l": (255, 140, 155, 255),     # переходный блик
    "S": (95, 20, 30, 255),        # глубокая тень внизу колбы
}
POTION_ICON = [
    "............",
    "....CC......",
    "...cCCc.....",
    "...OccO.....",
    "..RRFFRR....",
    ".RFLlFFFR...",
    ".RFlFFFFR...",
    ".RFFFFFFR...",
    ".RFFFFFFR...",
    "..RFFFFR....",
    "..RSFFSR....",
    "...RRRR.....",
]


SPRITES = [
    ("potion_icon.png", POTION_ICON, POTION_PALETTE),
]

# Ground pickup — тот же силуэт, но 16×16 (крупнее, чуть больше
# детализации сфере). Живёт рядом с пикапом-сценой, не в HUD.
PICKUP_DIR = Path(__file__).resolve().parents[1] / "assets" / "sprites" / "pickups"

POTION_PICKUP = [
    "................",
    "................",
    ".....CC.........",
    "....cCCc........",
    "....cCCc........",
    "....OccO........",
    "...RRFFRR.......",
    "..RFLlFFFR......",
    "..RFllFFFR......",
    "..RFFFFFFR......",
    "..RFFFFFFR......",
    "...RFFFFR.......",
    "...RSFFSR.......",
    "....RRRR........",
    "................",
    "................",
]

PICKUP_SPRITES = [
    ("health_potion.png", POTION_PICKUP, POTION_PALETTE),
]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for filename, rows, palette in SPRITES:
        img = render(rows, palette)
        out = OUT_DIR / filename
        img.save(out)
        print(f"wrote {out} ({img.width}x{img.height})")
    PICKUP_DIR.mkdir(parents=True, exist_ok=True)
    for filename, rows, palette in PICKUP_SPRITES:
        img = render(rows, palette)
        out = PICKUP_DIR / filename
        img.save(out)
        print(f"wrote {out} ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
