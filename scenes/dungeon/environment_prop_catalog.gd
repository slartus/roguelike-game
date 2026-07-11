class_name EnvironmentPropCatalog
extends RefCounted

# Регистр всех EnvironmentPropDefinition. Работает по тому же
# паттерну, что EnvironmentVisualProfiles: определения собираются в
# коде через _build(), а не из .tres. Единый статический источник
# истины для RoomDecorationPlanner и тестов.
#
# Один prop идентифицируется StringName-ID (те же ID, что и имя PNG
# в assets/sprites/props/<id>.png). Тесты проверяют что все ID
# уникальны и что для каждой роли есть подходящие props.

const _ROLE := preload("res://scenes/dungeon/room_roles.gd")
const _ZONE := preload("res://scenes/dungeon/tower_zone.gd")
const _DEF := preload("res://scenes/dungeon/environment_prop_definition.gd")

# --- Prop ID constants (стабильный контракт) -------------------------------
# Один PNG в assets/sprites/props/<id>.png ↔ одна константа здесь.
const PROP_BED: StringName = &"bed"
const PROP_WARDROBE: StringName = &"wardrobe"
const PROP_BOOKSHELF: StringName = &"bookshelf"
const PROP_DESK: StringName = &"desk"
const PROP_SMALL_TABLE: StringName = &"small_table"
const PROP_CHAIR: StringName = &"chair"
const PROP_RUG: StringName = &"rug"
const PROP_CABINET: StringName = &"cabinet"
const PROP_WALL_PICTURE: StringName = &"wall_picture"

const PROP_CRATE: StringName = &"crate"
const PROP_BARREL: StringName = &"barrel"
const PROP_SACK: StringName = &"sack"
const PROP_SHELF: StringName = &"shelf"
const PROP_BROKEN_CRATE: StringName = &"broken_crate"
const PROP_ROPE_COIL: StringName = &"rope_coil"

const PROP_BOILER: StringName = &"boiler"
const PROP_RUNE_ENGINE: StringName = &"rune_engine"
const PROP_ALCHEMICAL_VAT: StringName = &"alchemical_vat"
const PROP_PIPE_STRAIGHT: StringName = &"pipe_straight"
const PROP_VALVE: StringName = &"valve"
const PROP_FLOOR_GRATE: StringName = &"floor_grate"
const PROP_WORKBENCH: StringName = &"workbench"

const PROP_CHAINS: StringName = &"chains"
const PROP_COT: StringName = &"cot"
const PROP_BUCKET: StringName = &"bucket"
const PROP_BONES: StringName = &"bones"
const PROP_RUBBLE: StringName = &"rubble"
const PROP_STALAGMITE: StringName = &"stalagmite"
const PROP_MUSHROOM: StringName = &"mushroom"
const PROP_CRYSTAL: StringName = &"crystal"
const PROP_ROOTS: StringName = &"roots"

static var _defs: Dictionary = {}

static func get_definition(id: StringName) -> EnvironmentPropDefinition:
	if _defs.is_empty():
		_build()
	return _defs.get(id, null)

static func has_definition(id: StringName) -> bool:
	if _defs.is_empty():
		_build()
	return _defs.has(id)

static func all_ids() -> Array:
	if _defs.is_empty():
		_build()
	return _defs.keys()

static func all_definitions() -> Array:
	if _defs.is_empty():
		_build()
	return _defs.values()

# Возвращает props подходящие для (zone, role, room_size_cells) с
# учётом category-фильтра. Используется planner'ом.
static func filter(
	zone: StringName,
	role: StringName,
	room_size_cells: Vector2i,
	category: StringName,
) -> Array:
	var result: Array = []
	for def in all_definitions():
		var d: EnvironmentPropDefinition = def
		if d.category != category:
			continue
		if not d.is_allowed_in(zone, role):
			continue
		if not d.fits_in_room(room_size_cells):
			continue
		result.append(d)
	return result

# Только для тестов: сбрасывает кеш, чтобы _build() перезапустился.
static func _reset_for_tests() -> void:
	_defs.clear()

# --- Builder ---------------------------------------------------------------

static func _build() -> void:
	_defs.clear()
	_register_residential()
	_register_storage()
	_register_technical()
	_register_basement_cave()

