extends GutTest

# Necromancer — фазы по HP (PR 4). Плановые пороги:
#   phase 1 (100–60%) — только aimed + summon (радиального залпа НЕТ);
#   phase 2 (60–25%)  — добавляется radial_volley;
#   phase 3 (25–0%)   — cadence немного быстрее (aimed короче interval,
#                        summon короче cooldown), damage per hit не растёт.
# Каждый переход — visible PHASE_TRANSITION-стейт (scheduler на паузе),
# сигнал phase_changed эмиттится ровно один раз на порог.

const BossScene: PackedScene = preload("res://scenes/enemies/boss.tscn")
const NecromancerScript: Script = preload("res://scenes/enemies/necromancer.gd")

var _snapshot: Dictionary

func before_each() -> void:
	# take_damage(999) в тестах death дёргает `_handle_death` → award_xp/gold/
	# enemy_kill. Snapshot покрывает все поля, которые тесты могут задеть,
	# чтобы соседи в suite не увидели dirty state.
	_snapshot = {
		"floor": GameState.current_floor_number,
		"xp": GameState.player_xp,
		"gold": GameState.total_gold,
		"player_level": GameState.player_level,
		"player_max_health": GameState.player_max_health,
		"player_health": GameState.player_health,
		"pending_upgrade_levels": GameState.pending_upgrade_levels.duplicate(),
		"run_enemies_killed": GameState.run_enemies_killed,
		"run_gold": GameState.run_gold,
	}
	GameState.current_floor_number = 15

func after_each() -> void:
	GameState.current_floor_number = _snapshot["floor"]
	GameState.player_xp = _snapshot["xp"]
	GameState.total_gold = _snapshot["gold"]
	GameState.player_level = _snapshot["player_level"]
	GameState.player_max_health = _snapshot["player_max_health"]
	GameState.player_health = _snapshot["player_health"]
	GameState.pending_upgrade_levels = _snapshot["pending_upgrade_levels"]
	GameState.run_enemies_killed = _snapshot["run_enemies_killed"]
	GameState.run_gold = _snapshot["run_gold"]

func _spawn_boss() -> Node:
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	return boss

# --- Threshold values -----------------------------------------------------

func test_phase_two_threshold_is_sixty_percent() -> void:
	# Плановые границы: phase 2 при 60% HP.
	assert_almost_eq(NecromancerScript.PHASE_2_HP_FRACTION, 0.60, 0.001,
		"phase 2 threshold — 60% HP")

func test_phase_three_threshold_is_twenty_five_percent() -> void:
	# Плановые границы: phase 3 при 25% HP.
	assert_almost_eq(NecromancerScript.PHASE_3_HP_FRACTION, 0.25, 0.001,
		"phase 3 threshold — 25% HP")

func test_phase_for_health_fraction_maps_correctly() -> void:
	var boss = _spawn_boss()
	assert_eq(boss._phase_for_health_fraction(1.0), 1, "100% HP → phase 1")
	assert_eq(boss._phase_for_health_fraction(0.70), 1, "70% HP → phase 1")
	assert_eq(boss._phase_for_health_fraction(0.60), 2, "60% HP (пороговый) → phase 2")
	assert_eq(boss._phase_for_health_fraction(0.40), 2, "40% HP → phase 2")
	assert_eq(boss._phase_for_health_fraction(0.25), 3, "25% HP (пороговый) → phase 3")
	assert_eq(boss._phase_for_health_fraction(0.10), 3, "10% HP → phase 3")
	assert_eq(boss._phase_for_health_fraction(0.01), 3, "1% HP → phase 3")

# --- Phase 1: no radial ---------------------------------------------------

