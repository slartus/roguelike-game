#!/usr/bin/env python3
"""
Генератор анимированных gif-ов для процедурных эффектов в игре.

Мы намеренно НЕ гоняем Godot в movie-mode: это требует display server и
плохо катится в headless. Вместо этого Python-код повторяет _draw
формулы соответствующих скриптов один-в-один — так gif точно отражает
то, что видит игрок, без разъезжания.

Как добавить новую анимацию:
1. Написать функцию `render_<name>()`, возвращающую list[PIL.Image].
2. Добавить её в `ANIMATIONS`.
3. Запустить `python3 tools/gen_animation_gifs.py`.
4. Встроить получившийся gif в соответствующий раздел
   `docs/gamedesign/*.md`.

Если ты меняешь `_draw`-код в проекте — обнови соответствующую
Python-функцию и перегенерируй gif. Это часть workflow'а фичи
(см. CLAUDE.md, «Анимации и gif-ы»).
"""
from __future__ import annotations

import math
import os
import random
from dataclasses import dataclass
from typing import Callable

from PIL import Image, ImageDraw

TAU = math.tau
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "docs", "gamedesign", "media")
os.makedirs(OUT_DIR, exist_ok=True)

# Единый масштаб «px в игре → px в gif». Игра рендерит 480×270, gif-ы
# идут для документации — увеличиваем чтобы читалось на github.
SCALE = 8
FRAMES_PER_SECOND = 30


@dataclass
class Animation:
    name: str
    duration_s: float
    canvas_size_px: int          # размер квадратного канваса в игровых пикселях
    render: Callable[[float, ImageDraw.ImageDraw, int], None]
    background: tuple = (24, 20, 32, 255)


def _blend_alpha(color: tuple, alpha_mult: float) -> tuple:
    r, g, b, a = color
    return (r, g, b, int(a * max(0.0, min(1.0, alpha_mult))))


def _to_gif_coords(cx: int, xy: tuple[float, float]) -> tuple[float, float]:
    """Игровые (0,0) в центре канваса → координаты Pillow (0,0 сверху-слева)."""
    x, y = xy
    return (cx + x * SCALE, cx + y * SCALE)


# ---- poison cloud ----------------------------------------------------------

POISON_CLOUD_LIFETIME = 4.0
POISON_CLOUD_RADIUS = 16.0
POISON_CLOUD_COLOR = (int(0.4 * 255), int(0.75 * 255), int(0.2 * 255), int(0.55 * 255))
POISON_FADE_IN_FRACTION = 0.1
POISON_PUFF_COUNT = 6
POISON_PUFF_ORBIT_RADIUS = 9.0
POISON_PUFF_BASE_RADIUS = 8.5
POISON_PUFF_PULSE_AMPLITUDE = 2.0
POISON_PUFF_PULSE_FREQUENCY = 1.9
POISON_CLOUD_ROTATION_SPEED = 0.55
POISON_CORE_PUFF_RADIUS = 7.0
POISON_CORE_PUFF_ALPHA_MULT = 1.15
POISON_PUFF_ALPHA_MULT = 0.8
POISON_PUFF_GREEN_MULT = 1.05
POISON_PUFF_BLUE_MULT = 0.8


def _poison_alpha_factor(t_alive: float) -> float:
    t = min(1.0, max(0.0, t_alive / POISON_CLOUD_LIFETIME))
    if t < POISON_FADE_IN_FRACTION:
        alpha = t / POISON_FADE_IN_FRACTION
    else:
        alpha = 1.0 - (t - POISON_FADE_IN_FRACTION) / (1.0 - POISON_FADE_IN_FRACTION)
    return max(0.0, min(1.0, alpha))


