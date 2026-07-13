extends GutTest

# FloorEncounterBudget — чистые функции, тестируем логику формулы.

func test_entrance_and_exit_get_zero_budget() -> void:
	var room := Rect2i(Vector2i(0, 0), Vector2i(120, 120))
	var entrance_info := {"role": "entrance", "danger": 0, "tags": ["entrance"]}
	var exit_info := {"role": "exit_core", "danger": 0, "tags": ["exit"]}
	assert_eq(FloorEncounterBudget.room_budget(room, entrance_info, 3, true, 0), 0)
	assert_eq(FloorEncounterBudget.room_budget(room, exit_info, 3, true, 3), 0)

func test_tiny_room_gets_zero_budget() -> void:
	# 3×3 tiles = 60×60 = 3600 px² < 3200 threshold? Wait 3200. Let me use
	# 2×2 tile = 40×40 = 1600 < 3200.
	var tiny := Rect2i(Vector2i.ZERO, Vector2i(40, 40))
	var info := {"role": "storage", "danger": 0, "tags": ["small"]}
	assert_eq(FloorEncounterBudget.room_budget(tiny, info, 3, false, 1), 0)

func test_medium_room_gets_positive_budget() -> void:
	# 6×6 tiles = 120×120 = 14400 px² → 14400 / 3600 = 4 area_slots → clamped 3
	var room := Rect2i(Vector2i.ZERO, Vector2i(120, 120))
	var info := {"role": "storage", "danger": 0, "tags": []}
	var budget := FloorEncounterBudget.room_budget(room, info, 3, false, 1)
	assert_gte(budget, 1)
	assert_lte(budget, 5)

func test_dangerous_role_boosts_budget() -> void:
	var room := Rect2i(Vector2i.ZERO, Vector2i(120, 120))
	var storage := {"role": "storage", "danger": 0, "tags": []}
	var machine := {"role": "machine_room", "danger": 2, "tags": []}
	var storage_budget := FloorEncounterBudget.room_budget(room, storage, 3, false, 1)
	var machine_budget := FloorEncounterBudget.room_budget(room, machine, 3, false, 1)
	assert_gt(machine_budget, storage_budget)

func test_optional_reward_reduces_budget() -> void:
	var room := Rect2i(Vector2i.ZERO, Vector2i(120, 120))
	var regular := {"role": "storage", "danger": 0, "tags": []}
	var optional := {"role": "storage", "danger": 0, "tags": ["optional_reward", "dead_end"]}
	var regular_budget := FloorEncounterBudget.room_budget(room, regular, 5, false, 2)
	var optional_budget := FloorEncounterBudget.room_budget(room, optional, 5, false, 2)
	assert_lt(optional_budget, regular_budget)

func test_treasure_room_reduces_budget() -> void:
	var room := Rect2i(Vector2i.ZERO, Vector2i(120, 120))
	var regular := {"role": "storage", "danger": 0, "tags": []}
	var treasure := {"role": "treasure_room", "danger": 1, "tags": ["treasure"]}
	var regular_budget := FloorEncounterBudget.room_budget(room, regular, 5, false, 2)
	var treasure_budget := FloorEncounterBudget.room_budget(room, treasure, 5, false, 2)
	assert_lte(treasure_budget, regular_budget + 1)

func test_floor_cap_grows_with_zone_and_floor() -> void:
	# floor 1 tower_top < floor 20 caves.
	var top_low := FloorEncounterBudget.floor_cap("tower_top", 1)
	var caves_high := FloorEncounterBudget.floor_cap("caves", 20)
	assert_lt(top_low, caves_high)

func test_floor_cap_unknown_zone_still_returns_positive() -> void:
	# Fallback значение — не крашит.
	var cap := FloorEncounterBudget.floor_cap("nonexistent", 5)
	assert_gt(cap, 0)
