extends GutTest

# PR 2: Player projectile identity.
#
# Каждый ranged/magic weapon использует собственную projectile scene
# (не переиспользует enemy scenes). Стрелы/болты вращаются вдоль
# direction. Круглые orbs держат rotation = 0. Цвет применяется после
# _ready() (регресс: раньше modulate падал на @onready null visual).
# WeaponController спавнит снаряд у оружия, а не в центре игрока.

const ShortBowRes = preload("res://resources/weapons/short_bow.tres")
const CrossbowRes = preload("res://resources/weapons/crossbow.tres")
const WandRes = preload("res://resources/weapons/wand.tres")
const StaffRes = preload("res://resources/weapons/apprentice_staff.tres")

const PlayerArrowScene = preload("res://scenes/bullets/player_arrow.tscn")
const PlayerCrossbowBoltScene = preload("res://scenes/bullets/player_crossbow_bolt.tscn")
const PlayerWandOrbScene = preload("res://scenes/bullets/player_wand_orb.tscn")
const PlayerStaffOrbScene = preload("res://scenes/bullets/player_staff_orb.tscn")

const BulletScript = preload("res://scenes/bullets/bullet.gd")
const EnemyBulletScript = preload("res://scenes/bullets/enemy_bullet.gd")

const WeaponControllerScript = preload("res://scenes/player/weapon_controller.gd")
const DefaultBulletScene = preload("res://scenes/bullets/bullet.tscn")

# --- Identity: weapons wired to distinct scenes ---

func test_each_ranged_weapon_has_its_own_projectile_scene() -> void:
	for weapon in [ShortBowRes, CrossbowRes, WandRes, StaffRes]:
		assert_not_null(weapon.projectile_scene,
			"%s должен иметь собственный projectile_scene" % weapon.display_name)

func test_ranged_weapon_scenes_are_all_different() -> void:
	var paths: Dictionary = {}
	for weapon in [ShortBowRes, CrossbowRes, WandRes, StaffRes]:
		var path: String = weapon.projectile_scene.resource_path
		assert_false(paths.has(path),
			"projectile_scene %s повторяется — снаряды не отличимы" % path)
		paths[path] = true

func test_short_bow_uses_player_arrow_scene() -> void:
	assert_eq(ShortBowRes.projectile_scene.resource_path,
		PlayerArrowScene.resource_path)

func test_crossbow_uses_player_crossbow_bolt_scene() -> void:
	assert_eq(CrossbowRes.projectile_scene.resource_path,
		PlayerCrossbowBoltScene.resource_path)

func test_wand_uses_player_wand_orb_scene() -> void:
	assert_eq(WandRes.projectile_scene.resource_path,
		PlayerWandOrbScene.resource_path)

func test_staff_uses_player_staff_orb_scene() -> void:
	assert_eq(StaffRes.projectile_scene.resource_path,
		PlayerStaffOrbScene.resource_path)

# --- Player damage logic (не enemy) ---

func test_player_projectiles_use_player_damage_script_not_enemy() -> void:
	# Регресс: player projectiles должны использовать bullet.gd
	# (наносит урон врагам). enemy_bullet.gd — обратная логика (бьёт игрока).
	# Сравниваем через identity скриптов (BulletScript.resource_path не
	# резолвится как type-property preload'ed const в Godot 4.7).
	for scene in [PlayerArrowScene, PlayerCrossbowBoltScene,
			PlayerWandOrbScene, PlayerStaffOrbScene]:
		var bullet = scene.instantiate()
		add_child_autofree(bullet)
		assert_true(bullet.get_script() == BulletScript,
			"%s должен использовать player bullet.gd" % scene.resource_path)
		assert_false(bullet.get_script() == EnemyBulletScript,
			"%s НЕ должен использовать enemy_bullet.gd" % scene.resource_path)

# --- Rotation: elongated projectiles rotate, orbs stay flat ---

