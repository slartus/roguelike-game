extends GutTest

# Scheduler-инварианты Necromancer'а (PR 4):
# - Mutual exclusion: summon / aimed / radial выпускаются по одному, а не
#   одновременно из независимых таймеров.
# - После radial минимум RADIAL_MIN_PAUSE секунд никакая атака не выбирается.
# - Первый aimed не летит мгновенно после спавна (delay ≥ AIMED_TELEGRAPH).
# - Boss-specific RNG detersministic по (tower_seed, floor).
# - Приоритет: summon > radial > aimed (при готовых cooldown'ах).

const BossScene: PackedScene = preload("res://scenes/enemies/boss.tscn")
const NecromancerScript: Script = preload("res://scenes/enemies/necromancer.gd")

var _snapshot: Dictionary

func before_each() -> void:
	_snapshot = {"floor": GameState.current_floor_number}
	GameState.current_floor_number = 15

func after_each() -> void:
	GameState.current_floor_number = _snapshot["floor"]

func _spawn_boss() -> Node:
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	return boss

func _fill_minion_quotas(boss: Node) -> void:
	# Заполняем миньонов, чтобы scheduler не выбирал summon и мы могли
	# наблюдать выбор между aimed / radial.
	for i in boss.SUMMON_MELEE_COUNT:
		var f := Node2D.new()
		add_child_autofree(f)
		boss._melee_minions.append(f)
	for i in boss.SUMMON_RANGED_COUNT:
		var f := Node2D.new()
		add_child_autofree(f)
		boss._ranged_minions.append(f)

# --- Mutual exclusion between three attack types --------------------------

func test_summon_has_priority_when_quota_missing() -> void:
	# Summon — приоритет №1 в scheduler'е: если квота свиты не полная и
	# cooldown ready — выбирается именно summon, а не radial/aimed.
	var boss = _spawn_boss()
	boss._target = Node2D.new()
	add_child_autofree(boss._target)
	boss.current_phase = 2
	# Все cooldown'ы готовы, но свита пустая.
	boss._summon_cooldown_timer = 0.0
	boss._radial_cooldown_timer = 0.0
	boss._aimed_cooldown_timer = 0.0
	boss._post_radial_pause_timer = 0.0
	assert_eq(boss._pick_next_action(), boss.ATTACK_SUMMON_MINIONS,
		"при пустой свите summon приоритетнее radial/aimed")

func test_radial_beats_aimed_when_both_ready() -> void:
	# Radial > aimed в приоритете, чтобы aimed с короче cooldown'ом не
	# «съедал» очередь radial'а каждый раз.
	var boss = _spawn_boss()
	boss._target = Node2D.new()
	add_child_autofree(boss._target)
	boss.current_phase = 2
	_fill_minion_quotas(boss)
	boss._summon_cooldown_timer = 999.0
	boss._radial_cooldown_timer = 0.0
	boss._aimed_cooldown_timer = 0.0
	boss._post_radial_pause_timer = 0.0
	assert_eq(boss._pick_next_action(), boss.ATTACK_RADIAL_VOLLEY,
		"radial имеет приоритет над aimed, когда оба готовы (phase 2+)")

func test_aimed_picked_when_radial_on_cooldown() -> void:
	var boss = _spawn_boss()
	boss._target = Node2D.new()
	add_child_autofree(boss._target)
	boss.current_phase = 2
	_fill_minion_quotas(boss)
	boss._summon_cooldown_timer = 999.0
	boss._radial_cooldown_timer = 999.0
	boss._aimed_cooldown_timer = 0.0
	boss._post_radial_pause_timer = 0.0
	assert_eq(boss._pick_next_action(), boss.ATTACK_AIMED_PROJECTILE,
		"aimed выбирается, когда radial ещё на cooldown'е")

# --- Post-radial pause: no aimed inside RADIAL_MIN_PAUSE seconds ----------