static func _make(
	id: StringName,
	category: StringName,
	texture_path: String,
	footprint: Vector2i,
	blocks_movement: bool,
) -> EnvironmentPropDefinition:
	var def := EnvironmentPropDefinition.new()
	def.id = id
	def.category = category
	def.footprint_cells = footprint
	def.blocks_movement = blocks_movement
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		def.texture = load(texture_path)
	return def

static func _register(def: EnvironmentPropDefinition) -> void:
	_defs[def.id] = def

static func _tex(prop_id: String) -> String:
	return "res://assets/sprites/props/%s.png" % prop_id

# --- Жилые (residential + tower_top) ---------------------------------------

static func _register_residential() -> void:
	# Общие zones — жилые части башни. Верхние зоны NO_CAVE_ZONES.
	var residential_zones: Array[StringName] = [
		StringName(_ZONE.ZONE_TOWER_TOP),
		StringName(_ZONE.ZONE_RESIDENTIAL),
	]

	var bed := _make(PROP_BED, _DEF.CATEGORY_WALL_ADJACENT_PROP, _tex(PROP_BED), Vector2i(2, 1), true)
	bed.allowed_zones = residential_zones
	bed.allowed_room_roles = [StringName(_ROLE.ROLE_BEDROOM)]
	bed.min_room_size_cells = Vector2i(4, 4)
	bed.weight = 3
	_register(bed)

	var wardrobe := _make(PROP_WARDROBE, _DEF.CATEGORY_WALL_ADJACENT_PROP, _tex(PROP_WARDROBE), Vector2i(1, 2), true)
	wardrobe.allowed_zones = residential_zones
	wardrobe.allowed_room_roles = [
		StringName(_ROLE.ROLE_BEDROOM),
		StringName(_ROLE.ROLE_LIVING_ROOM),
	]
	wardrobe.min_room_size_cells = Vector2i(4, 4)
	wardrobe.weight = 2
	_register(wardrobe)

	var bookshelf := _make(PROP_BOOKSHELF, _DEF.CATEGORY_WALL_ADJACENT_PROP, _tex(PROP_BOOKSHELF), Vector2i(2, 1), true)
	bookshelf.allowed_zones = residential_zones
	bookshelf.allowed_room_roles = [
		StringName(_ROLE.ROLE_STUDY),
		StringName(_ROLE.ROLE_LIVING_ROOM),
	]
	bookshelf.min_room_size_cells = Vector2i(4, 4)
	bookshelf.weight = 3
	_register(bookshelf)

	var desk := _make(PROP_DESK, _DEF.CATEGORY_WALL_ADJACENT_PROP, _tex(PROP_DESK), Vector2i(2, 1), true)
	desk.allowed_zones = residential_zones
	desk.allowed_room_roles = [StringName(_ROLE.ROLE_STUDY)]
	desk.min_room_size_cells = Vector2i(4, 4)
	desk.weight = 3
	_register(desk)

	var small_table := _make(PROP_SMALL_TABLE, _DEF.CATEGORY_FLOOR_PROP, _tex(PROP_SMALL_TABLE), Vector2i(1, 1), true)
	small_table.allowed_zones = residential_zones
	small_table.allowed_room_roles = [
		StringName(_ROLE.ROLE_BEDROOM),
		StringName(_ROLE.ROLE_LIVING_ROOM),
		StringName(_ROLE.ROLE_KITCHEN),
		StringName(_ROLE.ROLE_STUDY),
		StringName(_ROLE.ROLE_SMALL_ROOM),
	]
	small_table.weight = 2
	_register(small_table)

	var chair := _make(PROP_CHAIR, _DEF.CATEGORY_FLOOR_PROP, _tex(PROP_CHAIR), Vector2i(1, 1), false)
	chair.allowed_zones = residential_zones
	chair.allowed_room_roles = [
		StringName(_ROLE.ROLE_LIVING_ROOM),
		StringName(_ROLE.ROLE_KITCHEN),
		StringName(_ROLE.ROLE_STUDY),
		StringName(_ROLE.ROLE_SMALL_ROOM),
	]
	chair.weight = 2
	_register(chair)

	var rug := _make(PROP_RUG, _DEF.CATEGORY_FLOOR_DECAL, _tex(PROP_RUG), Vector2i(2, 2), false)
	rug.allowed_zones = residential_zones
	rug.allowed_room_roles = [
		StringName(_ROLE.ROLE_BEDROOM),
		StringName(_ROLE.ROLE_LIVING_ROOM),
		StringName(_ROLE.ROLE_STUDY),
		StringName(_ROLE.ROLE_TREASURE_ROOM),
	]
	rug.min_room_size_cells = Vector2i(4, 4)
	rug.weight = 2
	_register(rug)

	var cabinet := _make(PROP_CABINET, _DEF.CATEGORY_WALL_ADJACENT_PROP, _tex(PROP_CABINET), Vector2i(1, 1), true)
	cabinet.allowed_zones = residential_zones
	cabinet.allowed_room_roles = [
		StringName(_ROLE.ROLE_LIVING_ROOM),
		StringName(_ROLE.ROLE_KITCHEN),
		StringName(_ROLE.ROLE_STUDY),
		StringName(_ROLE.ROLE_SMALL_ROOM),
	]
	cabinet.weight = 2
	_register(cabinet)

	var wall_picture := _make(PROP_WALL_PICTURE, _DEF.CATEGORY_WALL_SURFACE, _tex(PROP_WALL_PICTURE), Vector2i(1, 1), false)
	wall_picture.allowed_zones = residential_zones
	wall_picture.allowed_room_roles = [
		StringName(_ROLE.ROLE_BEDROOM),
		StringName(_ROLE.ROLE_LIVING_ROOM),
		StringName(_ROLE.ROLE_STUDY),
		StringName(_ROLE.ROLE_TREASURE_ROOM),
	]
	wall_picture.weight = 1
	_register(wall_picture)

