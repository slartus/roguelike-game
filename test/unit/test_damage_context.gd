extends GutTest

# Тесты DamageContext factories и serialization.

class FakeEnemy extends CharacterBody2D:
	# Реальные поля должны быть объявлены в script attached — Object.set()
	# на raw CharacterBody2D не создаёт property. Используем class-based fake.
	var display_name: String = "ENEMY_UNKNOWN"
	var monster_level: int = 0
	var elite_rank: int = 0
	var temperament_id: StringName = &""

func test_new_context_has_unknown_defaults() -> void:
	var ctx := DamageContext.new()
	assert_eq(ctx.source_type, &"unknown")
	assert_eq(ctx.source_id, &"unknown")
	assert_eq(ctx.attack_id, &"unknown")
	assert_eq(ctx.target_type, &"unknown")
	assert_eq(ctx.damage_type, &"physical")
	assert_eq(ctx.amount, 0)
	assert_eq(ctx.elite_rank, 0)

func test_to_dictionary_contains_all_fields() -> void:
	var ctx := DamageContext.new()
	ctx.source_type = &"player_weapon"
	ctx.source_id = &"dagger"
	ctx.attack_id = &"melee_arc"
	ctx.amount = 3
	ctx.elite_rank = 1
	var dict := ctx.to_dictionary()
	assert_eq(dict["source_type"], "player_weapon")
	assert_eq(dict["source_id"], "dagger")
	assert_eq(dict["attack_id"], "melee_arc")
	assert_eq(dict["amount"], 3)
	assert_eq(dict["elite_rank"], 1)
	assert_true(dict.has("temperament_id"))
	assert_true(dict.has("room_id"))

func test_from_enemy_attack_populates_source_from_scene() -> void:
	var fake := FakeEnemy.new()
	fake.display_name = "ENEMY_GOBLIN"
	fake.scene_file_path = "res://scenes/enemies/goblin.tscn"
	fake.monster_level = 3
	fake.elite_rank = 1
	fake.temperament_id = &"aggressive"
	add_child_autofree(fake)
	var ctx := DamageContext.from_enemy_attack(fake, &"contact")
	assert_eq(ctx.source_type, &"enemy")
	assert_eq(ctx.source_id, &"goblin")
	assert_eq(ctx.attack_id, &"contact")
	assert_eq(ctx.source_level, 3)
	assert_eq(ctx.elite_rank, 1)
	assert_eq(ctx.temperament_id, &"aggressive")
	assert_eq(ctx.target_type, &"player")

func test_from_enemy_projectile_marks_source_type() -> void:
	var fake := FakeEnemy.new()
	fake.scene_file_path = "res://scenes/enemies/skeleton_archer.tscn"
	add_child_autofree(fake)
	var ctx := DamageContext.from_enemy_projectile(fake, &"aimed_shot")
	assert_eq(ctx.source_type, &"enemy_projectile")
	assert_eq(ctx.source_id, &"skeleton_archer")
	assert_eq(ctx.attack_id, &"aimed_shot")

func test_from_enemy_ability_sets_poison_damage_type() -> void:
	var ctx := DamageContext.from_enemy_ability(null, &"poison_tick")
	assert_eq(ctx.source_type, &"enemy_ability")
	assert_eq(ctx.attack_id, &"poison_tick")
	assert_eq(ctx.damage_type, &"poison")

func test_unknown_context_returns_defaults() -> void:
	var ctx := DamageContext.unknown()
	assert_eq(ctx.source_type, &"unknown")
	assert_eq(ctx.attack_id, &"unknown")
