extends GutTest

# Интеграционные тесты новых PR 2 API в Analytics autoload:
#  - weapon_equipped
#  - upgrade_offer_shown / upgrade_selected
#  - potion_used / potion_received / chest_opened
#  - room_first_entered
#  - floor summaries (weapon/enemy/economy) на finish_floor
#  - death attribution в run_finished
#
# Использует in-memory sink чтобы snapshot состояние без реального user://.

class InMemorySink extends AnalyticsSink:
	var events: Array = []
	func write_event(event: Dictionary) -> void:
		events.append(event)

var _snapshot_sink: AnalyticsSink
var _snapshot_enabled: bool
var _snapshot_tower_seed: int
var _snapshot_floor_number: int
var _sink: InMemorySink

func before_each() -> void:
	_snapshot_sink = Analytics._get_sink_for_testing()
	_snapshot_enabled = Analytics.is_enabled()
	_snapshot_tower_seed = GameState.tower_seed
	_snapshot_floor_number = GameState.current_floor_number
	_sink = InMemorySink.new()
	Analytics._set_sink_for_testing(_sink)
	Analytics._force_regenerate_ids_for_testing()

func after_each() -> void:
	Analytics._get_run_state_for_testing().reset()
	Analytics.set_enabled(_snapshot_enabled)
	Analytics._set_sink_for_testing(_snapshot_sink)
	GameState.tower_seed = _snapshot_tower_seed
	GameState.current_floor_number = _snapshot_floor_number

func _find_event(name: String) -> Dictionary:
	for e in _sink.events:
		if e["event_name"] == name:
			return e
	return {}

func _find_all_events(name: String) -> Array:
	var out: Array = []
	for e in _sink.events:
		if e["event_name"] == name:
			out.append(e)
	return out

# --- weapon_equipped -------------------------------------------------------

func test_weapon_equipped_emits_event() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	Analytics.record_weapon_equipped(&"dagger", &"", Analytics.WEAPON_SOURCE_STARTING)
	var event := _find_event("weapon_equipped")
	assert_false(event.is_empty())
	assert_eq(event["payload"]["weapon_id"], "dagger")
	assert_eq(event["payload"]["source"], "starting")

func test_weapon_switch_generates_two_events() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	Analytics.record_weapon_equipped(&"dagger", &"", Analytics.WEAPON_SOURCE_STARTING)
	Analytics.record_weapon_equipped(&"spear", &"dagger", Analytics.WEAPON_SOURCE_PICKUP)
	assert_eq(_find_all_events("weapon_equipped").size(), 2)
	var second := _find_all_events("weapon_equipped")[1]
	assert_eq(second["payload"]["weapon_id"], "spear")
	assert_eq(second["payload"]["previous_weapon_id"], "dagger")
	assert_eq(second["payload"]["source"], "pickup")

# --- upgrade offer/selected -----------------------------------------------

func test_upgrade_offer_shown_emits_full_context() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 3})
	Analytics.record_upgrade_offer_shown({
		"choice_level": 5,
		"current_weapon_id": "spear",
		"current_weapon_style": "warrior",
		"current_attack_type": "melee_thrust",
		"offered_ids": ["heavy_strike", "long_reach", "second_wind"],
		"offered_positions": {"heavy_strike": 0, "long_reach": 1, "second_wind": 2},
		"current_stacks": {"heavy_strike": 1},
		"player_health": 4,
		"player_max_health": 7,
	})
	var event := _find_event("upgrade_offer_shown")
	assert_false(event.is_empty())
	assert_eq(event["payload"]["choice_level"], 5)
	assert_eq(event["payload"]["current_weapon_id"], "spear")
	assert_eq((event["payload"]["offered_ids"] as Array).size(), 3)

