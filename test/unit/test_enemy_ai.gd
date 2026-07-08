extends GutTest

# Smoke-тесты AI: perception, wander, state machine.
# Тонкие взаимодействия с игроком проверяются вручную через F5;
# здесь — только инварианты, которые легко проверить без физики.

const EnemyScene = preload("res://scenes/enemies/enemy.tscn")
const GoblinScene = preload("res://scenes/enemies/goblin.tscn")
const OrcScene = preload("res://scenes/enemies/orc.tscn")
const ChargerScene = preload("res://scenes/enemies/charger.tscn")
const RangedScene = preload("res://scenes/enemies/ranged_enemy.tscn")
const LichScene = preload("res://scenes/enemies/lich.tscn")
const BossScene = preload("res://scenes/enemies/boss.tscn")

func test_melee_default_perception_is_positive() -> void:
	var e = EnemyScene.instantiate()
	assert_gt(e.perception_radius, 0.0, "perception_radius > 0")
	assert_gt(e.wander_speed_ratio, 0.0, "wander slower than chase")
	assert_lte(e.wander_speed_ratio, 1.0, "wander not faster than chase")
	assert_gt(e.wander_change_interval, 0.0, "wander changes direction periodically")
	e.free()

func test_all_melee_variants_expose_perception() -> void:
	for scene in [GoblinScene, OrcScene]:
		var e = scene.instantiate()
		assert_gt(e.perception_radius, 0.0, "%s perception > 0" % scene.resource_path)
		e.free()

func test_charger_has_perception() -> void:
	var e = ChargerScene.instantiate()
	assert_gt(e.perception_radius, 0.0)
	e.free()

func test_ranged_and_lich_have_perception() -> void:
	for scene in [RangedScene, LichScene]:
		var e = scene.instantiate()
		assert_gt(e.perception_radius, 0.0, "%s perception > 0" % scene.resource_path)
		e.free()

func test_boss_sees_across_arena() -> void:
	var e = BossScene.instantiate()
	assert_gt(e.perception_radius, 1000.0, "boss must see across a big arena")
	e.free()

func test_melee_wander_direction_is_unit_vector() -> void:
	var e = EnemyScene.instantiate()
	e._pick_wander_direction()
	assert_almost_eq(e._wander_direction.length(), 1.0, 0.01,
		"wander direction must be normalized")
	assert_gt(e._wander_timer, 0.0, "wander_timer reset after pick")
	e.free()

func test_charger_starts_in_watch_state() -> void:
	var e = ChargerScene.instantiate()
	add_child_autofree(e)
	await get_tree().process_frame
	# State.WATCH = 0 (первый вариант enum)
	assert_eq(e._state, 0, "charger starts in WATCH")
