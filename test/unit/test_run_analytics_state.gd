extends GutTest

# Тесты RunAnalyticsState — damage_history, weapon counters, enemy counters,
# economy, room tracking. Не пересекается с test_analytics_service (там
# — публичный API autoload'а). Здесь — сам класс counters.

const DAMAGE_LIMIT: int = 16

var _state: RunAnalyticsState

func before_each() -> void:
	_state = RunAnalyticsState.new()
	_state.start_run("test-run", 0)

func test_add_damage_taken_appends_to_history() -> void:
	var ctx := DamageContext.new()
	ctx.source_type = &"enemy"
	ctx.source_id = &"goblin"
	ctx.attack_id = &"contact"
	_state.add_damage_taken(2, ctx, 1000)
	assert_eq(_state.damage_history.size(), 1)
	assert_eq(_state.damage_history[0]["source_id"], "goblin")
	assert_eq(_state.damage_history[0]["damage"], 2)
	assert_eq(_state.damage_history[0]["ticks_ms"], 1000)

func test_damage_history_ring_buffer_caps_at_limit() -> void:
	var ctx := DamageContext.new()
	for i in range(DAMAGE_LIMIT + 5):
		_state.add_damage_taken(1, ctx, i * 100)
	assert_eq(_state.damage_history.size(), DAMAGE_LIMIT,
		"history is capped at DAMAGE_HISTORY_LIMIT")

func test_add_damage_taken_records_last_context() -> void:
	var ctx1 := DamageContext.new()
	ctx1.source_id = &"first"
	var ctx2 := DamageContext.new()
	ctx2.source_id = &"second"
	_state.add_damage_taken(1, ctx1, 100)
	_state.add_damage_taken(1, ctx2, 200)
	assert_eq(_state.last_damage_context.source_id, &"second",
		"last_damage_context reflects most recent")

func test_add_damage_taken_updates_enemy_damage_to_player() -> void:
	var ctx := DamageContext.new()
	ctx.source_type = &"enemy"
	ctx.source_id = &"spider"
	ctx.temperament_id = &"aggressive"
	ctx.elite_rank = 1
	_state.add_damage_taken(3, ctx, 500)
	_state.add_damage_taken(2, ctx, 700)
	var summaries := _state.floor_enemy_summaries()
	assert_eq(summaries.size(), 1)
	assert_eq(summaries[0]["damage_to_player"], 5)
	assert_eq(summaries[0]["hits_to_player"], 2)

func test_weapon_switch_finalizes_equipped_seconds() -> void:
	_state.switch_current_weapon(&"dagger", 0)
	_state.switch_current_weapon(&"spear", 5000)  # 5s later
	var summaries := _state.floor_weapon_summaries()
	# Dagger должен иметь equipped_seconds=5.
	var dagger_found := false
	for s in summaries:
		if s["weapon_id"] == "dagger":
			dagger_found = true
			assert_almost_eq(s["equipped_seconds"], 5.0, 0.01)
	assert_true(dagger_found)

func test_record_attack_increments_weapon_counter() -> void:
	_state.switch_current_weapon(&"short_bow", 0)
	_state.record_attack(&"")
	_state.record_attack(&"")
	_state.record_attack_hit(&"")
	var summaries := _state.floor_weapon_summaries()
	assert_eq(summaries[0]["attacks"], 2)
	assert_eq(summaries[0]["attacks_with_hit"], 1)
	# Инварианты BLOCKER 3: run-scope counters должны отражать те же
	# значения — иначе run_finished.weapon_totals не показывает реальные totals.
	var run_summaries := _state.run_weapon_summaries()
	assert_eq(run_summaries[0]["attacks"], 2)
	assert_eq(run_summaries[0]["attacks_with_hit"], 1)

func test_record_kill_and_damage_dealt_accumulate_in_run_totals() -> void:
	_state.switch_current_weapon(&"dagger", 0)
	_state.add_damage_dealt(3, &"", null)
	_state.add_damage_dealt(5, &"", null)
	_state.record_kill(&"", 0)
	var run_summaries := _state.run_weapon_summaries()
	assert_eq(run_summaries[0]["damage_dealt"], 8)
	assert_eq(run_summaries[0]["kills"], 1)
	assert_eq(run_summaries[0]["targets_hit"], 2)

func test_record_projectile_fired_and_hit() -> void:
	_state.switch_current_weapon(&"short_bow", 0)
	_state.record_projectile_fired(&"")
	_state.record_projectile_fired(&"")
	_state.record_projectile_fired(&"")
	_state.record_projectile_hit(&"")
	var summaries := _state.floor_weapon_summaries()
	assert_eq(summaries[0]["projectiles_fired"], 3)
	assert_eq(summaries[0]["projectiles_hit"], 1)

func test_record_kill_updates_weapon_kills() -> void:
	_state.switch_current_weapon(&"dagger", 0)
	_state.record_kill(&"", 0)
	_state.record_kill(&"dagger", 2)
	var summaries := _state.floor_weapon_summaries()
	assert_eq(summaries[0]["kills"], 2)
	assert_eq(summaries[0]["overkill_damage"], 2)

func test_record_enemy_spawned_creates_summary_row() -> void:
	_state.record_enemy_spawned(&"goblin", &"aggressive", 0)
	_state.record_enemy_spawned(&"goblin", &"aggressive", 0)
	_state.record_enemy_spawned(&"goblin", &"cautious", 0)
	var summaries := _state.floor_enemy_summaries()
	assert_eq(summaries.size(), 2, "different temperaments = separate rows")

func test_record_enemy_killed_increments_summary() -> void:
	_state.record_enemy_spawned(&"goblin", &"aggressive", 0)
	_state.record_enemy_killed(&"goblin", &"aggressive", 0)
	var summaries := _state.floor_enemy_summaries()
	assert_eq(summaries[0]["spawned"], 1)
	assert_eq(summaries[0]["killed"], 1)

func test_room_visit_returns_true_only_on_first() -> void:
	assert_true(_state.record_room_visit(&"room_1"))
	assert_false(_state.record_room_visit(&"room_1"), "second visit returns false")
	assert_true(_state.record_room_visit(&"room_2"))
	assert_eq(_state.rooms_visited_count, 2)

func test_start_floor_resets_floor_counters_but_keeps_run_totals() -> void:
	_state.switch_current_weapon(&"dagger", 0)
	_state.add_gold(10)
	_state.add_kill()
	_state.add_damage_dealt(5, &"", null)
	_state.record_enemy_spawned(&"goblin", &"", 0)
	_state.record_room_visit(&"room_1")

	_state.start_floor(2, 3000)

	assert_eq(_state.floor_gold_earned, 0)
	assert_eq(_state.floor_kills, 0)
	assert_eq(_state.floor_damage_dealt, 0)
	assert_eq(_state.rooms_visited_count, 0)
	assert_eq(_state.floor_enemy_counters.size(), 0)
	assert_eq(_state.floor_weapon_counters.size(), 1,
		"start_floor стартует новую сессию для текущего оружия")
	# Run-total сохраняется.
	assert_eq(_state.gold_earned_total, 10)
	assert_eq(_state.enemies_killed_total, 1)

func test_finalize_floor_weapon_time_commits_delta() -> void:
	_state.switch_current_weapon(&"dagger", 0)
	_state.finalize_floor_weapon_time(2000)
	var summaries := _state.floor_weapon_summaries()
	assert_almost_eq(summaries[0]["equipped_seconds"], 2.0, 0.01)