func test_upgrade_selected_records_choice_time() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 3})
	Analytics.record_upgrade_offer_shown({"choice_level": 3})
	Analytics.record_upgrade_selected({
		"selected_id": "long_reach",
		"offer_position": 1,
		"stack_before": 0,
		"stack_after": 1,
	})
	var event := _find_event("upgrade_selected")
	assert_false(event.is_empty())
	assert_eq(event["payload"]["selected_id"], "long_reach")
	assert_eq(event["payload"]["offer_position"], 1)
	assert_eq(event["payload"]["stack_before"], 0)
	assert_eq(event["payload"]["stack_after"], 1)
	assert_true(event["payload"]["choice_time_seconds"] >= 0.0)

# --- potions ----------------------------------------------------------------

func test_potion_used_records_overheal() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	# health_before=5, max_health=6, heal_amount=3 → actual=1, overheal=2.
	Analytics.record_potion_used(5, 6, 3)
	var event := _find_event("potion_used")
	assert_false(event.is_empty())
	assert_eq(event["payload"]["actual_healed"], 1)
	assert_eq(event["payload"]["overheal"], 2)

func test_chest_opened_counts_in_economy() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	Analytics.record_chest_opened()
	Analytics.record_chest_opened()
	Analytics.finish_floor({})
	var summary := _find_event("floor_economy_summary")
	assert_false(summary.is_empty())
	assert_eq(summary["payload"]["chests_opened"], 2)

func test_gold_source_split_in_economy_summary() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	Analytics.record_gold_earned(5, &"enemy")
	Analytics.record_gold_earned(10, &"chest")
	Analytics.record_gold_earned(3, &"prop")
	Analytics.finish_floor({})
	var summary := _find_event("floor_economy_summary")
	assert_eq(summary["payload"]["gold_enemy"], 5)
	assert_eq(summary["payload"]["gold_chest"], 10)
	assert_eq(summary["payload"]["gold_props"], 3)
	assert_eq(summary["payload"]["gold_total"], 18)

# --- rooms ------------------------------------------------------------------

func test_room_first_entered_emits_once() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	Analytics.record_room_entered(&"room_1", {"role": "start"})
	Analytics.record_room_entered(&"room_1", {"role": "start"})
	assert_eq(_find_all_events("room_first_entered").size(), 1,
		"second visit does not emit")

func test_room_first_entered_payload() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 2})
	Analytics.record_room_entered(&"room_boss", {
		"role": "boss",
		"critical_path": true,
		"player_health": 3,
		"alive_enemies": 4,
		"reward_present": true,
	})
	var event := _find_event("room_first_entered")
	assert_eq(event["payload"]["room_id"], "room_boss")
	assert_eq(event["payload"]["role"], "boss")
	assert_true(event["payload"]["critical_path"])
	assert_eq(event["payload"]["player_health"], 3)

# --- floor summaries -------------------------------------------------------

func test_finish_floor_emits_all_summary_events() -> void:
	# start_run со starting_weapon_id триггерит первый weapon_equipped
	# автоматически — не нужно явно вызывать record_weapon_equipped.
	Analytics.start_run({"starting_weapon_id": "dagger"})
	Analytics.start_floor({"floor": 1})
	Analytics.record_enemy_spawned(&"goblin", &"aggressive", 0)
	Analytics.record_gold_earned(3, &"enemy")
	Analytics.finish_floor({})
	assert_false(_find_event("floor_completed").is_empty())
	assert_false(_find_event("floor_economy_summary").is_empty())
	assert_gt(_find_all_events("floor_weapon_summary").size(), 0)
	assert_gt(_find_all_events("floor_enemy_summary").size(), 0)

func test_start_run_with_starting_weapon_emits_weapon_equipped() -> void:
	Analytics.start_run({"starting_weapon_id": "short_sword"})
	var equipped_events := _find_all_events("weapon_equipped")
	assert_eq(equipped_events.size(), 1, "starting weapon triggers first equip event")
	assert_eq(equipped_events[0]["payload"]["weapon_id"], "short_sword")
	assert_eq(equipped_events[0]["payload"]["source"], "starting")

