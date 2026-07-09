extends GutTest

# Слайм при смерти распадается на 2 половинных слайма:
# - `_spawn_death_split` спавнит DEATH_SPLIT_COUNT=2 детей у родителя;
# - дети получают scale=0.5, половинные HP/xp/gold, no pickup_scene;
# - дети помечены `_is_sterile=true` — не почкуются и не делятся дальше;
# - take_damage override при смертельном ударе триггерит split, но
#   стерильные слаймы split пропускают.

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

func test_split_children_are_sterile() -> void:
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	var snapshot := parent.get_children().duplicate()
	await get_tree().process_frame
	slime._spawn_death_split()
	var children := _find_new_slime_children(parent, snapshot, slime)
	assert_eq(children.size(), 2)
	for child in children:
		assert_eq(child._is_sterile, true,
			"дети split должны быть стерильны")

func test_split_children_scaled_half() -> void:
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	var snapshot := parent.get_children().duplicate()
	await get_tree().process_frame
	slime._spawn_death_split()
	var children := _find_new_slime_children(parent, snapshot, slime)
	for child in children:
		assert_almost_eq(child.scale.x, slime.DEATH_SPLIT_SCALE, 0.001)
		assert_almost_eq(child.scale.y, slime.DEATH_SPLIT_SCALE, 0.001)

func test_split_children_have_halved_stats() -> void:
	var slime = _spawn_slime()
	var parent := slime.get_parent()
	var snapshot := parent.get_children().duplicate()
	await get_tree().process_frame
	# max_health/xp/gold после _ready = scaled(base, floor). Ловим их
	# значения ДО split — они одинаковые у матери и у свежих детей,
	# потому что и там и там прогоняется Balance с тем же floor.
	var expected_hp := maxi(1, slime.max_health / 2)
	var expected_xp := maxi(1, slime.xp_reward / 2)
	var expected_gold := maxi(1, slime.gold_reward / 2)
	slime._spawn_death_split()
	var children := _find_new_slime_children(parent, snapshot, slime)
	for child in children:
		assert_eq(child.max_health, expected_hp,
			"HP ребёнка = половина от материнского (не меньше 1)")
		assert_eq(child.health, child.max_health,
			"health синхронизирован с max_health после половинения")
		assert_eq(child.xp_reward, expected_xp)
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
