extends GutTest

# Тесты autoload'а Analytics: session/run/floor lifecycle, sink switching,
# disabled mode, safe fallback при sink failure.
#
# Analytics — global autoload, поэтому snapshot/restore обязателен.
# Установка in-memory sink через _set_sink_for_testing изолирует записи
# от реального user://analytics/*.jsonl.

class InMemorySink extends AnalyticsSink:
	var events: Array = []
	var flush_count: int = 0
	var close_count: int = 0
	var broken: bool = false

	func write_event(event: Dictionary) -> void:
		events.append(event)

	func flush() -> void:
		flush_count += 1

	func close() -> void:
		close_count += 1

	func is_broken() -> bool:
		return broken

class BrokenSink extends AnalyticsSink:
	var events: Array = []

	func write_event(event: Dictionary) -> void:
		events.append(event)

	func is_broken() -> bool:
		return true

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
	# Восстанавливаем enabled флаг ДО set_sink, потому что set_enabled(true)
	# внутри создаёт новый JsonlAnalyticsSink и стирает наш переопределённый.
	Analytics.set_enabled(_snapshot_enabled)
	Analytics._set_sink_for_testing(_snapshot_sink)
	GameState.tower_seed = _snapshot_tower_seed
	GameState.current_floor_number = _snapshot_floor_number

func _last_event_name() -> String:
	if _sink.events.is_empty():
		return ""
	return _sink.events.back()["event_name"]

func test_session_started_emits_event() -> void:
	Analytics.start_session()
	assert_eq(_sink.events.size(), 1)
	assert_eq(_sink.events[0]["event_name"], "session_started")
	assert_true(_sink.events[0]["payload"].has("debug_build"))

func test_session_started_is_idempotent() -> void:
	Analytics.start_session()
	Analytics.start_session()
	assert_eq(_sink.events.size(), 1, "duplicate start_session ignored")

func test_end_session_emits_finished_with_reason() -> void:
	Analytics.start_session()
	Analytics.end_session(Analytics.SESSION_END_QUIT_TO_MENU)
	assert_eq(_last_event_name(), "session_finished")
	assert_eq(_sink.events.back()["payload"]["reason"], "quit_to_menu")

func test_end_session_without_start_does_nothing() -> void:
	Analytics.end_session(Analytics.SESSION_END_NORMAL)
	assert_eq(_sink.events.size(), 0)

func test_start_run_emits_event_and_returns_run_id() -> void:
	var run_id := Analytics.start_run({
		"starting_weapon_id": "dagger",
		"starting_max_health": 5,
		"starting_level": 1,
	})
	assert_ne(run_id, "")
	assert_eq(_sink.events.size(), 1)
	assert_eq(_sink.events[0]["event_name"], "run_started")
	assert_eq(_sink.events[0]["payload"]["starting_weapon_id"], "dagger")

func test_run_id_changes_between_runs() -> void:
	var run1 := Analytics.start_run({})
	Analytics.finish_run({"reason": Analytics.RUN_END_DEATH})
	var run2 := Analytics.start_run({})
	assert_ne(run1, run2, "each start_run creates a new run_id")

func test_finish_run_without_active_run_is_noop() -> void:
	Analytics.finish_run({"reason": Analytics.RUN_END_DEATH})
	assert_eq(_sink.events.size(), 0)

func test_start_floor_stores_floor_number_in_state() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 3, "zone": "residential"})
	assert_eq(Analytics._get_run_state_for_testing().current_floor, 3)

func test_finish_floor_emits_summary_with_counters() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	Analytics.record_enemy_killed()
	Analytics.record_enemy_killed()
	Analytics.record_gold_earned(5)
	Analytics.record_damage_taken(2)
	Analytics.finish_floor({})
	var payload: Dictionary = _sink.events.back()["payload"]
	assert_eq(payload["kills"], 2)
	assert_eq(payload["gold_earned"], 5)
	assert_eq(payload["damage_taken"], 2)

func test_counters_reset_between_floors() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	Analytics.record_enemy_killed()
	Analytics.record_gold_earned(10)
	Analytics.finish_floor({})
	Analytics.start_floor({"floor": 2})
	assert_eq(Analytics._get_run_state_for_testing().floor_kills, 0)
	assert_eq(Analytics._get_run_state_for_testing().floor_gold_earned, 0)

func test_run_totals_accumulate_across_floors() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	Analytics.record_enemy_killed()
	Analytics.record_gold_earned(3)
	Analytics.finish_floor({})
	Analytics.start_floor({"floor": 2})
	Analytics.record_enemy_killed()
	Analytics.record_gold_earned(4)
	Analytics.finish_run({"reason": Analytics.RUN_END_VICTORY})
	var payload: Dictionary = _sink.events.back()["payload"]
	assert_eq(payload["enemies_killed"], 2)
	assert_eq(payload["gold_earned"], 7)

func test_finish_run_calls_sink_flush() -> void:
	Analytics.start_run({})
	Analytics.finish_run({"reason": Analytics.RUN_END_DEATH})
	assert_gt(_sink.flush_count, 0, "finish_run must flush the sink")