def render_poison_cloud(t: float, draw: ImageDraw.ImageDraw, canvas_size: int) -> None:
    cx = canvas_size // 2
    alpha_factor = _poison_alpha_factor(t)
    base_color = _blend_alpha(POISON_CLOUD_COLOR, alpha_factor)
    # Core puff.
    core_color = _blend_alpha(
        (
            int(base_color[0] * 0.9),
            base_color[1],
            int(base_color[2] * 0.7),
            base_color[3],
        ),
        POISON_CORE_PUFF_ALPHA_MULT,
    )
    r_core = POISON_CORE_PUFF_RADIUS * SCALE
    draw.ellipse(
        (cx - r_core, cx - r_core, cx + r_core, cx + r_core),
        fill=core_color,
    )
    puff_base = (
        base_color[0],
        min(255, int(base_color[1] * POISON_PUFF_GREEN_MULT)),
        int(base_color[2] * POISON_PUFF_BLUE_MULT),
        int(base_color[3] * POISON_PUFF_ALPHA_MULT),
    )
    rotation_offset = t * POISON_CLOUD_ROTATION_SPEED
    for i in range(POISON_PUFF_COUNT):
        angle = TAU * i / POISON_PUFF_COUNT + rotation_offset
        pos = (
            math.cos(angle) * POISON_PUFF_ORBIT_RADIUS,
            math.sin(angle) * POISON_PUFF_ORBIT_RADIUS,
        )
        pulse = math.sin(t * POISON_PUFF_PULSE_FREQUENCY + i)
        r = (POISON_PUFF_BASE_RADIUS + pulse * POISON_PUFF_PULSE_AMPLITUDE) * SCALE
        px, py = _to_gif_coords(cx, pos)
        draw.ellipse(
            (px - r, py - r, px + r, py + r),
            fill=puff_base,
        )


# ---- spider web LANDED (ragged) --------------------------------------------

WEB_LANDED_LIFETIME = 12.0
WEB_LANDED_RADIUS = 14.0
WEB_COLOR_LANDED = (int(0.9 * 255), int(0.9 * 255), int(0.95 * 255), int(0.75 * 255))
WEB_BACKING_ALPHA_MULT = 0.25
WEB_SPOKE_COUNT = 8
WEB_SPOKE_LENGTH_MIN_RATIO = 0.55
WEB_SPOKE_LENGTH_MAX_RATIO = 1.0
WEB_SPOKE_ANGLE_JITTER = 0.18
WEB_RING_COUNT = 3
WEB_RING_SEGMENTS = 24
WEB_RING_GAP_COUNT = 2
WEB_RING_GAP_ARC_MIN = 0.25
WEB_RING_GAP_ARC_MAX = 0.7
WEB_STRAND_TAIL_CHANCE = 0.5
WEB_STRAND_TAIL_LENGTH = 3.0
WEB_STRAND_TAIL_ANGLE_JITTER = 0.9


def _build_web_geometry(rng: random.Random) -> dict:
    spokes = []
    tails = []
    for i in range(WEB_SPOKE_COUNT):
        base_angle = TAU * i / WEB_SPOKE_COUNT
        angle = base_angle + rng.uniform(-WEB_SPOKE_ANGLE_JITTER, WEB_SPOKE_ANGLE_JITTER)
        length_ratio = rng.uniform(WEB_SPOKE_LENGTH_MIN_RATIO, WEB_SPOKE_LENGTH_MAX_RATIO)
        length = WEB_LANDED_RADIUS * length_ratio
        tip = (math.cos(angle) * length, math.sin(angle) * length)
        spokes.append(tip)
        if rng.random() < WEB_STRAND_TAIL_CHANCE:
            tail_angle = angle + rng.uniform(-WEB_STRAND_TAIL_ANGLE_JITTER, WEB_STRAND_TAIL_ANGLE_JITTER)
            tail_tip = (
                tip[0] + math.cos(tail_angle) * WEB_STRAND_TAIL_LENGTH,
                tip[1] + math.sin(tail_angle) * WEB_STRAND_TAIL_LENGTH,
            )
            tails.append((tip, tail_tip))
    rings = []
    for ring_index in range(1, WEB_RING_COUNT + 1):
        ring_radius = WEB_LANDED_RADIUS * ring_index / WEB_RING_COUNT
        rings.append(_build_ring_arcs(rng, ring_radius))
    return {"spokes": spokes, "tails": tails, "rings": rings}


def _build_ring_arcs(rng: random.Random, ring_radius: float) -> list:
    gaps = []
    for _ in range(WEB_RING_GAP_COUNT):
        gap_start = rng.random() * TAU
        gap_arc = rng.uniform(WEB_RING_GAP_ARC_MIN, WEB_RING_GAP_ARC_MAX)
        gaps.append((gap_start, (gap_start + gap_arc) % TAU))
    arcs = []
    current = []
    for seg in range(WEB_RING_SEGMENTS + 1):
        seg_angle = TAU * seg / WEB_RING_SEGMENTS
        if _in_any_gap(seg_angle, gaps):
            if len(current) >= 2:
                arcs.append(current)
            current = []
            continue
        current.append((math.cos(seg_angle) * ring_radius, math.sin(seg_angle) * ring_radius))
    if len(current) >= 2:
        arcs.append(current)
    return arcs


