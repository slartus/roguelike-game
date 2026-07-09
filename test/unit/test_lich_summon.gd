extends GutTest

# Lich призывает одного скелета за раз.
# - первый призыв — через SUMMON_COOLDOWN после спавна;
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

func test_no_immediate_summon_at_spawn() -> void:
	var lich = _spawn_lich()
	assert_null(lich._summoned_minion,
		"сразу после спавна лич ещё не призвал никого")
	assert_almost_eq(lich._summon_cooldown_timer, lich.SUMMON_COOLDOWN, 0.001,
		"кулдаун стартует полным")

func test_summon_after_cooldown_expires() -> void:
	var lich = _spawn_lich()
	lich._summon_cooldown_timer = 0.01
	lich._update_summon(0.05)
	assert_not_null(lich._summoned_minion,
		"по истечении кулдауна лич призывает скелета")
	assert_almost_eq(lich._summon_cooldown_timer, lich.SUMMON_COOLDOWN, 0.001,
		"кулдаун сбрасывается на новую константу после призыва")

func test_does_not_summon_while_minion_alive() -> void:
	var lich = _spawn_lich()
	# Форсируем «есть живой миньон» и обнуляем кулдаун — второй призыв
	# не должен случиться.
	var minion = Node2D.new()
	add_child_autofree(minion)
	lich._summoned_minion = minion
	lich._summon_cooldown_timer = 0.0
	lich._update_summon(0.05)
	# Ссылка не поменялась — второй скелет не заспавнен.
	assert_eq(lich._summoned_minion, minion,
		"при живом миньоне лич не призывает ещё одного")

func test_new_summon_after_minion_dies_plus_cooldown() -> void:
	var lich = _spawn_lich()
	var minion = Node2D.new()
	add_child_autofree(minion)
	lich._summoned_minion = minion
	minion.queue_free()
	await get_tree().process_frame  # даём queue_free сработать
	# Теперь _summoned_minion — freed reference; is_instance_valid = false.
	lich._summon_cooldown_timer = 0.0
	lich._update_summon(0.05)
	# Ссылка обновилась на новую живую ноду.
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
	lich._update_summon(0.05)
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
	lich._update_summon(0.05)
	assert_not_null(lich._summoned_minion,
		"на пустом этаже лич должен призвать скелета")

func test_summoned_skeleton_has_no_rewards() -> void:
	var lich = _spawn_lich()
	lich._summon_cooldown_timer = 0.0
	lich._update_summon(0.05)
	var minion = lich._summoned_minion
	assert_eq(minion.xp_reward, 0,
		"призванные скелеты не должны давать XP")
	assert_eq(minion.gold_reward, 0,
		"призванные скелеты не должны давать gold")
	assert_null(minion.pickup_scene,
		"призванные скелеты не должны ронять пикапы")
	# Убираем миньон вручную, чтобы не оставить в дереве.
	minion.queue_free()
