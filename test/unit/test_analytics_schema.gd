extends GutTest

# Проверяет envelope-инварианты: schema_version, обязательные поля,
# правильное включение run_id/floor/tower_seed по scope'у.
# Все проверки идут через in-memory sink чтобы посмотреть на реальную
# структуру события, которую увидит sink.

class InMemorySink extends AnalyticsSink:
	var events: Array = []

	func write_event(event: Dictionary) -> void:
		events.append(event)

var _snapshot_sink: AnalyticsSink
var _snapshot_tower_seed: int
var _snapshot_floor_number: int
var _sink: InMemorySink

const ENVELOPE_REQUIRED_FIELDS: Array = [
	"schema_version",
	"event_name",
	"event_id",
	"timestamp_ms",
	"installation_id",
	"session_id",
	"game_version",
	"build_commit",
	"balance_version",
	"platform",
	"locale",
	"payload",
]

func before_each() -> void:
	_snapshot_sink = Analytics._get_sink_for_testing()
	_snapshot_tower_seed = GameState.tower_seed
	_snapshot_floor_number = GameState.current_floor_number
	_sink = InMemorySink.new()
	Analytics._set_sink_for_testing(_sink)
	Analytics._force_regenerate_ids_for_testing()

func after_each() -> void:
	Analytics._get_run_state_for_testing().reset()
	Analytics._set_sink_for_testing(_snapshot_sink)
	GameState.tower_seed = _snapshot_tower_seed
	GameState.current_floor_number = _snapshot_floor_number

func test_envelope_contains_required_fields() -> void:
	Analytics.start_session()
	var event: Dictionary = _sink.events[0]
	for field in ENVELOPE_REQUIRED_FIELDS:
		assert_true(event.has(field), "envelope missing '%s'" % field)

func test_envelope_includes_schema_version_int() -> void:
	Analytics.start_session()
	assert_eq(_sink.events[0]["schema_version"], Analytics.ANALYTICS_SCHEMA_VERSION)
	assert_typeof(_sink.events[0]["schema_version"], TYPE_INT)

func test_envelope_includes_balance_version() -> void:
	Analytics.start_session()
	assert_eq(_sink.events[0]["balance_version"], Balance.BALANCE_VERSION)

func test_run_started_event_has_run_id_and_tower_seed() -> void:
	GameState.tower_seed = 42
	Analytics.start_run({})
	var event: Dictionary = _sink.events.back()
	assert_eq(event["event_name"], "run_started")
	assert_true(event.has("run_id"))
	assert_ne(event["run_id"], "")
	assert_eq(event["tower_seed"], 42)

func test_session_started_event_has_no_run_id() -> void:
	Analytics.start_session()
	var event: Dictionary = _sink.events[0]
	assert_false(event.has("run_id"), "session event must not carry run_id")
	assert_false(event.has("tower_seed"))
	assert_false(event.has("floor"))

func test_floor_started_event_has_floor() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 5, "zone": "residential"})
	var event: Dictionary = _sink.events.back()
	assert_eq(event["event_name"], "floor_started")
	assert_eq(event["floor"], 5)
	assert_eq(event["payload"]["zone"], "residential")

func test_floor_completed_event_has_floor() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 7})
	Analytics.finish_floor({})
	# PR 2 finish_floor эмитит несколько events: floor_completed, floor_weapon_summary,
	# floor_enemy_summary, floor_economy_summary. Ищем именно floor_completed.
	var event := _find_event(_sink.events, "floor_completed")
	assert_false(event.is_empty(), "floor_completed event must be emitted")
	assert_eq(event["event_name"], "floor_completed")
	assert_eq(event["floor"], 7)

func _find_event(events: Array, name: String) -> Dictionary:
	for e in events:
		if e["event_name"] == name:
			return e
	return {}

func test_run_finished_event_has_summary_fields() -> void:
	Analytics.start_run({})
	Analytics.start_floor({"floor": 3})
	Analytics.record_enemy_killed()
	Analytics.record_gold_earned(15)
	Analytics.record_damage_taken(2)
	Analytics.finish_run({
		"reason": Analytics.RUN_END_DEATH,
		"floor_reached": 3,
		"player_level": 4,
	})
	var event: Dictionary = _sink.events.back()
	var payload: Dictionary = event["payload"]
	assert_eq(payload["reason"], "player_death")
	assert_eq(payload["floor_reached"], 3)
	assert_eq(payload["player_level"], 4)
	assert_eq(payload["enemies_killed"], 1)
	assert_eq(payload["gold_earned"], 15)
	assert_eq(payload["damage_taken"], 2)

func test_event_ids_unique_within_session() -> void:
	Analytics.start_session()
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	Analytics.finish_floor({})
	Analytics.finish_run({"reason": Analytics.RUN_END_DEATH})
	Analytics.end_session(Analytics.SESSION_END_NORMAL)
	var seen := {}
	for event in _sink.events:
		var id: String = event["event_id"]
		assert_false(seen.has(id), "duplicate event_id: %s" % id)
		seen[id] = true

func test_platform_field_is_lowercase() -> void:
	Analytics.start_session()
	var platform: String = _sink.events[0]["platform"]
	assert_eq(platform, platform.to_lower(), "platform must be lowercase")

func test_locale_field_populated() -> void:
	Analytics.start_session()
	assert_ne(_sink.events[0]["locale"], "")

func test_build_commit_has_safe_fallback() -> void:
	# Если build_info.txt отсутствует, build_commit=='unknown'.
	# Аналитика не должна ронять запуск.
	Analytics.start_session()
	assert_ne(_sink.events[0]["build_commit"], "")

func test_duration_uses_monotonic_time() -> void:
	# Дюрации floor/run измеряются Time.get_ticks_msec() (monotonic).
	# Здесь просто убеждаемся, что duration_seconds >= 0 и не NaN/negative.
	Analytics.start_run({})
	Analytics.start_floor({"floor": 1})
	Analytics.finish_floor({})
	var event := _find_event(_sink.events, "floor_completed")
	assert_false(event.is_empty())
	assert_true(event["payload"]["duration_seconds"] >= 0.0)