def _in_any_gap(angle: float, gaps: list) -> bool:
    a = angle % TAU
    for start_a, end_a in gaps:
        if start_a <= end_a:
            if start_a <= a <= end_a:
                return True
        else:
            if a >= start_a or a <= end_a:
                return True
    return False


# Кешируем геометрию — она случайная, но должна оставаться неизменной в
# течение всего gif'а (иначе паутина визуально «дрожит»).
_WEB_GEOMETRY_CACHE: dict | None = None


def _web_alpha_factor(t: float) -> float:
    t_norm = min(1.0, max(0.0, t / WEB_LANDED_LIFETIME))
    if t_norm < 0.75:
        return 1.0
    return max(0.0, 1.0 - (t_norm - 0.75) / 0.25)


def render_web_landed(t: float, draw: ImageDraw.ImageDraw, canvas_size: int) -> None:
    global _WEB_GEOMETRY_CACHE
    if _WEB_GEOMETRY_CACHE is None:
        _WEB_GEOMETRY_CACHE = _build_web_geometry(random.Random(42))
    geom = _WEB_GEOMETRY_CACHE
    cx = canvas_size // 2
    alpha = _web_alpha_factor(t)
    line_color = _blend_alpha(WEB_COLOR_LANDED, alpha)
    backing = _blend_alpha(WEB_COLOR_LANDED, alpha * WEB_BACKING_ALPHA_MULT)
    r = WEB_LANDED_RADIUS * SCALE
    draw.ellipse((cx - r, cx - r, cx + r, cx + r), fill=backing)
    for tip in geom["spokes"]:
        px, py = _to_gif_coords(cx, tip)
        draw.line((cx, cx, px, py), fill=line_color, width=2)
    for tail_start, tail_end in geom["tails"]:
        sx, sy = _to_gif_coords(cx, tail_start)
        ex, ey = _to_gif_coords(cx, tail_end)
        draw.line((sx, sy, ex, ey), fill=line_color, width=2)
    for ring_arcs in geom["rings"]:
        for arc in ring_arcs:
            pts = [_to_gif_coords(cx, p) for p in arc]
            for a, b in zip(pts, pts[1:]):
                draw.line((a[0], a[1], b[0], b[1]), fill=line_color, width=2)


# ---- cast pulse (lich/boss) ------------------------------------------------

CAST_DURATION = 0.8
# GDScript использует Color(0.7, 1.6, 0.85, 1.0). Компонент 1.6 — over-bright:
# при lerp с Color.WHITE зелёный уходит в потолок раньше, чем sRGB clamp
# успевает это заметить. Умножаем зелёный целевой канал на mix_g_boost,
# чтобы Python-версия достигала полного насыщения при том же прогрессе.
CAST_TINT = (int(0.7 * 255), 255, int(0.85 * 255))
CAST_TINT_G_OVERBRIGHT = 1.6
CAST_PULSE_FREQ = math.pi * 8.0
# _visual_base_modulate = Color.WHITE у Sprite2D по умолчанию; в игре в
# _apply_cast_visual лерпится именно от белого, не от 240/245.
CAST_BASE = (255, 255, 255)


def render_cast_pulse(t: float, draw: ImageDraw.ImageDraw, canvas_size: int) -> None:
    # Показываем sprite-like квадрат, у которого modulate лерпится с
    # CAST_TINT по формуле лича/босса. Прогресс каста t / CAST_DURATION.
    cx = canvas_size // 2
    progress = min(1.0, max(0.0, t / CAST_DURATION))
    pulse = (math.sin(progress * CAST_PULSE_FREQ) + 1.0) * 0.5
    mix = max(0.0, min(1.0, 0.3 + progress * 0.4 + pulse * 0.3))
    # Симуляция over-bright: усиливаем mix зелёного канала, чтобы pre-clamp
    # реального Color(0.7, 1.6, 0.85) отразился в 8-bit sRGB gif'е.
    mix_g = min(1.0, mix * CAST_TINT_G_OVERBRIGHT)
    r = int(CAST_BASE[0] * (1 - mix) + CAST_TINT[0] * mix)
    g = int(CAST_BASE[1] * (1 - mix_g) + CAST_TINT[1] * mix_g)
    b = int(CAST_BASE[2] * (1 - mix) + CAST_TINT[2] * mix)
    sprite_r = 8 * SCALE
    draw.rectangle(
        (cx - sprite_r, cx - sprite_r, cx + sprite_r, cx + sprite_r),
        fill=(r, g, b, 255),
    )


