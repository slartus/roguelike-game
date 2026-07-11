extends Node

# ============================================================================
# Analytics autoload — machine-readable telemetry для баланса.
#
# ВАЖНО: это НЕ замена EventLog'у. EventLog — локализованные строки для UI;
# Analytics — типизированные события с версией схемы для offline-анализа.
# Парсить EventLog как источник аналитики запрещено (см. .claude/rules/
# и docs/engineering/analytics.md).
#
# Приватность (PR 1): собираем только random installation_id, session_id,
# run_id, версию/коммит/платформу/локаль и gameplay-параметры. Никаких
# usernames, путей, IP, координат.
#
# Детерминизм: генерация UUID и логирование НЕ трогают глобальный
# randi() стрим Godot. dungeon RNG, spawn table, upgrade offer generator
# видят точно тот же поток чисел, что без аналитики.
#
# Отказоустойчивость: любая IO-ошибка приводит к переключению на
# NullAnalyticsSink с warning. Gameplay не должен видеть ошибок.
# ============================================================================

const ANALYTICS_SCHEMA_VERSION: int = 1

# Причины завершения сессии — фиксированный enum.
const SESSION_END_NORMAL: StringName = &"normal_exit"
const SESSION_END_QUIT_TO_MENU: StringName = &"quit_to_menu"
const SESSION_END_RESTART: StringName = &"restart"
# WM_CLOSE_REQUEST — игрок закрыл окно ОС (крестик, cmd+Q).
# Отдельная причина, чтобы pipeline PR 3 отличал явный клик «Выход»
# на title screen (normal_exit) от закрытия окна.
const SESSION_END_APPLICATION_CLOSED: StringName = &"application_closed"
const SESSION_END_UNKNOWN: StringName = &"unknown"

# Причины завершения run'а — фиксированный enum.
const RUN_END_DEATH: StringName = &"player_death"
const RUN_END_VICTORY: StringName = &"victory"
const RUN_END_QUIT_TO_MENU: StringName = &"quit_to_menu"
const RUN_END_RESTART: StringName = &"restart"
const RUN_END_APPLICATION_CLOSED: StringName = &"application_closed"
const RUN_END_UNKNOWN: StringName = &"unknown"

# Источник переключения оружия. Заполняется в PR 2, но enum
# фиксируем сразу чтобы не переписывать интерфейс.
const WEAPON_SOURCE_STARTING: StringName = &"starting"
const WEAPON_SOURCE_CHEST: StringName = &"chest"
const WEAPON_SOURCE_PICKUP: StringName = &"pickup"
const WEAPON_SOURCE_DEBUG: StringName = &"debug"
const WEAPON_SOURCE_OTHER: StringName = &"other"

# Flush policy: сколько буферизованных событий терпим до принудительной записи.
const BUFFER_EVENT_LIMIT: int = 32

var _installation_id: String = ""
var _session_id: String = ""
var _sink: AnalyticsSink = null
var _enabled: bool = false
var _session_started: bool = false
var _run_state: RunAnalyticsState = RunAnalyticsState.new()

# Мемоизированные метаданные окружения — читаются один раз в _ready.
var _game_version: String = "0.0.0"
var _build_commit: String = "unknown"
var _platform: String = "unknown"
var _locale: String = "unknown"
var _debug_build: bool = false

func _ready() -> void:
	_installation_id = AnalyticsIds.load_or_create_installation_id()
	_session_id = AnalyticsIds.new_uuid()
	_platform = _detect_platform()
	_locale = TranslationServer.get_locale()
	_debug_build = OS.is_debug_build()
	_game_version = ProjectSettings.get_setting("application/config/version", "0.0.0")
	_build_commit = _read_build_commit_metadata()
	# Analytics по умолчанию включена только в debug builds. Prod-переключение
	# делается через set_enabled() из settings screen (M13, вне scope PR 1).
	set_enabled(_debug_build)
	# Перехватываем quit чтобы успеть flush'нуть буфер и правильно закрыть
	# run/session. Большинство игроков закрывают игру не через кнопку
	# «Выход» на title screen, а окном ОС — без этого хука мы бы теряли
	# до BUFFER_EVENT_LIMIT событий и не эмиттили finish_run для active run.
	# ВНИМАНИЕ: Analytics owns WM_CLOSE_REQUEST. Если в проекте появится
	# ещё один компонент, хотящий перехватить close (custom quit dialog),
	# его handler должен звать Analytics._handle_application_close перед
	# своей логикой.
	get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_handle_application_close()
		get_tree().quit()