func test_arrow_rotates_with_direction() -> void:
	var arrow = PlayerArrowScene.instantiate()
	arrow.direction = Vector2(0, 1)  # вниз
	add_child_autofree(arrow)
	# _ready прочитал direction и повернул node.
	assert_almost_eq(arrow.rotation, PI / 2, 0.001,
		"arrow должна повернуться вдоль direction (0,1) → PI/2")

func test_crossbow_bolt_rotates_with_direction() -> void:
	var bolt = PlayerCrossbowBoltScene.instantiate()
	bolt.direction = Vector2(-1, 0)  # влево
	add_child_autofree(bolt)
	assert_almost_eq(bolt.rotation, PI, 0.001,
		"bolt должен повернуться вдоль direction (-1,0) → PI")

func test_wand_orb_does_not_rotate() -> void:
	var orb = PlayerWandOrbScene.instantiate()
	orb.direction = Vector2(0, 1)
	add_child_autofree(orb)
	assert_almost_eq(orb.rotation, 0.0, 0.001,
		"круглый wand orb должен держать rotation = 0")

func test_staff_orb_does_not_rotate() -> void:
	var orb = PlayerStaffOrbScene.instantiate()
	orb.direction = Vector2(-1, 1)
	add_child_autofree(orb)
	assert_almost_eq(orb.rotation, 0.0, 0.001,
		"круглый staff orb должен держать rotation = 0")

# --- Color caching: applied after _ready() ---

func test_projectile_color_applied_after_ready() -> void:
	# Регресс: WeaponController выставляет direction+stats ДО add_child.
	# @onready _visual при этом ещё null → apply_weapon_stats не мог тонировать.
	# Ждём кадр — _ready теперь читает _pending_visual_color и применяет.
	var arrow = PlayerArrowScene.instantiate()
	var stats := WeaponStats.new()
	stats.damage = 1
	stats.projectile_speed = 100.0
	stats.projectile_lifetime = 1.0
	stats.pierce = 0
	stats.projectile_color = Color(0.2, 0.8, 0.4, 1.0)  # зелёный
	arrow.apply_weapon_stats(stats)
	# ДО add_child _visual == null → modulate не должен применяться,
	# но цвет закеширован в _pending_visual_color.
	add_child_autofree(arrow)
	await get_tree().process_frame
	var visual: Sprite2D = arrow.get_node("Visual")
	assert_eq(visual.modulate, Color(0.2, 0.8, 0.4, 1.0),
		"projectile_color должен быть применён к _visual.modulate после _ready")

# --- Spawn origin: from weapon, not player center ---

func _make_controller_with_owner_at(pos: Vector2) -> WeaponController:
	# parent (GUT runner) может иметь собственный transform, поэтому
	# `global_position = pos` после add_child не гарантирует что owner
	# окажется именно в `pos`. Тесты не завязаны на абсолютные координаты
	# и сравнивают через `_owner_player.global_position` — pos здесь только
	# для читаемости имён.
	var owner_player := CharacterBody2D.new()
	add_child_autofree(owner_player)
	owner_player.global_position = pos
	var wc: WeaponController = WeaponControllerScript.new()
	wc.default_projectile_scene = DefaultBulletScene
	owner_player.add_child(wc)
	wc.setup(owner_player)
	return wc

# Собирает все bullet-подобные ноды в дереве по критерию has_method + Node2D.
# Возвращает set (Dictionary с true) для быстрого diff.
func _snapshot_bullets() -> Dictionary:
	var seen := {}
	_collect_bullets_into(get_tree().root, seen)
	return seen

func _collect_bullets_into(node: Node, out: Dictionary) -> void:
	if node.has_method("apply_weapon_stats") and node is Node2D:
		out[node.get_instance_id()] = node
	for child in node.get_children():
		_collect_bullets_into(child, out)

# Возвращает первую пулю, которой не было в snapshot before — то есть
# только что заспавненную текущим try_attack. Не находит старые пули от
# предыдущих тестов.
func _find_new_projectile(before: Dictionary) -> Node2D:
	var after := _snapshot_bullets()
	for iid in after.keys():
		if not before.has(iid):
			return after[iid]
	return null

