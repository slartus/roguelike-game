extends GutTest

# Necromancer (босс) призывает батчем 5 скелетов с кулдауном 10s.
# После каст-фазы 1.2s топ-апит до SUMMON_COUNT — если убили не всех,
# спавнит только недостающих.

const BossScene = preload("res://scenes/enemies/boss.tscn")

class FakeFloor:
	extends Node2D
	var astar_grid: AStarGrid2D
	func _init(cols: int, rows: int, solid_everywhere: bool) -> void:
		astar_grid = AStarGrid2D.new()
		astar_grid.region = Rect2i(0, 0, cols, rows)
		astar_grid.cell_size = Vector2(20, 20)
		astar_grid.update()
		if solid_everywhere:
			for x in cols:
				for y in rows:
					astar_grid.set_point_solid(Vector2i(x, y), true)
	func _ready() -> void:
		add_to_group("floor")

func _spawn_boss():
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	return boss

func _spawn_player_and_floor():
	var f := FakeFloor.new(200, 200, false)
	add_child_autofree(f)
	var p := Node2D.new()
	p.global_position = Vector2(600, 100)
	p.add_to_group("player")
	add_child_autofree(p)

func test_boss_summons_full_batch_of_five_on_first_cast() -> void:
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss.global_position = Vector2(400, 400)
	boss._target = get_tree().get_first_node_in_group("player")
	# Форсируем истечение кулдауна и старт каста.
	boss._summon_cooldown_timer = 0.0
	boss._maybe_start_summon(0.05)
	assert_gt(boss._summon_cast_timer, 0.0, "каст должен стартовать")
	boss._tick_cast(boss.SUMMON_CAST_DURATION + 0.1)
	assert_eq(boss._minions.size(), boss.SUMMON_COUNT,
		"первый каст должен призвать полный батч из %d скелетов" % boss.SUMMON_COUNT)
	# Кулдаун сбрасывается на новую константу после успешного спавна.
	assert_almost_eq(boss._summon_cooldown_timer, boss.SUMMON_COOLDOWN, 0.001)

func test_boss_tops_up_partial_batch() -> void:
	# Если 3 миньона выжили — следующий каст доспавнит только 2,
	# не 5. Это удерживает популяцию на SUMMON_COUNT, а не растёт.
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss.global_position = Vector2(400, 400)
	boss._target = get_tree().get_first_node_in_group("player")
	# Пре-заполняем 3-мя fake-минионами.
	for i in 3:
		var fake := Node2D.new()
		add_child_autofree(fake)
		boss._minions.append(fake)
	boss._summon_cooldown_timer = 0.0
	boss._maybe_start_summon(0.05)
	boss._tick_cast(boss.SUMMON_CAST_DURATION + 0.1)
	assert_eq(boss._minions.size(), boss.SUMMON_COUNT,
		"после topping-up должно быть ровно SUMMON_COUNT миньонов")

func test_boss_skips_cast_if_already_full() -> void:
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss._target = get_tree().get_first_node_in_group("player")
	# Пре-заполняем полный комплект.
	for i in boss.SUMMON_COUNT:
		var fake := Node2D.new()
		add_child_autofree(fake)
		boss._minions.append(fake)
	boss._summon_cooldown_timer = 0.0
	boss._maybe_start_summon(0.05)
	assert_eq(boss._summon_cast_timer, 0.0,
		"при полном комплекте миньонов каст не должен стартовать")

func test_boss_cast_visual_tints_green() -> void:
	var boss = _spawn_boss()
	boss._summon_cast_timer = boss.SUMMON_CAST_DURATION * 0.5
	boss._apply_cast_visual()
	var visual: Sprite2D = boss.get_node("Visual")
	assert_gt(visual.modulate.g, visual.modulate.r,
		"во время каста зелёный доминирует над красным")
	boss._reset_cast_visual()
	assert_eq(visual.modulate, boss._visual_base_modulate,
		"после reset — базовый modulate")

func test_boss_summons_biased_toward_player() -> void:
	_spawn_player_and_floor()
	var player := get_tree().get_first_node_in_group("player")
	var boss = _spawn_boss()
	boss.global_position = Vector2(400, 100)  # игрок в (600, 100) — справа.
	boss._target = player
	boss._summon_cooldown_timer = 0.0
	boss._maybe_start_summon(0.05)
	boss._tick_cast(boss.SUMMON_CAST_DURATION + 0.1)
	var toward_player: Vector2 = (player.global_position - boss.global_position).normalized()
	var hits := 0
	for minion in boss._minions:
		var to_minion: Vector2 = (minion.global_position - boss.global_position).normalized()
		if to_minion.dot(toward_player) > 0.2:
			hits += 1
	assert_gte(hits, boss.SUMMON_COUNT - 1,
		"минимум %d из %d миньонов должны появиться в сторону игрока (получили %d)" %
		[boss.SUMMON_COUNT - 1, boss.SUMMON_COUNT, hits])