class_name RunAnalyticsState
extends RefCounted

# Аккумулятор ран-скоуп статистики для аналитики. Инициализируется на
# Analytics.start_run(), инкрементируется gameplay-хуками через
# Analytics.record_*() методы, снимается snapshot'ом на finish_run().
#
# PR 2 расширил его с минимальных counters до полноценного набора:
# damage_history, weapon counters, enemy counters, economy, room tracking.

const DAMAGE_HISTORY_LIMIT: int = 16

var run_id: String = ""
var run_started_ticks_ms: int = 0
var floor_started_ticks_ms: int = 0
var current_floor: int = 0

# --- Run-level totals ---
var enemies_killed_total: int = 0
var gold_earned_total: int = 0
var damage_taken_total: int = 0
var damage_dealt_total: int = 0

# --- Floor-level totals (сбрасываются в start_floor) ---
var floor_kills: int = 0
var floor_gold_earned: int = 0
var floor_damage_taken: int = 0
var floor_damage_dealt: int = 0

# --- Damage attribution ---
# Последние DAMAGE_HISTORY_LIMIT damage-событий против игрока с временными
# метками, для death attribution в run_finished.
var damage_history: Array = []
# Последний damage-context для death attribution.
var last_damage_context: DamageContext = null

# --- Weapon analytics ---
# Dictionary weapon_id → WeaponAnalyticsCounters на текущий этаж.
var floor_weapon_counters: Dictionary = {}
var current_weapon_id: StringName = &""
var current_weapon_equipped_ticks_ms: int = 0
# Run-total per weapon.
var run_weapon_counters: Dictionary = {}

# --- Enemy analytics ---
var floor_enemy_counters: Dictionary = {}

# --- Economy ---
var economy: EconomyCounters = EconomyCounters.new()

# --- Room tracking ---
var visited_room_ids: Dictionary = {}
var rooms_visited_count: int = 0

# --- Upgrade offer timing ---
var current_upgrade_offer_shown_ticks_ms: int = 0

func reset() -> void:
	run_id = ""
	run_started_ticks_ms = 0
	floor_started_ticks_ms = 0
	current_floor = 0
	enemies_killed_total = 0
	gold_earned_total = 0
	damage_taken_total = 0
	damage_dealt_total = 0
	floor_kills = 0
	floor_gold_earned = 0
	floor_damage_taken = 0
	floor_damage_dealt = 0
	damage_history = []
	last_damage_context = null
	floor_weapon_counters = {}
	current_weapon_id = &""
	current_weapon_equipped_ticks_ms = 0
	run_weapon_counters = {}
	floor_enemy_counters = {}
	economy = EconomyCounters.new()
	visited_room_ids = {}
	rooms_visited_count = 0
	current_upgrade_offer_shown_ticks_ms = 0

func start_run(new_run_id: String, ticks_ms: int) -> void:
	reset()
	run_id = new_run_id
	run_started_ticks_ms = ticks_ms

func start_floor(floor_number: int, ticks_ms: int) -> void:
	# Перед сбросом floor-полей: коммитим equipped_seconds текущего оружия.
	_finalize_current_weapon_equipped_time(ticks_ms)
	current_floor = floor_number
	floor_started_ticks_ms = ticks_ms
	floor_kills = 0
	floor_gold_earned = 0
	floor_damage_taken = 0
	floor_damage_dealt = 0
	floor_weapon_counters = {}
	floor_enemy_counters = {}
	economy.reset()
	visited_room_ids = {}
	rooms_visited_count = 0
	# Если оружие уже экипировано, стартуем новый equipped timer.
	if current_weapon_id != &"":
		current_weapon_equipped_ticks_ms = ticks_ms
		_ensure_weapon_counters(current_weapon_id)

func add_kill() -> void:
	enemies_killed_total += 1
	floor_kills += 1

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold_earned_total += amount
	floor_gold_earned += amount

