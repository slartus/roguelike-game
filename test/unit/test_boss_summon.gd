extends GutTest

# Necromancer (босс) призывает свиту в фиксированной композиции
# 3 melee + 2 archer. После PR 4 summon встроен в scheduler-state-machine:
# APPROACH → SUMMON_CAST (1.2 s) → SUMMON_RECOVERY (0.5 s) → APPROACH.
# Кулдаун phase 1/2 = 10 s, phase 3 = 7.5 s. Топ-ап раздельный по ролям
# (см. plans/necromancer-minion-rebalance + plans/boss-roadmap PR 4).

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

var _game_state_snapshot: Dictionary

func before_each() -> void:
	# Тесты форсируют boss floor 15 (Necromancer), чтобы scaling считался
	# от нужного этажа. Snapshot восстанавливаем в after_each.
	_game_state_snapshot = {"floor": GameState.current_floor_number}
	GameState.current_floor_number = 15

func after_each() -> void:
	GameState.current_floor_number = _game_state_snapshot["floor"]

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

func test_boss_summon_cooldown_starts_at_zero_for_immediate_cast() -> void:
	# Босс — призыватель, роль должна читаться сразу. `_summon_cooldown_timer`
	# инициализирован нулём → первый APPROACH-тик тут же запустит каст свиты.
	var boss = _spawn_boss()
	assert_eq(boss._summon_cooldown_timer, 0.0,
		"кулдаун стартует нулевым — каст свиты стартует на первом же APPROACH-тике")
	assert_eq(int(boss._state), int(boss.State.IDLE),
		"босс стартует в IDLE (нет цели); в SUMMON_CAST перейдёт при первом APPROACH-выборе")
	assert_eq(boss._melee_minions.size(), 0,
		"melee-миньонов пока нет: скелеты появятся после SUMMON_CAST_DURATION")
	assert_eq(boss._ranged_minions.size(), 0,
		"ranged-миньонов пока нет: лучники появятся после SUMMON_CAST_DURATION")

func test_boss_summons_full_batch_of_five_on_first_cast() -> void:
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss.global_position = Vector2(400, 400)
	boss._target = get_tree().get_first_node_in_group("player")
	# Форсируем переход в APPROACH — scheduler выберет summon (первая
	# доступная атака при пустой свите и нулевом cooldown'е).
	boss._set_state(boss.State.APPROACH)
	boss._tick_approach(0.05)
	assert_eq(int(boss._state), int(boss.State.SUMMON_CAST),
		"scheduler должен выбрать summon как первую атаку")
	# Прогоняем cast до конца — spawn происходит в _finish_cast.
	boss._tick_summon_cast(boss.SUMMON_CAST_DURATION + 0.1)
	assert_eq(boss._melee_minions.size(), boss.SUMMON_MELEE_COUNT,
		"первый каст должен призвать %d melee-скелетов" % boss.SUMMON_MELEE_COUNT)
	assert_eq(boss._ranged_minions.size(), boss.SUMMON_RANGED_COUNT,
		"первый каст должен призвать %d ranged-лучников" % boss.SUMMON_RANGED_COUNT)
	assert_eq(boss._total_alive_minions(), boss.SUMMON_COUNT,
		"общее число миньонов = melee + ranged = %d" % boss.SUMMON_COUNT)
	# Кулдаун сбрасывается на phase 1/2 константу после успешного спавна.
	assert_almost_eq(boss._summon_cooldown_timer, boss.SUMMON_COOLDOWN_PHASE12, 0.001)
	# После завершения cast'а босс уходит в SUMMON_RECOVERY, не в APPROACH.
	assert_eq(int(boss._state), int(boss.State.SUMMON_RECOVERY),
		"после _finish_cast босс переходит в SUMMON_RECOVERY (0.5 s)")