func test_post_radial_pause_blocks_all_attack_choices() -> void:
	# Плановый инвариант: после radial минимум RADIAL_MIN_PAUSE секунд
	# scheduler не выбирает никакую атаку, даже aimed.
	var boss = _spawn_boss()
	boss._target = Node2D.new()
	add_child_autofree(boss._target)
	boss.current_phase = 2
	_fill_minion_quotas(boss)
	boss._summon_cooldown_timer = 999.0
	boss._radial_cooldown_timer = 999.0
	boss._aimed_cooldown_timer = 0.0
	# Устанавливаем post-radial gap как только что после радиального залпа.
	boss._post_radial_pause_timer = boss.RADIAL_MIN_PAUSE
	assert_eq(boss._pick_next_action(), &"",
		"внутри post-radial pause scheduler возвращает `\"\"` (боец двигается)")

func test_radial_min_pause_matches_plan() -> void:
	# Плановая константа — 0.6 s.
	assert_almost_eq(NecromancerScript.RADIAL_MIN_PAUSE, 0.6, 0.001,
		"post-radial pause = 0.6 s (см. план)")

func test_radial_interval_matches_plan() -> void:
	# Плановая cadence radial — около 3.0 s.
	assert_almost_eq(NecromancerScript.RADIAL_INTERVAL, 3.0, 0.001,
		"radial interval ≈ 3.0 s (см. план)")

# --- No instant aimed shot on spawn ---------------------------------------

func test_aimed_cooldown_starts_nonzero_after_ready() -> void:
	# Плановый инвариант: no instant ranged shot on spawn. Aimed cooldown
	# инициализирован ненулевым — первый aimed не летит на самом первом
	# physics-frame'е.
	var boss = _spawn_boss()
	assert_gt(boss._aimed_cooldown_timer, 0.0,
		"aimed cooldown стартует ненулевым — первый выстрел не мгновенно")
	# Delay должен быть не меньше telegraph-времени (0.45s), чтобы у игрока
	# было окно среагировать на телеграф.
	assert_gte(boss._aimed_cooldown_timer, boss.AIMED_TELEGRAPH,
		"first-shot delay >= AIMED_TELEGRAPH — окно на реакцию")

# --- Aimed vs radial: no simultaneous attacks (плановый инвариант #9) ----

func test_no_radial_starts_during_aimed_telegraph() -> void:
	# Плановый инвариант «no simultaneous aimed+radial». Пока идёт
	# AIMED_TELEGRAPH, scheduler не должен эмиттить attack_started для
	# radial — cadence-таймеры radial'а не тикают вне APPROACH.
	var boss = _spawn_boss()
	boss._target = Node2D.new()
	add_child_autofree(boss._target)
	boss.current_phase = 2
	# Radial cooldown готов, но boss в AIMED_TELEGRAPH — scheduler в
	# _pick_next_action не вызывается, а _tick_aimed_telegraph работает
	# только с state_timer'ом.
	boss._radial_cooldown_timer = 0.0
	boss._start_attack(boss.ATTACK_AIMED_PROJECTILE)
	watch_signals(boss)
	# Тикаем часть telegraph'а (не до конца) — radial не должен стартовать.
	for i in 3:
		boss._tick_aimed_telegraph(0.1)
	assert_signal_not_emitted(boss, "attack_started",
		"во время AIMED_TELEGRAPH scheduler не эмиттит attack_started для radial")

func test_no_aimed_starts_during_radial_telegraph() -> void:
	# Симметричный invariant: радиальный залп нельзя перебить aimed'ом.
	var boss = _spawn_boss()
	boss._target = Node2D.new()
	add_child_autofree(boss._target)
	boss.current_phase = 2
	boss._aimed_cooldown_timer = 0.0
	boss._start_attack(boss.ATTACK_RADIAL_VOLLEY)
	watch_signals(boss)
	for i in 5:
		boss._tick_radial_telegraph(0.1)
	assert_signal_not_emitted(boss, "attack_started",
		"во время RADIAL_TELEGRAPH scheduler не эмиттит attack_started для aimed")

