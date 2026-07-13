extends GutTest

# EnvironmentDropTable tests: детерминизм, floor cap, распределение.

const _DROP_TABLE := preload("res://scenes/dungeon/environment_drop_table.gd")

func test_same_seed_placement_produces_same_result() -> void:
	# Тот же (seed, floor, prop_id, placement_index) должен всегда давать
	# одинаковый result — гарантия для save/load детерминизма.
	var t1: EnvironmentDropTable = _DROP_TABLE.new_for_floor(12345, 4)
	var t2: EnvironmentDropTable = _DROP_TABLE.new_for_floor(12345, 4)
	for i in 5:
		var r1 := t1.roll(&"destructible_crate", i)
		var r2 := t2.roll(&"destructible_crate", i)
		assert_eq(r1, r2, "same seed, same index должны давать тот же result")

func test_different_placement_indices_can_differ() -> void:
	# Разные placement_index — хотя бы иногда должны давать разные results.
	var t: EnvironmentDropTable = _DROP_TABLE.new_for_floor(12345, 4)
	var seen: Dictionary = {}
	for i in 20:
		seen[t.roll(&"destructible_crate", i)] = true
	assert_gt(seen.size(), 1,
		"по 20 разным index'ам должен быть хотя бы один вариантных result")

func test_floor_cap_blocks_further_rolls() -> void:
	# Roll до исчерпания budget'а — дальше только RESULT_NONE.
	var t: EnvironmentDropTable = _DROP_TABLE.new_for_floor(999, 1)
	# Насильно вычерпаем весь бюджет через много прогонов на разных
	# seed'ах — но по контракту, если spent_value >= cap, roll возвращает NONE.
	# Просто roll'им 100 раз — сумма value спокойно превысит cap 12.
	var non_none_count := 0
	for i in 100:
		var r := t.roll(&"destructible_crate", i)
		if r != _DROP_TABLE.RESULT_NONE:
			non_none_count += 1
	assert_lte(t.spent_value(), 15,
		"spent_value не должен сильно превышать FLOOR_TOTAL_VALUE_CAP (12) + одна валидная выдача")
	assert_gt(non_none_count, 0,
		"хотя бы один roll должен успешно упасть в валидный результат до cap'а")

func test_none_result_does_not_consume_budget() -> void:
	# nothing-result не должен списывать value. Ищем placement_index,
	# который на seed=1/floor=1 даёт NONE — пробуем 40 подряд, gaurantied
	# что хотя бы один NONE найдётся (chance ≈ 80%).
	var t: EnvironmentDropTable = _DROP_TABLE.new_for_floor(1, 1)
	var found_none: bool = false
	for i in 40:
		var before := t.spent_value()
		var r := t.roll(&"destructible_crate", i)
		if r == _DROP_TABLE.RESULT_NONE:
			assert_eq(t.spent_value(), before,
				"NONE-ролл не должен увеличивать spent_value (index=%d)" % i)
			found_none = true
			break
		# Non-NONE — переходим к следующему index'у. Стоп-cap невозможен —
		# 40 попыток мало чтобы упереться в cap 12 по gold_small (~15%).
	assert_true(found_none,
		"на 40 попытках должен найтись хотя бы один NONE-ролл (chance ≈80%)")

func test_different_prop_ids_produce_different_seed_streams() -> void:
	# Разные prop_id для того же placement_index должны давать разные
	# roll-последовательности — иначе floor.gd будет тратить бюджет
	# синхронно между разными типами props.
	var t: EnvironmentDropTable = _DROP_TABLE.new_for_floor(42, 3)
	# Roll'им один и тот же index для разных prop_id и проверяем что
	# результаты не совпадают целиком — вероятность совпадения по 5
	# броскам подряд крайне мала при разных seed streams.
	var results_a: Array[StringName] = []
	var results_b: Array[StringName] = []
	for i in 5:
		var t_a: EnvironmentDropTable = _DROP_TABLE.new_for_floor(42, 3)
		var t_b: EnvironmentDropTable = _DROP_TABLE.new_for_floor(42, 3)
		results_a.append(t_a.roll(&"destructible_crate", i))
		results_b.append(t_b.roll(&"urn", i))
	# Хотя бы одна пара должна отличаться.
	var identical := true
	for i in results_a.size():
		if results_a[i] != results_b[i]:
			identical = false
			break
	assert_false(identical, "разные prop_id должны давать различные результаты")

func test_value_of_matches_result_codes() -> void:
	assert_eq(_DROP_TABLE.value_of(_DROP_TABLE.RESULT_NONE), 0)
	assert_eq(_DROP_TABLE.value_of(_DROP_TABLE.RESULT_GOLD_SMALL), _DROP_TABLE.VALUE_GOLD_SMALL)
	assert_eq(_DROP_TABLE.value_of(_DROP_TABLE.RESULT_POTION), _DROP_TABLE.VALUE_POTION)
	assert_eq(_DROP_TABLE.value_of(_DROP_TABLE.RESULT_GOLD_LARGE), _DROP_TABLE.VALUE_GOLD_LARGE)

func test_distribution_biased_toward_nothing() -> void:
	# Sanity: большинство roll'ов должно быть NONE (chance 80%). 100 бросков
	# на разных placement_index'ах — минимум 60 NONE, обычно 75-85.
	var t: EnvironmentDropTable = _DROP_TABLE.new_for_floor(777, 5)
	var none_count := 0
	for i in 100:
		if t.roll(&"destructible_crate", i) == _DROP_TABLE.RESULT_NONE:
			none_count += 1
	assert_gte(none_count, 60,
		"по политике drop >=60/100 бросков должны быть NONE (actual=%d)" % none_count)
