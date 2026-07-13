extends GutTest

# Rune Golem — второй босс башни (этаж 10). Тесты фокусируются на
# инвариантах плана PR 3:
# - registry mapping (floor 10 → rune_golem, не Necromancer fallback);
# - stable ID;
# - HP (65 базовый, скейлится Balance.scaled_hp);
# - phase threshold 50%;
# - slam telegraph precedes damage frame;
# - single-hit damage caps (max 3, contact <= 2);
# - state machine invariants (no attack during recovery/overheat/transition);
# - overheat триггерится после 3 тяжёлых actions, длится 2 s;
# - vulnerability multiplier применяется ТОЛЬКО во время OVERHEATED;
# - boss не атакует во время overheat;
# - phase transition эмиттит `phase_changed(2)` строго один раз;
# - active rune_line ноды удаляются при смерти босса.

const RuneGolemScene: PackedScene = preload("res://scenes/enemies/rune_golem.tscn")
const RuneLineScene: PackedScene = preload("res://scenes/enemies/rune_line.tscn")
const RuneGolemScript: Script = preload("res://scenes/enemies/rune_golem.gd")

var _snapshot: Dictionary

func before_each() -> void:
	# take_damage(999) в тестах смерти босса дёргает `_handle_death` →
	# award_xp/gold/enemy_kill. award_xp может level up'нуть игрока и
	# запросить upgrade choice; award_gold триггерит `_save()` на диск.
	# Snapshot должен покрывать все поля, которые тесты могут потрогать,
	# чтобы соседи в suite не увидели dirty state (см. `test_player_level_rewards.gd`).
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
	GameState.current_floor_number = 10

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

# --- Player-фейк ----------------------------------------------------------
class FakePlayer:
	extends CharacterBody2D
	var _hits: Array = []
	func _init() -> void:
		add_to_group("player")
	func take_damage(amount: int, context: DamageContext = null) -> void:
		_hits.append({"amount": amount, "attack_id": context.attack_id if context != null else &""})
	func last_hit_amount() -> int:
		return int(_hits[-1]["amount"]) if _hits.size() > 0 else 0
	func hit_count(attack_id: StringName) -> int:
		var count := 0
		for h in _hits:
			if h["attack_id"] == attack_id:
				count += 1
		return count
	func total_hits() -> int:
		return _hits.size()

# --- Registry / spawn -----------------------------------------------------

func test_floor_ten_registry_resolves_to_rune_golem() -> void:
	var definition := BossRegistry.definition_for_floor(10)
	assert_not_null(definition, "floor 10 обязан иметь definition")
	assert_eq(definition.id, &"rune_golem",
		"этаж 10 — Rune Golem (не fallback Necromancer)")

func test_boss_has_stable_id() -> void:
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	assert_eq(boss.boss_id, &"rune_golem",
		"stable boss_id для аналитики/логов")

func test_boss_i18n_key_upper_case() -> void:
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	var key := String(boss.display_name)
	assert_eq(key, key.to_upper(),
		"display_name — UPPER_SNAKE_CASE i18n-ключ")
	assert_true(key.begins_with("ENEMY_"),
		"i18n-ключ босса стартует с ENEMY_")

func test_boss_inherits_boss_base() -> void:
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	assert_true(boss is BossBase,
		"root Rune Golem должен наследовать BossBase")

# --- Базовые параметры / phase threshold ----------------------------------

func test_base_max_health_matches_plan() -> void:
	# План: base HP=65; на этаже 10 скейлится Balance.scaled_hp(65, 10).
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	assert_eq(boss.max_health, Balance.scaled_hp(65, 10),
		"max_health скейлится Balance.scaled_hp(65, 10)")

func test_phase_two_threshold_is_fifty_percent() -> void:
	# Плановый инвариант: transition при 50% HP.
	assert_eq(RuneGolemScript.PHASE_2_HP_FRACTION, 0.5,
		"phase 2 threshold — 50% HP (см. план PR 3)")

# --- Damage caps ----------------------------------------------------------

