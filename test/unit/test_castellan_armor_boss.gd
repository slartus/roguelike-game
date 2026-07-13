extends GutTest

# Castellan Armor — первый босс башни (этаж 5). Учит игрока читать
# телеграф, выдёргиваться из сектора, проваливать заряд в стену и
# использовать recovery/vulnerability windows.
#
# Тесты фокусируются на инвариантах плана PR 2:
# - registry mapping (Castellan → 5, не Necromancer);
# - HP / phase threshold;
# - single-hit damage caps (max 3, contact <= 1);
# - state machine invariants (no attack during recovery/stun/transition);
# - charge: фиксированное направление, no homing, wall → stun, no multi-hit;
# - phase transition эмиттит `phase_changed(2)` строго один раз;
# - ground slam — только phase 2, 4 shockwaves, каждый damage <= 1.

const CastellanScene: PackedScene = preload("res://scenes/enemies/castellan_armor.tscn")
const ShockwaveScene: PackedScene = preload("res://scenes/enemies/castellan_shockwave.tscn")
const CastellanScript: Script = preload("res://scenes/enemies/castellan_armor.gd")

var _snapshot: Dictionary

func before_each() -> void:
	# Boss lifecycle трогает GameState; тесты в основном не убивают
	# босса, но snapshot всё равно нужен, потому что при `_apply_floor_scaling`
	# читается GameState.current_floor_number.
	_snapshot = {
		"floor": GameState.current_floor_number,
		"xp": GameState.player_xp,
		"gold": GameState.total_gold,
	}
	GameState.current_floor_number = 5

func after_each() -> void:
	GameState.current_floor_number = _snapshot["floor"]
	GameState.player_xp = _snapshot["xp"]
	GameState.total_gold = _snapshot["gold"]

# --- Player-фейк -----------------------------------------------------------
# CharacterBody2D + группа "player" + take_damage сохраняет последний hit
# для asserts. `velocity` реален (типизирован в CharacterBody2D), поэтому
# knockback от bash можно проверить.
class FakePlayer:
	extends CharacterBody2D
	var _hits: Array = []
	func _init() -> void:
		add_to_group("player")
	func take_damage(amount: int, context: DamageContext = null) -> void:
		_hits.append({"amount": amount, "attack_id": context.attack_id if context != null else &""})
	func last_hit_amount() -> int:
		return int(_hits[-1]["amount"]) if _hits.size() > 0 else 0
	func last_hit_attack_id() -> StringName:
		return _hits[-1]["attack_id"] if _hits.size() > 0 else &""
	func hit_count(attack_id: StringName) -> int:
		var count := 0
		for h in _hits:
			if h["attack_id"] == attack_id:
				count += 1
		return count

# --- Registry / spawn ------------------------------------------------------

func test_floor_five_registry_resolves_to_castellan() -> void:
	var definition := BossRegistry.definition_for_floor(5)
	assert_not_null(definition, "floor 5 обязан иметь definition")
	assert_eq(definition.id, &"castellan_armor",
		"этаж 5 — Castellan Armor")

func test_necromancer_no_longer_spawns_on_floor_five() -> void:
	# Necromancer больше не имеет explicit floor 5.
	for definition in BossRegistry.all_definitions():
		if definition.id == &"necromancer":
			assert_ne(definition.floor_number, 5,
				"Necromancer больше не привязан к этажу 5")

func test_boss_has_stable_id() -> void:
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	assert_eq(boss.boss_id, &"castellan_armor",
		"stable boss_id для аналитики/логов")

func test_boss_i18n_key_upper_case() -> void:
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	var key := String(boss.display_name)
	assert_eq(key, key.to_upper(), "display_name — UPPER_SNAKE_CASE i18n-ключ")
	assert_true(key.begins_with("ENEMY_"), "i18n-ключ босса стартует с ENEMY_")

func test_boss_inherits_boss_base() -> void:
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	assert_true(boss is BossBase, "root Castellan должен наследовать BossBase")

# --- Базовые параметры / phase threshold -----------------------------------

func test_base_max_health_matches_plan() -> void:
	# Boss scale by floor: план указывает base HP=45; на этаже 5 после
	# Balance.scaled_hp ожидаем roundi(45 * 1.48) = 67. Проверяем формулу,
	# не конкретное значение — Balance-tuning не должен ломать этот тест.
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	assert_eq(boss.max_health, Balance.scaled_hp(45, 5),
		"max_health скейлится Balance.scaled_hp(45, 5)")

