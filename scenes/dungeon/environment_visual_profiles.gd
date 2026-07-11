class_name EnvironmentVisualProfiles
extends RefCounted

# Регистр EnvironmentVisualProfile по zone-ID. Один вход в
# профиль зоны через `for_zone(zone)`. Resolve-функции возвращают
# `StringName` материала для конкретной клетки — floor.gd берёт
# этот ID и достаёт текстуру из `EnvironmentMaterialCatalog`.
#
# Профили описаны в коде (не как `.tres`), потому что они собираются
# один раз, их немного и они ссылаются на материалы через
# StringName-ID — никаких Texture2D preload'ов в этом файле, что
# упрощает тестирование.
#
# Fallback: неизвестная zone возвращает профиль ZONE_TOWER_TOP.

static var FALLBACK_ZONE: StringName = StringName(TowerZone.ZONE_TOWER_TOP)

static var _profiles: Dictionary = {}

static func for_zone(zone: StringName) -> EnvironmentVisualProfile:
	if _profiles.is_empty():
		_build()
	if _profiles.has(zone):
		return _profiles[zone]
	return _profiles[FALLBACK_ZONE]

static func has_zone(zone: StringName) -> bool:
	if _profiles.is_empty():
		_build()
	return _profiles.has(zone)

static func all_zones() -> Array:
	if _profiles.is_empty():
		_build()
	return _profiles.keys()

# Приоритеты material resolution:
# 1. corridor material для клеток коридора;
# 2. room-role override для клеток внутри room с известной ролью;
# 3. zone default для остальных.
static func resolve_floor_material(
	zone: StringName,
	room_role: StringName,
	is_corridor: bool,
) -> StringName:
	var profile := for_zone(zone)
	if is_corridor:
		return profile.corridor_floor_material
	if profile.room_role_floor_overrides.has(room_role):
		return profile.room_role_floor_overrides[room_role]
	return profile.default_floor_material

static func resolve_wall_material(
	zone: StringName,
	room_role: StringName,
) -> StringName:
	var profile := for_zone(zone)
	if profile.room_role_wall_overrides.has(room_role):
		return profile.room_role_wall_overrides[room_role]
	return profile.default_wall_material

static func _reset_for_tests() -> void:
	_profiles.clear()

static func _build() -> void:
	# Ключи регистра — StringName поверх TowerZone.ZONE_*. Литералы
	# здесь запрещены: переименование в TowerZone поймается компилятором
	# сразу, а не молча оставит профиль под старым ключом.
	_profiles.clear()
	_profiles[StringName(TowerZone.ZONE_TOWER_TOP)] = _make_tower_top()
	_profiles[StringName(TowerZone.ZONE_RESIDENTIAL)] = _make_residential()
	_profiles[StringName(TowerZone.ZONE_TECHNICAL)] = _make_technical()
	_profiles[StringName(TowerZone.ZONE_LOWER_TOWER)] = _make_lower_tower()
	_profiles[StringName(TowerZone.ZONE_BASEMENT)] = _make_basement()
	_profiles[StringName(TowerZone.ZONE_CAVES)] = _make_caves()

static func _make_tower_top() -> EnvironmentVisualProfile:
	# Верх башни — старые деревянные доски + штукатурка. Тёплая
	# приглушённая палитра, немного каменных вставок в кабинетах.
	var p := EnvironmentVisualProfile.new()
	p.id = StringName(TowerZone.ZONE_TOWER_TOP)
	p.background_color = Color(0.05, 0.04, 0.06, 1.0)
	p.default_floor_material = &"wood_floor"
	p.corridor_floor_material = &"corridor_stone"
	p.default_wall_material = &"plaster_wall"
	p.room_role_floor_overrides = {
		StringName(RoomRoles.ROLE_STUDY): &"dark_wood_floor",
		StringName(RoomRoles.ROLE_STORAGE): &"wood_floor",
	}
	p.room_role_wall_overrides = {}
	return p