func test_boss_tops_up_missing_melee_only_when_ranged_full() -> void:
	# Если 3 melee убиты, а 2 ranged живы — следующий каст доспавнит
	# только 3 melee. Не «5 недостающих», не «случайный микс». Каждая
	# роль пополняется по своей квоте.
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss.global_position = Vector2(400, 400)
	boss._target = get_tree().get_first_node_in_group("player")
	# Пре-заполняем 2 fake-ranged'а.
	for i in boss.SUMMON_RANGED_COUNT:
		var fake := Node2D.new()
		add_child_autofree(fake)
		boss._ranged_minions.append(fake)
	var spawned: int = boss._summon_batch()
	assert_eq(spawned, boss.SUMMON_MELEE_COUNT,
		"должно быть добавлено ровно %d melee'ев" % boss.SUMMON_MELEE_COUNT)
	assert_eq(boss._melee_minions.size(), boss.SUMMON_MELEE_COUNT,
		"melee квота восстановилась до %d" % boss.SUMMON_MELEE_COUNT)
	assert_eq(boss._ranged_minions.size(), boss.SUMMON_RANGED_COUNT,
		"ranged квота не превышена: как было 2, так и осталось 2")

func test_boss_skips_summon_action_if_all_quotas_full() -> void:
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	boss._target = get_tree().get_first_node_in_group("player")
	# Пре-заполняем полный комплект по обеим ролям.
	for i in boss.SUMMON_MELEE_COUNT:
		var fake := Node2D.new()
		add_child_autofree(fake)
		boss._melee_minions.append(fake)
	for i in boss.SUMMON_RANGED_COUNT:
		var fake := Node2D.new()
		add_child_autofree(fake)
		boss._ranged_minions.append(fake)
	boss._summon_cooldown_timer = 0.0
	# Scheduler не должен выбрать summon при полных квотах.
	assert_ne(boss._pick_next_action(), boss.ATTACK_SUMMON_MINIONS,
		"при полной свите scheduler не выбирает summon")

func test_boss_cast_visual_tints_green() -> void:
	var boss = _spawn_boss()
	boss._set_state(boss.State.SUMMON_CAST)
	boss._state_timer = boss.SUMMON_CAST_DURATION * 0.5
	boss._apply_cast_visual()
	var visual: Sprite2D = boss.get_node("Visual")
	assert_gt(visual.modulate.g, visual.modulate.r,
		"во время каста зелёный доминирует над красным")
	boss._reset_cast_visual()
	assert_eq(visual.modulate, boss._visual_base_modulate,
		"после reset — базовый modulate")

func test_boss_cleanup_removes_freed_minions_from_role_lists() -> void:
	# Когда скелеты queue_free()'нулись между кастами, _cleanup_minions
	# должен вычистить invalid ссылки из ОБЕИХ role-list'ов, иначе
	# _total_alive_minions() перекрутит и scheduler'у покажется, что
	# квоты полные, и следующий каст никогда не стартует.
	_spawn_player_and_floor()
	var boss = _spawn_boss()
	var dead_melee := Node2D.new()
	var dead_ranged := Node2D.new()
	boss._melee_minions.append(dead_melee)
	boss._ranged_minions.append(dead_ranged)
	dead_melee.free()
	dead_ranged.free()
	boss._cleanup_minions()
	assert_eq(boss._melee_minions.size(), 0,
		"melee list должен очиститься от freed nodes")
	assert_eq(boss._ranged_minions.size(), 0,
		"ranged list должен очиститься от freed nodes")

func test_summon_cooldown_shortens_in_phase_three() -> void:
	# Плановый инвариант: в phase 3 summon cooldown немного короче
	# (нарастающее давление), но композиция 3+2 не расширяется.
	var boss = _spawn_boss()
	boss.current_phase = 3
	assert_almost_eq(boss._summon_cooldown_for_phase(), boss.SUMMON_COOLDOWN_PHASE3, 0.001,
		"phase 3 использует более короткий cooldown")
	assert_lt(boss.SUMMON_COOLDOWN_PHASE3, boss.SUMMON_COOLDOWN_PHASE12,
		"phase 3 cooldown < phase 1/2 cooldown")
	# Композиция не меняется по фазе.
	assert_eq(boss.SUMMON_MELEE_COUNT, 3, "phase 3 не увеличивает melee count")
	assert_eq(boss.SUMMON_RANGED_COUNT, 2, "phase 3 не увеличивает ranged count")