# --- Хранилище (storage/warehouse на разных этажах) -----------------------

static func _register_storage() -> void:
	# Storage-props появляются во всех zones — коробки/бочки уместны везде.
	var crate := _make(PROP_CRATE, _DEF.CATEGORY_FLOOR_PROP, _tex(PROP_CRATE), Vector2i(1, 1), true)
	crate.allowed_room_roles = [
		StringName(_ROLE.ROLE_STORAGE),
		StringName(_ROLE.ROLE_WAREHOUSE),
		StringName(_ROLE.ROLE_KITCHEN),
		StringName(_ROLE.ROLE_TREASURE_ROOM),
		StringName(_ROLE.ROLE_SMALL_ROOM),
	]
	crate.weight = 3
	_register(crate)

	var barrel := _make(PROP_BARREL, _DEF.CATEGORY_FLOOR_PROP, _tex(PROP_BARREL), Vector2i(1, 1), true)
	barrel.allowed_room_roles = [
		StringName(_ROLE.ROLE_STORAGE),
		StringName(_ROLE.ROLE_WAREHOUSE),
		StringName(_ROLE.ROLE_KITCHEN),
		StringName(_ROLE.ROLE_MACHINE_ROOM),
		StringName(_ROLE.ROLE_BOILER_ROOM),
	]
	barrel.weight = 3
	_register(barrel)

	var sack := _make(PROP_SACK, _DEF.CATEGORY_FLOOR_PROP, _tex(PROP_SACK), Vector2i(1, 1), false)
	sack.allowed_room_roles = [
		StringName(_ROLE.ROLE_STORAGE),
		StringName(_ROLE.ROLE_WAREHOUSE),
		StringName(_ROLE.ROLE_KITCHEN),
	]
	sack.weight = 2
	_register(sack)

	var shelf := _make(PROP_SHELF, _DEF.CATEGORY_WALL_SURFACE, _tex(PROP_SHELF), Vector2i(2, 1), false)
	shelf.allowed_room_roles = [
		StringName(_ROLE.ROLE_STORAGE),
		StringName(_ROLE.ROLE_WAREHOUSE),
		StringName(_ROLE.ROLE_KITCHEN),
		StringName(_ROLE.ROLE_STUDY),
	]
	shelf.min_room_size_cells = Vector2i(4, 4)
	shelf.weight = 2
	_register(shelf)

	var broken_crate := _make(PROP_BROKEN_CRATE, _DEF.CATEGORY_FLOOR_PROP, _tex(PROP_BROKEN_CRATE), Vector2i(1, 1), false)
	broken_crate.allowed_room_roles = [
		StringName(_ROLE.ROLE_STORAGE),
		StringName(_ROLE.ROLE_WAREHOUSE),
		StringName(_ROLE.ROLE_RUINED_ROOM),
		StringName(_ROLE.ROLE_BASEMENT_CELL),
	]
	broken_crate.weight = 1
	_register(broken_crate)

	var rope_coil := _make(PROP_ROPE_COIL, _DEF.CATEGORY_FLOOR_PROP, _tex(PROP_ROPE_COIL), Vector2i(1, 1), false)
	rope_coil.allowed_room_roles = [
		StringName(_ROLE.ROLE_STORAGE),
		StringName(_ROLE.ROLE_WAREHOUSE),
	]
	rope_coil.weight = 1
	_register(rope_coil)

