#!/usr/bin/env python3
"""
Генератор placeholder-спрайтов пропов окружения (мебель, стены, мелкие
предметы). Спрайты — программно нарисованные силуэты через
Pillow.ImageDraw: прямоугольники, круги и линии. Каждый prop имеет
характерную форму + палитру, чтобы отличаться от tile-текстур пола.

Размер клетки = TILE = 20 px (совпадает с scenes/dungeon/floor.gd::TILE_SIZE).
Prop 2×1 → 40×20 px, prop 2×2 → 40×40 px и т.д. Origin спрайта (0,0)
= левый верх; planner ставит sprite так, чтобы центр Sprite2D совпадал
с центром зарезервированного bbox'а — floor.gd применяет offset
`Vector2(-w/2, -h/2)`.

Прозрачность фона обязательна: пропы рисуются поверх пола, за
walls (в терминах z_index Sprite2D по умолчанию — раньше добавлены
в дерево). Alpha=0 для фона, alpha=255 для тела пропа.

Все пропы имеют:
- тёмный контур 1 px (устраняет размытие на границе);
- 1-2 px highlight сверху (лёгкий 3D-эффект);
- отличительный силуэт (не generic ящик).

Скрипт неотделим от документации: изменение спрайта пропа обязательно
регенерирует png и попадает в тот же коммит (см. .claude/rules/60-player-weapon-showcase.md
и dungeon.md, раздел «Декор комнат»).
"""

from __future__ import annotations

from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw

OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "sprites" / "props"

TILE = 20

# --- Хелперы -------------------------------------------------------------


def new_image(cells_w: int, cells_h: int) -> Image.Image:
    return Image.new("RGBA", (cells_w * TILE, cells_h * TILE), (0, 0, 0, 0))


def draw_box(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int, int, int],
    fill: tuple[int, int, int, int],
    outline: tuple[int, int, int, int] | None = None,
    highlight: tuple[int, int, int, int] | None = None,
) -> None:
    """Прямоугольник с опциональной тёмной рамкой и светлой полоской сверху."""
    x0, y0, x1, y1 = xy
    draw.rectangle((x0, y0, x1, y1), fill=fill, outline=outline)
    if highlight is not None and y1 - y0 >= 2:
        draw.rectangle((x0 + 1, y0 + 1, x1 - 1, y0 + 1), fill=highlight)


def draw_circle(
    draw: ImageDraw.ImageDraw,
    center: tuple[int, int],
    radius: int,
    fill: tuple[int, int, int, int],
    outline: tuple[int, int, int, int] | None = None,
) -> None:
    cx, cy = center
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=fill, outline=outline)


# --- Пропы: жилые --------------------------------------------------------