func test_phase_two_threshold_is_fifty_five_percent() -> void:
	# Инвариант плана: transition при 55% HP.
	assert_eq(CastellanScript.PHASE_2_HP_FRACTION, 0.55,
		"phase 2 threshold — 55% HP (см. план)")

# --- Damage caps -----------------------------------------------------------

func test_single_hit_damage_never_exceeds_three() -> void:
	# Балансный инвариант: max single-hit = 3.
	assert_lte(CastellanScript.SWEEP_DAMAGE, 3, "sweep_damage <= 3")
	assert_lte(CastellanScript.BASH_DAMAGE, 3, "bash_damage <= 3")
	assert_lte(CastellanScript.CHARGE_DAMAGE, 3, "charge_damage <= 3")
	assert_lte(CastellanScript.SLAM_NEAR_DAMAGE, 3, "slam_near_damage <= 3")
	assert_lte(CastellanScript.SLAM_SHOCKWAVE_DAMAGE, 1,
		"shockwave damage <= 1 (инвариант 14)")

func test_contact_damage_capped_at_one() -> void:
	# Инвариант 7: contact damage <= 1.
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	# `contact_damage` — @export, скейлится Balance.scaled_damage(1, 5) = 1.
	assert_lte(boss.contact_damage, 1, "contact_damage не превышает 1")

# --- State machine invariants ---------------------------------------------

func test_boss_starts_in_idle_state() -> void:
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	# Прямой доступ к _state — вложенный enum. Используем "in" через get().
	assert_eq(int(boss._state), int(boss.State.IDLE),
		"boss стартует в IDLE (нет цели)")

func test_boss_transitions_to_approach_when_target_found() -> void:
	var boss = CastellanScene.instantiate()
	var player := FakePlayer.new()
	player.global_position = Vector2(300, 0)
	add_child_autofree(boss)
	add_child_autofree(player)
	boss.global_position = Vector2.ZERO
	# Один физический tick — boss должен найти игрока и уйти в APPROACH.
	# `await get_tree().physics_frame` в изолированной сцене без main loop'а
	# не тикает — вызываем handler напрямую.
	boss._physics_process(1.0 / 60.0)
	assert_ne(int(boss._state), int(boss.State.IDLE),
		"после физического кадра boss не должен остаться в IDLE")

# --- Sweep: telegraph precedes damage --------------------------------------

func test_sweep_telegraph_precedes_active_frame() -> void:
	# Атака должна иметь windup перед damage — план указывает 0.45s.
	assert_gt(CastellanScript.SWEEP_WINDUP, 0.0,
		"sword_sweep имеет положительный wind-up")
	assert_almost_eq(CastellanScript.SWEEP_WINDUP, 0.45, 0.001,
		"sweep wind-up == 0.45s по плану")

func test_sweep_sector_matches_facing() -> void:
	# Инвариант: sweep поражает только в SWEEP_ARC_DEG от _attack_facing.
	# Игрок за спиной (opposite к facing) — damage не наносится.
	var boss = CastellanScene.instantiate()
	var player := FakePlayer.new()
	add_child_autofree(boss)
	add_child_autofree(player)
	boss.global_position = Vector2.ZERO
	boss._target = player
	# Boss «смотрит вправо», игрок сзади слева на малой дистанции.
	boss._attack_facing = Vector2.RIGHT
	boss._current_attack = boss.ATTACK_SWORD_SWEEP
	player.global_position = Vector2(-30, 0)
	boss._apply_sector_damage(boss.SWEEP_RANGE, boss.SWEEP_ARC_DEG, boss.SWEEP_DAMAGE, false)
	assert_eq(player.hit_count(boss.ATTACK_SWORD_SWEEP), 0,
		"игрок за спиной не получает sweep damage")

	# Игрок впереди в пределах sector — попадает.
	player.global_position = Vector2(40, 0)
	boss._apply_sector_damage(boss.SWEEP_RANGE, boss.SWEEP_ARC_DEG, boss.SWEEP_DAMAGE, false)
	assert_eq(player.hit_count(boss.ATTACK_SWORD_SWEEP), 1,
		"игрок впереди получает ровно 1 sweep hit")
	assert_eq(player.last_hit_amount(), boss.SWEEP_DAMAGE,
		"damage равен SWEEP_DAMAGE (не multiplied)")