# ---- slime hop (squash & stretch) ------------------------------------------

SLIME_REST_DURATION = 0.55
SLIME_JUMP_DURATION = 0.35
SLIME_BOUNCE_STRETCH_Y = 0.35
SLIME_BOUNCE_SQUASH_X = 0.15
SLIME_BASE_SIZE = 12  # игровые px
SLIME_COLOR = (120, 200, 100, 255)


def render_slime_hop(t: float, draw: ImageDraw.ImageDraw, canvas_size: int) -> None:
    # Один цикл REST → JUMP → REST. В JUMP scale.y растёт, scale.x падает.
    cycle_len = SLIME_REST_DURATION + SLIME_JUMP_DURATION
    phase_t = t % cycle_len
    if phase_t < SLIME_REST_DURATION:
        sx, sy = 1.0, 1.0
    else:
        j = (phase_t - SLIME_REST_DURATION) / SLIME_JUMP_DURATION
        pulse = math.sin(j * math.pi)
        sy = 1.0 + SLIME_BOUNCE_STRETCH_Y * pulse
        sx = 1.0 - SLIME_BOUNCE_SQUASH_X * pulse
    cx = canvas_size // 2
    w = SLIME_BASE_SIZE * SCALE * sx
    h = SLIME_BASE_SIZE * SCALE * sy
    # «Земля» под слаймом фиксирована — bounding-квадрат прижат низом.
    ground_y = cx + SLIME_BASE_SIZE * SCALE * 0.5
    draw.ellipse(
        (cx - w / 2, ground_y - h, cx + w / 2, ground_y),
        fill=SLIME_COLOR,
    )


# ---- spider web FLYING glob ------------------------------------------------

WEB_FLYING_RADIUS = 3.0
WEB_COLOR_FLYING = (int(0.95 * 255), int(0.95 * 255), int(0.95 * 255), int(0.85 * 255))
WEB_FLIGHT_SPEED = 140.0


def render_web_flying(t: float, draw: ImageDraw.ImageDraw, canvas_size: int) -> None:
    # Летящий комок движется слева направо со скоростью FLIGHT_SPEED.
    cx = canvas_size // 2
    span_px = 40.0  # длина полёта в игровых пикселях
    travel = (t * WEB_FLIGHT_SPEED) % span_px - span_px * 0.5
    center = (travel, 0.0)
    r_main = WEB_FLYING_RADIUS * SCALE
    px, py = _to_gif_coords(cx, center)
    draw.ellipse(
        (px - r_main, py - r_main, px + r_main, py + r_main),
        fill=WEB_COLOR_FLYING,
    )
    highlight = _blend_alpha((255, 255, 255, WEB_COLOR_FLYING[3]), 0.6)
    hx, hy = _to_gif_coords(
        cx,
        (
            center[0] - WEB_FLYING_RADIUS * 0.4,
            center[1] - WEB_FLYING_RADIUS * 0.4,
        ),
    )
    r_hl = WEB_FLYING_RADIUS * 0.45 * SCALE
    draw.ellipse((hx - r_hl, hy - r_hl, hx + r_hl, hy + r_hl), fill=highlight)


# ---- melee arc swing (short sword) -----------------------------------------

# Повторяет _draw формулу scenes/player/melee_hitbox.gd для attack_type=melee_arc.
# Значения — из resources/weapons/short_sword.tres: hitbox_length=34, arc=80°,
# active_time=0.08. MIN_VISUAL_LIFE=0.16 в скрипте — visual тянется дольше
# active-фазы, поэтому и в gif duration=0.16.
MELEE_MIN_VISUAL_LIFE = 0.16
MELEE_FADE_IN_RATIO = 0.15
MELEE_HOLD_RATIO = 0.35
MELEE_ARC_SEGMENTS = 14
MELEE_ARC_INNER_RADIUS_RATIO = 0.55
MELEE_ARC_OUTER_RADIUS_RATIO = 0.92
MELEE_ARC_STREAK_COVERAGE = 0.85
MELEE_ARC_LINE_WIDTH_PX = 2
MELEE_SWING_COLOR = (int(1.0 * 255), int(0.95 * 255), int(0.7 * 255), int(0.7 * 255))
MELEE_SWING_EDGE_COLOR = (int(1.0 * 255), int(0.98 * 255), int(0.85 * 255), int(0.9 * 255))
MELEE_THRUST_TIP_COLOR = (int(1.0 * 255), int(0.9 * 255), int(0.6 * 255), int(0.9 * 255))
MELEE_THRUST_STREAK_LENGTH_RATIO = 0.7
MELEE_THRUST_STREAK_OFFSET_RATIO = 0.35
PLAYER_MARKER_COLOR = (180, 180, 190, 255)
PLAYER_MARKER_RADIUS_PX = 2.0