def render_bed(cells_w: int, cells_h: int) -> Image.Image:
    """Кровать: длинная рама + подушка + одеяло."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    frame_dark = (55, 30, 15, 255)
    frame = (110, 65, 30, 255)
    frame_light = (155, 100, 55, 255)
    blanket = (140, 60, 55, 255)
    blanket_dark = (95, 40, 35, 255)
    pillow = (235, 220, 190, 255)
    pillow_shade = (185, 170, 145, 255)
    w = cells_w * TILE
    h = cells_h * TILE
    # рама
    draw_box(d, (1, 3, w - 2, h - 2), frame, frame_dark, frame_light)
    # одеяло
    draw_box(d, (12, 5, w - 3, h - 4), blanket, blanket_dark)
    # подушка (слева)
    draw_box(d, (3, 5, 11, h - 5), pillow, frame_dark, pillow_shade)
    return img


def render_wardrobe(cells_w: int, cells_h: int) -> Image.Image:
    """Шкаф: высокий, двухдверный, с ручками."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (45, 25, 12, 255)
    wood = (95, 60, 30, 255)
    wood_light = (135, 90, 50, 255)
    handle = (200, 175, 100, 255)
    w, h = cells_w * TILE, cells_h * TILE
    draw_box(d, (1, 1, w - 2, h - 2), wood, dark, wood_light)
    # центральная разделительная линия
    d.line([(w // 2, 3), (w // 2, h - 3)], fill=dark, width=1)
    # ручки
    d.rectangle((w // 2 - 3, h // 2 - 1, w // 2 - 2, h // 2 + 1), fill=handle)
    d.rectangle((w // 2 + 2, h // 2 - 1, w // 2 + 3, h // 2 + 1), fill=handle)
    return img


def render_bookshelf(cells_w: int, cells_h: int) -> Image.Image:
    """Стеллаж: рамка + горизонтальные полки с корешками книг."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (40, 24, 12, 255)
    wood = (85, 55, 28, 255)
    wood_light = (125, 85, 45, 255)
    w, h = cells_w * TILE, cells_h * TILE
    draw_box(d, (1, 1, w - 2, h - 2), wood, dark, wood_light)
    # полки
    shelf_count = max(2, cells_h * 2 - 1) if cells_h > 1 else 2
    for i in range(1, shelf_count):
        y = 1 + i * (h - 2) // shelf_count
        d.line([(2, y), (w - 3, y)], fill=dark, width=1)
        # книги
        book_colors = [
            (140, 40, 40, 255),
            (200, 160, 50, 255),
            (40, 90, 140, 255),
            (60, 120, 60, 255),
        ]
        for j in range(3, w - 3, 4):
            color = book_colors[(i + j) % len(book_colors)]
            d.rectangle((j, y - 4, j + 2, y - 1), fill=color, outline=dark)
    return img


def render_desk(cells_w: int, cells_h: int) -> Image.Image:
    """Письменный стол: столешница + ножки + свиток."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (45, 28, 15, 255)
    wood = (110, 75, 35, 255)
    wood_light = (155, 110, 60, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # столешница
    draw_box(d, (1, 4, w - 2, 10), wood, dark, wood_light)
    # ножки
    d.rectangle((3, 10, 5, h - 3), fill=wood, outline=dark)
    d.rectangle((w - 6, 10, w - 4, h - 3), fill=wood, outline=dark)
    # свиток
    scroll_light = (225, 210, 175, 255)
    scroll_shade = (180, 165, 130, 255)
    d.rectangle((7, 5, 15, 9), fill=scroll_light, outline=dark)
    d.line([(8, 7), (14, 7)], fill=scroll_shade, width=1)
    return img


def render_small_table(cells_w: int, cells_h: int) -> Image.Image:
    """Столик 1×1: круглая столешница + ножка."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (45, 25, 12, 255)
    wood = (105, 70, 32, 255)
    wood_light = (150, 105, 55, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # ножка
    d.rectangle((w // 2 - 2, 10, w // 2 + 1, h - 3), fill=wood, outline=dark)
    # столешница
    draw_circle(d, (w // 2, 8), 6, wood, dark)
    d.line([(w // 2 - 3, 6), (w // 2 + 2, 6)], fill=wood_light, width=1)
    return img


def render_chair(cells_w: int, cells_h: int) -> Image.Image:
    """Стул 1×1: сиденье + спинка."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (40, 22, 10, 255)
    wood = (100, 68, 30, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # спинка
    d.rectangle((5, 3, w - 6, 10), fill=wood, outline=dark)
    d.line([(7, 5), (w - 8, 5)], fill=dark, width=1)
    d.line([(7, 8), (w - 8, 8)], fill=dark, width=1)
    # сиденье
    d.rectangle((3, 10, w - 4, 14), fill=wood, outline=dark)
    # ножки
    d.rectangle((4, 14, 5, h - 3), fill=wood, outline=dark)
    d.rectangle((w - 6, 14, w - 5, h - 3), fill=wood, outline=dark)
    return img


def render_rug(cells_w: int, cells_h: int) -> Image.Image:
    """Ковёр: floor_decal — прямоугольник с узором. Полупрозрачный."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (55, 25, 25, 210)
    body = (135, 55, 55, 205)
    accent = (220, 175, 90, 205)
    w, h = cells_w * TILE, cells_h * TILE
    draw_box(d, (2, 2, w - 3, h - 3), body, dark)
    # диагональный узор
    for i in range(4, w - 4, 4):
        d.line([(i, 4), (i + 3, h - 5)], fill=accent, width=1)
    # рамка внутри
    d.rectangle((5, 5, w - 6, h - 6), outline=accent)
    return img


def render_cabinet(cells_w: int, cells_h: int) -> Image.Image:
    """Тумба: короткая, с одной дверцей и ручкой."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (45, 28, 15, 255)
    wood = (95, 62, 30, 255)
    wood_light = (135, 90, 45, 255)
    handle = (200, 175, 100, 255)
    w, h = cells_w * TILE, cells_h * TILE
    draw_box(d, (1, 4, w - 2, h - 2), wood, dark, wood_light)
    d.line([(w // 2, 6), (w // 2, h - 4)], fill=dark, width=1)
    d.rectangle((w // 2 + 2, h // 2 - 1, w // 2 + 3, h // 2 + 1), fill=handle)
    return img


def render_wall_picture(cells_w: int, cells_h: int) -> Image.Image:
    """Настенная картина: рамка + внутренний пейзаж."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (35, 20, 10, 255)
    frame = (150, 105, 55, 255)
    sky = (95, 130, 165, 255)
    ground = (105, 75, 45, 255)
    w, h = cells_w * TILE, cells_h * TILE
    draw_box(d, (2, 2, w - 3, h - 3), frame, dark)
    d.rectangle((4, 4, w - 5, h // 2), fill=sky)
    d.rectangle((4, h // 2, w - 5, h - 5), fill=ground)
    return img


# --- Пропы: хранилище ----------------------------------------------------


def render_crate(cells_w: int, cells_h: int) -> Image.Image:
    """Ящик: квадратный, деревянный, с диагоналями."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (55, 30, 15, 255)
    wood = (135, 90, 45, 255)
    wood_light = (175, 130, 75, 255)
    w, h = cells_w * TILE, cells_h * TILE
    draw_box(d, (2, 2, w - 3, h - 3), wood, dark, wood_light)
    d.line([(2, 2), (w - 3, h - 3)], fill=dark, width=1)
    d.line([(w - 3, 2), (2, h - 3)], fill=dark, width=1)
    return img


def render_barrel(cells_w: int, cells_h: int) -> Image.Image:
    """Бочка: круглая, с обручами."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (40, 25, 12, 255)
    wood = (110, 70, 35, 255)
    wood_light = (155, 105, 55, 255)
    hoop = (65, 40, 20, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # тело бочки — вертикальный овал
    d.ellipse((3, 2, w - 4, h - 3), fill=wood, outline=dark)
    d.line([(5, 6), (w - 6, 6)], fill=hoop, width=1)
    d.line([(5, h - 7), (w - 6, h - 7)], fill=hoop, width=1)
    d.line([(w // 2, 4), (w // 2, h - 5)], fill=wood_light, width=1)
    return img


def render_sack(cells_w: int, cells_h: int) -> Image.Image:
    """Мешок: округлый, перевязка сверху."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (55, 42, 25, 255)
    cloth = (135, 110, 65, 255)
    cloth_light = (175, 150, 100, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # тело
    d.ellipse((2, 6, w - 3, h - 3), fill=cloth, outline=dark)
    # перевязка
    d.rectangle((6, 4, w - 7, 8), fill=cloth, outline=dark)
    d.line([(8, 3), (w - 9, 3)], fill=cloth_light, width=1)
    # шов
    d.line([(w // 2, 8), (w // 2, h - 5)], fill=cloth_light, width=1)
    return img


def render_shelf(cells_w: int, cells_h: int) -> Image.Image:
    """Настенная полка: длинная планка с предметами."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (45, 25, 12, 255)
    wood = (110, 75, 35, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # планка
    draw_box(d, (1, h // 2 - 1, w - 2, h // 2 + 2), wood, dark)
    # предметы сверху
    d.rectangle((4, h // 2 - 5, 7, h // 2 - 1), fill=(70, 40, 20, 255), outline=dark)
    d.rectangle((10, h // 2 - 4, 12, h // 2 - 1), fill=(200, 175, 90, 255), outline=dark)
    if w > 20:
        d.rectangle((16, h // 2 - 6, 19, h // 2 - 1), fill=(80, 100, 140, 255), outline=dark)
    return img


def render_broken_crate(cells_w: int, cells_h: int) -> Image.Image:
    """Разбитый ящик: треснувший, с щепками."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (45, 25, 12, 255)
    wood = (105, 70, 35, 255)
    wood_light = (145, 100, 55, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # основа ящика
    draw_box(d, (2, h // 2, w - 3, h - 3), wood, dark, wood_light)
    # трещины и щепки
    d.line([(3, h // 2), (7, 4)], fill=dark, width=1)
    d.line([(w - 4, h // 2), (w - 8, 5)], fill=dark, width=1)
    d.line([(w // 2, h // 2), (w // 2, 7)], fill=dark, width=1)
    return img


def render_rope_coil(cells_w: int, cells_h: int) -> Image.Image:
    """Моток верёвки: концентрические круги."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (75, 55, 25, 255)
    rope = (145, 115, 55, 255)
    rope_light = (185, 155, 90, 255)
    w, h = cells_w * TILE, cells_h * TILE
    cx, cy = w // 2, h // 2 + 2
    d.ellipse((cx - 8, cy - 5, cx + 7, cy + 5), fill=rope, outline=dark)
    d.ellipse((cx - 5, cy - 3, cx + 4, cy + 3), fill=rope_light, outline=dark)
    d.ellipse((cx - 2, cy - 1, cx + 1, cy + 1), fill=dark)
    return img


# --- Пропы: fantasy technical --------------------------------------------


def render_boiler(cells_w: int, cells_h: int) -> Image.Image:
    """Медный котёл: круглое тело + труба + пламя внизу."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (45, 25, 10, 255)
    copper = (180, 110, 50, 255)
    copper_light = (225, 155, 75, 255)
    copper_dark = (120, 65, 25, 255)
    fire_core = (255, 200, 80, 255)
    fire_outer = (255, 120, 40, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # основной корпус
    d.ellipse((3, 5, w - 4, h - 6), fill=copper, outline=dark)
    # блик
    d.line([(7, 8), (w - 8, 8)], fill=copper_light, width=1)
    d.line([(6, h - 12), (w - 7, h - 12)], fill=copper_dark, width=1)
    # труба сверху
    d.rectangle((w // 2 - 3, 1, w // 2 + 2, 5), fill=copper_dark, outline=dark)
    # огонь снизу
    d.polygon(
        [
            (w // 2 - 4, h - 3),
            (w // 2 - 2, h - 7),
            (w // 2, h - 4),
            (w // 2 + 2, h - 7),
            (w // 2 + 4, h - 3),
        ],
        fill=fire_outer,
        outline=dark,
    )
    d.polygon(
        [
            (w // 2 - 2, h - 4),
            (w // 2 - 1, h - 6),
            (w // 2, h - 5),
            (w // 2 + 1, h - 6),
            (w // 2 + 2, h - 4),
        ],
        fill=fire_core,
    )
    return img


def render_rune_engine(cells_w: int, cells_h: int) -> Image.Image:
    """Рунический двигатель: тёмный камень + светящаяся руна."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (20, 15, 25, 255)
    stone = (75, 65, 90, 255)
    stone_light = (105, 90, 125, 255)
    rune = (120, 200, 255, 255)
    rune_bright = (200, 235, 255, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # камень
    draw_box(d, (2, 3, w - 3, h - 3), stone, dark, stone_light)
    # руна: круг с крестом внутри
    cx, cy = w // 2, h // 2
    d.ellipse((cx - 8, cy - 8, cx + 7, cy + 7), outline=rune, width=1)
    d.line([(cx - 6, cy), (cx + 5, cy)], fill=rune_bright, width=1)
    d.line([(cx, cy - 6), (cx, cy + 5)], fill=rune_bright, width=1)
    d.line([(cx - 4, cy - 4), (cx + 3, cy + 3)], fill=rune, width=1)
    d.line([(cx + 3, cy - 4), (cx - 4, cy + 3)], fill=rune, width=1)
    return img


def render_alchemical_vat(cells_w: int, cells_h: int) -> Image.Image:
    """Алхимическая колба: стеклянная сфера с зелёной жидкостью."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (25, 40, 25, 255)
    metal = (85, 85, 95, 255)
    glass = (95, 180, 110, 220)
    glass_bright = (170, 235, 180, 240)
    bubble = (220, 255, 220, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # основание
    d.rectangle((3, h - 7, w - 4, h - 3), fill=metal, outline=dark)
    # сфера
    d.ellipse((4, 3, w - 5, h - 7), fill=glass, outline=dark)
    # блик
    d.line([(8, 7), (12, 7)], fill=glass_bright, width=1)
    # пузырьки
    draw_circle(d, (w // 2 - 3, h // 2), 1, bubble)
    draw_circle(d, (w // 2 + 3, h // 2 + 3), 1, bubble)
    draw_circle(d, (w // 2, h // 2 - 3), 1, bubble)
    return img


def render_pipe_straight(cells_w: int, cells_h: int) -> Image.Image:
    """Медная труба (горизонтальная), крепится к стене."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (55, 30, 15, 255)
    copper = (170, 105, 45, 255)
    copper_light = (215, 150, 75, 255)
    w, h = cells_w * TILE, cells_h * TILE
    y0 = h // 2 - 3
    y1 = h // 2 + 3
    d.rectangle((0, y0, w - 1, y1), fill=copper, outline=dark)
    d.line([(1, y0 + 1), (w - 2, y0 + 1)], fill=copper_light, width=1)
    # фланцы
    d.rectangle((0, y0 - 1, 3, y1 + 1), fill=copper, outline=dark)
    d.rectangle((w - 4, y0 - 1, w - 1, y1 + 1), fill=copper, outline=dark)
    return img


def render_valve(cells_w: int, cells_h: int) -> Image.Image:
    """Вентиль: круглый штурвал + короткая труба."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (35, 25, 12, 255)
    metal = (95, 85, 75, 255)
    metal_light = (135, 125, 110, 255)
    w, h = cells_w * TILE, cells_h * TILE
    cx, cy = w // 2, h // 2
    # круглый штурвал
    d.ellipse((cx - 6, cy - 6, cx + 5, cy + 5), fill=metal, outline=dark)
    d.line([(cx - 6, cy), (cx + 5, cy)], fill=metal_light, width=1)
    d.line([(cx, cy - 6), (cx, cy + 5)], fill=metal_light, width=1)
    # труба ниже
    d.rectangle((cx - 2, cy + 5, cx + 2, h - 2), fill=metal, outline=dark)
    return img


def render_floor_grate(cells_w: int, cells_h: int) -> Image.Image:
    """Пол-решётка (floor_decal): металлическая сетка."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (30, 25, 15, 255)
    metal = (80, 75, 65, 240)
    metal_light = (120, 115, 105, 240)
    w, h = cells_w * TILE, cells_h * TILE
    d.rectangle((1, 1, w - 2, h - 2), fill=metal, outline=dark)
    # решётка
    for x in range(3, w - 3, 3):
        d.line([(x, 2), (x, h - 3)], fill=dark, width=1)
    for y in range(3, h - 3, 3):
        d.line([(2, y), (w - 3, y)], fill=dark, width=1)
    # блики
    d.line([(2, 2), (w - 3, 2)], fill=metal_light, width=1)
    return img


def render_workbench(cells_w: int, cells_h: int) -> Image.Image:
    """Верстак: столешница + инструменты + тиски."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (40, 25, 12, 255)
    wood = (95, 65, 30, 255)
    wood_light = (135, 90, 45, 255)
    metal = (95, 90, 80, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # столешница
    draw_box(d, (1, 4, w - 2, 12), wood, dark, wood_light)
    # ножки
    d.rectangle((3, 12, 5, h - 3), fill=wood, outline=dark)
    d.rectangle((w - 6, 12, w - 4, h - 3), fill=wood, outline=dark)
    # тиски (справа)
    d.rectangle((w - 12, 2, w - 8, 5), fill=metal, outline=dark)
    # молоток (слева)
    d.rectangle((3, 3, 8, 4), fill=(50, 35, 20, 255))
    d.rectangle((7, 2, 10, 5), fill=metal, outline=dark)
    return img


# --- Пропы: подземелье и пещеры ------------------------------------------


def render_chains(cells_w: int, cells_h: int) -> Image.Image:
    """Настенные цепи: три вертикальных звена."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (25, 20, 20, 255)
    metal = (75, 75, 85, 255)
    metal_light = (110, 110, 120, 255)
    w, h = cells_w * TILE, cells_h * TILE
    cx = w // 2
    # крепление сверху
    d.rectangle((cx - 3, 2, cx + 2, 4), fill=metal, outline=dark)
    # звенья
    for i in range(3):
        y = 5 + i * 4
        d.ellipse((cx - 2, y, cx + 2, y + 3), outline=dark, fill=metal)
        d.point((cx - 1, y + 1), fill=metal_light)
    # подвеска внизу
    d.line([(cx, 17), (cx, h - 3)], fill=metal, width=1)
    return img


def render_cot(cells_w: int, cells_h: int) -> Image.Image:
    """Койка: простая рама с соломой."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (45, 30, 15, 255)
    frame = (85, 60, 30, 255)
    frame_light = (130, 90, 45, 255)
    straw = (185, 155, 70, 255)
    straw_dark = (140, 115, 45, 255)
    w, h = cells_w * TILE, cells_h * TILE
    draw_box(d, (1, 5, w - 2, h - 3), frame, dark, frame_light)
    # солома
    d.rectangle((3, 7, w - 4, h - 5), fill=straw, outline=dark)
    # тени соломы
    for x in range(4, w - 4, 3):
        d.line([(x, 8), (x + 1, h - 6)], fill=straw_dark, width=1)
    return img


def render_bucket(cells_w: int, cells_h: int) -> Image.Image:
    """Ведро: сужающееся снизу, с ручкой."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (35, 25, 15, 255)
    wood = (100, 70, 40, 255)
    wood_light = (140, 100, 55, 255)
    hoop = (75, 55, 25, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # тело — трапеция
    d.polygon(
        [(4, 5), (w - 5, 5), (w - 6, h - 3), (5, h - 3)],
        fill=wood,
        outline=dark,
    )
    d.line([(6, 6), (w - 7, 6)], fill=wood_light, width=1)
    # обручи
    d.line([(5, 8), (w - 6, 8)], fill=hoop, width=1)
    d.line([(5, h - 5), (w - 6, h - 5)], fill=hoop, width=1)
    # ручка
    d.arc((4, 1, w - 5, 8), start=180, end=360, fill=dark, width=1)
    return img


def render_bones(cells_w: int, cells_h: int) -> Image.Image:
    """Кости на полу (floor_decal): череп + бедренная кость."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (55, 45, 30, 210)
    bone = (215, 200, 165, 220)
    bone_shade = (170, 155, 120, 200)
    w, h = cells_w * TILE, cells_h * TILE
    # бедренная кость
    d.line([(3, h - 5), (w - 4, 5)], fill=bone, width=2)
    d.line([(3, h - 5), (w - 4, 5)], fill=bone_shade, width=1)
    d.ellipse((2, h - 7, 5, h - 3), fill=bone, outline=dark)
    d.ellipse((w - 5, 3, w - 2, 7), fill=bone, outline=dark)
    # череп
    cx, cy = w // 2 - 2, h // 2 + 2
    d.ellipse((cx - 3, cy - 3, cx + 2, cy + 2), fill=bone, outline=dark)
    d.point((cx - 1, cy - 1), fill=dark)
    d.point((cx + 1, cy - 1), fill=dark)
    return img


def render_rubble(cells_w: int, cells_h: int) -> Image.Image:
    """Груда камней (floor_decal)."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (35, 30, 30, 220)
    stone_dark = (75, 70, 65, 220)
    stone = (115, 105, 100, 220)
    stone_light = (155, 145, 135, 220)
    w, h = cells_w * TILE, cells_h * TILE
    # большие камни
    d.polygon([(3, h - 4), (5, 8), (10, 6), (13, h - 4)], fill=stone, outline=dark)
    d.polygon([(11, h - 4), (14, 10), (w - 4, 12), (w - 3, h - 4)], fill=stone_dark, outline=dark)
    # маленькие
    d.ellipse((6, h - 8, 9, h - 5), fill=stone_light, outline=dark)
    d.ellipse((w - 8, h - 6, w - 5, h - 3), fill=stone, outline=dark)
    return img


def render_stalagmite(cells_w: int, cells_h: int) -> Image.Image:
    """Сталагмит: треугольный камень."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (35, 30, 30, 255)
    stone = (95, 85, 80, 255)
    stone_light = (140, 130, 120, 255)
    stone_shade = (65, 55, 50, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # тело
    d.polygon(
        [
            (w // 2, 2),
            (w - 3, h - 3),
            (3, h - 3),
        ],
        fill=stone,
        outline=dark,
    )
    # блик слева
    d.polygon(
        [
            (w // 2, 3),
            (w // 2 - 1, h - 4),
            (4, h - 4),
        ],
        fill=stone_light,
    )
    # тень справа
    d.polygon(
        [
            (w // 2, 5),
            (w - 4, h - 4),
            (w // 2, h - 4),
        ],
        fill=stone_shade,
    )
    return img


def render_mushroom(cells_w: int, cells_h: int) -> Image.Image:
    """Гриб: ножка + шляпка с пятнами."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (55, 20, 20, 255)
    cap = (180, 55, 55, 255)
    cap_light = (220, 100, 100, 255)
    stem = (230, 220, 195, 255)
    spot = (245, 240, 220, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # ножка
    d.rectangle((w // 2 - 2, h // 2, w // 2 + 2, h - 3), fill=stem, outline=dark)
    # шляпка
    d.ellipse((3, 4, w - 4, h // 2 + 3), fill=cap, outline=dark)
    d.arc((3, 4, w - 4, h // 2 + 3), start=180, end=270, fill=cap_light, width=1)
    # пятна
    draw_circle(d, (w // 2 - 3, h // 2 - 2), 1, spot)
    draw_circle(d, (w // 2 + 3, h // 2 - 1), 1, spot)
    draw_circle(d, (w // 2, h // 2 - 4), 1, spot)
    return img


def render_crystal(cells_w: int, cells_h: int) -> Image.Image:
    """Кристалл: гранёный, светящийся."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (25, 40, 55, 255)
    body = (95, 165, 210, 255)
    body_bright = (165, 220, 245, 255)
    body_shade = (60, 115, 160, 255)
    w, h = cells_w * TILE, cells_h * TILE
    # основной кристалл
    d.polygon(
        [
            (w // 2, 3),
            (w - 4, h // 2),
            (w // 2 + 2, h - 4),
            (w // 2 - 2, h - 4),
            (3, h // 2),
        ],
        fill=body,
        outline=dark,
    )
    # блик
    d.polygon(
        [
            (w // 2, 4),
            (w // 2 - 1, h // 2 - 2),
            (w // 2 - 3, h // 2),
            (4, h // 2 + 1),
        ],
        fill=body_bright,
    )
    # тень
    d.polygon(
        [
            (w // 2, 6),
            (w - 5, h // 2),
            (w // 2 + 1, h - 5),
        ],
        fill=body_shade,
    )
    return img


def render_roots(cells_w: int, cells_h: int) -> Image.Image:
    """Корни (floor_decal): извивающиеся линии."""
    img = new_image(cells_w, cells_h)
    d = ImageDraw.Draw(img)
    dark = (35, 25, 12, 220)
    root = (80, 55, 25, 220)
    root_light = (115, 85, 45, 220)
    w, h = cells_w * TILE, cells_h * TILE
    # основной корень
    d.line([(2, 3), (7, 6), (10, 10), (w - 4, h - 3)], fill=root, width=2)
    d.line([(2, 3), (7, 6), (10, 10), (w - 4, h - 3)], fill=dark, width=1)
    # ветви
    d.line([(7, 6), (3, 12)], fill=root, width=1)
    d.line([(10, 10), (w - 4, 5)], fill=root_light, width=1)
    d.line([(w - 6, 10), (w - 3, 14)], fill=root, width=1)
    return img


# --- Registry ------------------------------------------------------------

# (id, cells_w, cells_h, render_fn)
Renderer = Callable[[int, int], Image.Image]
PROPS: list[tuple[str, int, int, Renderer]] = [
    # Residential
    ("bed", 2, 1, render_bed),
    ("wardrobe", 1, 2, render_wardrobe),
    ("bookshelf", 2, 1, render_bookshelf),
    ("desk", 2, 1, render_desk),
    ("small_table", 1, 1, render_small_table),
    ("chair", 1, 1, render_chair),
    ("rug", 2, 2, render_rug),
    ("cabinet", 1, 1, render_cabinet),
    ("wall_picture", 1, 1, render_wall_picture),
    # Storage
    ("crate", 1, 1, render_crate),
    ("barrel", 1, 1, render_barrel),
    ("sack", 1, 1, render_sack),
    ("shelf", 2, 1, render_shelf),
    ("broken_crate", 1, 1, render_broken_crate),
    ("rope_coil", 1, 1, render_rope_coil),
    # Fantasy technical
    ("boiler", 2, 2, render_boiler),
    ("rune_engine", 2, 2, render_rune_engine),
    ("alchemical_vat", 2, 2, render_alchemical_vat),
    ("pipe_straight", 2, 1, render_pipe_straight),
    ("valve", 1, 1, render_valve),
    ("floor_grate", 2, 1, render_floor_grate),
    ("workbench", 2, 1, render_workbench),
    # Basement / caves
    ("chains", 1, 1, render_chains),
    ("cot", 2, 1, render_cot),
    ("bucket", 1, 1, render_bucket),
    ("bones", 1, 1, render_bones),
    ("rubble", 1, 1, render_rubble),
    ("stalagmite", 1, 1, render_stalagmite),
    ("mushroom", 1, 1, render_mushroom),
    ("crystal", 1, 1, render_crystal),
    ("roots", 1, 1, render_roots),
]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for prop_id, cw, ch, fn in PROPS:
        img = fn(cw, ch)
        out = OUT_DIR / f"{prop_id}.png"
        img.save(out)
        print(f"wrote {out} ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