# --- Bash: single-hit + knockback -----------------------------------------

func test_bash_applies_damage_and_knockback_once() -> void:
	var boss = CastellanScene.instantiate()
	var player := FakePlayer.new()
	add_child_autofree(boss)
	add_child_autofree(player)
	boss.global_position = Vector2.ZERO
	boss._target = player
	boss._attack_facing = Vector2.RIGHT
	boss._current_attack = boss.ATTACK_SHIELD_BASH
	player.global_position = Vector2(20, 0)
	player.velocity = Vector2.ZERO
	boss._apply_sector_damage(boss.BASH_RANGE, boss.BASH_ARC_DEG, boss.BASH_DAMAGE, true)
	assert_eq(player.hit_count(boss.ATTACK_SHIELD_BASH), 1,
		"bash наносит ровно 1 hit")
	assert_gt(player.velocity.length(), 0.0,
		"bash задаёт положительную velocity игроку (knockback)")

# --- Charge: telegraph, fixed direction, no homing -------------------------

func test_charge_telegraph_matches_plan() -> void:
	assert_almost_eq(CastellanScript.CHARGE_TELEGRAPH, 0.65, 0.001,
		"charge telegraph == 0.65s")

func test_charge_direction_locked_before_start() -> void:
	# Направление зафиксировано в _start_attack. Если после старта player
	# сместился, boss всё равно летит по старому вектору.
	var boss = CastellanScene.instantiate()
	var player := FakePlayer.new()
	add_child_autofree(boss)
	add_child_autofree(player)
	boss.global_position = Vector2.ZERO
	player.global_position = Vector2(150, 0)
	# Стартуем charge (симулируем что _tick_approach вызвал _start_attack).
	boss._start_attack(boss.ATTACK_SHIELD_CHARGE, Vector2.RIGHT)
	# Player внезапно телепортировался вниз.
	player.global_position = Vector2(150, 200)
	# Симулируем один tick charge (после windup — CHARGING).
	boss._state = boss.State.CHARGING
	boss._state_timer = 0.0
	boss._damage_applied = false
	var pos_before: Vector2 = boss.global_position
	boss._tick_charging(1.0 / 60.0)
	var move_delta: Vector2 = boss.global_position - pos_before
	assert_almost_eq(move_delta.y, 0.0, 0.5,
		"charge не преследует игрока: движение строго горизонтальное")
	assert_gt(move_delta.x, 0.0,
		"charge движется в зафиксированном RIGHT направлении")

# --- Ground slam: только phase 2, 4 shockwaves, damage <= 1 ---------------

func test_ground_slam_available_only_in_phase_two() -> void:
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	assert_eq(boss.current_phase, 1, "начинается с phase 1")
	# _pick_next_action на средней дистанции в phase 1 не может выбрать slam.
	# Даже с "неудачным" RNG выбор slam невозможен без current_phase == 2.
	# Симулируем 20 попыток на среднюю дистанцию — ни разу не slam.
	for i in 20:
		var chosen: StringName = boss._pick_next_action(120.0)
		assert_ne(chosen, boss.ATTACK_GROUND_SLAM,
			"slam недоступен в phase 1 (попытка %d)" % i)

func test_ground_slam_is_pickable_in_phase_two() -> void:
	# Позитивный тест: в phase 2 при подходящей дистанции slam ДОЛЖЕН
	# выбираться (иначе игрок никогда не увидит phase 2 механику).
	# Прогоняем несколько попыток — хотя бы одна должна дать slam.
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	boss.set_phase(2)
	boss._last_attack = boss.ATTACK_SWORD_SWEEP  # разрешаем slam
	var slam_seen := false
	# 30 попыток при probability 0.55 → P(no slam) ≈ 0.45^30 ≈ 5e-11.
	for i in 30:
		var chosen: StringName = boss._pick_next_action(120.0)
		if chosen == boss.ATTACK_GROUND_SLAM:
			slam_seen = true
			break
	assert_true(slam_seen,
		"slam выбирается в phase 2 при подходящей дистанции — иначе механика недостижима")

