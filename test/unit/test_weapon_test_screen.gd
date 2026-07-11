extends GutTest

# Debug weapon-sandbox сцена. Проверяем структурный контракт:
# - в комнате появляется Player;
# - в верхнем ряду разложены ровно len(WEAPON_ROSTER) пикапов;
# - каждый пикап держит валидный WeaponResource;
# - каждое оружие из resources/weapons/ покрыто хотя бы одним пикапом
#   (защита от «забыли обновить список после добавления оружия»);
# - reset_run зашит в _ready и снимает стартовое оружие с игрока.

const WeaponTestScene = preload("res://scenes/debug/weapon_test_screen.tscn")
const WeaponTestScript = preload("res://scenes/debug/weapon_test_screen.gd")

var _snapshot: Dictionary

func before_each() -> void:
	_snapshot = {
		"floor": GameState.current_floor_number,
		"hp": GameState.player_health,
		"max_hp": GameState.player_max_health,
		"weapon": GameState.equipped_weapon,
		"level": GameState.player_level,
		"xp": GameState.player_xp,
		"tower_seed": GameState.tower_seed,
		"gold": GameState.total_gold,
		"health_potions": GameState.health_potions,
		"run_gold": GameState.run_gold,
		"run_kills": GameState.run_enemies_killed,
	}

func after_each() -> void:
	GameState.current_floor_number = _snapshot["floor"]
	GameState.player_health = _snapshot["hp"]
	GameState.player_max_health = _snapshot["max_hp"]
	GameState.equipped_weapon = _snapshot["weapon"]
	GameState.player_level = _snapshot["level"]
	GameState.player_xp = _snapshot["xp"]
	GameState.tower_seed = _snapshot["tower_seed"]
	GameState.total_gold = _snapshot["gold"]
	GameState.health_potions = _snapshot["health_potions"]
	GameState.run_gold = _snapshot["run_gold"]
	GameState.run_enemies_killed = _snapshot["run_kills"]

func test_scene_spawns_player_at_configured_position() -> void:
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var player_root: Node2D = screen.get_node("PlayerRoot")
	assert_eq(player_root.get_child_count(), 1,
		"PlayerRoot должен содержать ровно одного игрока")
	var player: CharacterBody2D = player_root.get_child(0)
	assert_true(player.is_in_group("player"), "игрок должен быть в группе 'player'")
	assert_eq(player.position, WeaponTestScript.PLAYER_SPAWN_POSITION)

func test_scene_lays_out_full_weapon_roster_in_a_row() -> void:
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var weapons_root: Node2D = screen.get_node("Weapons")
	assert_eq(weapons_root.get_child_count(), WeaponTestScript.WEAPON_ROSTER.size(),
		"должно быть по одному пикапу на каждое оружие из WEAPON_ROSTER")
	var expected_y := float(WeaponTestScript.WEAPONS_ROW_Y)
	var last_x := -INF
	for pickup in weapons_root.get_children():
		assert_not_null(pickup.weapon,
			"каждый WeaponPickup должен нести валидный WeaponResource")
		assert_eq(pickup.position.y, expected_y,
			"пикапы должны лежать в один горизонтальный ряд на y=%s" % expected_y)
		assert_gt(pickup.position.x, last_x,
			"пикапы должны идти слева направо без наложения")
		last_x = pickup.position.x

func test_all_weapons_in_resources_dir_are_included_in_roster() -> void:
	# Если добавили новое оружие в resources/weapons/, а WEAPON_ROSTER
	# не обновили — дебаг-сцена умалчивает про новое оружие. Проверка
	# защищает от такой рассинхронизации.
	var dir := DirAccess.open("res://resources/weapons/")
	assert_not_null(dir, "resources/weapons/ должна быть читаемой директорией")
	var expected_ids: Array[String] = []
	for filename in dir.get_files():
		if filename.ends_with(".tres"):
			expected_ids.append(filename.get_basename())
	var roster_ids: Array[String] = []
	for weapon in WeaponTestScript.WEAPON_ROSTER:
		roster_ids.append(weapon.resource_path.get_file().get_basename())
	expected_ids.sort()
	roster_ids.sort()
	assert_eq(roster_ids, expected_ids,
		"WEAPON_ROSTER должен содержать все .tres из resources/weapons/")

func test_ready_clears_equipped_weapon_so_player_starts_bare_handed() -> void:
	# Дебаг-сцена — сандбокс подбора: игрок должен реально подойти к
	# пикапу, а не начинать с дефолтного меча.
	GameState.equipped_weapon = preload("res://resources/weapons/dagger.tres")
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	assert_null(GameState.equipped_weapon,
		"после _ready() игрок стартует без оружия — подберёт из ряда")
	var player: CharacterBody2D = screen.get_node("PlayerRoot").get_child(0)
	assert_null(player.equipped_weapon,
		"Player.equipped_weapon тоже должен быть null")

func test_pickup_room_walls_confine_camera() -> void:
	# Камера игрока должна упираться в стены комнаты, а не в пустоту вне
	# viewport'а. Если limits не выставлены — camera выезжает за пределы.
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var player: CharacterBody2D = screen.get_node("PlayerRoot").get_child(0)
	var camera: Camera2D = player.get_node("Camera2D")
	assert_eq(camera.limit_left, 0)
	assert_eq(camera.limit_top, 0)
	assert_eq(camera.limit_right, WeaponTestScript.ROOM_WIDTH)
	assert_eq(camera.limit_bottom, WeaponTestScript.ROOM_HEIGHT)
