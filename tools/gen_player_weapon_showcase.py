#!/usr/bin/env python3
"""
Генератор docs-картинок «персонаж с каждым оружием».

Показывает, как игрок в бою держит каждое оружие: пиксельарт игрока
+ иконка оружия, спозиционированные и повёрнутые ровно так же, как
это делает движок (см. scenes/player/player.gd).

Совмещённая математика (единственный источник правды — код):
- Player 16×16, Sprite2D.Visual центрируется в origin игрока.
- Weapon Sprite2D сидит в позиции (HAND_X_OFFSET * facing, HAND_Y_OFFSET)
  относительно игрока — по коду HAND_X_OFFSET=5, HAND_Y_OFFSET=3.
- Weapon.offset = (0, -icon_texture.get_height() * 0.5) — pivot вращения
  переносится к нижнему центру текстуры (в handle).
- Rest-угол: для melee (attack_type ∈ {melee_arc, melee_thrust}) равен
  MELEE_REST_ANGLE * facing = 0.35 rad ≈ 20° (наружу от игрока).
  Для projectile/spell rest-угол = 0.
- Для showcase используется facing = +1 (игрок смотрит вправо).

Godot вращает по часовой при положительном угле (Y вниз, X вправо);
PIL rotate() — против часовой при положительном. Инвертируем знак.

Вход: resources/weapons/*.tres (читаем attack_type),
       assets/sprites/player/player.png,
       assets/sprites/weapons/<id>.png.
Выход: docs/gamedesign/media/player_with_<id>.png.

Использование:
    python3 tools/gen_player_weapon_showcase.py
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

# Синхронизировано с scenes/player/player.gd. При изменении констант
# в .gd — обновить и здесь (см. .claude/rules/60-player-weapon-showcase.md).
HAND_X_OFFSET = 5
HAND_Y_OFFSET = 3
MELEE_REST_ANGLE = 0.35  # rad
MELEE_ATTACK_TYPES = {"melee_arc", "melee_thrust"}

# Масштаб пиксельарта на итоговой картинке. 8× даёт 128 px тело игрока —
# читаемо в docs и не размывается при обычном просмотре.
SCALE = 8
CANVAS_SIZE = 256

ROOT = Path(__file__).resolve().parents[1]
PLAYER_PNG = ROOT / "assets" / "sprites" / "player" / "player.png"
WEAPONS_DIR = ROOT / "resources" / "weapons"
SPRITES_DIR = ROOT / "assets" / "sprites" / "weapons"
OUT_DIR = ROOT / "docs" / "gamedesign" / "media"

# Fallback только для повреждённого .tres без `attack_type` — активные
# fantasy оружия его всегда задают явно.
LEGACY_ATTACK_TYPE = "projectile"


@dataclass(frozen=True)
class WeaponMeta:
    weapon_id: str
    attack_type: str
    sprite_path: Path


def parse_weapon_tres(path: Path) -> WeaponMeta:
    text = path.read_text(encoding="utf-8")
    id_match = re.search(r'''^id\s*=\s*["']([^"']+)["']''', text, re.MULTILINE)
    weapon_id = id_match.group(1) if id_match else path.stem
    at_match = re.search(r'''^attack_type\s*=\s*["']([^"']+)["']''', text, re.MULTILINE)
    attack_type = at_match.group(1) if at_match else LEGACY_ATTACK_TYPE
    sprite = SPRITES_DIR / f"{weapon_id}.png"
    if not sprite.exists():
        raise FileNotFoundError(f"weapon sprite not found: {sprite}")
    return WeaponMeta(weapon_id=weapon_id, attack_type=attack_type, sprite_path=sprite)


def load_scaled(path: Path, scale: int) -> Image.Image:
    img = Image.open(path).convert("RGBA")
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def rotate_weapon_around_handle(weapon: Image.Image, angle_rad: float) -> tuple[Image.Image, int]:
    """
    Возвращает (rotated_layer, pivot_center) — слой, у которого центр
    изображения совпадает с pivot (bottom-center исходной текстуры), а
    сама текстура вращена вокруг этого pivot.
    Знак угла инвертирован под PIL (CCW-positive) относительно Godot (CW-positive).
    """
    ww, wh = weapon.size
    pivot_x = ww // 2
    pivot_y = wh  # нижняя граница текстуры — точка «в руке»

    # Слой с запасом, чтобы клинок при вращении не обрезался.
    layer_size = 2 * max(ww, wh)
    layer = Image.new("RGBA", (layer_size, layer_size), (0, 0, 0, 0))
    layer_center = layer_size // 2
    layer.paste(weapon, (layer_center - pivot_x, layer_center - pivot_y), weapon)

    pil_degrees = -math.degrees(angle_rad)
    rotated = layer.rotate(pil_degrees, resample=Image.BICUBIC, expand=False)
    return rotated, layer_center


def compose_showcase(player_img: Image.Image, weapon_img: Image.Image, angle_rad: float) -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    cx = CANVAS_SIZE // 2
    cy = CANVAS_SIZE // 2

    player_paste_x = cx - player_img.width // 2
    player_paste_y = cy - player_img.height // 2
    canvas.paste(player_img, (player_paste_x, player_paste_y), player_img)

    rotated_weapon, pivot_center = rotate_weapon_around_handle(weapon_img, angle_rad)
    weapon_pivot_x = cx + HAND_X_OFFSET * SCALE
    weapon_pivot_y = cy + HAND_Y_OFFSET * SCALE
    canvas.paste(
        rotated_weapon,
        (weapon_pivot_x - pivot_center, weapon_pivot_y - pivot_center),
        rotated_weapon,
    )
    return canvas


def rest_angle_for(attack_type: str) -> float:
    if attack_type in MELEE_ATTACK_TYPES:
        return MELEE_REST_ANGLE  # facing = +1 → положительный угол
    return 0.0


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    player_img = load_scaled(PLAYER_PNG, SCALE)

    weapon_files = sorted(WEAPONS_DIR.glob("*.tres"))
    if not weapon_files:
        raise SystemExit(f"no weapons found in {WEAPONS_DIR}")

    for tres in weapon_files:
        meta = parse_weapon_tres(tres)
        weapon_img = load_scaled(meta.sprite_path, SCALE)
        angle = rest_angle_for(meta.attack_type)
        image = compose_showcase(player_img, weapon_img, angle)
        out = OUT_DIR / f"player_with_{meta.weapon_id}.png"
        image.save(out)
        print(f"wrote {out} ({image.width}x{image.height}, attack_type={meta.attack_type})")


if __name__ == "__main__":
    main()