func add_damage_taken(amount: int, context: DamageContext, now_ticks_ms: int) -> void:
	if amount <= 0:
		return
	damage_taken_total += amount
	floor_damage_taken += amount
	# damage_taken_while_equipped для текущего оружия.
	if current_weapon_id != &"":
		var counters := _ensure_weapon_counters(current_weapon_id)
		counters.damage_taken_while_equipped += amount
	# Enemy attribution.
	if context != null and context.source_type != &"unknown":
		var key := EnemyAnalyticsCounters.make_key(
			context.source_id, context.temperament_id, context.elite_rank
		)
		var enemy_counters: EnemyAnalyticsCounters = floor_enemy_counters.get(key, null)
		if enemy_counters == null:
			enemy_counters = EnemyAnalyticsCounters.new(
				context.source_id, context.temperament_id, context.elite_rank
			)
			floor_enemy_counters[key] = enemy_counters
		enemy_counters.damage_to_player += amount
		enemy_counters.hits_to_player += 1
	# damage_history ring buffer.
	var entry := {
		"source_type": String(context.source_type) if context != null else "unknown",
		"source_id": String(context.source_id) if context != null else "unknown",
		"attack_id": String(context.attack_id) if context != null else "unknown",
		"temperament_id": String(context.temperament_id) if context != null else "",
		"elite_rank": context.elite_rank if context != null else 0,
		"damage": amount,
		"ticks_ms": now_ticks_ms,
		"floor": current_floor,
	}
	damage_history.append(entry)
	if damage_history.size() > DAMAGE_HISTORY_LIMIT:
		damage_history.remove_at(0)
	# Не перезаписываем last_damage_context null'ом от legacy callsite —
	# death attribution должен опираться на последний non-null context.
	if context != null:
		last_damage_context = context

func add_damage_dealt(amount: int, weapon_id: StringName, target_context: DamageContext) -> void:
	if amount <= 0:
		return
	damage_dealt_total += amount
	floor_damage_dealt += amount
	var effective_id := weapon_id if weapon_id != &"" else current_weapon_id
	if effective_id != &"":
		for counters in _both_weapon_counters(effective_id):
			counters.damage_dealt += amount
			counters.targets_hit += 1
	# Enemy damage_received attribution — ensure_enemy_counters создаёт запись
	# если её нет (враг может быть runtime-spawn'ом без record_enemy_spawned).
	if target_context != null:
		var enemy_counters := _ensure_enemy_counters(
			target_context.target_id, target_context.temperament_id, target_context.elite_rank
		)
		enemy_counters.damage_received += amount

func record_attack(weapon_id: StringName) -> void:
	var effective_id := weapon_id if weapon_id != &"" else current_weapon_id
	if effective_id == &"":
		return
	for counters in _both_weapon_counters(effective_id):
		counters.attacks += 1

func record_attack_hit(weapon_id: StringName) -> void:
	var effective_id := weapon_id if weapon_id != &"" else current_weapon_id
	if effective_id == &"":
		return
	for counters in _both_weapon_counters(effective_id):
		counters.attacks_with_hit += 1

func record_projectile_fired(weapon_id: StringName) -> void:
	var effective_id := weapon_id if weapon_id != &"" else current_weapon_id
	if effective_id == &"":
		return
	for counters in _both_weapon_counters(effective_id):
		counters.projectiles_fired += 1

func record_projectile_hit(weapon_id: StringName) -> void:
	var effective_id := weapon_id if weapon_id != &"" else current_weapon_id
	if effective_id == &"":
		return
	for counters in _both_weapon_counters(effective_id):
		counters.projectiles_hit += 1

func record_kill(weapon_id: StringName, overkill_amount: int) -> void:
	var effective_id := weapon_id if weapon_id != &"" else current_weapon_id
	if effective_id == &"":
		return
	for counters in _both_weapon_counters(effective_id):
		counters.kills += 1
		counters.overkill_damage += maxi(0, overkill_amount)

func record_enemy_spawned(enemy_id: StringName, temperament: StringName, rank: int) -> void:
	var key := EnemyAnalyticsCounters.make_key(enemy_id, temperament, rank)
	var enemy_counters: EnemyAnalyticsCounters = floor_enemy_counters.get(key, null)
	if enemy_counters == null:
		enemy_counters = EnemyAnalyticsCounters.new(enemy_id, temperament, rank)
		floor_enemy_counters[key] = enemy_counters
	enemy_counters.spawned += 1

