extends GutTest

# Тесты системы темпераментов существ:
# - каталог: пять ID, девять пулов, весы, детерминизм;
# - применение: enemy.gd / ranged_enemy.gd / charger.gd;
# - override не перезаписывается random roll;
# - runtime-созданные существа получают темперамент через fallback seed;
# - босс исключён.

const SmallSlimeScene = preload("res://scenes/enemies/small_slime.tscn")
const AdultSlimeScene = preload("res://scenes/enemies/enemy.tscn")
const GoblinScene = preload("res://scenes/enemies/goblin.tscn")
const OrcScene = preload("res://scenes/enemies/orc.tscn")
const SkeletonScene = preload("res://scenes/enemies/skeleton.tscn")
const ZombieScene = preload("res://scenes/enemies/zombie.tscn")
const SpiderScene = preload("res://scenes/enemies/charger.tscn")
const ArcherScene = preload("res://scenes/enemies/ranged_enemy.tscn")
const LichScene = preload("res://scenes/enemies/lich.tscn")
const BossScene = preload("res://scenes/enemies/boss.tscn")

# Snapshot GameState — тесты меняют current_floor_number/tower_seed
# для fallback-сида; после каждого теста откатываем.
var _snapshot: Dictionary

func before_each() -> void:
	_snapshot = {
		"floor": GameState.current_floor_number,
		"tower_seed": GameState.tower_seed,
	}

func after_each() -> void:
	GameState.current_floor_number = _snapshot["floor"]
	GameState.tower_seed = _snapshot["tower_seed"]

# ---- Каталог -----------------------------------------------------------

func test_all_five_temperament_ids_are_known() -> void:
	for id in [
		CreatureTemperament.AGGRESSIVE,
		CreatureTemperament.CAUTIOUS,
		CreatureTemperament.PERSISTENT,
		CreatureTemperament.RESTLESS,
		CreatureTemperament.WATCHFUL,
	]:
		assert_true(CreatureTemperament.is_known(id),
			"каталог должен знать %s" % id)
	assert_eq(CreatureTemperament.ALL_IDS.size(), 5,
		"ALL_IDS содержит ровно 5 темпераментов")

func test_unknown_id_reports_not_known() -> void:
	assert_false(CreatureTemperament.is_known(&"berserk"))
	assert_false(CreatureTemperament.is_known(&""))

func test_all_nine_monsters_have_pool() -> void:
	for creature_type in [
		&"small_slime", &"adult_slime", &"goblin", &"orc", &"skeleton",
		&"zombie", &"spider", &"skeleton_archer", &"lich",
	]:
		assert_true(CreatureTemperament.has_pool(creature_type),
			"монстр %s должен иметь пул" % creature_type)
		var pool: Array = CreatureTemperament.POOLS[creature_type]
		assert_gt(pool.size(), 0, "пул %s не пуст" % creature_type)

func test_pool_entries_use_known_temperaments_and_positive_weights() -> void:
	for creature_type in CreatureTemperament.POOLS.keys():
		var pool: Array = CreatureTemperament.POOLS[creature_type]
		for entry in pool:
			var id: StringName = entry["id"]
			var weight: int = int(entry["weight"])
			assert_true(CreatureTemperament.is_known(id),
				"%s: неизвестный темперамент %s в пуле" % [creature_type, id])
			assert_gt(weight, 0,
				"%s: weight должен быть > 0, для %s = %d" % [creature_type, id, weight])

func test_pool_weights_sum_to_100() -> void:
	for creature_type in CreatureTemperament.POOLS.keys():
		var pool: Array = CreatureTemperament.POOLS[creature_type]
		var total := 0
		for entry in pool:
			total += int(entry["weight"])
		assert_eq(total, 100, "%s: сумма весов должна быть 100, получили %d" % [creature_type, total])

func test_same_seed_produces_same_roll_sequence() -> void:
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 42
	rng_b.seed = 42
	for _i in 20:
		var a := CreatureTemperament.roll_for(&"goblin", rng_a)
		var b := CreatureTemperament.roll_for(&"goblin", rng_b)
		assert_eq(a, b, "детерминизм по одному сиду нарушен")