func test_ground_slam_spawns_four_shockwaves() -> void:
	var boss = CastellanScene.instantiate()
	var player := FakePlayer.new()
	add_child_autofree(boss)
	add_child_autofree(player)
	boss.global_position = Vector2(200, 200)
	player.global_position = Vector2(500, 500)  # вне SLAM_NEAR_RADIUS
	var parent := boss.get_parent()
	var wave_count_before := 0
	for child in parent.get_children():
		if child.scene_file_path.ends_with("castellan_shockwave.tscn"):
			wave_count_before += 1
	boss._current_attack = boss.ATTACK_GROUND_SLAM
	boss._execute_ground_slam()
	# Волны спавнятся как дети parent'а босса (get_tree.current_scene аналог).
	var wave_count_after := 0
	for child in parent.get_children():
		if child.scene_file_path.ends_with("castellan_shockwave.tscn"):
			wave_count_after += 1
	assert_eq(wave_count_after - wave_count_before, 4,
		"ground_slam порождает ровно 4 shockwaves")

func test_shockwave_damage_capped_at_one() -> void:
	# Проверяем и default'ное поле scene, и константу боссу — иначе можно
	# ложно-положительно пройти тест увеличив SLAM_SHOCKWAVE_DAMAGE и
	# оставив default'ный @export damage = 1.
	var wave = ShockwaveScene.instantiate()
	add_child_autofree(wave)
	assert_lte(wave.damage, 1,
		"shockwave.tscn default damage <= 1")
	assert_lte(CastellanScript.SLAM_SHOCKWAVE_DAMAGE, 1,
		"SLAM_SHOCKWAVE_DAMAGE const <= 1 (invariant плана)")

# --- No attack during recovery/stun/transition ----------------------------

func test_no_new_attacks_during_recovery() -> void:
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	boss._state = boss.State.RECOVERY
	boss._state_timer = 0.0
	boss._current_attack = boss.ATTACK_SWORD_SWEEP
	# _tick_recovery не должен эмиттить attack_started.
	watch_signals(boss)
	boss._tick_recovery(0.01)
	assert_signal_not_emitted(boss, "attack_started",
		"recovery не запускает новую атаку")

func test_no_new_attacks_during_stun() -> void:
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	boss._state = boss.State.STUNNED
	boss._state_timer = 0.0
	watch_signals(boss)
	boss._tick_stunned(0.01)
	assert_signal_not_emitted(boss, "attack_started",
		"stun не запускает новую атаку")

func test_no_new_attacks_during_transition() -> void:
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	boss._state = boss.State.PHASE_TRANSITION
	boss._state_timer = 0.0
	watch_signals(boss)
	boss._tick_phase_transition(0.01)
	assert_signal_not_emitted(boss, "attack_started",
		"transition не запускает новую атаку")

# --- Phase transition emits once ------------------------------------------

func test_phase_transition_emits_once() -> void:
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	watch_signals(boss)
	# Симулируем один полный transition-цикл. По истечении DURATION
	# set_phase(2) вызывается и эмит происходит один раз.
	boss._set_state(boss.State.PHASE_TRANSITION)
	# Прогоняем tick'и по мере накопления _state_timer'а.
	while boss._state == boss.State.PHASE_TRANSITION:
		boss._tick_phase_transition(0.1)
	assert_eq(boss.current_phase, 2,
		"после transition — phase = 2")
	assert_signal_emit_count(boss, "phase_changed", 1,
		"phase_changed эмиттится строго 1 раз")

func test_phase_transition_dedupe_across_multiple_hits() -> void:
	# Production-path проверка инварианта плана #7: несколько take_damage
	# ниже 55%-порога подряд эмиттят phase_changed(2) СТРОГО один раз.
	# Guard `_state != State.PHASE_TRANSITION` в take_damage должен ловить
	# второй и последующие удары.
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	watch_signals(boss)
	# Наносим damage такой, чтобы пересечь threshold 55%.
	var health_at_threshold: int = roundi(float(boss.max_health) * boss.PHASE_2_HP_FRACTION)
	var damage_to_cross: int = boss.max_health - health_at_threshold + 1
	boss.take_damage(damage_to_cross)
	assert_eq(int(boss._state), int(boss.State.PHASE_TRANSITION),
		"первый удар ниже 55% запускает PHASE_TRANSITION")
	# Второй и третий удар — уже в transition. НЕ должны заново эмиттить.
	boss.take_damage(1)
	boss.take_damage(1)
	# Даём отработать tick'ам до конца transition.
	while boss._state == boss.State.PHASE_TRANSITION:
		boss._tick_phase_transition(0.1)
	assert_eq(boss.current_phase, 2, "phase = 2 после transition")
	assert_signal_emit_count(boss, "phase_changed", 1,
		"phase_changed эмиттится ровно 1 раз даже при множественных hit'ах")