# --- Interrupt guard: PHASE_TRANSITION эмиттит attack_resolved(false) ----

func test_phase_transition_interrupting_aimed_emits_attack_resolved_false() -> void:
	# Symmetry contract: `attack_started` без парного `attack_resolved`
	# ломает telemetry. Если phase transition прерывает aimed telegraph,
	# _set_state обязан эмиттнуть attack_resolved(aimed, false).
	var boss = _spawn_boss()
	boss._target = Node2D.new()
	add_child_autofree(boss._target)
	boss._start_attack(boss.ATTACK_AIMED_PROJECTILE)
	# state == AIMED_TELEGRAPH, _current_attack == aimed.
	watch_signals(boss)
	boss._set_state(boss.State.PHASE_TRANSITION)
	# GUT-signature: assert_signal_emitted_with_parameters(obj, signal, params, index=-1).
	# Четвёртый аргумент — index (int), не текст-сообщение, поэтому не
	# передаём. Смысл теста в комментарии выше.
	assert_signal_emitted_with_parameters(boss, "attack_resolved",
		[boss.ATTACK_AIMED_PROJECTILE, false])

func test_normal_aimed_completion_does_not_double_emit_attack_resolved() -> void:
	# Обратная сторона interrupt guard'а: нормальный переход
	# AIMED_TELEGRAPH → AIMED_RECOVERY после _fire_aimed_shot не должен
	# добавлять второй attack_resolved (первый уже эмиттнут в fire_shot).
	var boss = _spawn_boss()
	boss.aimed_bullet_scene = null  # fire эмиттит resolved(false)
	boss._start_attack(boss.ATTACK_AIMED_PROJECTILE)
	watch_signals(boss)
	boss._tick_aimed_telegraph(boss.AIMED_TELEGRAPH + 0.01)
	# Ровно один resolved: от _fire_aimed_shot (null scene → false). Ноль
	# resolved от _set_state — _current_attack уже был обнулён в fire.
	assert_signal_emit_count(boss, "attack_resolved", 1,
		"после fire → recovery ровно один attack_resolved (не два)")

# --- One attack at a time: state machine transitions ----------------------

func test_starting_aimed_moves_to_telegraph_state() -> void:
	var boss = _spawn_boss()
	boss._start_attack(boss.ATTACK_AIMED_PROJECTILE)
	assert_eq(int(boss._state), int(boss.State.AIMED_TELEGRAPH),
		"_start_attack(aimed) → AIMED_TELEGRAPH")

func test_starting_radial_moves_to_telegraph_state() -> void:
	var boss = _spawn_boss()
	boss._start_attack(boss.ATTACK_RADIAL_VOLLEY)
	assert_eq(int(boss._state), int(boss.State.RADIAL_TELEGRAPH),
		"_start_attack(radial) → RADIAL_TELEGRAPH")

func test_starting_summon_moves_to_cast_state() -> void:
	var boss = _spawn_boss()
	boss._start_attack(boss.ATTACK_SUMMON_MINIONS)
	assert_eq(int(boss._state), int(boss.State.SUMMON_CAST),
		"_start_attack(summon) → SUMMON_CAST")

# --- Boss-specific RNG deterministic --------------------------------------
#
# Проверяем реальный контракт: `_ready()` seed'ит RNG формулой от
# `_spawn_context.(tower_seed, floor_number)`. Два независимых босса с
# одним и тем же контекстом → одинаковый `randf()` stream. Без такого
# теста случайная замена `_spawn_context.tower_seed` на `randi()` в
# `_ready` не поймается.

func _boss_with_context(tower_seed: int, floor_number: int) -> Node:
	# Instantiate + apply_spawn_context ДО add_child — только так `_ready()`
	# увидит spawn_context (add_child триггерит _ready).
	var boss = BossScene.instantiate()
	var ctx := BossSpawnContext.new()
	ctx.tower_seed = tower_seed
	ctx.floor_number = floor_number
	boss.apply_spawn_context(ctx)
	add_child_autofree(boss)
	return boss