func test_single_hit_damage_never_exceeds_three() -> void:
	# Балансный инвариант: max single-hit = 3 (heavy hit по плану).
	assert_lte(RuneGolemScript.SLAM_DAMAGE, 3,
		"slam_damage <= 3 (heavy hit cap)")
	assert_lte(RuneGolemScript.RUNE_DAMAGE, 1,
		"rune line damage <= 1 (standard hit)")

func test_contact_damage_capped_at_two() -> void:
	# Плановый инвариант: contact damage <= 2 (standard hit).
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	assert_lte(boss.contact_damage, Balance.scaled_damage(2, 10),
		"contact_damage не превышает скейл 2 damage на этаже 10")

# --- Slam telegraph precedes damage ---------------------------------------

func test_slam_telegraph_matches_plan() -> void:
	assert_almost_eq(RuneGolemScript.SLAM_WINDUP, 0.55, 0.001,
		"slam wind-up == 0.55s")
	assert_gt(RuneGolemScript.SLAM_WINDUP, 0.0,
		"slam имеет положительный wind-up перед damage frame")

func test_slam_windup_does_not_apply_damage() -> void:
	var boss = RuneGolemScene.instantiate()
	var player := FakePlayer.new()
	add_child_autofree(boss)
	add_child_autofree(player)
	boss.global_position = Vector2.ZERO
	boss._target = player
	player.global_position = Vector2(40, 0)
	# Стартуем slam. WINDUP занимает 0.55s — damage не должен применяться.
	boss._start_attack(boss.ATTACK_FIST_SLAM, Vector2.RIGHT)
	assert_eq(int(boss._state), int(boss.State.SLAM_WINDUP),
		"после _start_attack — SLAM_WINDUP")
	# Тикаем 0.4s — всё ещё wind-up.
	boss._tick_slam_windup(0.4)
	assert_eq(player.total_hits(), 0,
		"во время SLAM_WINDUP damage не применяется")

func test_slam_active_applies_damage_once() -> void:
	var boss = RuneGolemScene.instantiate()
	var player := FakePlayer.new()
	add_child_autofree(boss)
	add_child_autofree(player)
	boss.global_position = Vector2.ZERO
	boss._target = player
	boss._slam_facing = Vector2.RIGHT
	boss._current_attack = boss.ATTACK_FIST_SLAM
	# Игрок прямо перед боссом на ближней дистанции.
	player.global_position = Vector2(40, 0)
	# Симулируем переход в SLAM_ACTIVE.
	boss._set_state(boss.State.SLAM_ACTIVE)
	boss._tick_slam_active(0.05)
	assert_eq(player.hit_count(boss.ATTACK_FIST_SLAM), 1,
		"slam наносит ровно 1 hit")
	assert_eq(player.last_hit_amount(), boss.SLAM_DAMAGE,
		"damage равен SLAM_DAMAGE")
	# Повторный tick не должен наносить ещё один hit — _damage_applied guard.
	boss._tick_slam_active(0.01)
	assert_eq(player.hit_count(boss.ATTACK_FIST_SLAM), 1,
		"повторный tick не даёт multi-hit")

func test_slam_sector_matches_facing() -> void:
	# Slam поражает только в конусе SLAM_ARC_DEG от _slam_facing.
	var boss = RuneGolemScene.instantiate()
	var player := FakePlayer.new()
	add_child_autofree(boss)
	add_child_autofree(player)
	boss.global_position = Vector2.ZERO
	boss._target = player
	boss._slam_facing = Vector2.RIGHT
	boss._current_attack = boss.ATTACK_FIST_SLAM
	# Игрок сзади (opposite к facing) — damage не наносится.
	player.global_position = Vector2(-30, 0)
	boss._apply_slam_damage()
	assert_eq(player.hit_count(boss.ATTACK_FIST_SLAM), 0,
		"игрок за спиной не получает slam damage")

# --- State machine invariants ---------------------------------------------

func test_boss_starts_in_idle_state() -> void:
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	assert_eq(int(boss._state), int(boss.State.IDLE),
		"boss стартует в IDLE (нет цели)")