static func _make_residential() -> EnvironmentVisualProfile:
	# Жилые этажи — дерево в комнатах, камень в коридорах, панели
	# на стенах. Кухня — светлая плитка, чтобы явно контрастировать
	# со спальнями.
	var p := EnvironmentVisualProfile.new()
	p.id = StringName(TowerZone.ZONE_RESIDENTIAL)
	p.background_color = Color(0.04, 0.04, 0.06, 1.0)
	p.default_floor_material = &"wood_floor"
	p.corridor_floor_material = &"corridor_stone"
	p.default_wall_material = &"wood_panel_wall"
	p.room_role_floor_overrides = {
		StringName(RoomRoles.ROLE_BEDROOM): &"wood_floor",
		StringName(RoomRoles.ROLE_LIVING_ROOM): &"wood_floor",
		StringName(RoomRoles.ROLE_STUDY): &"dark_wood_floor",
		StringName(RoomRoles.ROLE_KITCHEN): &"light_stone_tile",
		StringName(RoomRoles.ROLE_STORAGE): &"wood_floor",
	}
	p.room_role_wall_overrides = {
		StringName(RoomRoles.ROLE_KITCHEN): &"plaster_wall",
	}
	return p

static func _make_technical() -> EnvironmentVisualProfile:
	# Служебные этажи — каменные плиты, металлические вставки,
	# рунические каналы. НЕ современный индустриал: цвета сдвинуты
	# в медь/латунь.
	var p := EnvironmentVisualProfile.new()
	p.id = StringName(TowerZone.ZONE_TECHNICAL)
	p.background_color = Color(0.04, 0.03, 0.05, 1.0)
	p.default_floor_material = &"reinforced_stone"
	p.corridor_floor_material = &"stone_metal_grid"
	p.default_wall_material = &"technical_stone_wall"
	p.room_role_floor_overrides = {
		StringName(RoomRoles.ROLE_MACHINE_ROOM): &"reinforced_stone",
		StringName(RoomRoles.ROLE_BOILER_ROOM): &"heat_stained_stone",
		StringName(RoomRoles.ROLE_SWITCH_ROOM): &"stone_metal_grid",
		StringName(RoomRoles.ROLE_STORAGE): &"reinforced_stone",
	}
	p.room_role_wall_overrides = {}
	return p

static func _make_lower_tower() -> EnvironmentVisualProfile:
	# Нижняя башня — руины. Разрушенная плитка, обнажённая кладка.
	# Коридор — тот же материал, что и комнаты, потому что здесь
	# коридор перестал быть «жилой прожилкой».
	var p := EnvironmentVisualProfile.new()
	p.id = StringName(TowerZone.ZONE_LOWER_TOWER)
	p.background_color = Color(0.03, 0.02, 0.04, 1.0)
	p.default_floor_material = &"damaged_tower_stone"
	p.corridor_floor_material = &"damaged_tower_stone"
	p.default_wall_material = &"tower_stone_wall"
	p.room_role_floor_overrides = {}
	p.room_role_wall_overrides = {}
	return p

static func _make_basement() -> EnvironmentVisualProfile:
	# Подвалы — сырой кирпич, влажный пол. Мох как декор уже даётся
	# DecorProfiles; здесь материал сдвигается в холодную палитру.
	var p := EnvironmentVisualProfile.new()
	p.id = StringName(TowerZone.ZONE_BASEMENT)
	p.background_color = Color(0.02, 0.02, 0.03, 1.0)
	p.default_floor_material = &"wet_basement_stone"
	p.corridor_floor_material = &"wet_basement_stone"
	p.default_wall_material = &"basement_brick_wall"
	p.room_role_floor_overrides = {}
	p.room_role_wall_overrides = {}
	return p

static func _make_caves() -> EnvironmentVisualProfile:
	# Пещеры — естественный камень и земля. НЕ regular brick, чтобы
	# зона визуально ощущалась как «под фундаментом башни».
	var p := EnvironmentVisualProfile.new()
	p.id = StringName(TowerZone.ZONE_CAVES)
	p.background_color = Color(0.02, 0.02, 0.02, 1.0)
	p.default_floor_material = &"cave_ground"
	p.corridor_floor_material = &"cave_ground"
	p.default_wall_material = &"natural_cave_wall"
	p.room_role_floor_overrides = {}
	p.room_role_wall_overrides = {}
	return p
