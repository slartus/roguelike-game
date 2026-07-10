extends GutTest

# Тесты для data-driven MonsterSpawnTable.
#
# Не тестируем integration с Main — это подфича 4. Здесь только:
# - целостность MONSTERS (все обязательные поля, PackedScene загружается);
# - eligibility rules по floor и room_tags;
# - детерминированность choose_weighted при одинаковом seed;
# - формулы roll_monster_level / roll_elite_rank.

const REQUIRED_KEYS := [
	"id", "scene", "min_floor", "max_floor", "weight", "threat",
	"tags", "room_tags", "level_offset_min", "level_offset_max",
	"elite_chance",
]

func _ids_on_floor(floor_number: int) -> Array:
	# Проверяем чисто floor gating, без room-tag фильтра. С room_tags
	# eligibility может отсеять монстров, которые не хотят конкретной темы
	# комнаты (например Lich не имеет "generic" room_tag).
	var out: Array = []
	for def in MonsterSpawnTable.get_eligible_defs(floor_number, []):
		out.append(def.id)
	return out

func test_all_defs_have_required_keys() -> void:
	for def in MonsterSpawnTable.get_all_defs():
		for key in REQUIRED_KEYS:
			assert_true(def.has(key),
				"def id=%s должен содержать поле '%s'" % [def.get("id", "?"), key])

func test_all_scenes_load() -> void:
	for def in MonsterSpawnTable.get_all_defs():
		assert_not_null(def.scene,
			"scene у %s не должна быть null (сломался preload)" % def.id)
		var inst = def.scene.instantiate()
		assert_not_null(inst, "instantiate у %s должен работать" % def.id)
		inst.free()

func test_all_weights_positive() -> void:
	for def in MonsterSpawnTable.get_all_defs():
		assert_gt(int(def.weight), 0, "weight > 0 у %s" % def.id)

func test_all_threats_positive() -> void:
	for def in MonsterSpawnTable.get_all_defs():
		assert_gt(int(def.threat), 0, "threat > 0 у %s" % def.id)

func test_all_min_floor_at_least_one() -> void:
	for def in MonsterSpawnTable.get_all_defs():
		assert_gte(int(def.min_floor), 1, "min_floor >= 1 у %s" % def.id)

func test_all_max_floor_at_least_min_floor() -> void:
	for def in MonsterSpawnTable.get_all_defs():
		assert_gte(int(def.max_floor), int(def.min_floor),
			"max_floor >= min_floor у %s" % def.id)

func test_floor_1_contains_small_slime_and_goblin() -> void:
	var ids := _ids_on_floor(1)
	assert_true(ids.has("small_slime"), "floor 1 должен содержать small_slime")
	assert_true(ids.has("goblin"), "floor 1 должен содержать goblin")

func test_floor_1_excludes_dangerous_enemies() -> void:
	# Ранняя игра защищена от high-threat врагов.
	var ids := _ids_on_floor(1)
	for forbidden in ["adult_slime", "orc", "spider", "zombie", "skeleton_archer", "lich"]:
		assert_false(ids.has(forbidden),
			"floor 1 НЕ должен содержать %s" % forbidden)

func test_floor_3_contains_adult_slime() -> void:
	var ids := _ids_on_floor(3)
	assert_true(ids.has("adult_slime"),
		"floor 3 должен разблокировать взрослого слайма")

func test_floor_7_contains_lich() -> void:
	var ids := _ids_on_floor(7)
	assert_true(ids.has("lich"), "floor 7 должен разблокировать лича")

func test_floor_5_excludes_lich() -> void:
	var ids := _ids_on_floor(5)
	assert_false(ids.has("lich"),
		"floor 5 (до min_floor=7) не должен содержать лича")

func test_get_eligible_defs_not_empty_on_key_floors() -> void:
	for f in [1, 3, 7, 12]:
		var defs := MonsterSpawnTable.get_eligible_defs(f, ["generic"])
		assert_false(defs.is_empty(),
			"eligible defs НЕ должен быть пустым на floor %d" % f)

func test_choose_weighted_is_deterministic_for_same_seed() -> void:
	var defs := MonsterSpawnTable.get_eligible_defs(3, ["generic"])
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 12345
	rng_b.seed = 12345
	# Одинаковый seed → одинаковая последовательность выборов.
	for _i in 20:
		var pick_a: Dictionary = MonsterSpawnTable.choose_weighted(defs, rng_a)
		var pick_b: Dictionary = MonsterSpawnTable.choose_weighted(defs, rng_b)
		assert_eq(pick_a.id, pick_b.id,
			"одинаковый seed → одинаковый выбор")

func test_choose_weighted_returns_empty_on_empty_input() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var pick: Dictionary = MonsterSpawnTable.choose_weighted([], rng)
	assert_true(pick.is_empty(),
		"пустой список eligible → пустой Dictionary, не крешит")

