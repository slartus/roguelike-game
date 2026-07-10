extends GutTest

# Слайм почкуется при первой аграции:
# - переход WANDER→CHASE запускает BUD_DELAY-таймер;
# - по истечении спавнится ещё один слайм у родителя (в scene tree);
# - каждый слайм почкуется максимум один раз (`_has_budded`);
# - без Floor валидация клетки пропускается, но спавн всё равно
#   проходит — тесты живут без dungeon.

const SlimeScene = preload("res://scenes/enemies/enemy.tscn")

# Мок-этаж, как в test_lich_summon.gd. Держит AStarGrid2D, чтобы
# _is_bud_walkable мог опрашивать is_point_solid.
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

func _spawn_slime():
	var slime = SlimeScene.instantiate()
	add_child_autofree(slime)
	return slime

func _count_slimes_under(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child.is_in_group("enemy"):
			n += 1
	return n

func test_bud_delay_not_started_before_aggro() -> void:
	var slime = _spawn_slime()
	await get_tree().process_frame
	assert_eq(slime._has_budded, false, "почкования ещё не было")
	assert_eq(slime._bud_delay_timer, 0.0, "таймер не тикает пока WANDER")

func test_transition_to_chase_starts_bud_timer() -> void:
	var slime = _spawn_slime()
	await get_tree().process_frame
	slime._state = slime.State.CHASE
	slime._tick_bud(0.01)
	assert_almost_eq(slime._bud_delay_timer, slime.BUD_DELAY - 0.01, 0.001,
		"фронт WANDER→CHASE должен взвести BUD_DELAY-таймер")

func test_second_aggro_within_delay_does_not_restart_timer() -> void:
	var slime = _spawn_slime()
	await get_tree().process_frame
	slime._state = slime.State.CHASE
	slime._tick_bud(0.1)
	var after_first: float = slime._bud_delay_timer
	# Сбрасываем и заново агримся до истечения таймера — таймер должен
	# продолжить тикать, а не рестартовать.
	slime._state = slime.State.WANDER
	slime._tick_bud(0.1)
	slime._state = slime.State.CHASE
	slime._tick_bud(0.1)
	assert_lt(slime._bud_delay_timer, after_first,
		"второй фронт до истечения не должен рестартовать таймер")

func test_bud_spawns_after_delay_and_sets_flag() -> void:
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	var before := _count_slimes_under(parent)
	await get_tree().process_frame
	slime._state = slime.State.CHASE
	slime._tick_bud(0.01)
	# Прокручиваем таймер за одну большую дельту.
	slime._tick_bud(slime.BUD_DELAY + 0.1)
	assert_true(slime._has_budded,
		"после истечения таймера флаг _has_budded должен встать")
	assert_eq(_count_slimes_under(parent), before + 1,
		"должен появиться ровно один новый слайм")

func test_each_slime_buds_only_once() -> void:
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	await get_tree().process_frame
	slime._state = slime.State.CHASE
	slime._tick_bud(0.01)
	slime._tick_bud(slime.BUD_DELAY + 0.1)
	var after_first := _count_slimes_under(parent)
	# Второй «агра-цикл» после WANDER — почкования уже не должно быть.
	slime._state = slime.State.WANDER
	slime._tick_bud(0.1)
	slime._state = slime.State.CHASE
	slime._tick_bud(slime.BUD_DELAY + 0.1)
	assert_eq(_count_slimes_under(parent), after_first,
		"второй агра-цикл не должен породить ещё одну почку")

func test_bud_position_within_offset_bounds() -> void:
	var slime = _spawn_slime()
	slime.global_position = Vector2(100, 100)
	var parent := slime.get_parent()
	var before_children := parent.get_children()
	await get_tree().process_frame
	slime._state = slime.State.CHASE
	slime._tick_bud(0.01)
	slime._tick_bud(slime.BUD_DELAY + 0.1)
	# Ищем новорождённого — это единственный новый child.
	var bud: Node2D = null
	for child in parent.get_children():
		if child == slime:
			continue
		if child in before_children:
			continue
		if child.is_in_group("enemy"):
			bud = child
			break
	assert_not_null(bud, "почка должна появиться как дочка родительской ноды")
	var dist: float = bud.global_position.distance_to(slime.global_position)
	# Без Floor валидация пропускается, offset = случайный вектор в
	# кольце [BUD_OFFSET_MIN, BUD_OFFSET_MAX].
	assert_gte(dist, slime.BUD_OFFSET_MIN - 0.5)
	assert_lte(dist, slime.BUD_OFFSET_MAX + 0.5)

func test_bud_not_spawned_when_all_cells_solid() -> void:
	# Регресс: слайм-мать не должна плодить почку внутри стены.
	# При solid_everywhere все BUD_SPAWN_ATTEMPTS попыток провалятся →
	# _spawn_bud вернёт false, _has_budded остаётся false.
	var fake_floor := FakeFloor.new(200, 200, true)
	add_child_autofree(fake_floor)
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	var before := _count_slimes_under(parent)
	await get_tree().process_frame
	slime._state = slime.State.CHASE
	slime._tick_bud(0.01)
	slime._tick_bud(slime.BUD_DELAY + 0.1)
	assert_eq(_count_slimes_under(parent), before,
		"на этаже без свободных клеток почка не должна появиться")
	assert_eq(slime._has_budded, false,
		"флаг _has_budded остаётся false — попытка провалилась")

func test_bud_spawned_when_at_least_one_cell_walkable() -> void:
	var fake_floor := FakeFloor.new(200, 200, false)
	add_child_autofree(fake_floor)
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	var before := _count_slimes_under(parent)
	await get_tree().process_frame
	slime._state = slime.State.CHASE
	slime._tick_bud(0.01)
	slime._tick_bud(slime.BUD_DELAY + 0.1)
	assert_eq(_count_slimes_under(parent), before + 1,
		"на пустом этаже почка должна появиться")
	assert_true(slime._has_budded)

func test_child_bud_is_small_slime_and_cannot_bud() -> void:
	# Почка Adult Slime — это Small Slime (bud_scene = small_slime.tscn).
	# У Small Slime can_bud=false, поэтому цепь остаётся конечной.
	var slime = _spawn_slime()
	await get_tree().process_frame
	slime._state = slime.State.CHASE
	slime._tick_bud(0.01)
	slime._tick_bud(slime.BUD_DELAY + 0.1)
	assert_true(slime._has_budded)
	# Ищем почку и проверяем её флаги.
	var parent := slime.get_parent()
	var bud: Node = null
	for child in parent.get_children():
		if child == slime:
			continue
		if child.is_in_group("enemy") and child.has_method("_tick_bud"):
			bud = child
			break
	assert_not_null(bud)
	assert_eq(bud.can_bud, false,
		"почка = Small Slime, она сама не почкуется")
	assert_eq(bud.can_split_on_death, false,
		"почка = Small Slime, она не распадается при смерти")