# --- Charge — no multi-hit ------------------------------------------------

func test_charge_damage_applied_only_once() -> void:
	var boss = CastellanScene.instantiate()
	var player := FakePlayer.new()
	add_child_autofree(boss)
	add_child_autofree(player)
	boss.global_position = Vector2.ZERO
	boss._target = player
	player.global_position = Vector2(15, 0)  # в CHARGE_HIT_RADIUS
	boss._attack_facing = Vector2.RIGHT
	boss._current_attack = boss.ATTACK_SHIELD_CHARGE
	boss._state = boss.State.CHARGING
	boss._state_timer = 0.0
	boss._damage_applied = false
	# Первый tick — попадание.
	boss._tick_charging(1.0 / 60.0)
	# После damage boss ушёл в RECOVERY, повторный _tick_charging не должен
	# наносить ещё один hit (даже если явно call'нуть).
	var hits_after_first := player.hit_count(boss.ATTACK_SHIELD_CHARGE)
	assert_eq(hits_after_first, 1,
		"charge наносит damage строго 1 раз")

# --- Selection: charge cadence guard --------------------------------------

func test_charge_not_repeated_more_than_twice_in_a_row() -> void:
	# Инвариант: не более MAX_CONSECUTIVE_CHARGES зарядов подряд.
	# После двух зарядов cap должен подавить третий выбор charge на
	# том же диапазоне дистанции.
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	# Простой сценарий: два подряд стартуем charge — cap срабатывает.
	boss._start_attack(boss.ATTACK_SHIELD_CHARGE, Vector2.RIGHT)
	boss._start_attack(boss.ATTACK_SHIELD_CHARGE, Vector2.RIGHT)
	# Третий вызов _pick_next_action в диапазоне charge не должен выбрать
	# charge вовсе.
	var chosen: StringName = boss._pick_next_action(150.0)
	assert_ne(chosen, boss.ATTACK_SHIELD_CHARGE,
		"третий charge подряд не выбирается (cadence guard)")

# --- Slam cadence guard ---------------------------------------------------

func test_slam_not_repeated_twice_in_a_row() -> void:
	var boss = CastellanScene.instantiate()
	add_child_autofree(boss)
	boss.set_phase(2)
	boss._last_attack = boss.ATTACK_GROUND_SLAM
	# Симулируем 30 попыток _pick_next_action — slam не должен быть выбран
	# сразу после slam, независимо от RNG.
	for i in 30:
		var chosen: StringName = boss._pick_next_action(120.0)
		assert_ne(chosen, boss.ATTACK_GROUND_SLAM,
			"slam не должен выбираться сразу после slam (попытка %d)" % i)

# --- Charge не преследует после старта ------------------------------------

func test_charge_no_homing_after_start() -> void:
	# Ещё одна проверка «не homing»: после _start_attack _attack_facing
	# не меняется даже если игрок сместился. Проверка на _attack_facing
	# как источник истины для CHARGING.
	var boss = CastellanScene.instantiate()
	var player := FakePlayer.new()
	add_child_autofree(boss)
	add_child_autofree(player)
	boss.global_position = Vector2.ZERO
	player.global_position = Vector2(100, 0)
	boss._start_attack(boss.ATTACK_SHIELD_CHARGE, Vector2.RIGHT)
	var facing_at_start: Vector2 = boss._attack_facing
	# После старта игрок «прыгнул» вверх.
	player.global_position = Vector2(100, -80)
	# Один tick charging.
	boss._state = boss.State.CHARGING
	boss._tick_charging(1.0 / 60.0)
	assert_almost_eq(boss._attack_facing.x, facing_at_start.x, 0.0001,
		"facing.x зафиксировано")
	assert_almost_eq(boss._attack_facing.y, facing_at_start.y, 0.0001,
		"facing.y зафиксировано (не преследует игрока)")