func test_no_new_attacks_during_slam_recovery() -> void:
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	boss._set_state(boss.State.SLAM_RECOVERY)
	watch_signals(boss)
	boss._tick_slam_recovery(0.01)
	assert_signal_not_emitted(boss, "attack_started",
		"recovery не запускает новую атаку")

func test_no_new_attacks_during_overheat() -> void:
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	boss._set_state(boss.State.OVERHEATED)
	watch_signals(boss)
	# Симулируем несколько tick'ов внутри overheat — attack_started не должен
	# эмиттиться.
	boss._tick_overheated(0.5)
	boss._tick_overheated(0.5)
	boss._tick_overheated(0.5)
	assert_signal_not_emitted(boss, "attack_started",
		"overheat не запускает новую атаку")

func test_no_new_attacks_during_transition() -> void:
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	boss._set_state(boss.State.PHASE_TRANSITION)
	watch_signals(boss)
	boss._tick_phase_transition(0.01)
	assert_signal_not_emitted(boss, "attack_started",
		"transition не запускает новую атаку")

# --- Overheat: тригер после 3 тяжёлых actions -----------------------------

func test_overheat_triggers_after_three_heavy_actions() -> void:
	# Плановый инвариант: overheat строго после `OVERHEAT_HEAVY_THRESHOLD`
	# тяжёлых действий. Не random.
	assert_eq(RuneGolemScript.OVERHEAT_HEAVY_THRESHOLD, 3,
		"threshold — 3 heavy actions (см. план)")
	var boss = RuneGolemScene.instantiate()
	var player := FakePlayer.new()
	add_child_autofree(boss)
	add_child_autofree(player)
	boss._target = player
	# Инкрементим 3 тяжёлых action'а вручную (симулирует завершение атак).
	boss._finish_heavy_action(boss.ATTACK_FIST_SLAM)
	boss._finish_heavy_action(boss.ATTACK_RUNE_LINE)
	boss._finish_heavy_action(boss.ATTACK_FIST_SLAM)
	assert_eq(boss._heavy_action_count, 3,
		"после 3 тяжёлых actions счётчик = 3")
	# Переходим в APPROACH — overheat gate должен сработать.
	boss._set_state(boss.State.APPROACH)
	boss._tick_approach(0.01)
	assert_eq(int(boss._state), int(boss.State.OVERHEATED),
		"после threshold'а следующий APPROACH → OVERHEATED")

func test_overheat_resets_counter_on_exit() -> void:
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	boss._heavy_action_count = 3
	boss._set_state(boss.State.OVERHEATED)
	# Прогоняем overheat до конца.
	while boss._state == boss.State.OVERHEATED:
		boss._tick_overheated(0.5)
	assert_eq(boss._heavy_action_count, 0,
		"counter сбрасывается после overheat exit")

func test_overheat_duration_matches_plan() -> void:
	assert_almost_eq(RuneGolemScript.OVERHEAT_DURATION, 2.0, 0.001,
		"overheat длится 2.0 s (см. план)")

# --- Overheat: vulnerability multiplier -----------------------------------

func test_vulnerability_multiplier_applies_only_during_overheat() -> void:
	# Балансный инвариант: 1.5x damage только когда OVERHEATED.
	assert_almost_eq(RuneGolemScript.OVERHEAT_DAMAGE_MULTIPLIER, 1.5, 0.001,
		"multiplier = 1.5x")
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	var base_hp: int = boss.health
	# Damage вне overheat — множитель не применяется.
	boss.take_damage(4)
	var hp_after_normal: int = boss.health
	# Кол-во снятого HP должно быть ровно 4 (не 6).
	assert_eq(base_hp - hp_after_normal, 4,
		"вне OVERHEATED damage = amount (без multiplier)")
	# Damage внутри OVERHEATED — множитель применяется.
	# Восстанавливаем HP и ставим состояние OVERHEATED.
	boss.health = base_hp
	boss._set_state(boss.State.OVERHEATED)
	boss.take_damage(4)
	var hp_after_overheat: int = boss.health
	# 4 * 1.5 = 6.
	assert_eq(base_hp - hp_after_overheat, 6,
		"OVERHEATED damage = amount * 1.5 = 6")

