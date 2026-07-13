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
	# Не ждём physics_frame: тест проверяет position, установленную
	# синхронно в _spawn_player() из _ready. Лишний physics tick запускает
	# CharacterBody2D-выталкивание из соседних тел, что для проверки
	# начальной spawn-позиции семантически не нужно.
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
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

func test_pickup_respawns_in_same_slot_after_being_taken() -> void:
	# Симулируем «игрок взял оружие»: pickup делает queue_free при контакте.
	# Дебаг-сцена должна заметить tree_exited и подставить в тот же слот
	# новый экземпляр того же оружия — иначе ряд редеет, и после N подборов
	# песочница становится пустой.
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var weapons_root: Node2D = screen.get_node("Weapons")
	var original_size: int = weapons_root.get_child_count()
	var taken: Area2D = weapons_root.get_child(0)
	var slot_position: Vector2 = taken.position
	var expected_weapon: WeaponResource = taken.weapon
	# remove_child + queue_free детерминированно: remove_child синхронно
	# эмиттит tree_exited (наш _on_pickup_taken запускается сразу), а
	# queue_free освобождает ноду в конце кадра. Голый queue_free тоже
	# работает, но в CI под нагрузкой tree_exited может уехать в следующий
	# кадр — тест начнёт флакать.
	weapons_root.remove_child(taken)
	taken.queue_free()
	await get_tree().process_frame
	assert_eq(weapons_root.get_child_count(), original_size,
		"после подбора должен появиться новый pickup, ряд остаётся полным")
	var respawned_at_slot: Area2D = null
	for pickup in weapons_root.get_children():
		if pickup.position.is_equal_approx(slot_position):
			respawned_at_slot = pickup
			break
	assert_not_null(respawned_at_slot,
		"новый pickup должен появиться в исходной позиции слота")
	assert_eq(respawned_at_slot.weapon, expected_weapon,
		"новый pickup должен нести то же оружие, что и подобранное")

func test_weapon_info_panel_starts_empty() -> void:
	# Игрок стартует без оружия — панель показывает placeholder, стат-строки
	# скрыты. Иначе UI рисует нули/мусор и вводит в заблуждение.
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var empty_label: Label = screen.get_node("HUD/WeaponInfoPanel/EmptyLabel")
	var stats_box: VBoxContainer = screen.get_node("HUD/WeaponInfoPanel/StatsBox")
	assert_true(empty_label.visible, "placeholder виден при пустой руке")
	assert_false(stats_box.visible, "5 стат-строк скрыты при пустой руке")

func test_weapon_info_panel_populates_on_equip() -> void:
	# После equip() игрок эмиттит weapon_changed → панель заполняется:
	# скрываем placeholder, показываем стат-строки со значениями из weapon.
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var player: CharacterBody2D = screen.get_node("PlayerRoot").get_child(0)
	var weapon: WeaponResource = preload("res://resources/weapons/short_sword.tres")
	player.equip(weapon)
	await get_tree().process_frame
	var empty_label: Label = screen.get_node("HUD/WeaponInfoPanel/EmptyLabel")
	var stats_box: VBoxContainer = screen.get_node("HUD/WeaponInfoPanel/StatsBox")
	assert_false(empty_label.visible, "placeholder скрыт когда есть оружие")
	assert_true(stats_box.visible, "стат-строки показаны когда есть оружие")
	var name_label: Label = screen.get_node("HUD/WeaponInfoPanel/StatsBox/NameLabel")
	var damage_label: Label = screen.get_node("HUD/WeaponInfoPanel/StatsBox/DamageLabel")
	assert_ne(name_label.text, "", "название оружия должно быть заполнено")
	assert_ne(name_label.text, "—", "название не должно остаться заглушкой")
	assert_string_contains(damage_label.text, str(weapon.damage))

func test_weapon_info_panel_switches_between_weapons() -> void:
	# Смена оружия обновляет все 5 стат-строк. Проверяем что damage поменялся
	# — если панель бы не подписалась на weapon_changed, второй equip оставил
	# бы старые значения.
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var player: CharacterBody2D = screen.get_node("PlayerRoot").get_child(0)
	var damage_label: Label = screen.get_node("HUD/WeaponInfoPanel/StatsBox/DamageLabel")
	player.equip(preload("res://resources/weapons/dagger.tres"))
	await get_tree().process_frame
	var first_text := damage_label.text
	player.equip(preload("res://resources/weapons/apprentice_staff.tres"))
	await get_tree().process_frame
	assert_ne(damage_label.text, first_text,
		"damage-строка обязана обновиться при смене оружия")

