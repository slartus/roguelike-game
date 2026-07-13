extends GutTest

# Integration-регресс: main.gd больше не использует ENEMY_SCENES.pick_random,
# а собирает врагов через MonsterSpawnTable. Полный main.tscn поднимать
# тяжело (Floor + Player + HUD + Camera + connections), поэтому проверяем
# кусочно:
# - в main.gd нет константы ENEMY_SCENES;
# - boss floor logic (BOSS_FLOOR_INTERVAL) сохранён и работает;
# - detem RNG-логика spawn'ится одинаково при одинаковом (tower_seed, floor).

const MAIN_SCRIPT: GDScript = preload("res://scenes/main.gd")

func _replay_spawn(tower_seed: int, floor_num: int, spawn_count: int) -> Array:
	# Реплицируем ту же RNG-формулу, что и в Main._spawn_enemies:
	# rng.seed = tower_seed × 100003 + floor × 9176 + 1337.
	# Возвращаем последовательность выбранных def.id для сравнения.
	var rng := RandomNumberGenerator.new()
	rng.seed = tower_seed * 100003 + floor_num * 9176 + 1337
	var out: Array = []
	for _i in spawn_count:
		var defs := MonsterSpawnTable.get_eligible_defs(floor_num, ["generic"])
		var def: Dictionary = MonsterSpawnTable.choose_weighted(defs, rng)
		if def.is_empty():
			continue
		var level := MonsterSpawnTable.roll_monster_level(floor_num, def, 0, rng)
		var elite := MonsterSpawnTable.roll_elite_rank(floor_num, def, 0, rng)
		out.append({"id": def.id, "level": level, "elite": elite})
	return out

func test_main_script_no_longer_declares_enemy_scenes_constant() -> void:
	# Раньше был массив ENEMY_SCENES с 8 врагами. Если он снова появится,
	# значит откатили MonsterSpawnTable интеграцию.
	assert_null(MAIN_SCRIPT.get("ENEMY_SCENES"),
		"ENEMY_SCENES должен быть удалён из main.gd — теперь через MonsterSpawnTable")

func test_main_script_delegates_boss_selection_to_registry() -> void:
	# После PR 1 hardcoded `BOSS_SCENE` и magic constant `BOSS_FLOOR_INTERVAL`
	# удалены из main.gd — выбор боссов идёт через BossRegistry (data-driven).
	# Если константы вернутся — значит откатили framework.
	assert_null(MAIN_SCRIPT.get("BOSS_SCENE"),
		"BOSS_SCENE должен быть удалён — теперь через BossRegistry")
	assert_null(MAIN_SCRIPT.get("BOSS_FLOOR_INTERVAL"),
		"BOSS_FLOOR_INTERVAL должен быть удалён — интервал определяет registry")
	# Sanity: registry действительно резолвит boss floor 5.
	assert_not_null(BossRegistry.definition_for_floor(5),
		"BossRegistry обязан вернуть definition для floor 5")

func test_floor_1_spawn_excludes_dangerous_enemies() -> void:
	# Регресс: Floor 1 не должен спавнить Adult Slime, Orc, Spider,
	# Zombie, Skeleton Archer, Lich — даже после нашей интеграции.
	var forbidden := ["adult_slime", "orc", "spider", "zombie", "skeleton_archer", "lich"]
	# Прогнать несколько seed'ов для устойчивости.
	for tower_seed in [123, 4567, 89012]:
		var picks := _replay_spawn(tower_seed, 1, 30)
		for pick in picks:
			assert_false(forbidden.has(pick.id),
				"Floor 1 seed=%d не должен спавнить %s" % [tower_seed, pick.id])

func test_spawn_deterministic_for_same_seed_and_floor() -> void:
	# Одинаковый seed + floor → одинаковая последовательность врагов и уровней.
	# Это критично для reproducible dungeon layouts.
	var picks_a := _replay_spawn(555, 7, 20)
	var picks_b := _replay_spawn(555, 7, 20)
	assert_eq(picks_a.size(), picks_b.size())
	for i in picks_a.size():
		assert_eq(picks_a[i].id, picks_b[i].id, "step %d id" % i)
		assert_eq(picks_a[i].level, picks_b[i].level, "step %d level" % i)
		assert_eq(picks_a[i].elite, picks_b[i].elite, "step %d elite" % i)

func test_different_seeds_generally_produce_different_spawn_sets() -> void:
	# Разные seed'ы не обязаны совпадать. Проверим что хотя бы один out
	# из 20 отличается — иначе это подозрительно (детерминизм превратился
	# в фиксированный ответ).
	var picks_a := _replay_spawn(111, 7, 20)
	var picks_b := _replay_spawn(999, 7, 20)
	var any_diff := false
	for i in mini(picks_a.size(), picks_b.size()):
		if picks_a[i].id != picks_b[i].id or picks_a[i].level != picks_b[i].level:
			any_diff = true
			break
	assert_true(any_diff,
		"разные seed'ы должны давать различающиеся спавны (проверка что RNG не залип)")