# --- Fantasy technical ---------------------------------------------------

static func _register_technical() -> void:
	var technical_zone: Array[StringName] = [StringName(_ZONE.ZONE_TECHNICAL)]

	var boiler := _make(PROP_BOILER, _DEF.CATEGORY_LARGE_PROP, _tex(PROP_BOILER), Vector2i(2, 2), true)
	boiler.allowed_zones = technical_zone
	boiler.allowed_room_roles = [StringName(_ROLE.ROLE_BOILER_ROOM)]
	boiler.min_room_size_cells = Vector2i(5, 5)
	boiler.weight = 3
	_register(boiler)

	var rune_engine := _make(PROP_RUNE_ENGINE, _DEF.CATEGORY_LARGE_PROP, _tex(PROP_RUNE_ENGINE), Vector2i(2, 2), true)
	rune_engine.allowed_zones = technical_zone
	rune_engine.allowed_room_roles = [StringName(_ROLE.ROLE_MACHINE_ROOM)]
	rune_engine.min_room_size_cells = Vector2i(5, 5)
	rune_engine.weight = 3
	_register(rune_engine)

	var alchemical_vat := _make(PROP_ALCHEMICAL_VAT, _DEF.CATEGORY_LARGE_PROP, _tex(PROP_ALCHEMICAL_VAT), Vector2i(2, 2), true)
	alchemical_vat.allowed_zones = technical_zone
	alchemical_vat.allowed_room_roles = [
		StringName(_ROLE.ROLE_MACHINE_ROOM),
		StringName(_ROLE.ROLE_BOILER_ROOM),
	]
	alchemical_vat.min_room_size_cells = Vector2i(5, 5)
	alchemical_vat.weight = 1
	_register(alchemical_vat)

	var pipe := _make(PROP_PIPE_STRAIGHT, _DEF.CATEGORY_WALL_SURFACE, _tex(PROP_PIPE_STRAIGHT), Vector2i(2, 1), false)
	pipe.allowed_zones = technical_zone
	pipe.allowed_room_roles = [
		StringName(_ROLE.ROLE_MACHINE_ROOM),
		StringName(_ROLE.ROLE_BOILER_ROOM),
		StringName(_ROLE.ROLE_SWITCH_ROOM),
		StringName(_ROLE.ROLE_CORRIDOR),
	]
	pipe.weight = 3
	_register(pipe)

	var valve := _make(PROP_VALVE, _DEF.CATEGORY_WALL_SURFACE, _tex(PROP_VALVE), Vector2i(1, 1), false)
	valve.allowed_zones = technical_zone
	valve.allowed_room_roles = [
		StringName(_ROLE.ROLE_MACHINE_ROOM),
		StringName(_ROLE.ROLE_BOILER_ROOM),
	]
	valve.weight = 2
	_register(valve)

	var grate := _make(PROP_FLOOR_GRATE, _DEF.CATEGORY_FLOOR_DECAL, _tex(PROP_FLOOR_GRATE), Vector2i(2, 1), false)
	grate.allowed_zones = technical_zone
	grate.allowed_room_roles = [
		StringName(_ROLE.ROLE_MACHINE_ROOM),
		StringName(_ROLE.ROLE_BOILER_ROOM),
		StringName(_ROLE.ROLE_SWITCH_ROOM),
	]
	grate.weight = 2
	_register(grate)

	var workbench := _make(PROP_WORKBENCH, _DEF.CATEGORY_WALL_ADJACENT_PROP, _tex(PROP_WORKBENCH), Vector2i(2, 1), true)
	workbench.allowed_zones = [
		StringName(_ZONE.ZONE_TECHNICAL),
		StringName(_ZONE.ZONE_RESIDENTIAL),
	]
	workbench.allowed_room_roles = [
		StringName(_ROLE.ROLE_MACHINE_ROOM),
		StringName(_ROLE.ROLE_KITCHEN),
	]
	workbench.min_room_size_cells = Vector2i(4, 4)
	workbench.weight = 2
	_register(workbench)

# --- Basement / caves ----------------------------------------------------