func test_player_preview_exists_with_3x_scale_at_bottom_left() -> void:
	# Проверяем сам факт наличия превью и его настройки — если сцену переверстают
	# и уронят preview node из tscn, симуляция статуса игрока в отладке пропадёт.
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var preview: Node2D = screen.get_node("PlayerPreview")
	assert_not_null(preview, "PlayerPreview должен присутствовать в сцене")
	assert_eq(preview.scale, Vector2(3, 3), "PlayerPreview масштабирован 3× по обеим осям")
	# Левая-нижняя четверть комнаты (x < ROOM_WIDTH/2, y > ROOM_HEIGHT/2).
	assert_lt(preview.position.x, float(WeaponTestScript.ROOM_WIDTH) * 0.5,
		"PlayerPreview расположен в левой половине")
	assert_gt(preview.position.y, float(WeaponTestScript.ROOM_HEIGHT) * 0.5,
		"PlayerPreview расположен в нижней половине")

func test_player_preview_mirrors_player_visual_texture() -> void:
	# _process должен скопировать текстуру Player.Visual в PreviewVisual.
	# Если синк сломан — превью не показывает спрайт игрока.
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var player: CharacterBody2D = screen.get_node("PlayerRoot").get_child(0)
	# Player._physics_process читает get_global_mouse_position и постоянно
	# обновляет _facing/весь weapon transform. В headless-тесте курсор не
	# контролируем — фризим physics_process, тогда состояние Player.Visual
	# и Player.Weapon становится детерминированным.
	player.set_physics_process(false)
	await get_tree().process_frame  # _process срабатывает после _ready на следующем кадре
	var player_visual: Sprite2D = player.get_node("Visual")
	var preview_visual: Sprite2D = screen.get_node("PlayerPreview/PreviewVisual")
	assert_eq(preview_visual.texture, player_visual.texture,
		"текстура превью должна совпадать с текстурой Player.Visual")

func test_player_preview_mirrors_weapon_after_equip() -> void:
	# После equip'а Player.Weapon.visible = true; превью-weapon тоже должен
	# стать видимым и получить те же текстуру/поворот/позицию.
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var player: CharacterBody2D = screen.get_node("PlayerRoot").get_child(0)
	# Фризим Player.physics_process — иначе _update_facing_from_aim может
	# флипнуть _facing из-за неконтролируемой mouse position и переставить
	# Player.Weapon (position/rotation/flip_h) между sync-ом preview и
	# assert'ом. Плюс детерминизируем facing перед equip.
	player.set_physics_process(false)
	player.face(1)
	player.equip(preload("res://resources/weapons/short_sword.tres"))
	await get_tree().process_frame  # _process синкает preview
	var player_weapon: Sprite2D = player.get_node("Weapon")
	var preview_weapon: Sprite2D = screen.get_node("PlayerPreview/PreviewWeapon")
	assert_true(player_weapon.visible, "Player.Weapon становится видимым после equip")
	assert_true(preview_weapon.visible, "PreviewWeapon зеркалит visible")
	assert_eq(preview_weapon.texture, player_weapon.texture,
		"текстура weapon-превью должна совпадать с Player.Weapon")
	assert_eq(preview_weapon.position, player_weapon.position,
		"позиция weapon-превью должна совпадать (в локальных координатах)")
	assert_eq(preview_weapon.rotation, player_weapon.rotation)
	assert_eq(preview_weapon.flip_h, player_weapon.flip_h)

func test_weapon_info_panel_hides_stats_when_weapon_cleared() -> void:
	# Если по какой-то причине equipped_weapon вернётся в null (эмулируем
	# ручной вызов signal) — панель должна снова спрятать стат-строки.
	var screen = WeaponTestScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var player: CharacterBody2D = screen.get_node("PlayerRoot").get_child(0)
	player.equip(preload("res://resources/weapons/spear.tres"))
	await get_tree().process_frame
	# Прямо эмиттим signal с null — публичного «unequip» на Player нет,
	# а API панели должен быть симметричным «равновесным» на null.
	player.weapon_changed.emit(null)
	await get_tree().process_frame
	var empty_label: Label = screen.get_node("HUD/WeaponInfoPanel/EmptyLabel")
	var stats_box: VBoxContainer = screen.get_node("HUD/WeaponInfoPanel/StatsBox")
	assert_true(empty_label.visible)
	assert_false(stats_box.visible)