func test_phase_one_scheduler_never_picks_radial() -> void:
	# Плановый инвариант: в phase 1 radial недоступен даже если radial
	# cooldown готов. Только aimed + summon.
	var boss = _spawn_boss()
	boss._target = Node2D.new()
	add_child_autofree(boss._target)
	boss.current_phase = 1
	# Форсируем summon-квоту полной (иначе summon будет выбран первым)
	# и radial-cooldown готовым — scheduler всё равно не должен выбрать
	# radial в phase 1.
	for i in boss.SUMMON_MELEE_COUNT:
		var f := Node2D.new()
		add_child_autofree(f)
		boss._melee_minions.append(f)
	for i in boss.SUMMON_RANGED_COUNT:
		var f := Node2D.new()
		add_child_autofree(f)
		boss._ranged_minions.append(f)
	boss._radial_cooldown_timer = 0.0
	boss._aimed_cooldown_timer = 999.0  # aimed не готов
	boss._post_radial_pause_timer = 0.0
	assert_ne(boss._pick_next_action(), boss.ATTACK_RADIAL_VOLLEY,
		"phase 1 не должна выбирать radial даже при готовом cooldown'е")

func test_phase_two_scheduler_can_pick_radial() -> void:
	# С phase 2 radial доступен, если готов cooldown и нет post-radial gap.
	var boss = _spawn_boss()
	boss._target = Node2D.new()
	add_child_autofree(boss._target)
	boss.current_phase = 2
	for i in boss.SUMMON_MELEE_COUNT:
		var f := Node2D.new()
		add_child_autofree(f)
		boss._melee_minions.append(f)
	for i in boss.SUMMON_RANGED_COUNT:
		var f := Node2D.new()
		add_child_autofree(f)
		boss._ranged_minions.append(f)
	boss._radial_cooldown_timer = 0.0
	boss._aimed_cooldown_timer = 0.0
	boss._post_radial_pause_timer = 0.0
	assert_eq(boss._pick_next_action(), boss.ATTACK_RADIAL_VOLLEY,
		"phase 2 с готовым radial'ом должна выбрать именно его (приоритет над aimed)")

# --- take_damage: phase transitions --------------------------------------

func test_take_damage_crossing_sixty_percent_enters_phase_transition() -> void:
	var boss = _spawn_boss()
	watch_signals(boss)
	# HP чуть выше threshold'а, damage пробивает его.
	var target_hp: int = int(float(boss.max_health) * boss.PHASE_2_HP_FRACTION)
	var damage: int = boss.max_health - target_hp + 1
	@warning_ignore("redundant_await")
	await boss.take_damage(damage)
	assert_eq(int(boss._state), int(boss.State.PHASE_TRANSITION),
		"пересечение 60% threshold'а → PHASE_TRANSITION")
	# Прогоняем transition до конца.
	while boss._state == boss.State.PHASE_TRANSITION:
		boss._tick_phase_transition(0.1)
	assert_eq(boss.current_phase, 2, "после transition — phase = 2")
	assert_signal_emit_count(boss, "phase_changed", 1,
		"phase_changed эмиттится ровно 1 раз на переход")

func test_take_damage_crossing_twenty_five_percent_enters_phase_three() -> void:
	var boss = _spawn_boss()
	watch_signals(boss)
	# Начинаем сразу с phase 2 (то, куда попадаем при 60%); просаживаем HP
	# ниже 25% threshold'а.
	boss.current_phase = 2
	boss.health = int(float(boss.max_health) * boss.PHASE_2_HP_FRACTION)
	var target_hp: int = int(float(boss.max_health) * boss.PHASE_3_HP_FRACTION)
	var damage: int = boss.health - target_hp + 1
	@warning_ignore("redundant_await")
	await boss.take_damage(damage)
	assert_eq(int(boss._state), int(boss.State.PHASE_TRANSITION),
		"пересечение 25% threshold'а → PHASE_TRANSITION")
	while boss._state == boss.State.PHASE_TRANSITION:
		boss._tick_phase_transition(0.1)
	assert_eq(boss.current_phase, 3, "после второго transition — phase = 3")
	assert_signal_emit_count(boss, "phase_changed", 1,
		"phase_changed эмиттится ровно 1 раз на этот переход")