func _handle_application_close() -> void:
	# Активный run считаем прерванным закрытием окна — эмиттим finish_run
	# с явной причиной, чтобы pipeline PR 3 отличал такие runs от смертей.
	if _run_state.run_id != "":
		finish_run({"reason": RUN_END_APPLICATION_CLOSED})
	if _session_started:
		end_session(SESSION_END_APPLICATION_CLOSED)
	flush()

# --- Публичный API ----------------------------------------------------------

func is_enabled() -> bool:
	return _enabled and _sink != null and not _sink.is_broken()

func set_enabled(enabled: bool) -> void:
	if enabled == _enabled and _sink != null:
		return
	_enabled = enabled
	if _sink != null:
		_sink.close()
	if enabled:
		_sink = JsonlAnalyticsSink.new(_session_id)
		if _sink.is_broken():
			# Если файл/директория не открылись — сразу переключаем в safe mode.
			_sink = NullAnalyticsSink.new()
	else:
		_sink = NullAnalyticsSink.new()

func start_session() -> void:
	if _session_started:
		return
	_session_started = true
	_emit_event(&"session_started", {
		"debug_build": _debug_build,
	})

func end_session(reason: StringName = SESSION_END_UNKNOWN) -> void:
	if not _session_started:
		return
	_emit_event(&"session_finished", {
		"reason": String(reason),
	})
	_session_started = false
	flush()

func start_run(context: Dictionary = {}) -> String:
	var run_id := AnalyticsIds.new_uuid()
	_run_state.start_run(run_id, _now_ticks_ms())
	var starting_weapon_id := String(context.get("starting_weapon_id", "unknown"))
	_emit_event(&"run_started", {
		"starting_weapon_id": starting_weapon_id,
		"starting_max_health": int(context.get("starting_max_health", 0)),
		"starting_level": int(context.get("starting_level", 1)),
	})
	# Starting weapon трактуем как первое эквип-событие: без этого
	# equipped_seconds / damage_taken_while_equipped / attribution kill'ов
	# стартовым оружием не пишутся пока игрок не подберёт второе.
	if starting_weapon_id != "" and starting_weapon_id != "unknown":
		record_weapon_equipped(
			StringName(starting_weapon_id), &"", WEAPON_SOURCE_STARTING
		)
	return run_id

func finish_run(summary: Dictionary = {}) -> void:
	if _run_state.run_id == "":
		return
	# Финализируем equipped_seconds текущего оружия и коммитим последний
	# floor_weapon_summary (иначе последний этаж не попадёт в run-агрегат).
	_run_state.finalize_floor_weapon_time(_now_ticks_ms())
	var payload := {
		"reason": String(summary.get("reason", RUN_END_UNKNOWN)),
		"duration_seconds": _run_state.run_duration_seconds(_now_ticks_ms()),
		"floor_reached": int(summary.get("floor_reached", _run_state.current_floor)),
		"player_level": int(summary.get("player_level", 0)),
		"gold_earned": _run_state.gold_earned_total,
		"enemies_killed": _run_state.enemies_killed_total,
		"damage_taken": _run_state.damage_taken_total,
		"damage_dealt": _run_state.damage_dealt_total,
		"equipped_weapon_id": String(_run_state.current_weapon_id),
		"potions_remaining": int(summary.get("potions_remaining", 0)),
		"upgrade_stacks": summary.get("upgrade_stacks", {}),
		"damage_history": _run_state.damage_history,
		"weapon_totals": _run_state.run_weapon_summaries(),
	}
	# Death attribution: для reason=player_death добавляем разбор источника
	# смертельного удара из last_damage_context.
	var reason := String(summary.get("reason", RUN_END_UNKNOWN))
	if reason == String(RUN_END_DEATH) and _run_state.last_damage_context != null:
		var ctx := _run_state.last_damage_context
		payload["death_source_type"] = String(ctx.source_type)
		payload["death_source_id"] = String(ctx.source_id)
		payload["death_attack_id"] = String(ctx.attack_id)
		payload["death_source_temperament"] = String(ctx.temperament_id)
		payload["death_source_elite_rank"] = ctx.elite_rank
	_emit_event(&"run_finished", payload)
	_run_state.reset()
	flush()