func test_rng_is_deterministic_across_instances_with_same_spawn_context() -> void:
	var b1 := _boss_with_context(42, 15)
	var b2 := _boss_with_context(42, 15)
	for i in 5:
		assert_almost_eq(b1._rng.randf(), b2._rng.randf(), 0.0001,
			"тот же (tower_seed, floor) → тот же randf() %d" % i)

func test_rng_differs_between_floors_in_spawn_context() -> void:
	# Sanity: разные floor'ы дают разные stream'ы, чтобы реплей на floor 15
	# не совпадал с реплеем на floor 20 (fallback).
	var b1 := _boss_with_context(100, 15)
	var b2 := _boss_with_context(100, 20)
	var b1_values: Array = [b1._rng.randf(), b1._rng.randf(), b1._rng.randf()]
	var b2_values: Array = [b2._rng.randf(), b2._rng.randf(), b2._rng.randf()]
	assert_ne(b1_values, b2_values,
		"разные floor'ы дают разные stream'ы RNG")

func test_rng_differs_between_tower_seeds_in_spawn_context() -> void:
	# Sanity: разные tower_seed'ы дают разные stream'ы, чтобы разные забеги
	# на 15-м этаже не оказывались с одинаковой последовательностью выборов.
	var b1 := _boss_with_context(42, 15)
	var b2 := _boss_with_context(43, 15)
	var b1_values: Array = [b1._rng.randf(), b1._rng.randf(), b1._rng.randf()]
	var b2_values: Array = [b2._rng.randf(), b2._rng.randf(), b2._rng.randf()]
	assert_ne(b1_values, b2_values,
		"разные tower_seed'ы дают разные stream'ы RNG")

# --- Full APPROACH cycle: choose → telegraph → resolve → recovery ---------

func test_aimed_cycle_returns_to_approach_after_recovery() -> void:
	# Полный жизненный цикл aimed: APPROACH → AIMED_TELEGRAPH → AIMED_RECOVERY
	# → APPROACH. Обычно fire_shot требует aimed_bullet_scene + current_scene,
	# но для теста лайфцикла нам не нужен реальный spawn — можем убрать
	# aimed_bullet_scene и убедиться, что transitions отрабатывают.
	var boss = _spawn_boss()
	boss.aimed_bullet_scene = null  # не спавним пулю, просто idle через states
	boss._set_state(boss.State.AIMED_TELEGRAPH)
	boss._tick_aimed_telegraph(boss.AIMED_TELEGRAPH + 0.01)
	assert_eq(int(boss._state), int(boss.State.AIMED_RECOVERY),
		"после telegraph → AIMED_RECOVERY")
	boss._tick_aimed_recovery(boss.AIMED_RECOVERY + 0.01)
	assert_eq(int(boss._state), int(boss.State.APPROACH),
		"после recovery → APPROACH")

func test_radial_cycle_sets_post_radial_pause() -> void:
	# После завершения RADIAL_TELEGRAPH scheduler устанавливает
	# _post_radial_pause_timer = RADIAL_MIN_PAUSE и уходит в RADIAL_RECOVERY.
	var boss = _spawn_boss()
	boss.bullet_scene = null  # без scene fire_volley отбьёт attack_resolved(false)
	boss._set_state(boss.State.RADIAL_TELEGRAPH)
	boss._tick_radial_telegraph(boss.RADIAL_TELEGRAPH + 0.01)
	assert_eq(int(boss._state), int(boss.State.RADIAL_RECOVERY),
		"после telegraph → RADIAL_RECOVERY")
	assert_almost_eq(boss._post_radial_pause_timer, boss.RADIAL_MIN_PAUSE, 0.001,
		"post-radial pause взведён на RADIAL_MIN_PAUSE")
	assert_almost_eq(boss._radial_cooldown_timer, boss.RADIAL_INTERVAL, 0.001,
		"radial cooldown взведён на RADIAL_INTERVAL")
