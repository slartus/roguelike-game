class_name WeaponAnalyticsCounters
extends RefCounted

# Runtime counters на одно оружие в рамках одного этажа (floor).
# Analytics.RunAnalyticsState держит Dictionary { weapon_id: WeaponAnalyticsCounters }
# и сбрасывает его в start_floor.
#
# `equipped_seconds` — «сколько времени игрок держал это оружие
# на этаже», считается прямо, через ticks_ms дельту между двумя
# `weapon_equipped` событиями.

var weapon_id: StringName = &""
var equipped_seconds: float = 0.0
# combat_seconds — время, пока игрок находился в бою (получал урон
# или наносил урон). PR 2 использует упрощённое определение: секунды,
# в течение которых был хотя бы один enemy alive в active room.
# Полная реализация — follow-up (нужна room-based combat state machine).
var combat_seconds: float = 0.0
var attacks: int = 0
var projectiles_fired: int = 0
var attacks_with_hit: int = 0
var projectiles_hit: int = 0
var targets_hit: int = 0
var damage_dealt: int = 0
var kills: int = 0
var overkill_damage: int = 0
var damage_taken_while_equipped: int = 0

func _init(id: StringName = &"") -> void:
	weapon_id = id

func to_dictionary() -> Dictionary:
	return {
		"weapon_id": String(weapon_id),
		"equipped_seconds": equipped_seconds,
		"combat_seconds": combat_seconds,
		"attacks": attacks,
		"projectiles_fired": projectiles_fired,
		"attacks_with_hit": attacks_with_hit,
		"projectiles_hit": projectiles_hit,
		"targets_hit": targets_hit,
		"damage_dealt": damage_dealt,
		"kills": kills,
		"overkill_damage": overkill_damage,
		"damage_taken_while_equipped": damage_taken_while_equipped,
	}
