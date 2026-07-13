class_name EnemyAnalyticsCounters
extends RefCounted

# Runtime counters по (enemy_id, temperament_id, elite_rank) в рамках
# одного этажа. Analytics агрегирует в Dictionary { key_tuple: EnemyAnalyticsCounters }.
#
# key_tuple собирается как "%s|%s|%d" (enemy_id, temperament_id, elite_rank)
# — обычная строка для hashable key в Dictionary.

var enemy_id: StringName = &""
var temperament_id: StringName = &""
var elite_rank: int = 0

var spawned: int = 0
var killed: int = 0
var damage_to_player: int = 0
var hits_to_player: int = 0
var damage_received: int = 0
var time_alive_seconds: float = 0.0
var player_deaths: int = 0

func _init(id: StringName = &"", temperament: StringName = &"", rank: int = 0) -> void:
	enemy_id = id
	temperament_id = temperament
	elite_rank = rank

# Key для Dictionary'ов. Дублирование enemy_id/temperament/rank в теле
# не проблема — тестируемо и понятно.
static func make_key(enemy_id: StringName, temperament_id: StringName, elite_rank: int) -> String:
	return "%s|%s|%d" % [String(enemy_id), String(temperament_id), elite_rank]

func to_dictionary() -> Dictionary:
	return {
		"enemy_id": String(enemy_id),
		"temperament_id": String(temperament_id),
		"elite_rank": elite_rank,
		"spawned": spawned,
		"killed": killed,
		"damage_to_player": damage_to_player,
		"hits_to_player": hits_to_player,
		"damage_received": damage_received,
		"time_alive_seconds": time_alive_seconds,
		"player_deaths": player_deaths,
	}
