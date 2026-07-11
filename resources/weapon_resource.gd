class_name WeaponResource
extends Resource

# Модель fantasy-оружия. Все активные .tres задают identity (id, style,
# attack_type, tier, tags) явно — legacy fallback (fire_interval,
# bullet_*, bullets_per_shot) удалён после fantasy roster overhaul.

# --- Identity ---
@export var id: String = "unknown"
@export_enum("warrior", "archer", "mage") var style: String = "warrior"
@export_enum("melee_arc", "melee_thrust", "projectile", "spell_projectile", "spell_area") var attack_type: String = "melee_arc"
@export var tier: int = 1
@export var tags: Array[String] = []

# --- Общие attack stats ---
@export var display_name: String = "WEAPON_UNKNOWN"
@export var damage: int = 1
@export var attack_interval: float = 0.25
# attack_range информативный. WeaponController использует hitbox_length для
# melee и projectile_lifetime × speed для ranged. `range` было бы удобнее,
# но это встроенная функция GDScript — shadowing вызывает warning.
@export var attack_range: float = 80.0
@export var icon_texture: Texture2D
# Отдельный цвет для WeaponPickup визуала — не завязан на projectile_color
# (тот про снаряд). У всех активных оружий свои icon_texture, поэтому дефолт
# WHITE рендерит спрайт как есть. Кастомный оттенок — если понадобится
# redshift-эффект / damage-flash / реролл-версия без своего PNG.
@export var icon_modulate: Color = Color.WHITE

# --- Projectile stats (для projectile / spell_projectile / spell_area) ---
# projectile_scene = null → WeaponController использует default bullet.
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 220.0
@export var projectile_lifetime: float = 1.2
@export var projectile_color: Color = Color(1.0, 0.9, 0.3, 1.0)
@export var projectiles_per_attack: int = 1
@export var spread_angle_deg: float = 0.0
# pierce > 0 → снаряд пробивает N врагов до queue_free.
@export var pierce: int = 0
# Смещение точки спавна снаряда относительно игрока. По умолчанию 0 —
# снаряд рождается в центре игрока (совместимо со старым поведением).
# Ненулевое `projectile_spawn_distance` сдвигает spawn на
# `direction * distance + direction.orthogonal() * lateral` — снаряд выходит
# от наконечника оружия, а не из центра тела.
@export var projectile_spawn_distance: float = 0.0
@export var projectile_spawn_lateral_offset: float = 0.0

# --- Melee stats ---
@export var arc_degrees: float = 80.0
@export var hitbox_width: float = 34.0
@export var hitbox_length: float = 36.0
@export var windup_time: float = 0.03
@export var active_time: float = 0.08
@export var recovery_time: float = 0.12
@export var knockback: float = 0.0

# --- Magic v1 (заготовка, реально не расходуется) ---
@export var mana_cost: int = 0
@export var status_effect: String = ""
@export var area_radius: float = 0.0

# --- Held visuals (в руке игрока) ---
# Разделяем icon (мировой pickup + HUD) и held (Sprite2D "Weapon" у Player).
# held_texture = null → fallback на icon_texture (совместимо с
# короткими .tres без явной held-metadata).
@export var held_texture: Texture2D
@export var held_sprite_offset: Vector2 = Vector2.ZERO
@export var held_scale: Vector2 = Vector2.ONE
# Player рендерит оружие с пиксельным смещением от корпуса. Дефолт (5, 3)
# совпадает с исходной константой HAND_X/Y_OFFSET в player.gd.
@export var held_hand_offset: Vector2 = Vector2(5, 3)
# Для side-rest оружия — угол наклона от вертикали в rest pose.
# Знак умножается на _facing, чтобы клинок смотрел «наружу» от игрока.
# 0.0 → без наклона (проекционные оружия по умолчанию).
@export var held_rest_rotation: float = 0.0
# true → в rest oружие следует aim direction (курсору) вместо side-rest.
# Актуально для лука, арбалета, копья, жезла — они должны смотреть на цель.
@export var held_aim_aligned: bool = false
# Смещение rotation при aim-aligned. Используется если исходный sprite
# нарисован «вверх» и нужно повернуть его на PI/2, чтобы «вправо».
@export var held_aim_rotation_offset: float = 0.0

func get_held_texture() -> Texture2D:
	return held_texture if held_texture != null else icon_texture

# --- Helpers для единого доступа к параметрам ---
# Клиенты (bullet, WeaponStats, debug UI) читают всё через эти helper'ы —
# фасад пережил legacy fallback fields и остаётся стабильным API.

func get_attack_interval() -> float:
	return attack_interval

func get_projectile_speed() -> float:
	return projectile_speed

func get_projectile_lifetime() -> float:
	return projectile_lifetime

func get_projectiles_per_attack() -> int:
	return projectiles_per_attack

func get_projectile_color() -> Color:
	return projectile_color