func start_floor(context: Dictionary = {}) -> void:
	# Guard: floor-события имеют смысл только внутри активного run.
	# Без него direct-load main.tscn из редактора / debug tools эмиттил
	# бы orphan floor_started без run_id/tower_seed в envelope.
	if _run_state.run_id == "":
		return
	var floor_num := int(context.get("floor", 0))
	_run_state.start_floor(floor_num, _now_ticks_ms())
	# floor_started payload расширен layout/room метриками — поля
	# опциональные, main.gd передаёт то, что знает.
	var payload := {
		"layout_archetype": String(context.get("layout_archetype", "unknown")),
		"zone": String(context.get("zone", "unknown")),
	}
	for key in ["room_count", "corridor_count", "enemy_count", "chest_count",
			"prop_count", "walkable_area_cells", "critical_path_length_cells",
			"branch_count", "dead_end_count", "loop_count",
			"total_enemy_threat", "blocking_prop_cells", "interactive_prop_count",
			"floor_width", "floor_height"]:
		if context.has(key):
			payload[key] = context[key]
	_emit_event(&"floor_started", payload)

func finish_floor(summary: Dictionary = {}) -> void:
	if _run_state.run_id == "":
		return
	if _run_state.current_floor == 0:
		return
	# Финализация equipped_seconds для текущего оружия перед сбором
	# floor_weapon_summary — иначе последний segment этажа потеряется.
	_run_state.finalize_floor_weapon_time(_now_ticks_ms())
	# Один суммарный floor_completed event.
	var payload := {
		"duration_seconds": _run_state.floor_duration_seconds(_now_ticks_ms()),
		"kills": _run_state.floor_kills,
		"gold_earned": _run_state.floor_gold_earned,
		"damage_taken": _run_state.floor_damage_taken,
		"damage_dealt": _run_state.floor_damage_dealt,
		"rooms_visited": _run_state.rooms_visited_count,
	}
	for key in summary.keys():
		payload[key] = summary[key]
	_emit_event(&"floor_completed", payload)
	# Затем — отдельные summary events на weapon/enemy/economy этажа,
	# каждый с payload от counters. Разделяем чтобы pipeline PR 3 мог
	# fanout'ить в отдельные CSV без парсинга nested arrays.
	for weapon_summary in _run_state.floor_weapon_summaries():
		_emit_event(&"floor_weapon_summary", weapon_summary)
	for enemy_summary in _run_state.floor_enemy_summaries():
		_emit_event(&"floor_enemy_summary", enemy_summary)
	_emit_event(&"floor_economy_summary", _run_state.economy.to_dictionary())
	flush()

func flush() -> void:
	if _sink == null:
		return
	_sink.flush()
	_check_sink_health()

# Инкременторы counters. Вызываются gameplay-хуками (award_gold,
# award_enemy_kill, take_damage). Все no-op когда run не активен.
func record_enemy_killed(context: DamageContext = null) -> void:
	# context — опциональный. Если задан, дополнительно инкрементим
	# enemy killed counter (иначе только общий kill counter).
	if _run_state.run_id == "":
		return
	_run_state.add_kill()
	if context != null:
		# target_id для kill = enemy id (kill эмитится когда enemy умирает,
		# в этом event enemy — это target damage, а source — weapon).
		# Если у нас есть attribution weapon → enemy, то weapon.kills++.
		var weapon_id: StringName = &""
		if context.source_type == &"player_weapon":
			weapon_id = context.source_id
		# overkill_damage = |context.amount| - remaining_hp_before. У нас
		# нет доступа к remaining_hp здесь — считаем 0 в PR 2 (можно
		# уточнить в PR 3 через explicit call сайт).
		_run_state.record_kill(weapon_id, 0)
		# Enemy attribution: killed++ для (enemy_id, temperament, rank).
		if context.target_type == &"enemy":
			_run_state.record_enemy_killed(
				context.target_id, context.temperament_id, context.elite_rank
			)

func record_enemy_spawned(enemy_id: StringName, temperament: StringName, elite_rank: int) -> void:
	if _run_state.run_id == "":
		return
	_run_state.record_enemy_spawned(enemy_id, temperament, elite_rank)

func record_gold_earned(amount: int, source: StringName = &"enemy") -> void:
	# source ∈ {"enemy", "chest", "prop", "boss"} — определяет экономику.
	if _run_state.run_id == "":
		return
	_run_state.add_gold(amount)
	match source:
		&"enemy":
			_run_state.economy.gold_from_enemies += amount
		&"chest":
			_run_state.economy.gold_from_chests += amount
		&"prop":
			_run_state.economy.gold_from_props += amount
		&"boss":
			_run_state.economy.gold_from_bosses += amount
		_:
			# Неизвестный source (typo вроде "enemies") тихо попадает
			# в enemy bucket — но warning помогает поймать опечатку в diff'е.
			push_warning("[analytics] unknown gold source '%s', defaulting to enemy" % source)
			_run_state.economy.gold_from_enemies += amount

func record_damage_taken(amount: int, context: DamageContext = null) -> void:
	if _run_state.run_id == "":
		return
	_run_state.add_damage_taken(amount, context, _now_ticks_ms())