static func _register_basement_cave() -> void:
	var basement_zones: Array[StringName] = [
		StringName(_ZONE.ZONE_LOWER_TOWER),
		StringName(_ZONE.ZONE_BASEMENT),
		StringName(_ZONE.ZONE_CAVES),
	]
	var cave_zones: Array[StringName] = [
		StringName(_ZONE.ZONE_BASEMENT),
		StringName(_ZONE.ZONE_CAVES),
	]

	var chains := _make(PROP_CHAINS, _DEF.CATEGORY_WALL_SURFACE, _tex(PROP_CHAINS), Vector2i(1, 1), false)
	chains.allowed_zones = basement_zones
	chains.allowed_room_roles = [
		StringName(_ROLE.ROLE_BASEMENT_CELL),
		StringName(_ROLE.ROLE_RUINED_ROOM),
	]
	chains.weight = 2
	_register(chains)

	var cot := _make(PROP_COT, _DEF.CATEGORY_WALL_ADJACENT_PROP, _tex(PROP_COT), Vector2i(2, 1), true)
	cot.allowed_zones = basement_zones
	cot.allowed_room_roles = [StringName(_ROLE.ROLE_BASEMENT_CELL)]
	cot.min_room_size_cells = Vector2i(4, 4)
	cot.weight = 3
	_register(cot)

	var bucket := _make(PROP_BUCKET, _DEF.CATEGORY_FLOOR_PROP, _tex(PROP_BUCKET), Vector2i(1, 1), false)
	bucket.allowed_zones = basement_zones
	bucket.allowed_room_roles = [
		StringName(_ROLE.ROLE_BASEMENT_CELL),
		StringName(_ROLE.ROLE_RUINED_ROOM),
	]
	bucket.weight = 1
	_register(bucket)

	var bones := _make(PROP_BONES, _DEF.CATEGORY_FLOOR_DECAL, _tex(PROP_BONES), Vector2i(1, 1), false)
	bones.allowed_zones = basement_zones
	bones.allowed_room_roles = [
		StringName(_ROLE.ROLE_BASEMENT_CELL),
		StringName(_ROLE.ROLE_CAVE_CHAMBER),
		StringName(_ROLE.ROLE_RUINED_ROOM),
	]
	bones.weight = 2
	_register(bones)

	var rubble := _make(PROP_RUBBLE, _DEF.CATEGORY_FLOOR_DECAL, _tex(PROP_RUBBLE), Vector2i(1, 1), false)
	rubble.allowed_zones = basement_zones
	rubble.allowed_room_roles = [
		StringName(_ROLE.ROLE_BASEMENT_CELL),
		StringName(_ROLE.ROLE_CAVE_CHAMBER),
		StringName(_ROLE.ROLE_RUINED_ROOM),
	]
	rubble.weight = 2
	_register(rubble)

	var stalagmite := _make(PROP_STALAGMITE, _DEF.CATEGORY_LARGE_PROP, _tex(PROP_STALAGMITE), Vector2i(1, 1), true)
	stalagmite.allowed_zones = cave_zones
	stalagmite.allowed_room_roles = [StringName(_ROLE.ROLE_CAVE_CHAMBER)]
	stalagmite.min_room_size_cells = Vector2i(5, 5)
	stalagmite.weight = 3
	_register(stalagmite)

	var mushroom := _make(PROP_MUSHROOM, _DEF.CATEGORY_FLOOR_PROP, _tex(PROP_MUSHROOM), Vector2i(1, 1), false)
	mushroom.allowed_zones = cave_zones
	mushroom.allowed_room_roles = [StringName(_ROLE.ROLE_CAVE_CHAMBER)]
	mushroom.weight = 3
	_register(mushroom)

	var crystal := _make(PROP_CRYSTAL, _DEF.CATEGORY_FLOOR_PROP, _tex(PROP_CRYSTAL), Vector2i(1, 1), false)
	crystal.allowed_zones = cave_zones
	crystal.allowed_room_roles = [
		StringName(_ROLE.ROLE_CAVE_CHAMBER),
		StringName(_ROLE.ROLE_TREASURE_ROOM),
	]
	crystal.weight = 2
	_register(crystal)

	var roots := _make(PROP_ROOTS, _DEF.CATEGORY_FLOOR_DECAL, _tex(PROP_ROOTS), Vector2i(1, 1), false)
	roots.allowed_zones = cave_zones
	roots.allowed_room_roles = [StringName(_ROLE.ROLE_CAVE_CHAMBER)]
	roots.weight = 1
	_register(roots)