func test_roll_never_returns_temperament_outside_pool() -> void:
	# Проверим все девять монстров, по 50 бросков — недостаточно для
	# полной статистики, но достаточно чтобы поймать «leak» темперамента
	# не из пула (например если catalog забыл сегментировать).
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for creature_type in CreatureTemperament.POOLS.keys():
		var pool_ids := {}
		for entry in CreatureTemperament.POOLS[creature_type]:
			pool_ids[entry["id"]] = true
		for _i in 50:
			var got: StringName = CreatureTemperament.roll_for(creature_type, rng)
			assert_true(pool_ids.has(got),
				"%s: получен %s, которого нет в пуле" % [creature_type, got])

func test_roll_for_unknown_type_returns_empty() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(CreatureTemperament.roll_for(&"", rng), &"")
	assert_eq(CreatureTemperament.roll_for(&"basilisk", rng), &"")

func test_resolve_id_preserves_valid_explicit_override() -> void:
	# Явно заданный валидный ID должен остаться нетронутым, независимо
	# от seed или пула.
	var got := CreatureTemperament.resolve_id(
		CreatureTemperament.PERSISTENT, &"goblin", 12345)
	assert_eq(got, CreatureTemperament.PERSISTENT,
		"валидный override должен быть сохранён без roll")

func test_resolve_id_rerolls_unknown_explicit_override() -> void:
	# «Bogus» ID сбрасывается и пул перебрасывается (не молча пропускается).
	var got := CreatureTemperament.resolve_id(&"bogus_id", &"goblin", 1)
	assert_ne(got, &"bogus_id", "'bogus_id' не должен молча применяться")
	# И результат — валидный из пула гоблина.
	var goblin_pool := {}
	for entry in CreatureTemperament.POOLS[&"goblin"]:
		goblin_pool[entry["id"]] = true
	assert_true(goblin_pool.has(got),
		"после сброса должен прийти валидный ID из пула goblin, получили %s" % got)

# ---- Сцены: правильный creature_type_id --------------------------------

func test_all_nine_scenes_have_correct_creature_type_id() -> void:
	var expected := {
		SmallSlimeScene: &"small_slime",
		AdultSlimeScene: &"adult_slime",
		GoblinScene: &"goblin",
		OrcScene: &"orc",
		SkeletonScene: &"skeleton",
		ZombieScene: &"zombie",
		SpiderScene: &"spider",
		ArcherScene: &"skeleton_archer",
		LichScene: &"lich",
	}
	for scene in expected.keys():
		var instance = scene.instantiate()
		assert_eq(instance.creature_type_id, expected[scene],
			"scene %s: creature_type_id != %s" % [scene.resource_path, expected[scene]])
		instance.free()

func test_all_nine_scenes_have_non_empty_temperament_after_ready() -> void:
	# После _ready() (add_child_autofree) каждый обычный монстр должен
	# получить темперамент через fallback-сид.
	for scene in [
		SmallSlimeScene, AdultSlimeScene, GoblinScene, OrcScene, SkeletonScene,
		ZombieScene, SpiderScene, ArcherScene, LichScene,
	]:
		var enemy = scene.instantiate()
		add_child_autofree(enemy)
		await get_tree().process_frame
		assert_ne(enemy.temperament_id, &"",
			"%s: temperament_id остался пустым после _ready()" % scene.resource_path)
		assert_true(CreatureTemperament.is_known(enemy.temperament_id),
			"%s: получил неизвестный %s" % [scene.resource_path, enemy.temperament_id])

func test_explicit_temperament_id_is_not_overwritten_by_roll() -> void:
	# Для трёх AI-семейств — melee/ranged/charger — проверяем override.
	# Явно задаём PERSISTENT (goblin, spider) и AGGRESSIVE (archer);
	# spider бы иначе никогда не получил PERSISTENT из пула — идеальный
	# способ увидеть что roll не сработал.
	var scenes := [
		[GoblinScene, CreatureTemperament.PERSISTENT],
		[SpiderScene, CreatureTemperament.PERSISTENT],
		[ArcherScene, CreatureTemperament.AGGRESSIVE],
	]
	for pair in scenes:
		var enemy = pair[0].instantiate()
		enemy.temperament_id = pair[1]
		add_child_autofree(enemy)
		await get_tree().process_frame
		assert_eq(enemy.temperament_id, pair[1],
			"%s: override должен сохраниться" % pair[0].resource_path)

