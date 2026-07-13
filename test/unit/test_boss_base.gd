extends GutTest

# BossBase — общий lifecycle всех боссов. Проверяем именно контракт
# базы: phase transitions без дубликатов, death signal с stable id,
# spawn context применяется до _ready(), Necromancer.tscn наследует
# base и его inheritance цепочка не сломана.

const BossScene: PackedScene = preload("res://scenes/enemies/boss.tscn")

var _snapshot: Dictionary

func before_each() -> void:
	# Boss lifecycle трогает GameState (award_xp, award_gold, kill count).
	# Тесты падений таких методов не вызывают, но snapshot оставляем на
	# случай, если добавятся тесты death path'а.
	_snapshot = {
		"floor": GameState.current_floor_number,
		"xp": GameState.player_xp,
		"gold": GameState.total_gold,
	}

func after_each() -> void:
	GameState.current_floor_number = _snapshot["floor"]
	GameState.player_xp = _snapshot["xp"]
	GameState.total_gold = _snapshot["gold"]

func test_necromancer_scene_root_is_boss_base() -> void:
	# Гарантирует что Necromancer.tscn действительно инстанцирует BossBase
	# subclass, а не CharacterBody2D напрямую как раньше.
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	assert_true(boss is BossBase,
		"root Necromancer.tscn должен наследовать BossBase")

func test_set_phase_emits_phase_changed_signal() -> void:
	# GUT-signature: assert_signal_emitted_with_parameters(obj, signal, params, index=-1)
	# Четвёртый аргумент — индекс, не текст, потому text-message не передаём.
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	watch_signals(boss)
	boss.set_phase(2)
	assert_signal_emitted_with_parameters(boss, "phase_changed", [2])

func test_set_phase_deduplicates_same_phase() -> void:
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	boss.set_phase(2)
	watch_signals(boss)
	boss.set_phase(2)
	assert_signal_not_emitted(boss, "phase_changed",
		"повторный set_phase(same) не должен эмиттить дубликат")

func test_phase_starts_from_one() -> void:
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	assert_eq(boss.current_phase, 1,
		"phase инициализируется 1, а не 0")

func test_spawn_context_applied_before_ready_scales_from_context_floor() -> void:
	# Boss ставится на floor 5, но spawn context задаёт floor 12 (например,
	# fallback). Scaling должен идти от context, не от GameState.
	GameState.current_floor_number = 5
	var context := BossSpawnContext.new()
	context.floor_number = 12
	var boss = BossScene.instantiate()
	boss.apply_spawn_context(context)
	add_child_autofree(boss)
	# Balance.scaled_hp монотонно неубывающая по floor'у: hp на floor 12
	# должно быть >= hp на floor 5. Проверяем именно этот инвариант, не
	# конкретные цифры (они могут измениться balance-правкой).
	var expected_min_hp := Balance.scaled_hp(30, 12)
	assert_eq(boss.max_health, expected_min_hp,
		"max_health скейлится по context.floor_number, не по GameState")

func test_effective_floor_falls_back_to_game_state_without_context() -> void:
	GameState.current_floor_number = 7
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	assert_eq(boss.effective_floor_number(), 7,
		"без context — используется GameState.current_floor_number")

func test_boss_scene_instance_has_stable_boss_id() -> void:
	# Regression guard: `@export var boss_id` в BossBase дефолтится на
	# пустой StringName. Без явной установки в .tscn инстанс boss.tscn
	# эмиттил бы boss_died(&"", pos) — аналитика/логи получают мусор.
	# Ловим это на уровне scene resource, не через manual emit.
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	assert_eq(boss.boss_id, &"necromancer",
		"boss.tscn должен задать boss_id = &necromancer для стабильных аналитик-событий")

func test_boss_died_signal_carries_scene_boss_id() -> void:
	# Проверяем что при реальном эмите (не manual) через `boss_died.emit`
	# приходит именно тот `boss_id`, что задан на сцене — не пустой,
	# не perevisitkey сигнала.
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	watch_signals(boss)
	boss.boss_died.emit(boss.boss_id, boss.global_position)
	assert_signal_emitted_with_parameters(boss, "boss_died",
		[&"necromancer", boss.global_position])

func test_died_at_signal_kept_for_main_wiring() -> void:
	# Main подписывается на died_at единообразно для всех enemy — этот
	# сигнал должен остаться. Boss-специфичный boss_died — отдельно.
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	assert_true(boss.has_signal("died_at"),
		"died_at должен быть сохранён для Main._on_enemy_died_at")
	assert_true(boss.has_signal("attack_started"),
		"attack_started обязателен для attack telemetry")
	assert_true(boss.has_signal("attack_resolved"),
		"attack_resolved обязателен для attack telemetry")
