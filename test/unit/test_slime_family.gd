extends GutTest

# Разделение Slime на Adult и Small формы:
# - Adult (enemy.tscn) — размножающийся: bud_scene и death_split_scene
#   указывают на small_slime.tscn.
# - Small (small_slime.tscn) — базовый ранний враг: can_bud=false,
#   can_split_on_death=false. Не почкуется и не распадается.

const AdultSlimeScene = preload("res://scenes/enemies/enemy.tscn")
const SmallSlimeScene = preload("res://scenes/enemies/small_slime.tscn")

func _find_new_children(parent: Node, snapshot: Array, exclude: Node) -> Array:
	var result: Array = []
	for child in parent.get_children():
		if child == exclude:
			continue
		if child in snapshot:
			continue
		if child.is_in_group("enemy"):
			result.append(child)
	return result

func test_small_slime_scene_loads() -> void:
	var small = SmallSlimeScene.instantiate()
	assert_not_null(small, "small_slime.tscn должен загружаться")
	small.free()

func test_small_slime_cannot_bud() -> void:
	var small = SmallSlimeScene.instantiate()
	add_child_autofree(small)
	assert_eq(small.can_bud, false,
		"Small Slime must have can_bud=false из .tscn")

func test_small_slime_cannot_split_on_death() -> void:
	var small = SmallSlimeScene.instantiate()
	add_child_autofree(small)
	assert_eq(small.can_split_on_death, false,
		"Small Slime must have can_split_on_death=false из .tscn")

func test_small_slime_display_name_is_i18n_key() -> void:
	var small = SmallSlimeScene.instantiate()
	add_child_autofree(small)
	assert_eq(small.display_name, "ENEMY_SMALL_SLIME",
		"display_name — UPPER_SNAKE_CASE ключ (см. i18n.md)")

func test_small_slime_does_not_spawn_children_on_death() -> void:
	# Летальный урон на Small Slime не должен ни бросать split, ни падать.
	var small = SmallSlimeScene.instantiate()
	add_child_autofree(small)
	var parent := small.get_parent()
	await get_tree().process_frame
	var children_before := parent.get_child_count()
	small.take_damage(small.health + 100)
	assert_eq(parent.get_child_count(), children_before,
		"Small Slime при смерти не спавнит детей")
	await get_tree().create_timer(0.15).timeout

func test_adult_slime_buds_into_small_slime() -> void:
	# Ключевой инвариант: почка Adult — это Small Slime, не ещё один Adult.
	var adult = AdultSlimeScene.instantiate()
	add_child_autofree(adult)
	var parent := adult.get_parent()
	var snapshot := parent.get_children().duplicate()
	await get_tree().process_frame
	adult._state = adult.State.CHASE
	adult._tick_bud(0.01)
	adult._tick_bud(adult.BUD_DELAY + 0.1)
	var children := _find_new_children(parent, snapshot, adult)
	assert_eq(children.size(), 1, "почка = ровно 1 дитё")
	var bud = children[0]
	# Small Slime отличается через can_bud=false — Adult имеет can_bud=true.
	assert_eq(bud.can_bud, false,
		"почка = Small Slime (can_bud=false)")
	assert_eq(bud.can_split_on_death, false)

func test_adult_slime_death_split_spawns_small_slimes() -> void:
	# Adult при смерти распадается на death_split_count Small Slime.
	var adult = AdultSlimeScene.instantiate()
	add_child_autofree(adult)
	var parent := adult.get_parent()
	var snapshot := parent.get_children().duplicate()
	await get_tree().process_frame
	adult._spawn_death_split()
	var children := _find_new_children(parent, snapshot, adult)
	assert_eq(children.size(), adult.death_split_count,
		"количество осколков = death_split_count")
	for child in children:
		assert_eq(child.can_bud, false,
			"осколки = Small Slime, не почкуются")
		assert_eq(child.can_split_on_death, false,
			"осколки = Small Slime, не распадаются")

func test_small_slime_children_have_no_pickup_when_born_from_adult() -> void:
	# Anti-фарм: pickup_scene у детей обнуляется при спавне через
	# _spawn_death_split, иначе Small роняли бы зелья.
	var adult = AdultSlimeScene.instantiate()
	add_child_autofree(adult)
	var parent := adult.get_parent()
	var snapshot := parent.get_children().duplicate()
	await get_tree().process_frame
	adult._spawn_death_split()
	var children := _find_new_children(parent, snapshot, adult)
	for child in children:
		assert_null(child.pickup_scene,
			"pickup_scene обнуляется у осколков — иначе фарм зелий")

func test_adult_slime_has_bud_and_death_split_scenes_configured() -> void:
	# Регресс-контракт: если кто-то удалит ExtResource small_slime из
	# enemy.tscn, размножение молча выключится. Ловим это тестом.
	var adult = AdultSlimeScene.instantiate()
	add_child_autofree(adult)
	assert_not_null(adult.bud_scene,
		"Adult Slime должен иметь bud_scene из .tscn")
	assert_not_null(adult.death_split_scene,
		"Adult Slime должен иметь death_split_scene из .tscn")
	assert_eq(adult.can_bud, true)
	assert_eq(adult.can_split_on_death, true)