func test_phase_transition_dedupe_across_multiple_hits() -> void:
	# Multiple hits ниже threshold'а — phase_changed эмиттит один раз.
	var boss = _spawn_boss()
	watch_signals(boss)
	var health_at_threshold: int = roundi(float(boss.max_health) * boss.PHASE_2_HP_FRACTION)
	var damage_to_cross: int = boss.max_health - health_at_threshold + 1
	# Первый удар: пробивает threshold → PHASE_TRANSITION (sync-часть).
	@warning_ignore("redundant_await")
	await boss.take_damage(damage_to_cross)
	assert_eq(int(boss._state), int(boss.State.PHASE_TRANSITION),
		"первый удар ниже 60% запускает PHASE_TRANSITION")
	# Дополнительные удары внутри transition — не должны эмиттить второй раз.
	@warning_ignore("redundant_await")
	await boss.take_damage(1)
	@warning_ignore("redundant_await")
	await boss.take_damage(1)
	while boss._state == boss.State.PHASE_TRANSITION:
		boss._tick_phase_transition(0.1)
	assert_eq(boss.current_phase, 2, "phase = 2 после transition")
	assert_signal_emit_count(boss, "phase_changed", 1,
		"phase_changed эмиттится ровно 1 раз даже при множественных hit'ах")

# --- Summon cast window: boss doesn't shoot while casting -----------------

func test_no_projectile_starts_during_summon_cast() -> void:
	# Плановый инвариант: пока идёт SUMMON_CAST, aimed/radial не стартуют.
	var boss = _spawn_boss()
	boss._target = Node2D.new()
	add_child_autofree(boss._target)
	# Помещаем aimed и radial cooldown'ы в готовое состояние — сам факт
	# нахождения в SUMMON_CAST должен блокировать выбор.
	boss._aimed_cooldown_timer = 0.0
	boss._radial_cooldown_timer = 0.0
	boss.current_phase = 2
	boss._set_state(boss.State.SUMMON_CAST)
	watch_signals(boss)
	# Тикаем время cast'а. Никакой attack_started кроме уже стартовавшего
	# summon'а не должен эмиттиться.
	for i in 5:
		boss._tick_summon_cast(0.1)
	assert_signal_not_emitted(boss, "attack_started",
		"во время SUMMON_CAST aimed/radial не стартуют")

func test_no_attacks_start_during_phase_transition() -> void:
	var boss = _spawn_boss()
	boss._set_state(boss.State.PHASE_TRANSITION)
	watch_signals(boss)
	boss._tick_phase_transition(0.01)
	assert_signal_not_emitted(boss, "attack_started",
		"transition не запускает новую атаку")

# --- Cleanup on boss death ------------------------------------------------

func test_dead_state_bails_physics_process() -> void:
	# В DEAD state _physics_process возвращается сразу — никакие таймеры
	# не тикают, никакие атаки не стартуют. Это защита от race'а «boss
	# успел выбрать атаку на том же кадре, где ему прилетел killing blow».
	var boss = _spawn_boss()
	boss._target = Node2D.new()
	add_child_autofree(boss._target)
	# Форсируем DEAD state вручную (не через killing blow — иначе boss
	# уже queue_free'н и watch_signals не сработает нормально).
	boss._state = boss.State.DEAD
	boss._aimed_cooldown_timer = 0.0
	boss._radial_cooldown_timer = 0.0
	boss._summon_cooldown_timer = 0.0
	watch_signals(boss)
	boss._physics_process(0.1)
	boss._physics_process(0.5)
	assert_signal_not_emitted(boss, "attack_started",
		"в DEAD state scheduler заморожен — attack_started не эмиттится")

func test_killing_blow_marks_boss_as_dead_and_freed() -> void:
	# Плановый инвариант «cleanup on boss death»: killing blow приводит
	# к queue_free() босса. Ссылки на минионов остаются жить сами по себе —
	# они не считаются в _alive_enemies (см. main.gd), и добить их всё
	# ещё можно, но boss удалён и не спавнит новых.
	var boss = _spawn_boss()
	boss.health = 1
	@warning_ignore("redundant_await")
	await boss.take_damage(999)
	await get_tree().process_frame
	assert_false(is_instance_valid(boss),
		"после killing blow boss queue_free'н")
