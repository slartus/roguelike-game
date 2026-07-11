class_name EnvironmentMaterialCatalog
extends RefCounted

# Каталог материалов окружения. Data-driven регистр всех известных
# EnvironmentMaterial. floor.gd резолвит материал по ID через
# `get_material(id)`.
#
# Материалы задаются в коде, а не как отдельные `.tres`, потому что:
# - их немного (~16), сам список стабилен и часть контракта;
# - большинство ID резолвятся из EnvironmentVisualProfile, где они
#   уже прописаны литералами → лишний уровень resource-навигации не
#   помогает;
# - тесты могут импортировать этот класс напрямую без preload'ов.
#
# Каталог lazy-инициализируется при первом обращении. Тесты могут
# принудительно сбросить кэш через `_reset_for_tests()`.

const _ASSETS := "res://assets/sprites/environment"

const FLOOR_MATERIAL_IDS := [
	&"wood_floor",
	&"dark_wood_floor",
	&"corridor_stone",
	&"light_stone_tile",
	&"reinforced_stone",
	&"stone_metal_grid",
	&"heat_stained_stone",
	&"damaged_tower_stone",
	&"wet_basement_stone",
	&"cave_ground",
]

const WALL_MATERIAL_IDS := [
	&"plaster_wall",
	&"wood_panel_wall",
	&"tower_stone_wall",
	&"technical_stone_wall",
	&"basement_brick_wall",
	&"natural_cave_wall",
]

static var _cache: Dictionary = {}

static func get_material(id: StringName) -> EnvironmentMaterial:
	if _cache.is_empty():
		_load_all()
	return _cache.get(id)

static func has_material(id: StringName) -> bool:
	if _cache.is_empty():
		_load_all()
	return _cache.has(id)

static func all_ids() -> Array:
	if _cache.is_empty():
		_load_all()
	return _cache.keys()

static func _reset_for_tests() -> void:
	_cache.clear()

static func _load_all() -> void:
	_cache.clear()
	# Floor materials — только floor_texture заполнен.
	_register_floor(&"wood_floor", "wood_floor.png")
	_register_floor(&"dark_wood_floor", "dark_wood_floor.png")
	_register_floor(&"corridor_stone", "corridor_stone.png")
	_register_floor(&"light_stone_tile", "light_stone_tile.png")
	_register_floor(&"reinforced_stone", "reinforced_stone.png")
	_register_floor(&"stone_metal_grid", "stone_metal_grid.png")
	_register_floor(&"heat_stained_stone", "heat_stained_stone.png")
	_register_floor(&"damaged_tower_stone", "damaged_tower_stone.png")
	_register_floor(&"wet_basement_stone", "wet_basement_stone.png")
	_register_floor(&"cave_ground", "cave_ground.png")
	# Wall materials — wall_texture + wall_cap_texture заполнены.
	_register_wall(&"plaster_wall", "plaster_wall.png", "plaster_wall_cap.png")
	_register_wall(&"wood_panel_wall", "wood_panel_wall.png", "wood_panel_wall_cap.png")
	_register_wall(&"tower_stone_wall", "tower_stone_wall.png", "tower_stone_wall_cap.png")
	_register_wall(&"technical_stone_wall", "technical_stone_wall.png", "technical_stone_wall_cap.png")
	_register_wall(&"basement_brick_wall", "basement_brick_wall.png", "basement_brick_wall_cap.png")
	_register_wall(&"natural_cave_wall", "natural_cave_wall.png", "natural_cave_wall_cap.png")
	# Doorway threshold — общий, живёт как отдельный «материал» для
	# удобного лукапа из resolve-функции.
	var doorway := EnvironmentMaterial.new()
	doorway.id = &"doorway_threshold"
	doorway.floor_texture = _load_tex("doorway_threshold.png")
	_cache[doorway.id] = doorway

static func _register_floor(id: StringName, filename: String) -> void:
	var mat := EnvironmentMaterial.new()
	mat.id = id
	mat.floor_texture = _load_tex(filename)
	_cache[id] = mat

static func _register_wall(id: StringName, face_filename: String, cap_filename: String) -> void:
	var mat := EnvironmentMaterial.new()
	mat.id = id
	mat.wall_texture = _load_tex(face_filename)
	mat.wall_cap_texture = _load_tex(cap_filename)
	_cache[id] = mat

static func _load_tex(filename: String) -> Texture2D:
	var path := "%s/%s" % [_ASSETS, filename]
	if not ResourceLoader.exists(path):
		push_warning("EnvironmentMaterialCatalog: texture not found: %s" % path)
		return null
	return load(path) as Texture2D
