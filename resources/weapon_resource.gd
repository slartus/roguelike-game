class_name WeaponResource
extends Resource

# Модель оружия v2. Готовим фундамент для warrior/archer/mage-стилей.
# Старые поля (damage, fire_interval, bullet_*, bullets_per_shot,
# spread_angle_deg) не удаляем — legacy Dagger/Pistol/Shotgun их читают
# напрямую. Новая система (WeaponController в следующем milestone) читает
# через helper'ы `get_*` — они возвращают новое поле, если оно задано,
# иначе fallback на старое.

# --- Identity ---
@export var id: String = "unknown"
@export_enum("warrior", "archer", "mage", "legacy") var style: String = "legacy"
@export_enum("melee_arc", "melee_thrust", "projectile", "spell_projectile", "spell_area") var attack_type: String = "projectile"
@export var tier: int = 1
@export var tags: Array[String] = []

# Default projectile color шарен между fallback-helper'ом и полем ниже —
# держим единственный источник, чтобы будущее изменение default не забыть
# в одном из мест.
const DEFAULT_PROJECTILE_COLOR := Color(1.0, 0.9, 0.3, 1.0)

# --- Общие attack stats ---
@export var display_name: String = "WEAPON_UNKNOWN"
@export var damage: int = 1
# 0 → fallback на fire_interval (legacy). Иначе используем это значение.
@export var attack_interval: float = 0.0
# attack_range информативный. WeaponController использует hitbox_length для
# melee и projectile_lifetime × speed для ranged. `range` было бы удобнее,
# но это встроенная функция GDScript — shadowing вызывает warning.
@export var attack_range: float = 80.0
@export var icon_texture: Texture2D
# Отдельный цвет для WeaponPickup визуала — не завязан на projectile_color.
# Legacy Dagger/Pistol/Shotgun имеют реальные icon_texture и оставляют
# icon_modulate по default'у (белый). Новые v2 оружия без спрайта используют
# icon_modulate чтобы отличаться визуально в мире (sword — стальной, staff
# — синий и т.д.). Дефолт WHITE — не искажает уже покрашенный icon_texture.
@export var icon_modulate: Color = Color.WHITE

# --- Projectile stats (для projectile / spell_projectile / spell_area) ---
# projectile_scene = null → WeaponController использует default bullet.
@export var projectile_scene: PackedScene
# 0.0 → fallback на bullet_speed (legacy).
@export var projectile_speed: float = 0.0
# 0.0 → fallback на bullet_lifetime.
@export var projectile_lifetime: float = 0.0
@export var projectile_color: Color = DEFAULT_PROJECTILE_COLOR
# 0 → fallback на bullets_per_shot.
@export var projectiles_per_attack: int = 0
@export var spread_angle_deg: float = 0.0
# pierce > 0 → снаряд пробивает N врагов до queue_free.
@export var pierce: int = 0

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

# --- Legacy поля (Dagger/Pistol/Shotgun ещё читают напрямую) ---
@export var fire_interval: float = 0.25
@export var bullet_speed: float = 220.0
@export var bullet_lifetime: float = 1.5
@export var bullet_color: Color = Color(1.0, 0.9, 0.3, 1.0)
@export var bullets_per_shot: int = 1

# --- Helpers для единого доступа к параметрам ---
# WeaponController v2 читает всё через эти helper'ы, поэтому и новые
# ресурсы (short_sword, short_bow, ...), и legacy (dagger, pistol) видны
# одинаково — второй просто попадает в fallback-ветку.

func get_attack_interval() -> float:
	if attack_interval > 0.0:
		return attack_interval
	return fire_interval

func get_projectile_speed() -> float:
	if projectile_speed > 0.0:
		return projectile_speed
	return bullet_speed

func get_projectile_lifetime() -> float:
	if projectile_lifetime > 0.0:
		return projectile_lifetime
	return bullet_lifetime

func get_projectiles_per_attack() -> int:
	if projectiles_per_attack > 0:
		return projectiles_per_attack
	return bullets_per_shot

func get_projectile_color() -> Color:
	# Приоритет как у остальных helper'ов: если новое поле задано (отличается
	# от default) — новое; иначе fallback на legacy bullet_color. Так и
	# Shotgun (bullet_color=оранжевый, projectile_color=default) отдаст свой
	# оранжевый через fallback, и новый Wand (projectile_color=фиолет,
	# bullet_color случайно остался желтый default) отдаст фиолетовый.
	if projectile_color != DEFAULT_PROJECTILE_COLOR:
		return projectile_color
	return bullet_color