func record_damage_dealt(amount: int, context: DamageContext) -> void:
	# Вызывается когда player weapon наносит damage enemy. Обновляет
	# floor_damage_dealt + weapon damage_dealt + enemy damage_received.
	if _run_state.run_id == "":
		return
	var weapon_id: StringName = &""
	if context != null and context.source_type == &"player_weapon":
		weapon_id = context.source_id
	_run_state.add_damage_dealt(amount, weapon_id, context)

func record_player_attack(weapon_id: StringName) -> void:
	# Один вызов на одну активацию attack (для melee — swing; для ranged —
	# нажатие кнопки). Bullet.gd НЕ вызывает это — projectile_fired вызовет.
	if _run_state.run_id == "":
		return
	_run_state.record_attack(weapon_id)

func record_player_attack_hit(weapon_id: StringName) -> void:
	if _run_state.run_id == "":
		return
	_run_state.record_attack_hit(weapon_id)

func record_projectile_fired(weapon_id: StringName) -> void:
	if _run_state.run_id == "":
		return
	_run_state.record_projectile_fired(weapon_id)

func record_projectile_hit(weapon_id: StringName) -> void:
	if _run_state.run_id == "":
		return
	_run_state.record_projectile_hit(weapon_id)

# --- Weapon equip ------------------------------------------------------------

func record_weapon_equipped(weapon_id: StringName, previous_weapon_id: StringName,
		source: StringName = WEAPON_SOURCE_OTHER) -> void:
	if _run_state.run_id == "":
		return
	_run_state.switch_current_weapon(weapon_id, _now_ticks_ms())
	_emit_event(&"weapon_equipped", {
		"weapon_id": String(weapon_id),
		"previous_weapon_id": String(previous_weapon_id),
		"source": String(source),
	})

# --- Upgrade offers ----------------------------------------------------------

func record_upgrade_offer_shown(context: Dictionary) -> void:
	# context: {choice_level, current_weapon_id, current_weapon_style,
	#           current_attack_type, offered_ids, offered_positions,
	#           current_stacks, player_health, player_max_health}.
	if _run_state.run_id == "":
		return
	_run_state.current_upgrade_offer_shown_ticks_ms = _now_ticks_ms()
	_emit_event(&"upgrade_offer_shown", {
		"choice_level": int(context.get("choice_level", 0)),
		"current_weapon_id": String(context.get("current_weapon_id", "unknown")),
		"current_weapon_style": String(context.get("current_weapon_style", "")),
		"current_attack_type": String(context.get("current_attack_type", "")),
		"offered_ids": context.get("offered_ids", []),
		"offered_positions": context.get("offered_positions", {}),
		"current_stacks": context.get("current_stacks", {}),
		"player_health": int(context.get("player_health", 0)),
		"player_max_health": int(context.get("player_max_health", 0)),
	})

func record_upgrade_selected(context: Dictionary) -> void:
	# context: {selected_id, offer_position, stack_before, stack_after}.
	if _run_state.run_id == "":
		return
	var choice_time := 0.0
	if _run_state.current_upgrade_offer_shown_ticks_ms > 0:
		choice_time = maxf(0.0,
			(_now_ticks_ms() - _run_state.current_upgrade_offer_shown_ticks_ms) / 1000.0)
	_run_state.current_upgrade_offer_shown_ticks_ms = 0
	_emit_event(&"upgrade_selected", {
		"selected_id": String(context.get("selected_id", "unknown")),
		"offer_position": int(context.get("offer_position", -1)),
		"choice_time_seconds": choice_time,
		"stack_before": int(context.get("stack_before", 0)),
		"stack_after": int(context.get("stack_after", 0)),
	})

# --- Rooms -------------------------------------------------------------------

func record_room_entered(room_id: StringName, context: Dictionary = {}) -> void:
	# Эмитим room_first_entered ТОЛЬКО при первом визите в комнату
	# на текущем этаже — повторные visits не логируются, floor summary
	# показывает суммарное количество visited rooms.
	if _run_state.run_id == "":
		return
	if not _run_state.record_room_visit(room_id):
		return
	var payload := {
		"room_id": String(room_id),
		"role": String(context.get("role", "unknown")),
		"critical_path": bool(context.get("critical_path", false)),
		"optional": bool(context.get("optional", false)),
		"seconds_since_floor_start": _run_state.floor_duration_seconds(_now_ticks_ms()),
		"player_health": int(context.get("player_health", 0)),
		"alive_enemies": int(context.get("alive_enemies", 0)),
		"reward_present": bool(context.get("reward_present", false)),
	}
	_emit_event(&"room_first_entered", payload)