func test_temperament_applied_only_once() -> void:
	# Двойная проверка guard'а: (1) флаг встаёт после _ready; (2) при
	# сохранённом флаге speed НЕ меняется; (3) при явном сбросе флага
	# повторный apply реально удвоит модификатор — это доказывает что
	# в шаге (2) именно guard остановил apply, а не «случайно тот же
	# результат».
	var enemy = OrcScene.instantiate()
	enemy.temperament_id = CreatureTemperament.AGGRESSIVE
	add_child_autofree(enemy)
	await get_tree().process_frame
	var speed_after_first: float = enemy.speed
	assert_true(enemy._temperament_applied,
		"после _ready флаг _temperament_applied должен быть true")
	# Guard стоит — второй apply не должен ничего сделать.
	enemy._apply_temperament()
	assert_almost_eq(enemy.speed, speed_after_first, 0.001,
		"с _temperament_applied=true повторный apply не двигает speed")
	# Обратная сторона: если flag reset'нуть — apply реально применит
	# модификатор ещё раз. Без этой проверки положительный результат
	# выше можно было бы получить и с полностью сломанным guard'ом,
	# если seed случайно давал тот же результат.
	enemy._temperament_applied = false
	enemy._apply_temperament()
	assert_almost_eq(enemy.speed, speed_after_first * 1.12, 0.01,
		"после reset _temperament_applied повторный apply должен умножить speed × 1.12")

# ---- Boss: не получает темперамент ------------------------------------

func test_boss_does_not_have_temperament_fields() -> void:
	# Boss.gd не наследуется от enemy.gd/ranged_enemy.gd/charger.gd,
	# поэтому у него не должно быть темперамент-полей. Это фиксирует что
	# босс явно исключён из системы.
	var boss = BossScene.instantiate()
	assert_null(boss.get("creature_type_id"),
		"босс не должен иметь creature_type_id")
	assert_null(boss.get("temperament_id"),
		"босс не должен иметь temperament_id")
	boss.free()

# ---- Модификаторы: melee ---------------------------------------------

func _spawn_with_temperament(scene: PackedScene, id: StringName) -> Node:
	var enemy = scene.instantiate()
	enemy.temperament_id = id
	add_child_autofree(enemy)
	return enemy

func test_aggressive_melee_speeds_up_and_shortens_cooldown() -> void:
	var base = OrcScene.instantiate()
	var base_speed: float = base.speed
	var base_cd: float = base.contact_cooldown
	base.free()
	var orc = _spawn_with_temperament(OrcScene, CreatureTemperament.AGGRESSIVE)
	await get_tree().process_frame
	assert_almost_eq(orc.speed, base_speed * 1.12, 0.01,
		"AGGRESSIVE melee: speed × 1.12")
	assert_almost_eq(orc.contact_cooldown, base_cd * 0.85, 0.01,
		"AGGRESSIVE melee: contact_cooldown × 0.85")

func test_aggressive_ranged_shortens_fire_interval_and_ranges() -> void:
	var base = ArcherScene.instantiate()
	var base_fire: float = base.fire_interval
	var base_speed: float = base.speed
	var base_pref: float = base.preferred_range
	var base_min: float = base.min_range
	base.free()
	var archer = _spawn_with_temperament(ArcherScene, CreatureTemperament.AGGRESSIVE)
	await get_tree().process_frame
	assert_almost_eq(archer.fire_interval, base_fire * 0.85, 0.01,
		"AGGRESSIVE ranged: fire_interval × 0.85")
	assert_almost_eq(archer.speed, base_speed * 1.08, 0.01,
		"AGGRESSIVE ranged: speed × 1.08")
	assert_almost_eq(archer.preferred_range, base_pref * 0.90, 0.1,
		"AGGRESSIVE ranged: preferred_range × 0.90")
	assert_almost_eq(archer.min_range, base_min * 0.90, 0.1,
		"AGGRESSIVE ranged: min_range × 0.90")