func _free_all_bullets() -> void:
	for iid in _snapshot_bullets().keys():
		var bullet: Node = instance_from_id(iid)
		if is_instance_valid(bullet):
			bullet.queue_free()

func after_each() -> void:
	_free_all_bullets()

func test_spawn_origin_shifted_along_direction_by_spawn_distance() -> void:
	# Aiming right → direction = (1, 0). Spawn distance 18 → пуля должна
	# оказаться в 18 пикселях справа от owner_player.global_position.
	var wc := _make_controller_with_owner_at(Vector2(100, 100))
	var owner: Node2D = wc.get_parent()
	var target: Vector2 = owner.global_position + Vector2(100, 0)
	var before := _snapshot_bullets()
	var attacked := wc.try_attack(ShortBowRes, target)
	assert_true(attacked)
	var bullet: Node2D = _find_new_projectile(before)
	assert_not_null(bullet, "стрела должна быть заспавнена")
	# ShortBowRes.projectile_spawn_distance = 18, spread 2°: bullet может
	# слегка отклониться от чистого (1,0). Проверяем что расстояние от
	# owner до spawn point ≈ 18 и позиция сдвинута вправо.
	var offset: Vector2 = bullet.global_position - owner.global_position
	assert_almost_eq(offset.length(), 18.0, 0.5,
		"spawn distance примерно совпадает с weapon.projectile_spawn_distance")
	assert_gt(offset.x, 0.0,
		"spawn сдвинут вправо от игрока (по direction)")

func test_spawn_origin_at_player_when_distance_zero() -> void:
	# Weapon без spawn_distance (0) → spawn в центре игрока — обратная
	# совместимость. Проверяем на synthetic weapon с distance=0.
	var wc := _make_controller_with_owner_at(Vector2(50, 50))
	var owner: Node2D = wc.get_parent()
	var weapon := WeaponResource.new()
	weapon.attack_type = "projectile"
	weapon.damage = 1
	weapon.attack_interval = 0.5
	weapon.projectile_speed = 100.0
	weapon.projectile_lifetime = 0.5
	weapon.projectiles_per_attack = 1
	weapon.projectile_spawn_distance = 0.0
	var before := _snapshot_bullets()
	var attacked := wc.try_attack(weapon, owner.global_position + Vector2(100, 0))
	assert_true(attacked)
	var bullet: Node2D = _find_new_projectile(before)
	assert_not_null(bullet)
	assert_true(bullet.global_position.is_equal_approx(owner.global_position),
		"spawn_distance=0 → снаряд в центре игрока (обратная совместимость)")

func test_spawn_origin_works_in_all_cardinal_directions() -> void:
	# Проверяем что spawn работает для 4 сторон — не только вправо.
	# ShortBowRes.projectile_spawn_distance = 18. offset считаем от owner.
	var direction_offsets := [
		[Vector2(100, 0),  Vector2(18, 0)],   # right
		[Vector2(-100, 0), Vector2(-18, 0)],  # left
		[Vector2(0, 100),  Vector2(0, 18)],   # down
		[Vector2(0, -100), Vector2(0, -18)],  # up
	]
	for pair in direction_offsets:
		var target_offset: Vector2 = pair[0]
		var expected_offset: Vector2 = pair[1]
		var wc := _make_controller_with_owner_at(Vector2(100, 100))
		var owner: Node2D = wc.get_parent()
		var before := _snapshot_bullets()
		wc.try_attack(ShortBowRes, owner.global_position + target_offset)
		var bullet: Node2D = _find_new_projectile(before)
		assert_not_null(bullet)
		var actual_offset: Vector2 = bullet.global_position - owner.global_position
		# Small spread (2°) может сместить пулю. Проверяем радиальную дистанцию.
		assert_almost_eq((actual_offset - expected_offset).length(), 0.0, 0.5,
			"cardinal spawn: expected offset≈%s, actual offset=%s" % [expected_offset, actual_offset])
		bullet.queue_free()
		await get_tree().process_frame
