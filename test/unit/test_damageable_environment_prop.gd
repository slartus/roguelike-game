extends GutTest

# Unit-тесты DamageableEnvironmentProp: take_damage, faction фильтр,
# idempotent destroy, destroyed signal.

const _SCENE: PackedScene = preload("res://scenes/dungeon/damageable_environment_prop.tscn")
const _DEF := preload("res://scenes/dungeon/environment_prop_definition.gd")

func _spawn_prop(max_hp: int, factions: Array[StringName] = []) -> DamageableEnvironmentProp:
	var prop: DamageableEnvironmentProp = _SCENE.instantiate()
	prop.configure(&"test_prop", max_hp, factions, Vector2i.ONE)
	add_child_autofree(prop)
	return prop

func test_take_damage_reduces_health() -> void:
	var prop := _spawn_prop(3)
	prop.take_damage(1)
	assert_eq(prop.current_health(), 2, "HP должен уменьшаться на damage amount")
	assert_false(prop.is_destroyed(), "prop не должен быть destroyed при HP > 0")

func test_take_damage_destroys_when_health_reaches_zero() -> void:
	var prop := _spawn_prop(2)
	prop.take_damage(2)
	assert_true(prop.is_destroyed(), "prop должен быть destroyed при HP <= 0")

func test_destroy_is_idempotent() -> void:
	var prop := _spawn_prop(1)
	watch_signals(prop)
	prop.take_damage(5)
	prop.take_damage(5)
	prop.destroy()
	assert_signal_emit_count(prop, "destroyed", 1,
		"destroyed эмиттится ровно один раз, даже при повторных take_damage/destroy")

func test_faction_filter_blocks_disallowed_damage() -> void:
	# damage_factions = [PLAYER] → environment damage игнорируется.
	var prop := _spawn_prop(2, [_DEF.FACTION_PLAYER])
	prop.take_damage_from(_DEF.FACTION_ENVIRONMENT, 5)
	assert_eq(prop.current_health(), 2, "environment damage не должен пройти")
	assert_false(prop.is_destroyed(), "prop не должен разрушаться от environment")

func test_faction_filter_allows_listed_damage() -> void:
	var prop := _spawn_prop(1, [_DEF.FACTION_PLAYER])
	prop.take_damage_from(_DEF.FACTION_PLAYER, 5)
	assert_true(prop.is_destroyed(), "player damage должен разрушить prop")

func test_empty_faction_list_accepts_any_source() -> void:
	# Пустой список = любая фракция.
	var prop := _spawn_prop(1, [])
	prop.take_damage_from(_DEF.FACTION_ENVIRONMENT, 1)
	assert_true(prop.is_destroyed(),
		"пустой damage_factions = любая фракция может ранить")

func test_zero_damage_ignored() -> void:
	var prop := _spawn_prop(2)
	prop.take_damage(0)
	prop.take_damage(-3)
	assert_eq(prop.current_health(), 2,
		"нулевой/отрицательный damage не изменяет HP")

func test_take_damage_after_destroy_is_noop() -> void:
	var prop := _spawn_prop(1)
	prop.take_damage(1)
	# Второй урон уже мёртвому — не должен эмиттить destroyed повторно.
	watch_signals(prop)
	prop.take_damage(1)
	assert_signal_emit_count(prop, "destroyed", 0,
		"take_damage после destroy не должен эмиттить сигнал")

func test_destroyed_signal_carries_prop_id_and_position() -> void:
	var prop := _spawn_prop(1)
	prop.global_position = Vector2(123, 456)
	watch_signals(prop)
	prop.take_damage(1)
	assert_signal_emitted_with_parameters(prop, "destroyed",
		[&"test_prop", Vector2(123, 456)])

func test_prop_joins_damageable_group() -> void:
	var prop := _spawn_prop(1)
	assert_true(prop.is_in_group("damageable_prop"),
		"prop должен добавляться в 'damageable_prop' group")
