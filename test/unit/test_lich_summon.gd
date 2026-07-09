extends GutTest

# Lich призывает одного скелета за раз.
# - первый призыв стартует сразу при спавне: `_summon_cooldown_timer`
#   инициализирован нулём, следующий physics-тик запускает каст;
# - пока миньон жив, новый не призывается;
# - как только миньон невалиден (queue_freed / удалён из дерева),
#   через SUMMON_COOLDOWN появляется следующий;
# - призванные скелеты не дают XP/gold и не роняют пикапы, иначе
#   лич превращается в фарм-точку.

const LichScene = preload("res://scenes/enemies/lich.tscn")

# Мок-этаж, притворяющийся Floor'ом в группе "floor". Держит
# настоящий AStarGrid2D, чтобы lich._pick_valid_spawn_position
# видел is_point_solid и рабочий is_in_boundsv.
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

func _spawn_lich():
	var lich = LichScene.instantiate()
	add_child_autofree(lich)
	return lich

func test_summon_cooldown_starts_at_zero_for_immediate_cast() -> void:
	# Лич — призыватель, и игроку это должно быть видно сразу. Стартовое
	# значение _summon_cooldown_timer = 0.0 → первый physics-тик тут же
	# запустит каст, скелет появится через SUMMON_CAST_DURATION.
	var lich = _spawn_lich()
	assert_null(lich._summoned_minion,
		"скелет ещё не заспавнен: между _ready и первым physics-тиком его нет")
	assert_eq(lich._summon_cooldown_timer, 0.0,
		"кулдаун стартует нулевым — каст запускается на первом же тике")
	assert_eq(lich._summon_cast_timer, 0.0,
		"каст ещё не стартовал — это делает _maybe_start_summon в _physics_process")

func test_first_physics_tick_starts_summon_cast() -> void:
	# Симулируем один physics-тик: _maybe_start_summon увидит cooldown = 0
	# и переведёт лича в каст-фазу.
	var lich = _spawn_lich()
	lich._maybe_start_summon(0.016)
	assert_almost_eq(lich._summon_cast_timer, lich.SUMMON_CAST_DURATION, 0.001,
		"первый же тик запускает каст первого скелета")

func test_summon_after_cooldown_starts_cast_not_immediate_spawn() -> void:
	# С добавлением каст-фазы _maybe_start_summon только СТАРТУЕТ каст,
	# сам скелет появляется только после _finish_cast (после
	# SUMMON_CAST_DURATION секунд tick_cast).
	var lich = _spawn_lich()
	lich._summon_cooldown_timer = 0.01
	lich._maybe_start_summon(0.05)
	assert_null(lich._summoned_minion,
		"после истечения кулдауна каст только СТАРТОВАЛ, скелета пока нет")
	assert_almost_eq(lich._summon_cast_timer, lich.SUMMON_CAST_DURATION, 0.001,
		"каст-таймер должен встать в полное значение")

func test_finish_cast_actually_spawns_skeleton() -> void:
	var lich = _spawn_lich()
	lich._summon_cooldown_timer = 0.01
	lich._maybe_start_summon(0.05)
	# Прокручиваем каст до конца через один _tick_cast с большим delta.
	lich._tick_cast(lich.SUMMON_CAST_DURATION + 0.1)
	assert_not_null(lich._summoned_minion,
		"после завершения каста скелет должен появиться")
	assert_almost_eq(lich._summon_cooldown_timer, lich.SUMMON_COOLDOWN, 0.001,
		"кулдаун сбрасывается на новую константу после успешного призыва")

func test_does_not_summon_while_minion_alive() -> void:
	var lich = _spawn_lich()
	# Форсируем «есть живой миньон» и обнуляем кулдаун — второй призыв
	# не должен случиться, каст не должен стартовать.
	var minion = Node2D.new()
	add_child_autofree(minion)
	lich._summoned_minion = minion
	lich._summon_cooldown_timer = 0.0
	lich._maybe_start_summon(0.05)
	assert_eq(lich._summoned_minion, minion,
		"при живом миньоне лич не призывает ещё одного")
	assert_eq(lich._summon_cast_timer, 0.0,
		"и не стартует каст")

func test_new_summon_after_minion_dies_plus_cooldown() -> void:
	var lich = _spawn_lich()
	var minion = Node2D.new()
	add_child_autofree(minion)
	lich._summoned_minion = minion
	minion.queue_free()
	await get_tree().process_frame  # даём queue_free сработать
	# Теперь _summoned_minion — freed reference; is_instance_valid = false.
	lich._summon_cooldown_timer = 0.0
	lich._maybe_start_summon(0.05)
	lich._tick_cast(lich.SUMMON_CAST_DURATION + 0.1)
	assert_not_null(lich._summoned_minion)
	assert_ne(lich._summoned_minion, minion,
		"после смерти миньона призывается НОВЫЙ, не тот же самый")

func test_summon_skips_when_all_surrounding_cells_are_solid() -> void:
	# Регресс: лич спавнил скелета в стене. Если все ближайшие
	# клетки в AStarGrid2D помечены solid — _summon_skeleton должен
	# вернуть false и НЕ трогать _summoned_minion, чтобы следующий
	# тик попробовал снова.
	var fake_floor := FakeFloor.new(200, 200, true)
	add_child_autofree(fake_floor)
	var lich = _spawn_lich()
	lich._summon_cooldown_timer = 0.0
	lich._maybe_start_summon(0.05)
	lich._tick_cast(lich.SUMMON_CAST_DURATION + 0.1)
	assert_null(lich._summoned_minion,
		"на этаже без свободных клеток скелет НЕ должен спавниться в стену")
	assert_lt(lich._summon_cooldown_timer, 0.0,
		"кулдаун остаётся отрицательным — следующий тик снова попробует")