func test_starting_weapon_tracks_damage_taken_while_equipped() -> void:
	Analytics.start_run({"starting_weapon_id": "dagger"})
	Analytics.start_floor({"floor": 1})
	Analytics.record_damage_taken(3, null)
	Analytics.finish_floor({})
	var weapon_summaries := _find_all_events("floor_weapon_summary")
	assert_gt(weapon_summaries.size(), 0)
	var dagger_summary: Dictionary = {}
	for s in weapon_summaries:
		if s["payload"]["weapon_id"] == "dagger":
			dagger_summary = s
	assert_false(dagger_summary.is_empty(), "dagger должен быть в summaries")
	assert_eq(dagger_summary["payload"]["damage_taken_while_equipped"], 3)

# --- death attribution -----------------------------------------------------

func test_run_finished_death_includes_source_attribution() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 3})
	var ctx := DamageContext.new()
	ctx.source_type = &"enemy"
	ctx.source_id = &"spider"
	ctx.attack_id = &"charge"
	ctx.temperament_id = &"aggressive"
	ctx.elite_rank = 1
	Analytics.record_damage_taken(2, ctx)
	Analytics.finish_run({
		"reason": Analytics.RUN_END_DEATH,
		"floor_reached": 3,
		"player_level": 2,
	})
	var event := _find_event("run_finished")
	assert_false(event.is_empty())
	assert_eq(event["payload"]["death_source_type"], "enemy")
	assert_eq(event["payload"]["death_source_id"], "spider")
	assert_eq(event["payload"]["death_attack_id"], "charge")
	assert_eq(event["payload"]["death_source_temperament"], "aggressive")
	assert_eq(event["payload"]["death_source_elite_rank"], 1)

func test_run_finished_non_death_omits_death_attribution() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	Analytics.finish_run({"reason": Analytics.RUN_END_VICTORY})
	var event := _find_event("run_finished")
	assert_false(event.is_empty())
	assert_false(event["payload"].has("death_source_id"),
		"non-death runs omit death attribution")

func test_run_finished_includes_damage_history() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	var ctx := DamageContext.new()
	ctx.source_id = &"goblin"
	ctx.attack_id = &"contact"
	Analytics.record_damage_taken(1, ctx)
	Analytics.record_damage_taken(1, ctx)
	Analytics.finish_run({"reason": Analytics.RUN_END_DEATH})
	var event := _find_event("run_finished")
	var history: Array = event["payload"]["damage_history"]
	assert_eq(history.size(), 2)

func test_run_finished_includes_weapon_totals() -> void:
	Analytics.start_run({"starting_weapon_id": "dagger"})
	Analytics.start_floor({"floor": 1})
	Analytics.record_player_attack(&"dagger")
	Analytics.record_player_attack(&"dagger")
	Analytics.finish_run({"reason": Analytics.RUN_END_DEATH})
	var event := _find_event("run_finished")
	assert_true(event["payload"].has("weapon_totals"))
	var totals: Array = event["payload"]["weapon_totals"]
	assert_gt(totals.size(), 0)
	# BLOCKER 3: run_weapon_counters должны аккумулировать attacks.
	var dagger_total: Dictionary = {}
	for t in totals:
		if t["weapon_id"] == "dagger":
			dagger_total = t
	assert_eq(dagger_total["attacks"], 2, "run_weapon_counters аккумулируют attacks")

# --- floor_started expansion -----------------------------------------------

func test_floor_started_carries_layout_metrics() -> void:
	Analytics.start_run({})
	Analytics.start_floor({
		"floor": 4,
		"layout_archetype": "residential_spine",
		"zone": "residential",
		"room_count": 9,
		"enemy_count": 14,
		"chest_count": 2,
	})
	var event := _find_event("floor_started")
	assert_false(event.is_empty())
	assert_eq(event["payload"]["layout_archetype"], "residential_spine")
	assert_eq(event["payload"]["room_count"], 9)
	assert_eq(event["payload"]["enemy_count"], 14)
	assert_eq(event["payload"]["chest_count"], 2)
