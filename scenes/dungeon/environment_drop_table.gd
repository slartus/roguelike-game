class_name EnvironmentDropTable
extends RefCounted

# Детерминированный roll drop'а из destructible environment prop'а.
# Один вызов = один результат. Seed составляется из (tower_seed,
# floor_number, prop_id, placement_index) — чтобы:
# - тот же placement дал ТОТ ЖЕ drop при повторном забеге (регенерация
#   этажа не переигрывает награду);
# - разные placements в одной комнате давали разные drops;
# - environment drop RNG не сдвигал gameplay RNG (спавны монстров, chest).
#
# Также поддерживается floor-wide budget: floor.gd на старте создаёт
# один экземпляр таблицы через `new_for_floor(tower_seed, floor)` и
# передаёт в него prop_placements по мере разрушения. При достижении
# `total_value_cap` даже успешный roll возвращает NONE — награда не
# выдаётся сверх бюджета.

# --- Result codes ---
const RESULT_NONE: StringName = &"none"
const RESULT_GOLD_SMALL: StringName = &"gold_small"
const RESULT_POTION: StringName = &"potion"
const RESULT_GOLD_LARGE: StringName = &"gold_large"

# --- Drop policy ---
# Ориентир из плана:
# nothing 75-85%, small currency 10-18%, minor consumable 2-5%, rare 0-1%.
# Используем 80/15/4/1 — попадает в середину диапазонов.
const CHANCE_NOTHING: float = 0.80
const CHANCE_GOLD_SMALL: float = 0.15
const CHANCE_POTION: float = 0.04
# rare_special = остаток = 0.01

# Величины наград — value используется в budget.
const VALUE_GOLD_SMALL: int = 1
const VALUE_POTION: int = 3
const VALUE_GOLD_LARGE: int = 5

# Floor-wide cap — суммарный value от destructible props за этаж.
# 12 = 4 монеты + 2 potion + 1 rare, ориентировочно.
const FLOOR_TOTAL_VALUE_CAP: int = 12

var _tower_seed: int = 0
var _floor_number: int = 0
var _spent_value: int = 0

static func new_for_floor(tower_seed: int, floor_number: int) -> EnvironmentDropTable:
	var t := EnvironmentDropTable.new()
	t._tower_seed = tower_seed
	t._floor_number = floor_number
	t._spent_value = 0
	return t

# Основной roll. placement_index — стабильный индекс prop'а в
# floor_plan.placements (planner фиксирует порядок).
func roll(prop_id: StringName, placement_index: int) -> StringName:
	if _spent_value >= FLOOR_TOTAL_VALUE_CAP:
		return RESULT_NONE
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(prop_id, placement_index)
	var r: float = rng.randf()
	if r < CHANCE_NOTHING:
		return RESULT_NONE
	r -= CHANCE_NOTHING
	if r < CHANCE_GOLD_SMALL:
		_spent_value += VALUE_GOLD_SMALL
		return RESULT_GOLD_SMALL
	r -= CHANCE_GOLD_SMALL
	if r < CHANCE_POTION:
		_spent_value += VALUE_POTION
		return RESULT_POTION
	_spent_value += VALUE_GOLD_LARGE
	return RESULT_GOLD_LARGE

func spent_value() -> int:
	return _spent_value

func remaining_budget() -> int:
	return maxi(0, FLOOR_TOTAL_VALUE_CAP - _spent_value)

# Detereministic seed от (tower_seed, floor_number, prop_id, placement_index).
# Формула — та же по духу что RoomDecorationPlanner._seed_for_room:
# большие простые множители + hash StringName'а для стабильности.
static func _seed_for_static(
	tower_seed: int,
	floor_number: int,
	prop_id: StringName,
	placement_index: int,
) -> int:
	var id_hash: int = String(prop_id).hash()
	var raw: int = (
		tower_seed * 2654435769
		+ floor_number * 65537
		+ id_hash * 1000003
		+ placement_index * 31
	)
	return absi(raw) + 1

func _seed_for(prop_id: StringName, placement_index: int) -> int:
	return _seed_for_static(_tower_seed, _floor_number, prop_id, placement_index)

# Величина reward для указанного результата — используется floor.gd для
# точного вычисления списываемой суммы (например, чтобы не тратить
# бюджет на nothing-result'ах).
static func value_of(result: StringName) -> int:
	match result:
		RESULT_GOLD_SMALL:
			return VALUE_GOLD_SMALL
		RESULT_POTION:
			return VALUE_POTION
		RESULT_GOLD_LARGE:
			return VALUE_GOLD_LARGE
		_:
			return 0
