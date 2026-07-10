extends GutTest

# Adult Slime при смерти распадается на death_split_count детей из
# death_split_scene (по конфигу enemy.tscn — small_slime.tscn):
# - `_spawn_death_split` спавнит детей у родителя;
# - дети — реальные Small Slime со своими stat из .tscn (max_health=1,
#   xp=2, gold=1, scale=0.5) — половинить их вручную больше не нужно;
# - дети не могут почковаться (`can_bud=false` в small_slime.tscn) и
#   не делятся дальше (`can_split_on_death=false`);
# - у детей обнуляется `pickup_scene` — иначе почкование становилось
#   бы лут-механикой;
# - take_damage override при смертельном ударе триггерит split, но
#   стерильные слаймы (`_is_sterile=true` или `can_split_on_death=false`)
#   split пропускают.

const SlimeScene = preload("res://scenes/enemies/enemy.tscn")

func _spawn_slime():
	var slime = SlimeScene.instantiate()
	add_child_autofree(slime)
	return slime

func _count_slimes_under(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child.is_in_group("enemy"):
			n += 1
	return n

func _find_new_slime_children(parent: Node, snapshot: Array, exclude: Node) -> Array:
	var result: Array = []
	for child in parent.get_children():
		if child == exclude:
			continue
		if child in snapshot:
			continue
		if child.is_in_group("enemy"):
			result.append(child)
	return result

func test_direct_split_spawns_two_children() -> void:
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	var before := _count_slimes_under(parent)
	await get_tree().process_frame
	slime._spawn_death_split()
	assert_eq(_count_slimes_under(parent), before + 2,
		"split должен спавнить ровно 2 детей")

func test_split_children_cannot_bud_or_split() -> void:
	# Small Slime как дети — сам себя блокирует через can_bud=false и
	# can_split_on_death=false, поэтому цепь остаётся конечной.
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	var snapshot := parent.get_children().duplicate()
	await get_tree().process_frame
	slime._spawn_death_split()
	var children := _find_new_slime_children(parent, snapshot, slime)
	assert_eq(children.size(), 2)
	for child in children:
		assert_eq(child.can_bud, false,
			"дети split (Small Slime) не почкуются")
		assert_eq(child.can_split_on_death, false,
			"дети split (Small Slime) не распадаются при смерти")

func test_split_children_scaled_by_scene() -> void:
	# Small Slime сам маленький через scale в .tscn (0.5, 0.5) — половинить
	# runtime уже не нужно.
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	var snapshot := parent.get_children().duplicate()
	await get_tree().process_frame
	slime._spawn_death_split()
	var children := _find_new_slime_children(parent, snapshot, slime)
	for child in children:
		assert_almost_eq(child.scale.x, 0.5, 0.001,
			"scale Small Slime = 0.5 из .tscn")
		assert_almost_eq(child.scale.y, 0.5, 0.001)

func test_split_children_have_small_slime_stats() -> void:
	# Small Slime приходит со своими base stat max_health=1, xp=2, gold=1
	# (после Balance.scaled_* на текущем этаже).
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	var snapshot := parent.get_children().duplicate()
	await get_tree().process_frame
	var floor_num := GameState.current_floor_number
	var expected_hp := Balance.scaled_hp(1, floor_num)
	var expected_xp := Balance.scaled_xp_reward(2, floor_num)
	var expected_gold := Balance.scaled_gold_reward(1, floor_num)
	slime._spawn_death_split()
	var children := _find_new_slime_children(parent, snapshot, slime)
	for child in children:
		assert_eq(child.max_health, expected_hp,
			"HP ребёнка = scaled(1, floor) — базовый Small Slime")
		assert_eq(child.health, child.max_health)
		assert_eq(child.xp_reward, expected_xp,
			"XP ребёнка = scaled(2, floor)")
		assert_eq(child.gold_reward, expected_gold)

func test_split_children_have_no_pickup() -> void:
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	var snapshot := parent.get_children().duplicate()
	await get_tree().process_frame
	slime._spawn_death_split()
	var children := _find_new_slime_children(parent, snapshot, slime)
	for child in children:
		assert_null(child.pickup_scene,
			"осколки не должны ронять пикапы — иначе фарм")

func test_sterile_slime_does_not_split_on_death() -> void:
	var slime = _spawn_slime()
	slime._is_sterile = true
	var parent := slime.get_parent()
	await get_tree().process_frame
	var before := _count_slimes_under(parent)
	# take_damage — coroutine из-за await в super. Не await'им: нам
	# нужен только синхронный split-код нашего override, который уже
	# отработал к моменту возврата.
	slime.take_damage(slime.health + 100)
	assert_eq(_count_slimes_under(parent), before,
		"стерильный слайм не спавнит осколков при смерти")
	# Даём super дожить до queue_free, чтобы GUT не ругался на orphan'а.
	await get_tree().create_timer(0.15).timeout

func test_take_damage_triggers_split_on_lethal_hit() -> void:
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	await get_tree().process_frame
	var before := _count_slimes_under(parent)
	slime.take_damage(slime.health + 100)  # летальный урон
	# После take_damage дети уже спавнены (сразу после синхронной части
	# super), мать ещё в дереве до окончания её собственного 0.08с awaits.
	assert_eq(_count_slimes_under(parent), before + 2,
		"летальный урон должен породить 2 осколка")
	await get_tree().create_timer(0.15).timeout

func test_non_lethal_hit_does_not_split() -> void:
	var slime = _spawn_slime()
	slime.max_health = 10
	slime.health = 10
	var parent := slime.get_parent()
	await get_tree().process_frame
	var before := _count_slimes_under(parent)
	slime.take_damage(1)  # НЕ убивает
	assert_eq(_count_slimes_under(parent), before,
		"нелетальный урон не должен ничего спавнить")

func test_sterile_slime_does_not_bud() -> void:
	# Feature 1 × Feature 2: осколок не почкуется при агре.
	var slime = _spawn_slime()
	slime._is_sterile = true
	await get_tree().process_frame
	slime._state = slime.State.CHASE
	slime._tick_bud(0.01)
	assert_eq(slime._bud_delay_timer, 0.0,
		"стерильный слайм не запускает bud-таймер даже на фронте агра")
	slime._tick_bud(slime.BUD_DELAY + 0.1)
	assert_eq(slime._has_budded, false,
		"стерильный слайм не помечается _has_budded — почки не было")