func test_choose_weighted_respects_weight_ratio() -> void:
	# Синтетические defs: {weight=90} и {weight=10}. За 1000 rolls ~90%
	# должны быть первый def. Допуск ±10% на дисперсию.
	var defs: Array = [
		{"id": "heavy", "weight": 90, "threat": 1, "tags": [], "room_tags": [], "scene": null,
			"min_floor": 1, "max_floor": 999, "level_offset_min": 0,
			"level_offset_max": 0, "elite_chance": 0.0},
		{"id": "light", "weight": 10, "threat": 1, "tags": [], "room_tags": [], "scene": null,
			"min_floor": 1, "max_floor": 999, "level_offset_min": 0,
			"level_offset_max": 0, "elite_chance": 0.0},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var heavy_count := 0
	for _i in 1000:
		var pick: Dictionary = MonsterSpawnTable.choose_weighted(defs, rng)
		if pick.id == "heavy":
			heavy_count += 1
	# 90% ± 5% = [850, 950]. Плюс запас на GDScript RNG variance.
	assert_between(heavy_count, 830, 970,
		"weight=90 vs weight=10 → ~90% выборов должны быть heavy")

func test_roll_monster_level_uses_floor_and_offset() -> void:
	var def := {
		"id": "test", "weight": 1, "threat": 1, "tags": [], "room_tags": [], "scene": null,
		"min_floor": 1, "max_floor": 999,
		"level_offset_min": -1, "level_offset_max": 1, "elite_chance": 0.0,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Прогоняем множество roll'ов — все должны быть в [floor+min_offset, floor+max_offset].
	for _i in 100:
		var level := MonsterSpawnTable.roll_monster_level(5, def, 0, rng)
		assert_gte(level, 4, "level >= floor + level_offset_min")
		assert_lte(level, 6, "level <= floor + level_offset_max")

func test_roll_monster_level_never_below_one() -> void:
	# Кейс с очень отрицательным offset и floor=1 → должен всё равно ≥1.
	var def := {
		"id": "test", "weight": 1, "threat": 1, "tags": [], "room_tags": [], "scene": null,
		"min_floor": 1, "max_floor": 999,
		"level_offset_min": -10, "level_offset_max": -5, "elite_chance": 0.0,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for _i in 20:
		var level := MonsterSpawnTable.roll_monster_level(1, def, 0, rng)
		assert_gte(level, 1, "level всегда >= 1")

func test_roll_monster_level_includes_room_danger() -> void:
	var def := {
		"id": "test", "weight": 1, "threat": 1, "tags": [], "room_tags": [], "scene": null,
		"min_floor": 1, "max_floor": 999,
		"level_offset_min": 0, "level_offset_max": 0, "elite_chance": 0.0,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	# fixed offset = 0, room_danger добавляет свой +N.
	var no_danger := MonsterSpawnTable.roll_monster_level(5, def, 0, rng)
	var with_danger := MonsterSpawnTable.roll_monster_level(5, def, 2, rng)
	assert_eq(no_danger, 5)
	assert_eq(with_danger, 7)

func test_roll_elite_rank_never_gives_elite_two_before_floor_ten() -> void:
	# Elite rank 2 требует floor >= 10 по нашей политике.
	var def := {
		"id": "test", "weight": 1, "threat": 1, "tags": [], "room_tags": [], "scene": null,
		"min_floor": 1, "max_floor": 999,
		"level_offset_min": 0, "level_offset_max": 0, "elite_chance": 1.0,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for f in [1, 3, 5, 7, 9]:
		for _i in 50:
			var rank := MonsterSpawnTable.roll_elite_rank(f, def, 0, rng)
			assert_ne(rank, 2, "elite rank 2 запрещён до floor 10 (floor=%d)" % f)

func test_get_eligible_defs_prefers_room_tags_when_matching() -> void:
	# Undead-комната на floor 7 отдаёт предпочтение undead defs.
	var undead_defs := MonsterSpawnTable.get_eligible_defs(7, ["undead"])
	var has_undead := false
	var non_undead_count := 0
	for def in undead_defs:
		if def.room_tags.has("undead"):
			has_undead = true
		else:
			non_undead_count += 1
	assert_true(has_undead,
		"undead room должен содержать хотя бы одного undead")
	assert_eq(non_undead_count, 0,
		"когда есть совпадение по room_tag, не-undead def не проходят")

func test_get_eligible_defs_falls_back_when_no_room_tag_match() -> void:
	# Специально несуществующий tag — должен упасть на floor-only список.
	var defs := MonsterSpawnTable.get_eligible_defs(1, ["nonexistent_theme"])
	assert_false(defs.is_empty(),
		"unknown room_tag → fallback на floor-only eligible list")
