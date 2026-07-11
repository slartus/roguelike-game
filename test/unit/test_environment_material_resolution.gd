extends GutTest

# Правила приоритета `EnvironmentVisualProfiles.resolve_floor_material`:
# 1. corridor material для клеток коридора;
# 2. room-role override для клеток внутри room;
# 3. zone default для остальных.
#
# Ключевые ожидания плана PR 1:
# - residential bedroom → wood floor;
# - residential kitchen → stone/tile floor;
# - residential corridor → corridor material;
# - technical machine room → technical material;
# - basement → wet/brick material;
# - caves не используют regular tower brick.

func test_residential_bedroom_uses_wood_floor() -> void:
	var mat := EnvironmentVisualProfiles.resolve_floor_material(
		&"residential", StringName(RoomRoles.ROLE_BEDROOM), false,
	)
	assert_eq(mat, &"wood_floor",
		"bedroom в residential должна получать wood floor, а не общий default")

func test_residential_kitchen_uses_stone_tile_floor() -> void:
	var mat := EnvironmentVisualProfiles.resolve_floor_material(
		&"residential", StringName(RoomRoles.ROLE_KITCHEN), false,
	)
	assert_eq(mat, &"light_stone_tile",
		"kitchen должна быть каменной/плиточной, а не деревянной")

func test_residential_study_uses_dark_wood() -> void:
	var mat := EnvironmentVisualProfiles.resolve_floor_material(
		&"residential", StringName(RoomRoles.ROLE_STUDY), false,
	)
	assert_eq(mat, &"dark_wood_floor",
		"кабинет — тёмное дерево (контраст со светлыми спальнями)")

func test_residential_corridor_uses_corridor_material() -> void:
	# corridor override должен применяться для is_corridor=true независимо
	# от role.
	var mat := EnvironmentVisualProfiles.resolve_floor_material(
		&"residential", StringName(RoomRoles.ROLE_BEDROOM), true,
	)
	assert_eq(mat, &"corridor_stone",
		"коридор режет всегда, даже если role совпадает с bedroom")

func test_technical_machine_room_uses_technical_material() -> void:
	var mat := EnvironmentVisualProfiles.resolve_floor_material(
		&"technical", StringName(RoomRoles.ROLE_MACHINE_ROOM), false,
	)
	assert_eq(mat, &"reinforced_stone",
		"machine_room в technical → reinforced_stone")

func test_technical_boiler_room_uses_heat_stained_stone() -> void:
	var mat := EnvironmentVisualProfiles.resolve_floor_material(
		&"technical", StringName(RoomRoles.ROLE_BOILER_ROOM), false,
	)
	assert_eq(mat, &"heat_stained_stone",
		"boiler_room должен иметь тёплый heat-stained материал")

func test_basement_default_uses_wet_stone() -> void:
	var mat := EnvironmentVisualProfiles.resolve_floor_material(
		&"basement", StringName(RoomRoles.ROLE_BASEMENT_CELL), false,
	)
	assert_eq(mat, &"wet_basement_stone",
		"basement пол — влажный подвальный камень")

func test_basement_wall_is_brick() -> void:
	var wall := EnvironmentVisualProfiles.resolve_wall_material(
		&"basement", StringName(RoomRoles.ROLE_BASEMENT_CELL),
	)
	assert_eq(wall, &"basement_brick_wall",
		"basement стены — кирпич (в отличие от tower_stone)")

func test_caves_do_not_use_tower_brick() -> void:
	# Ключевой инвариант: пещеры не должны выглядеть как жилая башня.
	var wall := EnvironmentVisualProfiles.resolve_wall_material(
		&"caves", StringName(RoomRoles.ROLE_CAVE_CHAMBER),
	)
	assert_ne(wall, &"tower_stone_wall",
		"caves не должны использовать regular tower brick wall")
	assert_ne(wall, &"basement_brick_wall",
		"caves не должны использовать basement brick wall (это все ещё кладка)")
	assert_eq(wall, &"natural_cave_wall",
		"caves должны использовать естественный камень (natural_cave_wall)")

func test_caves_floor_is_cave_ground() -> void:
	var mat := EnvironmentVisualProfiles.resolve_floor_material(
		&"caves", StringName(RoomRoles.ROLE_CAVE_CHAMBER), false,
	)
	assert_eq(mat, &"cave_ground",
		"caves пол — cave_ground, не корridor_stone")

func test_unknown_role_falls_back_to_default_floor() -> void:
	# Роль вне ZONE_ROLE_POOL и без override должна упасть в default
	# floor материал zone.
	var mat := EnvironmentVisualProfiles.resolve_floor_material(
		&"residential", &"role_that_does_not_exist", false,
	)
	var profile := EnvironmentVisualProfiles.for_zone(&"residential")
	assert_eq(mat, profile.default_floor_material,
		"неизвестная роль возвращает default")

func test_unknown_zone_uses_fallback_profile() -> void:
	var mat := EnvironmentVisualProfiles.resolve_floor_material(
		&"unknown_zone", StringName(RoomRoles.ROLE_BEDROOM), false,
	)
	var fallback := EnvironmentVisualProfiles.for_zone(&"unknown_zone")
	# fallback профиль — tower_top; bedroom не в его override'ах →
	# получаем его default.
	assert_eq(mat, fallback.default_floor_material,
		"unknown zone дает default fallback профиля")

func test_wall_and_cap_are_different_textures() -> void:
	# Инвариант плана PR 1: wall face и wall cap визуально разные.
	# Проверяем через каталог: у одного material'а обе текстуры заданы
	# и это разные Texture2D объекты.
	for wall_id in EnvironmentMaterialCatalog.WALL_MATERIAL_IDS:
		var mat: EnvironmentMaterial = EnvironmentMaterialCatalog.get_material(wall_id)
		assert_not_null(mat, "wall material %s должен быть в каталоге" % wall_id)
		assert_not_null(mat.wall_texture, "%s должен иметь wall_texture" % wall_id)
		assert_not_null(mat.wall_cap_texture, "%s должен иметь wall_cap_texture" % wall_id)
		assert_ne(mat.wall_texture.resource_path, mat.wall_cap_texture.resource_path,
			"%s: face и cap должны быть разными файлами" % wall_id)

func test_doorway_threshold_material_exists() -> void:
	assert_true(EnvironmentMaterialCatalog.has_material(&"doorway_threshold"),
		"doorway_threshold должен быть в каталоге для threshold overlay")
	var mat := EnvironmentMaterialCatalog.get_material(&"doorway_threshold")
	assert_not_null(mat.floor_texture,
		"doorway_threshold должен иметь floor_texture")