func test_aggressive_charger_shortens_wait_and_speeds_charge() -> void:
	var base = SpiderScene.instantiate()
	var base_wait: float = base.wait_duration
	var base_charge: float = base.charge_speed
	base.free()
	var spider = _spawn_with_temperament(SpiderScene, CreatureTemperament.AGGRESSIVE)
	await get_tree().process_frame
	assert_almost_eq(spider.wait_duration, base_wait * 0.80, 0.01,
		"AGGRESSIVE spider: wait_duration × 0.80")
	assert_almost_eq(spider.charge_speed, base_charge * 1.10, 0.1,
		"AGGRESSIVE spider: charge_speed × 1.10")

func test_persistent_raises_melee_memory_and_check_interval() -> void:
	var base = GoblinScene.instantiate()
	var base_check: float = base.memory_check_interval
	base.free()
	var goblin = _spawn_with_temperament(GoblinScene, CreatureTemperament.PERSISTENT)
	await get_tree().process_frame
	# memory поднимается до max(memory, 0.95) — гоблин имеет 0.55 в tscn.
	assert_almost_eq(goblin.memory, 0.95, 0.001,
		"PERSISTENT: memory поднимается минимум до 0.95")
	assert_almost_eq(goblin.memory_check_interval, base_check * 1.25, 0.01,
		"PERSISTENT: memory_check_interval × 1.25")

func test_restless_speeds_up_wander_and_shortens_interval_melee() -> void:
	var base = GoblinScene.instantiate()
	var base_ratio: float = base.wander_speed_ratio
	var base_interval: float = base.wander_change_interval
	base.free()
	var goblin = _spawn_with_temperament(GoblinScene, CreatureTemperament.RESTLESS)
	await get_tree().process_frame
	assert_almost_eq(goblin.wander_speed_ratio, minf(1.0, base_ratio * 1.35), 0.01,
		"RESTLESS melee: wander_speed_ratio × 1.35 (clamped)")
	assert_almost_eq(goblin.wander_change_interval, base_interval * 0.60, 0.01,
		"RESTLESS melee: wander_change_interval × 0.60")

func test_restless_charger_speeds_up_wander_speed() -> void:
	var base = SpiderScene.instantiate()
	var base_ws: float = base.wander_speed
	var base_interval: float = base.wander_change_interval
	base.free()
	var spider = _spawn_with_temperament(SpiderScene, CreatureTemperament.RESTLESS)
	await get_tree().process_frame
	assert_almost_eq(spider.wander_speed, base_ws * 1.35, 0.01,
		"RESTLESS spider: wander_speed × 1.35")
	assert_almost_eq(spider.wander_change_interval, base_interval * 0.60, 0.01,
		"RESTLESS spider: wander_change_interval × 0.60")

func test_watchful_increases_perception_for_all_families() -> void:
	# Все три семейства получают +30% perception и −20% wander.
	var configs := [
		[GoblinScene, "wander_speed_ratio", 0.80],
		[ArcherScene, "wander_speed_ratio", 0.80],
		[SpiderScene, "wander_speed", 0.80],
	]
	for cfg in configs:
		var scene: PackedScene = cfg[0]
		var wander_prop: String = cfg[1]
		var wander_mult: float = cfg[2]
		var base = scene.instantiate()
		var base_perception: float = base.perception_radius
		var base_wander: float = base.get(wander_prop)
		base.free()
		var enemy = _spawn_with_temperament(scene, CreatureTemperament.WATCHFUL)
		await get_tree().process_frame
		assert_almost_eq(enemy.perception_radius, base_perception * 1.30, 0.1,
			"%s WATCHFUL: perception × 1.30" % scene.resource_path)
		assert_almost_eq(enemy.get(wander_prop), base_wander * wander_mult, 0.01,
			"%s WATCHFUL: %s × %.2f" % [scene.resource_path, wander_prop, wander_mult])

# ---- CAUTIOUS: melee flee, ranged retreat -----------------------------

func test_cautious_melee_flees_when_hp_below_threshold() -> void:
	var goblin = _spawn_with_temperament(GoblinScene, CreatureTemperament.CAUTIOUS)
	await get_tree().process_frame
	# Сначала полное HP — не убегает.
	assert_false(goblin._is_fleeing, "полный HP: НЕ убегает")
	# Ниже 35% — переключается.
	goblin.health = int(goblin.max_health * 0.30)
	goblin._update_flee_state()
	assert_true(goblin._is_fleeing, "HP <= 35%%: должен убегать")

