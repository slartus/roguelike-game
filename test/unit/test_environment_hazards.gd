extends GutTest

# Explosive barrel: telegraph delay, radial damage, chain reaction guard.

const _EXPLOSIVE_SCENE: PackedScene = preload("res://scenes/dungeon/explosive_barrel.tscn")
const _DAMAGEABLE_SCENE: PackedScene = preload("res://scenes/dungeon/damageable_environment_prop.tscn")
const _DEF := preload("res://scenes/dungeon/environment_prop_definition.gd")

# Fake "enemy": принимает take_damage, чтобы hazard мог его ударить.
class FakeVictim extends Node2D:
	var health: int = 10
	var received_damage: int = 0
	func _init() -> void:
		add_to_group("enemy")
	func take_damage(amount: int) -> void:
		health -= amount
		received_damage += amount

func _spawn_explosive(radius: float, damage: int, telegraph: float) -> Node2D:
	var barrel: Node2D = _EXPLOSIVE_SCENE.instantiate()
	barrel.configure(&"explosive_barrel", 2, [_DEF.FACTION_PLAYER] as Array[StringName], Vector2i.ONE)
	barrel.configure_hazard(radius, damage, telegraph)
	add_child_autofree(barrel)
	return barrel

func _spawn_victim_at(pos: Vector2) -> FakeVictim:
	var v := FakeVictim.new()
	v.global_position = pos
	add_child_autofree(v)
	return v

func test_explosion_does_not_fire_before_telegraph_ends() -> void:
	var barrel := _spawn_explosive(50.0, 3, 0.5)
	barrel.global_position = Vector2.ZERO
	var victim := _spawn_victim_at(Vector2(10, 0))
	# Ломаем барель — начинается telegraph, урона ещё нет.
	barrel.take_damage(5)
	await get_tree().process_frame
	assert_eq(victim.received_damage, 0,
		"damage не должен наноситься до конца telegraph")

func test_explosion_hits_targets_in_radius_after_telegraph() -> void:
	var barrel := _spawn_explosive(30.0, 3, 0.05)  # короткий telegraph
	barrel.global_position = Vector2.ZERO
	var victim_close := _spawn_victim_at(Vector2(10, 0))
	var victim_far := _spawn_victim_at(Vector2(500, 0))
	barrel.take_damage(5)
	# Ждём > telegraph_time. Один frame = ~0.016s при 60fps; process_frame
	# от GUT — physics tick, дадим несколько кадров через таймер.
	await get_tree().create_timer(0.15).timeout
	assert_eq(victim_close.received_damage, 3,
		"близкий victim должен получить explosion damage")
	assert_eq(victim_far.received_damage, 0,
		"дальний victim (вне радиуса) не должен получить damage")

func test_chain_reaction_guarded_by_faction() -> void:
	# Два соседних барреля. При взрыве первого — второй получает
	# environment damage, но его damage_factions = [PLAYER] → отсекается,
	# он НЕ взрывается.
	var barrel_a := _spawn_explosive(50.0, 3, 0.05)
	barrel_a.global_position = Vector2.ZERO
	var barrel_b := _spawn_explosive(50.0, 3, 0.05)
	barrel_b.global_position = Vector2(20, 0)
	watch_signals(barrel_b)
	barrel_a.take_damage(5)  # trigger telegraph
	await get_tree().create_timer(0.2).timeout
	# barrel_b НЕ должен взорваться (не эмиттит destroyed).
	assert_signal_emit_count(barrel_b, "destroyed", 0,
		"chain reaction должен отсекаться damage_factions фильтром")

func test_hazard_destroyed_signal_emitted_once_after_telegraph() -> void:
	var barrel := _spawn_explosive(30.0, 3, 0.05)
	watch_signals(barrel)
	# destroyed эмиттится синхронно в _destroy → до await barrel ещё жив.
	barrel.take_damage(5)
	assert_signal_emit_count(barrel, "destroyed", 1,
		"destroyed эмиттится один раз в _destroy() (до explosion)")
	# Ждём взрыв, чтобы barrel довёл queue_free до конца — не оставить
	# unfreed node.
	await get_tree().create_timer(0.15).timeout

func test_ordinary_destructible_not_destroyed_by_environment_damage() -> void:
	# Обычный destructible crate в радиусе — тоже принимает только PLAYER
	# damage, поэтому environment explosion его не разрушит. Даёт
	# «предсказуемый» chain-behavior: игрок сам ломает, среда — нет.
	var barrel := _spawn_explosive(50.0, 5, 0.05)
	barrel.global_position = Vector2.ZERO
	var crate: DamageableEnvironmentProp = _DAMAGEABLE_SCENE.instantiate()
	crate.configure(&"destructible_crate", 2, [_DEF.FACTION_PLAYER] as Array[StringName], Vector2i.ONE)
	crate.global_position = Vector2(15, 0)
	add_child_autofree(crate)
	watch_signals(crate)
	barrel.take_damage(5)
	await get_tree().create_timer(0.15).timeout
	assert_signal_emit_count(crate, "destroyed", 0,
		"обычный destructible не должен разрушаться от environment damage")

func test_immediate_explosion_when_telegraph_zero() -> void:
	# Edge case: telegraph_time = 0 → взрыв в первом же tick'е после destroy.
	var barrel := _spawn_explosive(30.0, 2, 0.0)
	barrel.global_position = Vector2.ZERO
	var victim := _spawn_victim_at(Vector2(10, 0))
	barrel.take_damage(5)
	# Один physics tick достаточно.
	await get_tree().create_timer(0.05).timeout
	assert_eq(victim.received_damage, 2,
		"с telegraph=0 взрыв должен произойти сразу после первого tick'а")