func test_finish_floor_calls_sink_flush() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	var before := _sink.flush_count
	Analytics.finish_floor({})
	assert_gt(_sink.flush_count, before, "finish_floor must flush the sink")

func test_record_counters_ignored_without_active_run() -> void:
	Analytics.record_enemy_killed()
	Analytics.record_gold_earned(100)
	Analytics.record_damage_taken(50)
	var state := Analytics._get_run_state_for_testing()
	assert_eq(state.enemies_killed_total, 0)
	assert_eq(state.gold_earned_total, 0)
	assert_eq(state.damage_taken_total, 0)

func test_start_floor_ignored_without_active_run() -> void:
	Analytics.start_floor({"floor": 3, "zone": "residential"})
	# Без run guard'а сюда бы попало orphan floor_started без run_id.
	assert_eq(_sink.events.size(), 0, "no floor_started outside a run")
	assert_eq(Analytics._get_run_state_for_testing().current_floor, 0)

func test_finish_floor_ignored_without_active_run() -> void:
	Analytics.finish_floor({})
	assert_eq(_sink.events.size(), 0, "no floor_completed outside a run")

func test_disabled_mode_uses_null_sink() -> void:
	# Восстанавливаем прежний sink, потом переключаем через set_enabled(false).
	Analytics._set_sink_for_testing(_snapshot_sink)
	Analytics.set_enabled(false)
	Analytics.start_session()
	Analytics.start_run({})
	Analytics.record_enemy_killed()
	Analytics.finish_run({"reason": Analytics.RUN_END_DEATH})
	# NullSink не создаёт файлов, is_enabled() == false. Само по себе то,
	# что тут не упало exception'ом — уже success.
	assert_false(Analytics.is_enabled())
	# Убираем sink обратно на InMemory для after_each сброса.
	Analytics._set_sink_for_testing(_sink)

func test_broken_sink_triggers_switch_to_null() -> void:
	var broken := BrokenSink.new()
	Analytics._set_sink_for_testing(broken)
	Analytics.start_session()
	# После первого _emit_event broken sink должен привести к переключению
	# на NullAnalyticsSink. Broken sink получил событие, но затем service
	# переключился.
	var current: AnalyticsSink = Analytics._get_sink_for_testing()
	assert_true(current is NullAnalyticsSink, "service must switch to null on broken sink")

func test_analytics_does_not_shift_global_rng() -> void:
	# Ключевой invariant: логирование НЕ должно двигать глобальный
	# randi() стрим — иначе dungeon generation станет чувствительным
	# к тому, включена аналитика или нет.
	seed(9001)
	var expected := randi()
	seed(9001)
	Analytics.start_session()
	Analytics.start_run({"starting_weapon_id": "dagger"})
	Analytics.start_floor({"floor": 1})
	Analytics.record_enemy_killed()
	Analytics.record_gold_earned(5)
	Analytics.finish_floor({})
	Analytics.finish_run({"reason": Analytics.RUN_END_DEATH})
	Analytics.end_session(Analytics.SESSION_END_NORMAL)
	var actual := randi()
	assert_eq(actual, expected, "analytics must not consume global RNG")

func test_ids_stable_within_session() -> void:
	Analytics.start_session()
	Analytics.start_run({})
	var session_id := Analytics._get_session_id_for_testing()
	Analytics.start_floor({"floor": 1})
	Analytics.record_enemy_killed()
	Analytics.finish_floor({})
	assert_eq(Analytics._get_session_id_for_testing(), session_id,
		"session_id must not change during session")

func test_handle_application_close_emits_run_finished_and_end_session() -> void:
	Analytics.start_session()
	Analytics.start_run({})
	Analytics.start_floor({"floor": 2})
	Analytics._handle_application_close()
	# Ожидаем run_finished(reason=application_closed) и session_finished в очереди.
	var reasons_seen := []
	for event in _sink.events:
		if event["event_name"] == "run_finished":
			reasons_seen.append(["run_finished", event["payload"]["reason"]])
		elif event["event_name"] == "session_finished":
			reasons_seen.append(["session_finished", event["payload"]["reason"]])
	assert_eq(reasons_seen.size(), 2)
	assert_eq(reasons_seen[0], ["run_finished", "application_closed"])
	assert_eq(reasons_seen[1], ["session_finished", "application_closed"])

func test_handle_application_close_without_run_still_ends_session() -> void:
	Analytics.start_session()
	Analytics._handle_application_close()
	# Должен быть session_finished, но не должно быть run_finished (не было run'а).
	var run_finished_count := 0
	var session_finished_count := 0
	for event in _sink.events:
		if event["event_name"] == "run_finished":
			run_finished_count += 1
		elif event["event_name"] == "session_finished":
			session_finished_count += 1
	assert_eq(run_finished_count, 0, "no run to finish")
	assert_eq(session_finished_count, 1)

func test_installation_id_persists_across_runs() -> void:
	var installation_id := Analytics._get_installation_id_for_testing()
	assert_ne(installation_id, "", "installation_id populated on autoload ready")
	Analytics.start_run({})
	Analytics.finish_run({"reason": Analytics.RUN_END_DEATH})
	assert_eq(Analytics._get_installation_id_for_testing(), installation_id,
		"installation_id unchanged across runs")