# --- Potions -----------------------------------------------------------------

func record_potion_received() -> void:
	if _run_state.run_id == "":
		return
	_run_state.economy.potions_received += 1

func record_potion_used(health_before: int, max_health: int, heal_amount: int) -> void:
	if _run_state.run_id == "":
		return
	var actual_healed := clampi(max_health - health_before, 0, heal_amount)
	var overheal := maxi(0, heal_amount - actual_healed)
	_run_state.economy.potions_used += 1
	_run_state.economy.healing_received += actual_healed
	_run_state.economy.overheal += overheal
	_emit_event(&"potion_used", {
		"health_before": health_before,
		"max_health": max_health,
		"heal_amount": heal_amount,
		"actual_healed": actual_healed,
		"overheal": overheal,
	})

# --- Chests ------------------------------------------------------------------

func record_chest_opened() -> void:
	if _run_state.run_id == "":
		return
	_run_state.economy.chests_opened += 1

# --- Тестовые хуки (только для тестов) --------------------------------------
#
# Позволяют GUT-тесту снять реальный sink и подставить in-memory
# double, а также заглянуть в internal state envelope'а.

func _get_installation_id_for_testing() -> String:
	return _installation_id

func _get_session_id_for_testing() -> String:
	return _session_id

func _get_run_id_for_testing() -> String:
	return _run_state.run_id

func _get_sink_for_testing() -> AnalyticsSink:
	return _sink

func _set_sink_for_testing(sink: AnalyticsSink) -> void:
	_sink = sink

func _get_run_state_for_testing() -> RunAnalyticsState:
	return _run_state

func _force_regenerate_ids_for_testing() -> void:
	_session_id = AnalyticsIds.new_uuid()
	_run_state.reset()
	_session_started = false

# --- Внутренние методы ------------------------------------------------------

func _emit_event(event_name: StringName, payload: Dictionary) -> void:
	if _sink == null:
		return
	var event := _build_envelope(event_name, payload)
	_sink.write_event(event)
	_check_sink_health()

func _build_envelope(event_name: StringName, payload: Dictionary) -> Dictionary:
	var envelope := {
		"schema_version": ANALYTICS_SCHEMA_VERSION,
		"event_name": String(event_name),
		"event_id": AnalyticsIds.new_uuid(),
		"timestamp_ms": int(Time.get_unix_time_from_system() * 1000.0),

		"installation_id": _installation_id,
		"session_id": _session_id,

		"game_version": _game_version,
		"build_commit": _build_commit,
		"balance_version": Balance.BALANCE_VERSION,

		"platform": _platform,
		"locale": _locale,

		"payload": payload,
	}
	# Run-scoped поля добавляем только если run активен — иначе
	# session_started / session_finished получат мусор.
	if _run_state.run_id != "":
		envelope["run_id"] = _run_state.run_id
		envelope["tower_seed"] = GameState.tower_seed
	if _run_state.current_floor > 0:
		envelope["floor"] = _run_state.current_floor
	return envelope

func _check_sink_health() -> void:
	# Sink пометил себя broken → тихо переключаемся в safe mode, warning
	# уже логирован самим sink'ом. Gameplay продолжает работать.
	if _sink != null and _sink.is_broken():
		push_warning("[analytics] sink broken, switching to null sink")
		_sink = NullAnalyticsSink.new()

func _now_ticks_ms() -> int:
	# Monotonic clock — не подвержен изменению системного времени
	# в процессе игры. Используется только для durations, wall-clock
	# timestamp живёт в envelope.timestamp_ms.
	return Time.get_ticks_msec()

func _detect_platform() -> String:
	# OS.get_name() возвращает "macOS", "Windows", "Linux", "Android",
	# "iOS", "Web". Нормализуем в lowercase family.
	var raw := OS.get_name().to_lower()
	match raw:
		"macos", "osx":
			return "macos"
		"windows":
			return "windows"
		"linux", "freebsd", "netbsd", "openbsd", "bsd":
			return "linux"
		"android":
			return "android"
		"ios":
			return "ios"
		"web":
			return "web"
		_:
			return raw

func _read_build_commit_metadata() -> String:
	# Build metadata пишется в build_info.txt отдельным CI-шагом.
	# Отсутствие файла = "unknown", это допустимое состояние (dev-запуск,
	# первая версия) и НЕ должно ронять аналитику.
	var path := "res://build_info.txt"
	if not FileAccess.file_exists(path):
		return "unknown"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "unknown"
	var content := file.get_as_text().strip_edges()
	file.close()
	if content == "":
		return "unknown"
	return content