func record_enemy_killed(enemy_id: StringName, temperament: StringName, rank: int) -> void:
	var key := EnemyAnalyticsCounters.make_key(enemy_id, temperament, rank)
	var enemy_counters: EnemyAnalyticsCounters = floor_enemy_counters.get(key, null)
	if enemy_counters == null:
		enemy_counters = EnemyAnalyticsCounters.new(enemy_id, temperament, rank)
		floor_enemy_counters[key] = enemy_counters
	enemy_counters.killed += 1

func record_room_visit(room_id: StringName) -> bool:
	if room_id == &"" or visited_room_ids.has(room_id):
		return false
	visited_room_ids[room_id] = true
	rooms_visited_count += 1
	return true

func floor_duration_seconds(now_ticks_ms: int) -> float:
	if floor_started_ticks_ms <= 0:
		return 0.0
	return maxf(0.0, (now_ticks_ms - floor_started_ticks_ms) / 1000.0)

func run_duration_seconds(now_ticks_ms: int) -> float:
	if run_started_ticks_ms <= 0:
		return 0.0
	return maxf(0.0, (now_ticks_ms - run_started_ticks_ms) / 1000.0)

func switch_current_weapon(new_weapon_id: StringName, now_ticks_ms: int) -> void:
	_finalize_current_weapon_equipped_time(now_ticks_ms)
	current_weapon_id = new_weapon_id
	current_weapon_equipped_ticks_ms = now_ticks_ms
	if new_weapon_id != &"":
		_ensure_weapon_counters(new_weapon_id)

func finalize_floor_weapon_time(now_ticks_ms: int) -> void:
	_finalize_current_weapon_equipped_time(now_ticks_ms)
	if current_weapon_id != &"":
		current_weapon_equipped_ticks_ms = now_ticks_ms

func floor_weapon_summaries() -> Array:
	var out: Array = []
	for weapon_id in floor_weapon_counters.keys():
		var counters: WeaponAnalyticsCounters = floor_weapon_counters[weapon_id]
		out.append(counters.to_dictionary())
	return out

func floor_enemy_summaries() -> Array:
	var out: Array = []
	for key in floor_enemy_counters.keys():
		var counters: EnemyAnalyticsCounters = floor_enemy_counters[key]
		out.append(counters.to_dictionary())
	return out

func run_weapon_summaries() -> Array:
	var out: Array = []
	for weapon_id in run_weapon_counters.keys():
		var counters: WeaponAnalyticsCounters = run_weapon_counters[weapon_id]
		out.append(counters.to_dictionary())
	return out

func _ensure_weapon_counters(weapon_id: StringName) -> WeaponAnalyticsCounters:
	if not floor_weapon_counters.has(weapon_id):
		floor_weapon_counters[weapon_id] = WeaponAnalyticsCounters.new(weapon_id)
	if not run_weapon_counters.has(weapon_id):
		run_weapon_counters[weapon_id] = WeaponAnalyticsCounters.new(weapon_id)
	return floor_weapon_counters[weapon_id]

func _both_weapon_counters(weapon_id: StringName) -> Array:
	# Возвращает [floor_counter, run_counter] — record_* обновляет оба
	# синхронно чтобы run_weapon_counters отражал реальные totals.
	_ensure_weapon_counters(weapon_id)
	return [floor_weapon_counters[weapon_id], run_weapon_counters[weapon_id]]

func _ensure_enemy_counters(enemy_id: StringName, temperament: StringName, rank: int) -> EnemyAnalyticsCounters:
	var key := EnemyAnalyticsCounters.make_key(enemy_id, temperament, rank)
	var counters: EnemyAnalyticsCounters = floor_enemy_counters.get(key, null)
	if counters == null:
		counters = EnemyAnalyticsCounters.new(enemy_id, temperament, rank)
		floor_enemy_counters[key] = counters
	return counters

func _finalize_current_weapon_equipped_time(now_ticks_ms: int) -> void:
	# Только empty weapon пропускается — таймер могли стартовать в ticks=0
	# (первое оружие в run'е). Отрицательная delta невозможна через maxf.
	if current_weapon_id == &"":
		return
	var delta_seconds := maxf(0.0, (now_ticks_ms - current_weapon_equipped_ticks_ms) / 1000.0)
	var floor_counters := _ensure_weapon_counters(current_weapon_id)
	floor_counters.equipped_seconds += delta_seconds
	var run_counters: WeaponAnalyticsCounters = run_weapon_counters[current_weapon_id]
	run_counters.equipped_seconds += delta_seconds
