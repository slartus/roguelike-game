class_name WeaponStats
extends RefCounted

# Runtime-снимок фактических параметров атаки: base WeaponResource +
# GameState.get_player_upgrade_modifiers(). WeaponController читает
# эти поля, не raw weapon fields — так style cards влияют на attack
# без мутации .tres.
#
# Пороги/капы:
# - attack_interval не ниже MIN_ATTACK_INTERVAL (защита от zero cooldown);
# - archer_pierce_bonus капается на MAX_ARCHER_PIERCE_BONUS.

const MIN_ATTACK_INTERVAL := 0.05
const MAX_ARCHER_PIERCE_BONUS := 2

const MAX_ARC_DEGREES := 179.0

var attack_type: String = ""
# Attribution: weapon_id (path-basename .tres) для аналитики (weapon damage_dealt,
# kills, projectile_hit). Пустая StringName → "unknown" в аналитике.
var source_weapon_id: StringName = &""
var damage: int = 1
var attack_interval: float = 0.25
var projectile_speed: float = 220.0
var projectile_lifetime: float = 1.5
var projectile_color: Color = Color.WHITE
var projectiles_per_attack: int = 1
var spread_angle_deg: float = 0.0
var pierce: int = 0
var hitbox_width: float = 34.0
var hitbox_length: float = 36.0
var arc_degrees: float = 80.0
var active_time: float = 0.08
var knockback: float = 0.0

# Собирает финальный stats-snapshot для конкретного weapon и текущего
# upgrade state.
static func compute(weapon: WeaponResource, mods: Dictionary) -> WeaponStats:
	var s := WeaponStats.new()
	if weapon == null:
		return s
	# Скопировали base из weapon через helper'ы (учитывают legacy fallback).
	s.attack_type = weapon.attack_type
	s.source_weapon_id = StringName(weapon.resource_path.get_file().get_basename())
	s.damage = weapon.damage
	s.attack_interval = weapon.get_attack_interval()
	s.projectile_speed = weapon.get_projectile_speed()
	s.projectile_lifetime = weapon.get_projectile_lifetime()
	s.projectile_color = weapon.get_projectile_color()
	s.projectiles_per_attack = weapon.get_projectiles_per_attack()
	s.spread_angle_deg = weapon.spread_angle_deg
	s.pierce = weapon.pierce
	s.hitbox_width = weapon.hitbox_width
	s.hitbox_length = weapon.hitbox_length
	s.arc_degrees = weapon.arc_degrees
	s.active_time = weapon.active_time
	s.knockback = weapon.knockback

	# Style modifiers применяем только если weapon.style совпадает.
	# General модификаторы (speed_multiplier, potion_heal_bonus etc.) —
	# не про weapon, они в Player. WeaponStats заботится только про attack.
	match weapon.style:
		"warrior":
			s.damage += int(mods.get("warrior_damage_bonus", 0))
			s.hitbox_length *= float(mods.get("warrior_range_multiplier", 1.0))
			# arc_multiplier расширяет угол сектора только для arc-типа —
			# семантически это «шире замах», hitbox_width у arc-оружия больше
			# не используется (форма — сектор круга, а не прямоугольник).
			if weapon.attack_type == "melee_arc":
				s.arc_degrees *= float(mods.get("warrior_arc_multiplier", 1.0))
			s.knockback += float(mods.get("warrior_knockback_bonus", 0.0))
		"archer":
			s.damage += int(mods.get("archer_damage_bonus", 0))
			s.attack_interval *= float(mods.get("archer_attack_interval_multiplier", 1.0))
			s.spread_angle_deg *= float(mods.get("archer_spread_multiplier", 1.0))
			s.pierce += mini(
				int(mods.get("archer_pierce_bonus", 0)),
				MAX_ARCHER_PIERCE_BONUS,
			)
			s.projectile_speed *= float(mods.get("archer_projectile_speed_multiplier", 1.0))
		"mage":
			s.damage += int(mods.get("mage_damage_bonus", 0))
			s.attack_interval *= float(mods.get("mage_attack_interval_multiplier", 1.0))
			s.projectile_lifetime *= float(mods.get("mage_projectile_lifetime_multiplier", 1.0))
			# area_radius пока не используется — spell_area weapon type не готов.

	# Капим attack_interval — иначе спам атаки в один кадр.
	s.attack_interval = maxf(MIN_ATTACK_INTERVAL, s.attack_interval)
	# Отрицательный spread невозможен.
	s.spread_angle_deg = maxf(0.0, s.spread_angle_deg)
	# Сектор дуги ограничиваем строго ниже 360°, иначе арка «замкнётся» в
	# полный круг и потеряет читаемое направление атаки.
	s.arc_degrees = clampf(s.arc_degrees, 0.0, MAX_ARC_DEGREES)
	return s