func test_summon_succeeds_when_at_least_one_cell_is_free() -> void:
	# Инверт-кейс: solid_everywhere=false → все клетки walkable →
	# спавн должен пройти с первой попытки.
	var fake_floor := FakeFloor.new(200, 200, false)
	add_child_autofree(fake_floor)
	var lich = _spawn_lich()
	lich._summon_cooldown_timer = 0.0
	lich._maybe_start_summon(0.05)
	lich._tick_cast(lich.SUMMON_CAST_DURATION + 0.1)
	assert_not_null(lich._summoned_minion,
		"на пустом этаже лич должен призвать скелета")

func test_summon_position_biased_toward_player() -> void:
	# Когда игрок известен и весь этаж walkable, скелет должен
	# заспавниться ПО НАПРАВЛЕНИЮ к игроку. Проверяем что вектор от
	# лича к скелету имеет положительный dot-product с вектором к
	# игроку в 8+ из 10 попыток (arc ±50° → отклонения возможны, но
	# доминанта должна быть чёткой).
	var fake_floor := FakeFloor.new(200, 200, false)
	add_child_autofree(fake_floor)
	var player := Node2D.new()
	player.global_position = Vector2(300, 0)   # игрок справа от лича
	player.add_to_group("player")
	add_child_autofree(player)
	var toward_player_hits := 0
	for i in 10:
		var lich = _spawn_lich()
		lich.global_position = Vector2(100, 100)
		lich._target = player
		lich._summon_cooldown_timer = 0.0
		lich._maybe_start_summon(0.05)
		lich._tick_cast(lich.SUMMON_CAST_DURATION + 0.1)
		var minion = lich._summoned_minion
		assert_not_null(minion, "спавн должен пройти на пустом этаже")
		var to_minion: Vector2 = (minion.global_position - lich.global_position).normalized()
		var to_player: Vector2 = (player.global_position - lich.global_position).normalized()
		if to_minion.dot(to_player) > 0.2:
			toward_player_hits += 1
		minion.queue_free()
	assert_gte(toward_player_hits, 8,
		"минимум 8 из 10 спавнов в сторону игрока; получили %d" % toward_player_hits)

func test_summon_distance_within_bounds() -> void:
	# Проверяем что новый радиус SUMMON_OFFSET_MIN/MAX реально
	# ограничивает расстояние (миньон не появляется в 40+ px, как
	# раньше — «где-то там»).
	var fake_floor := FakeFloor.new(200, 200, false)
	add_child_autofree(fake_floor)
	var lich = _spawn_lich()
	lich.global_position = Vector2(100, 100)
	for i in 10:
		lich._summoned_minion = null
		lich._summon_cooldown_timer = 0.0
		lich._maybe_start_summon(0.05)
		lich._tick_cast(lich.SUMMON_CAST_DURATION + 0.1)
		var minion = lich._summoned_minion
		assert_not_null(minion)
		var dist: float = minion.global_position.distance_to(lich.global_position)
		assert_gte(dist, lich.SUMMON_OFFSET_MIN - 0.5,
			"миньон не ближе SUMMON_OFFSET_MIN: dist=%.1f" % dist)
		assert_lte(dist, lich.SUMMON_OFFSET_MAX + 0.5,
			"миньон не дальше SUMMON_OFFSET_MAX: dist=%.1f" % dist)
		minion.queue_free()

func test_summoned_skeleton_has_no_rewards() -> void:
	var lich = _spawn_lich()
	lich._summon_cooldown_timer = 0.0
	lich._maybe_start_summon(0.05)
	lich._tick_cast(lich.SUMMON_CAST_DURATION + 0.1)
	var minion = lich._summoned_minion
	assert_eq(minion.xp_reward, 0,
		"призванные скелеты не должны давать XP")
	assert_eq(minion.gold_reward, 0,
		"призванные скелеты не должны давать gold")
	assert_null(minion.pickup_scene,
		"призванные скелеты не должны ронять пикапы")
	# Убираем миньон вручную, чтобы не оставить в дереве.
	minion.queue_free()

func test_cast_visual_tints_lich_greenish() -> void:
	# Пока идёт каст, Visual.modulate должен уходить в зелёный.
	var lich = _spawn_lich()
	lich._summon_cast_timer = lich.SUMMON_CAST_DURATION * 0.5
	lich._apply_cast_visual()
	var visual: Sprite2D = lich.get_node("Visual")
	# Мы миксовали в CAST_TINT_COLOR = Color(0.7, 1.6, 0.85). Проверяем
	# что зелёный канал доминирует над красным (важно для читаемости).
	assert_gt(visual.modulate.g, visual.modulate.r,
		"во время каста зелёный доминирует: modulate = %s" % visual.modulate)

func test_cast_visual_resets_after_finish() -> void:
	var lich = _spawn_lich()
	lich._summon_cast_timer = 0.5
	lich._apply_cast_visual()
	# forced reset — как в _finish_cast.
	lich._reset_cast_visual()
	var visual: Sprite2D = lich.get_node("Visual")
	assert_eq(visual.modulate, lich._visual_base_modulate,
		"после каста modulate возвращается к базовому")