# --- Phase transition emits once ------------------------------------------

func test_phase_transition_emits_once() -> void:
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	watch_signals(boss)
	boss._set_state(boss.State.PHASE_TRANSITION)
	while boss._state == boss.State.PHASE_TRANSITION:
		boss._tick_phase_transition(0.1)
	assert_eq(boss.current_phase, 2,
		"после transition — phase = 2")
	assert_signal_emit_count(boss, "phase_changed", 1,
		"phase_changed эмиттится строго 1 раз")

func test_phase_transition_triggers_after_overheat_hp_drop() -> void:
	# Regression: overheat блокирует немедленный PHASE_TRANSITION в take_damage.
	# Если игрок хорошо использовал vulnerability window (1.5x) и пробил HP
	# ниже threshold во время OVERHEATED, boss обязан войти в PHASE_TRANSITION
	# на выходе из overheat, а не остаться в phase 1 навсегда.
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	watch_signals(boss)
	# Симулируем ситуацию: boss в OVERHEATED, HP просажен ниже threshold.
	boss._set_state(boss.State.OVERHEATED)
	# HP чуть ниже PHASE_2_HP_FRACTION * max_health (пробили).
	boss.health = int(float(boss.max_health) * boss.PHASE_2_HP_FRACTION) - 1
	# Прогоняем overheat до конца.
	while boss._state == boss.State.OVERHEATED:
		boss._tick_overheated(0.5)
	# На выходе overheat должен запустить PHASE_TRANSITION.
	assert_eq(int(boss._state), int(boss.State.PHASE_TRANSITION),
		"на выходе overheat при просаженном HP boss уходит в PHASE_TRANSITION")

func test_phase_transition_dedupe_across_multiple_hits() -> void:
	# Multiple hits ниже threshold'а — phase_changed эмиттит один раз.
	# take_damage async — не await'им здесь только для проверки sync-части
	# (переход в PHASE_TRANSITION происходит до `await create_timer`).
	# Проверка идёт по _state сразу после call'а; async-часть завершится
	# внутри цикла tick'ов ниже (transition eats time).
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	watch_signals(boss)
	var health_at_threshold: int = roundi(float(boss.max_health) * boss.PHASE_2_HP_FRACTION)
	var damage_to_cross: int = boss.max_health - health_at_threshold + 1
	# Первый удар: пробивает threshold → PHASE_TRANSITION (sync-часть).
	@warning_ignore("redundant_await")
	await boss.take_damage(damage_to_cross)
	assert_eq(int(boss._state), int(boss.State.PHASE_TRANSITION),
		"первый удар ниже 50% запускает PHASE_TRANSITION")
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

# --- Rune line cleanup on boss death --------------------------------------

func test_active_rune_lines_are_cleaned_on_boss_death() -> void:
	# Плановый инвариант: effects cleanup after boss death.
	var boss = RuneGolemScene.instantiate()
	add_child_autofree(boss)
	# Спавним rune_line вручную и регистрируем.
	var lane := RuneLineScene.instantiate()
	get_tree().root.add_child(lane)
	boss._active_rune_lines.append(lane)
	assert_true(is_instance_valid(lane) and lane.is_inside_tree(),
		"rune_line создан и в дереве")
	# Killing blow — health <= 0 → cleanup. take_damage is async (внутри
	# await create_timer 0.08s + queue_free), поэтому нужно ждать его.
	boss.health = 1
	await boss.take_damage(999)
	# Ещё process_frame чтобы queue_free реально удалил ноду.
	await get_tree().process_frame
	# После cleanup lane должна быть queue_free'жена. lane.is_inside_tree() уже
	# false, is_instance_valid может быть false после frame.
	assert_false(is_instance_valid(lane) and lane.is_inside_tree(),
		"rune_line удалена после смерти босса")