ARC_SHORT_SWORD_LENGTH = 34.0
ARC_SHORT_SWORD_DEGREES = 80.0
THRUST_SPEAR_LENGTH = 58.0
THRUST_SPEAR_WIDTH = 18.0


def _melee_visual_alpha(t: float, total: float) -> float:
    if total <= 0.0:
        return 0.0
    n = min(1.0, max(0.0, t / total))
    if n < MELEE_FADE_IN_RATIO:
        return n / MELEE_FADE_IN_RATIO
    end_hold = MELEE_FADE_IN_RATIO + MELEE_HOLD_RATIO
    if n < end_hold:
        return 1.0
    return max(0.0, 1.0 - (n - end_hold) / (1.0 - end_hold))


def _apply_alpha(color: tuple, mult: float) -> tuple:
    r, g, b, a = color
    return (r, g, b, int(a * max(0.0, min(1.0, mult))))


def _draw_arc_streak_gif(
    draw: ImageDraw.ImageDraw,
    origin_px: tuple[int, int],
    radius_game: float,
    coverage_half: float,
    color: tuple,
) -> None:
    # Полилиния по дуге радиуса `radius_game` (в игровых px). Origin — точка
    # игрока в pixel-space gif'а. +X = направление атаки.
    points = []
    for i in range(MELEE_ARC_SEGMENTS + 1):
        a = -coverage_half + (2.0 * coverage_half) * (i / MELEE_ARC_SEGMENTS)
        gx = origin_px[0] + int(math.cos(a) * radius_game * SCALE)
        gy = origin_px[1] + int(math.sin(a) * radius_game * SCALE)
        points.append((gx, gy))
    for a, b in zip(points, points[1:]):
        draw.line((a[0], a[1], b[0], b[1]), fill=color, width=MELEE_ARC_LINE_WIDTH_PX)


def render_melee_arc_swing(t: float, draw: ImageDraw.ImageDraw, canvas_size: int) -> None:
    cx = canvas_size // 2
    alpha = _melee_visual_alpha(t, MELEE_MIN_VISUAL_LIFE)
    # Маркер игрока — небольшой серый круг в центре. Показывает, откуда
    # «расходятся» дуги ветра.
    r_marker = PLAYER_MARKER_RADIUS_PX * SCALE
    draw.ellipse(
        (cx - r_marker, cx - r_marker, cx + r_marker, cx + r_marker),
        fill=PLAYER_MARKER_COLOR,
    )
    if alpha <= 0.0:
        return
    half_arc = math.radians(ARC_SHORT_SWORD_DEGREES) * 0.5
    length = ARC_SHORT_SWORD_LENGTH
    coverage_half = half_arc * MELEE_ARC_STREAK_COVERAGE
    # Два ветерка — внутренний (короче/ближе, меньшая alpha) и внешний
    # (длиннее/дальше, ярче). Читаются как след клинка.
    inner_alpha = alpha * 0.85
    inner_color = _apply_alpha(MELEE_SWING_COLOR, inner_alpha)
    outer_color = _apply_alpha(MELEE_SWING_EDGE_COLOR, alpha)
    _draw_arc_streak_gif(
        draw, (cx, cx), length * MELEE_ARC_INNER_RADIUS_RATIO, coverage_half, inner_color
    )
    _draw_arc_streak_gif(
        draw, (cx, cx), length * MELEE_ARC_OUTER_RADIUS_RATIO, coverage_half, outer_color
    )


