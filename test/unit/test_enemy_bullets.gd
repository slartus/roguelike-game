extends GutTest

# Регрессионные тесты для projectile sprites (commit 44d7a07):
# - каждая bullet сцена валидно грузится и имеет Sprite2D + texture
# - каждый ranged/boss шаблон ссылается на свою конкретную bullet сцену
#   (arrow / magic_bolt / dark_orb — не перепутаны)
# - enemy_bullet.gd в _ready поворачивает root по direction.angle()

const BulletExpectations := {
	"res://scenes/bullets/arrow_bullet.tscn": {
		"texture_path": "res://assets/sprites/bullets/arrow.png",
		"speed": 130.0,
		"lifetime": 3.0,
	},
	"res://scenes/bullets/magic_bolt_bullet.tscn": {
		"texture_path": "res://assets/sprites/bullets/magic_bolt.png",
		"speed": 100.0,
		"lifetime": 3.5,
	},
	"res://scenes/bullets/dark_orb_bullet.tscn": {
		"texture_path": "res://assets/sprites/bullets/dark_orb.png",
		"speed": 110.0,
		"lifetime": 3.5,
	},
}

func test_each_bullet_scene_has_visual_sprite_with_expected_texture() -> void:
	for path in BulletExpectations.keys():
		var scene: PackedScene = load(path)
		assert_not_null(scene, "bullet scene loads: %s" % path)
		var instance = scene.instantiate()
		var visual: Sprite2D = instance.get_node_or_null("Visual")
		assert_not_null(visual, "%s must have Visual: Sprite2D" % path.get_file())
		assert_not_null(visual.texture,
			"%s.Visual must have a texture assigned" % path.get_file())
		var expected_path: String = BulletExpectations[path]["texture_path"]
		assert_eq(visual.texture.resource_path, expected_path,
			"%s.Visual.texture must be %s" % [path.get_file(), expected_path])
		instance.free()

func test_each_bullet_scene_has_expected_speed_and_lifetime() -> void:
	for path in BulletExpectations.keys():
		var scene: PackedScene = load(path)
		var instance = scene.instantiate()
		var expected = BulletExpectations[path]
		assert_eq(instance.speed, expected["speed"],
			"%s.speed" % path.get_file())
		assert_eq(instance.lifetime, expected["lifetime"],
			"%s.lifetime" % path.get_file())
		instance.free()

func test_skeleton_archer_uses_arrow_bullet() -> void:
	var scene: PackedScene = load("res://scenes/enemies/ranged_enemy.tscn")
	var archer = scene.instantiate()
	assert_not_null(archer.bullet_scene)
	assert_eq(archer.bullet_scene.resource_path,
		"res://scenes/bullets/arrow_bullet.tscn",
		"Skeleton Archer должен стрелять стрелой")
	archer.free()

func test_lich_uses_magic_bolt_bullet() -> void:
	var scene: PackedScene = load("res://scenes/enemies/lich.tscn")
	var lich = scene.instantiate()
	assert_not_null(lich.bullet_scene)
	assert_eq(lich.bullet_scene.resource_path,
		"res://scenes/bullets/magic_bolt_bullet.tscn",
		"Lich должен стрелять magic bolt'ом")
	lich.free()

func test_boss_uses_dark_orb_bullet() -> void:
	var scene: PackedScene = load("res://scenes/enemies/boss.tscn")
	var boss = scene.instantiate()
	assert_not_null(boss.bullet_scene)
	assert_eq(boss.bullet_scene.resource_path,
		"res://scenes/bullets/dark_orb_bullet.tscn",
		"Necromancer должен стрелять dark orb'ами")
	boss.free()

func test_bullet_rotation_matches_direction_angle_on_ready() -> void:
	# direction устанавливается shooter'ом ДО add_child.
	# enemy_bullet.gd::_ready поворачивает root по direction.angle().
	var scene: PackedScene = load("res://scenes/bullets/arrow_bullet.tscn")
	var bullet = scene.instantiate()
	# Направление 45° вправо-вниз
	bullet.direction = Vector2(1, 1).normalized()
	var expected_angle: float = Vector2(1, 1).normalized().angle()
	add_child_autofree(bullet)
	# _ready уже вызван add_child'ом
	assert_almost_eq(bullet.rotation, expected_angle, 0.001,
		"bullet.rotation должен быть равен direction.angle()")

func test_bullet_rotation_defaults_to_zero_when_direction_zero() -> void:
	# Fallback: direction = Vector2.ZERO → Vector2.ZERO.angle() = 0 → rotation = 0
	var scene: PackedScene = load("res://scenes/bullets/magic_bolt_bullet.tscn")
	var bullet = scene.instantiate()
	bullet.direction = Vector2.ZERO
	add_child_autofree(bullet)
	assert_eq(bullet.rotation, 0.0,
		"нулевой direction → нулевой rotation, без ошибок")