func test_cautious_melee_does_not_flee_above_threshold() -> void:
	var goblin = _spawn_with_temperament(GoblinScene, CreatureTemperament.CAUTIOUS)
	await get_tree().process_frame
	# Выше порога — не должен переключаться в flee.
	goblin.health = int(goblin.max_health * 0.60)
	goblin._update_flee_state()
	assert_false(goblin._is_fleeing, "HP > 35%%: НЕ убегает")

func test_cautious_flee_direction_is_away_from_player() -> void:
	var player := Node2D.new()
	player.global_position = Vector2(100, 0)
	player.add_to_group("player")
	add_child_autofree(player)
	var goblin = _spawn_with_temperament(GoblinScene, CreatureTemperament.CAUTIOUS)
	goblin.global_position = Vector2(50, 0)  # игрок справа
	await get_tree().process_frame
	goblin._target = player
	goblin._is_fleeing = true
	goblin._flee_from_target(0.016)
	# Убегаем ВЛЕВО от игрока — velocity.x < 0.
	assert_lt(goblin.velocity.x, 0.0,
		"flee: velocity должно быть направлено ОТ игрока (влево от центра)")

func test_cautious_flee_does_not_damage_player() -> void:
	# Гоблин с cautious не наносит контактного урона во время бегства.
	# Ставим player-шпиона с take_damage-счётчиком прямо в позицию гоблина
	# — если бы _flee_from_target вызвал _handle_player_contact, счётчик
	# бы инкрементировался. Проверяем оба сигнала: (1) счётчик нулевой,
	# (2) _contact_timer не запущен (второй уровень защиты).
	var player := _DamageSpyPlayer.new()
	player.global_position = Vector2(50, 0)
	player.add_to_group("player")
	add_child_autofree(player)
	var goblin = _spawn_with_temperament(GoblinScene, CreatureTemperament.CAUTIOUS)
	goblin.global_position = Vector2(50, 0)  # прямо в игроке
	await get_tree().process_frame
	goblin._target = player
	goblin._is_fleeing = true
	var contact_before: float = goblin._contact_timer
	goblin._flee_from_target(0.016)
	assert_eq(player.damage_calls, 0,
		"flee не должен наносить урон player-у")
	assert_eq(goblin._contact_timer, contact_before,
		"flee не должен запускать _contact_timer через _handle_player_contact")

# Player-шпион: считает вызовы take_damage. Реальный player.tscn избыточен
# для этого теста — нам нужен только контракт «есть take_damage и группа».
class _DamageSpyPlayer:
	extends Node2D
	var damage_calls: int = 0
	func take_damage(_amount: int) -> void:
		damage_calls += 1

func test_cautious_ranged_increases_ranges_and_retreat_multiplier() -> void:
	var base = ArcherScene.instantiate()
	var base_pref: float = base.preferred_range
	var base_min: float = base.min_range
	base.free()
	var archer = _spawn_with_temperament(ArcherScene, CreatureTemperament.CAUTIOUS)
	await get_tree().process_frame
	assert_almost_eq(archer.preferred_range, base_pref * 1.15, 0.1,
		"CAUTIOUS ranged: preferred_range × 1.15")
	assert_almost_eq(archer.min_range, base_min * 1.20, 0.1,
		"CAUTIOUS ranged: min_range × 1.20")
	assert_almost_eq(archer.retreat_speed_multiplier, 1.20, 0.001,
		"CAUTIOUS ranged: retreat_speed_multiplier = 1.20")

func test_cautious_ranged_retreat_uses_multiplier_at_close_range() -> void:
	# Игрок вплотную (dist < min_range) — velocity должна быть с
	# retreat_speed_multiplier. По умолчанию базовый archer: speed=30, min_range=100.
	# CAUTIOUS: min_range = 120, retreat_multiplier = 1.20.
	var player := Node2D.new()
	player.global_position = Vector2(50, 0)  # dist 50 < 120
	player.add_to_group("player")
	add_child_autofree(player)
	var archer = _spawn_with_temperament(ArcherScene, CreatureTemperament.CAUTIOUS)
	archer.global_position = Vector2.ZERO
	await get_tree().process_frame
	var effective_speed: float = archer.speed * archer.retreat_speed_multiplier
	archer._physics_process(0.016)
	# velocity направлено назад (влево, поскольку игрок справа) и по модулю
	# равен effective_speed.
	assert_almost_eq(archer.velocity.length(), effective_speed, 0.5,
		"CAUTIOUS ranged retreat: |velocity| = speed × retreat_multiplier")
	assert_lt(archer.velocity.x, 0.0, "retreat идёт от игрока")

