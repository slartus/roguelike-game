class_name RunAnalyticsState
extends RefCounted

# Аккумулятор ран-скоуп статистики для аналитики. Инициализируется на
# Analytics.start_run(), инкрементируется gameplay-хуками через
# Analytics.increment_*() методы, снимается snapshot'ом на finish_run().
#
# Не заменяет GameState.run_gold / run_enemies_killed — те живут для UI
# (окно «Итоги забега» на title screen). Здесь копия, чтобы:
#  1. gameplay-инстанс легко чистился без потери UI-снимка;
#  2. аналитика не связана с сигналом изменения UI-полей.
#
# В PR 1 счётчики минимальные (kills, gold, damage_taken). PR 2
# расширяет ими всё разнообразие — weapon exposure, upgrades и т.п.

var run_id: String = ""
var run_started_ticks_ms: int = 0
var floor_started_ticks_ms: int = 0
var current_floor: int = 0

# Run-level counters.
var enemies_killed_total: int = 0
var gold_earned_total: int = 0
var damage_taken_total: int = 0

# Floor-level counters. Сбрасываются в start_floor.
var floor_kills: int = 0
var floor_gold_earned: int = 0
var floor_damage_taken: int = 0

func reset() -> void:
	run_id = ""
	run_started_ticks_ms = 0
	floor_started_ticks_ms = 0
	current_floor = 0
	enemies_killed_total = 0
	gold_earned_total = 0
	damage_taken_total = 0
	floor_kills = 0
	floor_gold_earned = 0
	floor_damage_taken = 0

func start_run(new_run_id: String, ticks_ms: int) -> void:
	reset()
	run_id = new_run_id
	run_started_ticks_ms = ticks_ms

func start_floor(floor_number: int, ticks_ms: int) -> void:
	current_floor = floor_number
	floor_started_ticks_ms = ticks_ms
	floor_kills = 0
	floor_gold_earned = 0
	floor_damage_taken = 0

func add_kill() -> void:
	enemies_killed_total += 1
	floor_kills += 1

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold_earned_total += amount
	floor_gold_earned += amount

func add_damage_taken(amount: int) -> void:
	if amount <= 0:
		return
	damage_taken_total += amount
	floor_damage_taken += amount

func floor_duration_seconds(now_ticks_ms: int) -> float:
	if floor_started_ticks_ms <= 0:
		return 0.0
	return maxf(0.0, (now_ticks_ms - floor_started_ticks_ms) / 1000.0)

func run_duration_seconds(now_ticks_ms: int) -> float:
	if run_started_ticks_ms <= 0:
		return 0.0
	return maxf(0.0, (now_ticks_ms - run_started_ticks_ms) / 1000.0)
