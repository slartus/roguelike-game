extends GutTest

# Проверки высокоуровневых composition правил:
# - каждая тематическая роль в подходящем размере получает signature prop;
# - modern-industrial props не появляются в верхних жилых зонах;
# - cave props не появляются в верхних зонах;
# - wall_surface (картинка) есть в жилых, но не обязателен;
# - decor RNG остаётся детерминированным между запусками.

const _PLANNER := preload("res://scenes/dungeon/room_decoration_planner.gd")
const _CATALOG := preload("res://scenes/dungeon/environment_prop_catalog.gd")
const _DEF := preload("res://scenes/dungeon/environment_prop_definition.gd")

const TILE := 20

func before_each() -> void:
	_CATALOG._reset_for_tests()

func _make_layout(role: String, zone: String, size: Vector2i) -> DungeonLayout:
	var layout := DungeonLayout.new()
	var room_rect := Rect2i(Vector2i.ZERO, size * TILE)
	layout.rooms = [room_rect]
	layout.corridors = []
	layout.zone = zone
	layout.floor_bounds = room_rect
	layout.player_start = Vector2i(-1, -1)
	layout.exit_position = Vector2i(-1, -1)
	layout.room_infos = [{
		"room_index": 0,
		"role": role,
		"zone": zone,
		"tags": [],
		"danger": 0,
	}]
	return layout

func _plan_and_get_ids(role: String, zone: String, size: Vector2i, seed_value: int, floor_number: int) -> Array:
	var layout := _make_layout(role, zone, size)
	var plan := _PLANNER.plan_floor(layout, {}, seed_value, floor_number)
	var ids: Array = []
	for placement in plan.placements:
		ids.append(placement.def.id)
	return ids

# --- Signature prop rule -------------------------------------------------

func test_bedroom_signature_bed_across_multiple_seeds() -> void:
	# Прогоняем несколько seed'ов — bed должен появляться в подавляющем
	# большинстве. Мы допускаем что 1 из 5 может проскочить (unlucky
	# candidate rejection), но не больше.
	var success := 0
	for seed_value in [1, 2, 3, 4, 5]:
		var ids := _plan_and_get_ids("bedroom", "residential", Vector2i(6, 6), seed_value, 3)
		if ids.has(_CATALOG.PROP_BED):
			success += 1
	assert_gte(success, 4, "bed должен появляться минимум в 4/5 bedroom с разными seeds")

func test_kitchen_gets_workbench_or_cabinet_or_barrel() -> void:
	# Kitchen composition: worktable / cabinet / barrels — хотя бы один
	# из ключевых объектов должен быть.
	var ids := _plan_and_get_ids("kitchen", "residential", Vector2i(6, 6), 12345, 4)
	var has_kitchen_prop := (
		ids.has(_CATALOG.PROP_WORKBENCH)
		or ids.has(_CATALOG.PROP_CABINET)
		or ids.has(_CATALOG.PROP_BARREL)
	)
	assert_true(has_kitchen_prop, "kitchen должен получить workbench, cabinet или barrel. placements=%s" % [ids])

func test_storage_gets_crate_or_barrel() -> void:
	var ids := _plan_and_get_ids("storage", "residential", Vector2i(6, 6), 12345, 4)
	var has_storage_prop := ids.has(_CATALOG.PROP_CRATE) or ids.has(_CATALOG.PROP_BARREL)
	assert_true(has_storage_prop, "storage должен получить crate или barrel. placements=%s" % [ids])

func test_basement_cell_gets_cot_or_chains() -> void:
	var ids := _plan_and_get_ids("basement_cell", "basement", Vector2i(6, 6), 12345, 16)
	var has_cell_prop := ids.has(_CATALOG.PROP_COT) or ids.has(_CATALOG.PROP_CHAINS)
	assert_true(has_cell_prop, "basement_cell должен получить cot или chains. placements=%s" % [ids])

# --- Zone constraint checks ---------------------------------------------

func test_residential_zone_never_has_cave_props() -> void:
	var cave_only: Array = [
		_CATALOG.PROP_STALAGMITE,
		_CATALOG.PROP_MUSHROOM,
		_CATALOG.PROP_CRYSTAL,
		_CATALOG.PROP_ROOTS,
	]
	for role in ["bedroom", "living_room", "kitchen", "study", "storage"]:
		var ids := _plan_and_get_ids(role, "residential", Vector2i(6, 6), 12345, 4)
		for cave_prop in cave_only:
			assert_false(ids.has(cave_prop),
				"%s (residential) не должен содержать cave prop %s" % [role, cave_prop])

func test_tower_top_never_has_technical_props() -> void:
	# Верхние жилые этажи не должны получать boiler/rune_engine/pipe.
	var technical_only: Array = [
		_CATALOG.PROP_BOILER,
		_CATALOG.PROP_RUNE_ENGINE,
		_CATALOG.PROP_ALCHEMICAL_VAT,
		_CATALOG.PROP_PIPE_STRAIGHT,
		_CATALOG.PROP_VALVE,
	]
	for role in ["study", "storage", "small_room"]:
		var ids := _plan_and_get_ids(role, "tower_top", Vector2i(6, 6), 12345, 1)
		for tech_prop in technical_only:
			assert_false(ids.has(tech_prop),
				"%s (tower_top) не должен содержать technical %s" % [role, tech_prop])

func test_caves_never_has_residential_props() -> void:
	# Кровати, шкафы, письменные столы не должны появляться в пещерах.
	var residential_only: Array = [
		_CATALOG.PROP_BED,
		_CATALOG.PROP_WARDROBE,
		_CATALOG.PROP_DESK,
	]
	var ids := _plan_and_get_ids("cave_chamber", "caves", Vector2i(6, 6), 12345, 20)
	for res_prop in residential_only:
		assert_false(ids.has(res_prop),
			"cave_chamber не должен содержать residential prop %s" % res_prop)

# --- Determinism ---------------------------------------------------------

func test_composition_deterministic_across_zones() -> void:
	# Full-floor симуляция: тот же seed → тот же plan для всех зон.
	for zone_and_role in [
		["residential", "bedroom"],
		["technical", "machine_room"],
		["basement", "basement_cell"],
		["caves", "cave_chamber"],
	]:
		var ids_a := _plan_and_get_ids(zone_and_role[1], zone_and_role[0], Vector2i(6, 6), 42, 4)
		var ids_b := _plan_and_get_ids(zone_and_role[1], zone_and_role[0], Vector2i(6, 6), 42, 4)
		assert_eq(ids_a, ids_b,
			"%s.%s должна быть детерминированной. a=%s b=%s" % [zone_and_role[0], zone_and_role[1], ids_a, ids_b])