func test_non_cautious_ranged_retreats_at_base_speed() -> void:
	# AGGRESSIVE archer тоже отступает при dist < min_range, но retreat_multiplier
	# у него 1.0 (default).
	var player := Node2D.new()
	player.global_position = Vector2(50, 0)
	player.add_to_group("player")
	add_child_autofree(player)
	var archer = _spawn_with_temperament(ArcherScene, CreatureTemperament.AGGRESSIVE)
	archer.global_position = Vector2.ZERO
	await get_tree().process_frame
	assert_almost_eq(archer.retreat_speed_multiplier, 1.0, 0.001,
		"AGGRESSIVE ranged: retreat_speed_multiplier должен остаться 1.0")

# ---- Runtime fallback + детерминизм ------------------------------------

func test_runtime_created_enemy_gets_fallback_temperament() -> void:
	# Runtime-созданный (без configure_spawn) должен получить темперамент
	# через fallback compute_fallback_seed(). Проверяем на каждом семействе.
	for scene in [GoblinScene, ArcherScene, SpiderScene]:
		var enemy = scene.instantiate()
		enemy.global_position = Vector2(123, 456)
		add_child_autofree(enemy)
		await get_tree().process_frame
		assert_ne(enemy.temperament_id, &"",
			"%s: runtime-created должен получить темперамент через fallback"
			% scene.resource_path)

func test_fallback_seed_deterministic_for_same_context() -> void:
	# Fallback стабилен: тот же tower_seed + floor + type + позиция →
	# один и тот же сид → один и тот же темперамент. Меняем tower_seed
	# на предсказуемый и проверяем идентичность.
	GameState.tower_seed = 7777
	GameState.current_floor_number = 3
	var s1 := CreatureTemperament.compute_fallback_seed(&"goblin", Vector2(100, 50))
	var s2 := CreatureTemperament.compute_fallback_seed(&"goblin", Vector2(100, 50))
	assert_eq(s1, s2, "fallback сид детерминирован при том же контексте")
	# Меняем один элемент — сид меняется.
	var s3 := CreatureTemperament.compute_fallback_seed(&"goblin", Vector2(101, 50))
	assert_ne(s1, s3, "разная позиция → разный сид")
	GameState.tower_seed = 8888
	var s4 := CreatureTemperament.compute_fallback_seed(&"goblin", Vector2(100, 50))
	assert_ne(s1, s4, "разный tower_seed → разный сид")

func test_main_spawn_temperament_is_deterministic_by_replay() -> void:
	# Реплицируем формулу Main._spawn_enemies (rng.seed = tower_seed×100003 +
	# floor×9176 + 1337) и проверяем: при одинаковых tower_seed×floor
	# последовательность creature_seed'ов повторяется.
	var expected := _replay_creature_seeds(555, 3, 10)
	var actual := _replay_creature_seeds(555, 3, 10)
	assert_eq(expected, actual,
		"одинаковый tower_seed×floor даёт ту же последовательность creature_seed'ов")

func _replay_creature_seeds(tower_seed: int, floor_num: int, count: int) -> Array:
	# Прямая копия последовательности вызовов из Main._spawn_enemies для
	# одной spawn-точки (get_eligible_defs + choose_weighted + roll_monster_level +
	# roll_elite_rank + randi для creature_seed). Тест не создаёт enemies —
	# только фиксирует что RNG-путь стабилен.
	var rng := RandomNumberGenerator.new()
	rng.seed = tower_seed * 100003 + floor_num * 9176 + 1337
	var seeds: Array = []
	for _i in count:
		var defs := MonsterSpawnTable.get_eligible_defs(floor_num, ["generic"])
		var def: Dictionary = MonsterSpawnTable.choose_weighted(defs, rng)
		if def.is_empty():
			continue
		MonsterSpawnTable.roll_monster_level(floor_num, def, 0, rng)
		MonsterSpawnTable.roll_elite_rank(floor_num, def, 0, rng)
		seeds.append(int(rng.randi()))
	return seeds