def render_melee_thrust_swing(t: float, draw: ImageDraw.ImageDraw, canvas_size: int) -> None:
    cx = canvas_size // 2
    alpha = _melee_visual_alpha(t, MELEE_MIN_VISUAL_LIFE)
    # Игрок смещён на length/2 влево — так штрихи копья визуально центрированы.
    length = THRUST_SPEAR_LENGTH
    width = THRUST_SPEAR_WIDTH
    origin_gif = (cx - int(length * 0.5 * SCALE), cx)
    r_marker = PLAYER_MARKER_RADIUS_PX * SCALE
    draw.ellipse(
        (
            origin_gif[0] - r_marker,
            origin_gif[1] - r_marker,
            origin_gif[0] + r_marker,
            origin_gif[1] + r_marker,
        ),
        fill=PLAYER_MARKER_COLOR,
    )
    if alpha <= 0.0:
        return
    # Два «ветерка» вдоль направления удара — сверху и снизу от древка.
    # Локально они центрированы на позиции hitbox-Area2D (в игре это
    # source + direction * length/2), т.е. на length/2 вперёд от игрока.
    streak_len = length * MELEE_THRUST_STREAK_LENGTH_RATIO
    streak_offset = width * MELEE_THRUST_STREAK_OFFSET_RATIO
    # Центр штриха в pixel-space: origin_gif[0] + length/2 * SCALE.
    hitbox_center_x = origin_gif[0] + int(length * 0.5 * SCALE)
    left_x = hitbox_center_x - int(streak_len * 0.5 * SCALE)
    right_x = hitbox_center_x + int(streak_len * 0.5 * SCALE)
    top_y = origin_gif[1] - int(streak_offset * SCALE)
    bot_y = origin_gif[1] + int(streak_offset * SCALE)
    streak_color = _apply_alpha(MELEE_SWING_EDGE_COLOR, alpha)
    draw.line((left_x, top_y, right_x, top_y), fill=streak_color, width=MELEE_ARC_LINE_WIDTH_PX)
    draw.line((left_x, bot_y, right_x, bot_y), fill=streak_color, width=MELEE_ARC_LINE_WIDTH_PX)
    # Наконечник у переднего края — треугольник, ярче.
    front_x = origin_gif[0] + int(length * SCALE)
    tip_color = _apply_alpha(MELEE_THRUST_TIP_COLOR, alpha)
    tip_len_game = min(6.0, length * 0.2)
    tip_wid_game = width * 0.5 + 3.0
    tip_pts = [
        (front_x, origin_gif[1]),
        (front_x - int(tip_len_game * SCALE), origin_gif[1] - int(tip_wid_game * SCALE)),
        (front_x - int(tip_len_game * SCALE), origin_gif[1] + int(tip_wid_game * SCALE)),
    ]
    draw.polygon(tip_pts, fill=tip_color)


# ---- driver ----------------------------------------------------------------

ANIMATIONS: list[Animation] = [
    Animation("poison_cloud", 4.0, 40, render_poison_cloud),
    Animation("spider_web_landed", 12.0, 40, render_web_landed),
    Animation("spider_web_flying", 1.5, 40, render_web_flying),
    Animation("cast_pulse", 0.8, 20, render_cast_pulse),
    Animation("slime_hop", 1.8, 24, render_slime_hop),
    Animation("melee_arc_swing", MELEE_MIN_VISUAL_LIFE, 80, render_melee_arc_swing),
    Animation("melee_thrust_swing", MELEE_MIN_VISUAL_LIFE, 130, render_melee_thrust_swing),
]


def render_animation(anim: Animation) -> str:
    frames_total = int(anim.duration_s * FRAMES_PER_SECOND)
    canvas = anim.canvas_size_px * SCALE
    frames = []
    for f in range(frames_total):
        t = f / FRAMES_PER_SECOND
        img = Image.new("RGBA", (canvas, canvas), anim.background)
        draw = ImageDraw.Draw(img, "RGBA")
        anim.render(t, draw, canvas)
        # Gif не поддерживает альфу с blending — flatten на фон.
        rgb = Image.new("RGB", (canvas, canvas), anim.background[:3])
        rgb.paste(img, mask=img.split()[3])
        frames.append(rgb)
    out_path = os.path.join(OUT_DIR, f"{anim.name}.gif")
    frame_ms = int(1000 / FRAMES_PER_SECOND)
    frames[0].save(
        out_path,
        save_all=True,
        append_images=frames[1:],
        duration=frame_ms,
        loop=0,
        optimize=True,
    )
    return out_path


def main() -> None:
    global _WEB_GEOMETRY_CACHE
    for anim in ANIMATIONS:
        # Сброс кеша между анимациями, чтобы web landing начал с нуля.
        _WEB_GEOMETRY_CACHE = None
        out = render_animation(anim)
        print(f"  wrote {out}")


if __name__ == "__main__":
    main()
