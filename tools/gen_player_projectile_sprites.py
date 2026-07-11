#!/usr/bin/env python3
"""
Спрайты снарядов игрока для fantasy roster (PR 2 projectile identity):

- player_arrow.png         (12×5) — деревянная стрела с оперением, для Short Bow.
- player_crossbow_bolt.png (9×5)  — короткий тяжёлый bolt со стальным корпусом,
                                    для Crossbow. Короче и толще стрелы.
- player_wand_orb.png      (7×7)  — компактный пурпурный орб с ярким ядром,
                                    для Wand. Быстрый, лёгкий.
- player_staff_orb.png     (11×11) — крупный сине-голубой орб, тяжёлый спелл,
                                    для Apprentice Staff. Медленный, ощутимый.

Все four sprites визуально различимы: стрела длинная деревянная, болт
короткий железный, орбы разной величины и цвета. Стрела и болт нарисованы
«вправо» — bullet.gd поворачивает их через rotate_with_direction. Орбы
круглые, rotation = 0.
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


# --- PLAYER ARROW 12×5 — тёплая деревянная стрела ---------------------
# Длиннее arrow_wood врага (10 px), чтобы визуально читалась как player
# projectile, а не как случайно подобранная вражья стрела. Оперение —
# белое с тёплой окантовкой, чтобы отличать от красных перьев enemy.
PLAYER_ARROW = [
    "............",
    "Ff..SsSsSsAa",
    "fFFFsSSSSSaA",
    "Ff..SsSsSsAa",
    "............",
]
PLAYER_ARROW_PALETTE = {
    ".": (0, 0, 0, 0),
    "F": (245, 235, 210, 255),   # светлое оперение
    "f": (185, 165, 120, 255),   # тень оперения
    "S": (150, 100, 55, 255),    # тёплое деревянное древко
    "s": (95, 60, 25, 255),      # тень древка
    "A": (215, 220, 230, 255),   # стальной наконечник
    "a": (130, 140, 155, 255),   # тень наконечника
}


# --- PLAYER CROSSBOW BOLT 9×5 — тяжёлый стальной bolt -----------------
# Короче стрелы (без оперения) и толще: центральное «тело» 2 пикселя.
# Металлический шафт + широкий наконечник — читается как арбалетный
# болт, не как стрела.
PLAYER_CROSSBOW_BOLT = [
    ".........",
    ".ssHHHHAa",
    "sSSHHHHhA",
    ".ssHHHHAa",
    ".........",
]
PLAYER_CROSSBOW_BOLT_PALETTE = {
    ".": (0, 0, 0, 0),
    "s": (75, 80, 90, 255),      # хвостовик — тёмная сталь
    "S": (125, 130, 140, 255),   # центральная тень
    "H": (185, 190, 200, 255),   # металлический шафт
    "h": (145, 150, 165, 255),   # тень шафта
    "A": (235, 240, 245, 255),   # закалённый наконечник
    "a": (150, 155, 170, 255),   # тень наконечника
}


# --- PLAYER WAND ORB 7×7 — компактный пурпурный ----------------------
# Меньше и легче staff orb (7×7 против 11×11). Тон совпадает с
# projectile_color Wand (0.8, 0.5, 1.0) — светло-пурпурный с розовым.
PLAYER_WAND_ORB = [
    "..PPP..",
    ".PLLLP.",
    "PLWWWLP",
    "PLWWWLP",
    "PLWWWLP",
    ".PLLLP.",
    "..PPP..",
]
PLAYER_WAND_ORB_PALETTE = {
    ".": (0, 0, 0, 0),
    "P": (170, 100, 220, 255),   # пурпурный контур
    "L": (215, 165, 245, 255),   # светло-пурпурный
    "W": (250, 235, 255, 255),   # ядро — почти белое свечение
}


# --- PLAYER STAFF ORB 11×11 — крупный сине-голубой --------------------
# Заметно крупнее wand orb, тон совпадает с projectile_color Apprentice
# Staff (0.5, 0.7, 1.0). Ядро с яркой сердцевиной — читается как
# «тяжёлый спелл».
PLAYER_STAFF_ORB = [
    "....BBB....",
    "..BBSLSBB..",
    ".BSLLWLLSB.",
    ".BLWWWWWLB.",
    "BSLWWCWWLSB",
    "BSLWCCCWLSB",
    "BSLWWCWWLSB",
    ".BLWWWWWLB.",
    ".BSLLWLLSB.",
    "..BBSLSBB..",
    "....BBB....",
]
PLAYER_STAFF_ORB_PALETTE = {
    ".": (0, 0, 0, 0),
    "B": (90, 130, 200, 255),    # синий контур
    "S": (130, 165, 220, 255),   # средний синий
    "L": (180, 210, 240, 255),   # светло-голубой
    "W": (230, 240, 255, 255),   # мягкое свечение
    "C": (255, 255, 255, 255),   # ядро — чистое белое
}


SPRITES = [
    ("player_arrow.png", PLAYER_ARROW, PLAYER_ARROW_PALETTE),
    ("player_crossbow_bolt.png", PLAYER_CROSSBOW_BOLT, PLAYER_CROSSBOW_BOLT_PALETTE),
    ("player_wand_orb.png", PLAYER_WAND_ORB, PLAYER_WAND_ORB_PALETTE),
    ("player_staff_orb.png", PLAYER_STAFF_ORB, PLAYER_STAFF_ORB_PALETTE),
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
