extends GutTest

# Проверки EnvironmentPropDefinition + Catalog:
# - все ID уникальны;
# - у каждого def валидная категория, texture, footprint > 0;
# - is_allowed_in уважает whitelist zones/roles;
# - fits_in_room проверяет footprint и min_room_size_cells;
# - filter возвращает подходящие defs по (zone, role, size, category).

const _DEF := preload("res://scenes/dungeon/environment_prop_definition.gd")
const _CATALOG := preload("res://scenes/dungeon/environment_prop_catalog.gd")

func before_each() -> void:
	_CATALOG._reset_for_tests()

func test_all_prop_ids_are_unique() -> void:
	var ids := _CATALOG.all_ids()
	var seen: Dictionary = {}
	for id in ids:
		assert_false(seen.has(id), "duplicate prop id: %s" % id)
		seen[id] = true

func test_all_definitions_have_valid_category() -> void:
	for def in _CATALOG.all_definitions():
		var d: EnvironmentPropDefinition = def
		assert_true(_DEF.ALL_CATEGORIES.has(d.category),
			"prop %s has invalid category %s" % [d.id, d.category])

func test_all_definitions_have_texture_or_scene() -> void:
	for def in _CATALOG.all_definitions():
		var d: EnvironmentPropDefinition = def
		var has_visual := d.texture != null or d.scene != null
		assert_true(has_visual, "prop %s must have texture or scene" % d.id)

func test_all_definitions_have_positive_footprint() -> void:
	for def in _CATALOG.all_definitions():
		var d: EnvironmentPropDefinition = def
		assert_gt(d.footprint_cells.x, 0, "prop %s footprint.x must be > 0" % d.id)
		assert_gt(d.footprint_cells.y, 0, "prop %s footprint.y must be > 0" % d.id)

func test_is_allowed_in_respects_zone_whitelist() -> void:
	var bed := _CATALOG.get_definition(_CATALOG.PROP_BED)
	assert_true(bed.is_allowed_in(&"residential", &"bedroom"),
		"bed разрешён в residential.bedroom")
	assert_false(bed.is_allowed_in(&"caves", &"bedroom"),
		"bed НЕ разрешён в caves (не в allowed_zones)")

func test_is_allowed_in_respects_role_whitelist() -> void:
	var bed := _CATALOG.get_definition(_CATALOG.PROP_BED)
	assert_false(bed.is_allowed_in(&"residential", &"kitchen"),
		"bed НЕ разрешён в kitchen (не в allowed_room_roles)")

func test_is_allowed_when_zone_whitelist_empty() -> void:
	# crate.allowed_zones == [] → разрешён везде, если role подходит.
	var crate := _CATALOG.get_definition(_CATALOG.PROP_CRATE)
	assert_eq(crate.allowed_zones.size(), 0,
		"crate имеет пустой zone whitelist")
	assert_true(crate.is_allowed_in(&"caves", &"storage"),
		"crate должен быть разрешён в caves.storage (zone whitelist пустой)")

func test_fits_in_room_rejects_smaller_than_footprint() -> void:
	var bed := _CATALOG.get_definition(_CATALOG.PROP_BED)
	# bed footprint 2x1 — комната 1x1 не подходит.
	assert_false(bed.fits_in_room(Vector2i(1, 1)),
		"bed 2x1 не должен помещаться в 1x1")

func test_fits_in_room_rejects_below_min_size() -> void:
	var bed := _CATALOG.get_definition(_CATALOG.PROP_BED)
	assert_gt(bed.min_room_size_cells.x, 0,
		"bed имеет min_room_size_cells")
	assert_false(bed.fits_in_room(Vector2i(3, 3)),
		"bed требует комнату 4x4 min, 3x3 отклоняется")

func test_fits_in_room_accepts_valid_size() -> void:
	var bed := _CATALOG.get_definition(_CATALOG.PROP_BED)
	assert_true(bed.fits_in_room(Vector2i(6, 6)),
		"bed должен помещаться в 6x6")

func test_filter_returns_only_matching_category() -> void:
	var wall_adjacent := _CATALOG.filter(
		&"residential", &"bedroom", Vector2i(6, 6),
		_DEF.CATEGORY_WALL_ADJACENT_PROP,
	)
	assert_gt(wall_adjacent.size(), 0, "должен быть хотя бы один wall_adjacent для bedroom")
	for def in wall_adjacent:
		var d: EnvironmentPropDefinition = def
		assert_eq(d.category, _DEF.CATEGORY_WALL_ADJACENT_PROP,
			"filter вернул prop %s с неверной категорией" % d.id)

func test_filter_returns_bed_for_bedroom() -> void:
	var wall_adjacent := _CATALOG.filter(
		&"residential", &"bedroom", Vector2i(6, 6),
		_DEF.CATEGORY_WALL_ADJACENT_PROP,
	)
	var ids := wall_adjacent.map(func(d): return d.id)
	assert_true(ids.has(_CATALOG.PROP_BED), "bedroom filter должен вернуть bed")

func test_filter_excludes_bed_from_caves() -> void:
	# Bed не разрешён в caves — filter не должен его вернуть.
	var results := _CATALOG.filter(
		&"caves", &"bedroom", Vector2i(6, 6),
		_DEF.CATEGORY_WALL_ADJACENT_PROP,
	)
	var ids := results.map(func(d): return d.id)
	assert_false(ids.has(_CATALOG.PROP_BED), "caves.bedroom filter НЕ должен вернуть bed")

func test_filter_returns_boiler_for_boiler_room() -> void:
	var large := _CATALOG.filter(
		&"technical", &"boiler_room", Vector2i(6, 6),
		_DEF.CATEGORY_LARGE_PROP,
	)
	var ids := large.map(func(d): return d.id)
	assert_true(ids.has(_CATALOG.PROP_BOILER),
		"boiler_room должен получить boiler в large_prop")

func test_filter_returns_stalagmite_for_cave_chamber() -> void:
	var large := _CATALOG.filter(
		&"caves", &"cave_chamber", Vector2i(6, 6),
		_DEF.CATEGORY_LARGE_PROP,
	)
	var ids := large.map(func(d): return d.id)
	assert_true(ids.has(_CATALOG.PROP_STALAGMITE),
		"cave_chamber должен получить stalagmite в large_prop")
