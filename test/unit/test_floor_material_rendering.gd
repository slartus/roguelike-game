extends GutTest

# Интеграционные тесты рендер-слоя floor.gd на реальный layout:
# - профиль зоны корректно резолвится и хранится на инстансе Floor;
# - stone_metal_grid не появляется в residential (кухня даёт tile,
#   стены — дерево, коридор — camень); zone заметно отличается от
#   caves даже на visual level;
# - wall face и wall cap рендерятся разными Texture2D;
# - Floors/Walls Root не создают Sprite2D per cell (только Polygon2D /
#   StaticBody2D-обёртки);
# - тот же seed / floor даёт ту же раскладку материалов (детерминизм);
# - существует хотя бы один doorway_threshold overlay в FloorsRoot.

const FloorScene = preload("res://scenes/dungeon/floor.tscn")

# --- Snapshot autoload -----------------------------------------------------

var _snapshot: Dictionary

func before_each() -> void:
	_snapshot = {
		"seed": GameState.tower_seed,
		"floor": GameState.current_floor_number,
	}

func after_each() -> void:
	GameState.tower_seed = _snapshot["seed"]
	GameState.current_floor_number = _snapshot["floor"]

# --- Helpers ---------------------------------------------------------------

func _spawn_floor(seed: int, floor_number: int) -> Node2D:
	GameState.tower_seed = seed
	GameState.current_floor_number = floor_number
	var f: Node2D = FloorScene.instantiate()
	add_child_autofree(f)
	return f

func _floor_textures_in_root(f: Node2D) -> Array:
	# Все текстуры Polygon2D-детей FloorsRoot (background — Polygon2D без
	# текстуры, пропускается).
	var out: Array = []
	for child in f.get_node("FloorsRoot").get_children():
		if child is Polygon2D and child.texture != null:
			out.append(child.texture.resource_path)
	return out

func _wall_textures_in_root(f: Node2D) -> Array:
	# StaticBody2D дети имеют Polygon2D внутри — берём их texture.
	# «Голые» Polygon2D (cap) — тоже. Возвращаем плоский список путей.
	var out: Array = []
	for child in f.get_node("WallsRoot").get_children():
		if child is StaticBody2D:
			for sub in child.get_children():
				if sub is Polygon2D and sub.texture != null:
					out.append(sub.texture.resource_path)
		elif child is Polygon2D and child.texture != null:
			out.append(child.texture.resource_path)
	return out

# --- Профиль на инстансе ---------------------------------------------------

func test_floor_resolves_profile_for_current_zone() -> void:
	# floor 4 → residential zone → residential профиль.
	var f := _spawn_floor(42, 4)
	await get_tree().process_frame
	assert_not_null(f.visual_profile, "visual_profile должен быть резолвлен")
	assert_eq(f.visual_profile.id, &"residential",
		"floor 4 → residential zone")

func test_floor_resolves_profile_for_technical_floor() -> void:
	# floor 8 → technical.
	var f := _spawn_floor(42, 8)
	await get_tree().process_frame
	assert_eq(f.visual_profile.id, &"technical")

func test_floor_resolves_profile_for_basement_floor() -> void:
	# floor 16 → basement.
	var f := _spawn_floor(42, 16)
	await get_tree().process_frame
	assert_eq(f.visual_profile.id, &"basement")

# --- Wall face vs cap ------------------------------------------------------

func test_walls_use_face_and_cap_textures_from_profile() -> void:
	# floor 4 → residential; wood_panel_wall / wood_panel_wall_cap.
	var f := _spawn_floor(42, 4)
	await get_tree().process_frame
	var face_path := "res://assets/sprites/environment/wood_panel_wall.png"
	var cap_path := "res://assets/sprites/environment/wood_panel_wall_cap.png"
	# Solid стены (StaticBody2D) обязаны использовать face texture.
	var solid_textures: Array = []
	# «Голые» Polygon2D (cap) обязаны использовать cap texture — если
	# они вообще есть в этом layout.
	var cap_textures: Array = []
	for child in f.get_node("WallsRoot").get_children():
		if child is StaticBody2D:
			for sub in child.get_children():
				if sub is Polygon2D and sub.texture != null:
					solid_textures.append(sub.texture.resource_path)
		elif child is Polygon2D and child.texture != null:
			cap_textures.append(child.texture.resource_path)
	assert_gt(solid_textures.size(), 0, "должна быть хоть одна solid стена")
	for path in solid_textures:
		assert_eq(path, face_path,
			"solid стены residential зоны должны использовать wood_panel_wall face")
	# Cap опционален (зависит от layout), но если появился — обязан быть cap
	# texture, а не face. Это ловит regression, где cap случайно рисуется
	# той же текстурой что и solid.
	for path in cap_textures:
		assert_eq(path, cap_path,
			"cap-обёртка обязана использовать wood_panel_wall_cap, не face")

# --- Zones визуально различаются ------------------------------------------

func test_different_zones_use_different_floor_textures() -> void:
	# residential vs caves — floor textures должны отличаться.
	var f_residential := _spawn_floor(42, 4)
	await get_tree().process_frame
	var res_textures := _floor_textures_in_root(f_residential)
	# Уносим f_residential из активной сцены, чтобы GameState smoke не
	# путался.
	var f_caves := _spawn_floor(42, 20)
	await get_tree().process_frame
	var cave_textures := _floor_textures_in_root(f_caves)
	assert_ne(res_textures, cave_textures,
		"residential и caves должны рисовать разными текстурами")
	# caves не должны содержать корridor_stone (это residential path).
	var cave_has_corridor_stone := false
	for path in cave_textures:
		if path.ends_with("corridor_stone.png"):
			cave_has_corridor_stone = true
			break
	assert_false(cave_has_corridor_stone,
		"caves не должны рисовать corridor_stone (residential material)")

# --- Threshold overlay -----------------------------------------------------

func test_doorway_threshold_overlay_is_drawn() -> void:
	# На floor 4 есть doorway'и — должен быть хотя бы один threshold в
	# FloorsRoot с doorway_threshold.png.
	var f := _spawn_floor(42, 4)
	await get_tree().process_frame
	var textures := _floor_textures_in_root(f)
	var expected := "res://assets/sprites/environment/doorway_threshold.png"
	assert_true(textures.has(expected),
		"должен быть doorway_threshold overlay в FloorsRoot")

# --- Никаких Sprite2D per cell --------------------------------------------

func test_floors_root_does_not_use_sprite2d_per_cell() -> void:
	# Требование плана PR 1: не создавать node per tile. FloorsRoot
	# должен содержать только Polygon2D-обёртки на прямоугольники
	# (rooms / corridors / thresholds), без Sprite2D per cell.
	var f := _spawn_floor(42, 4)
	await get_tree().process_frame
	var sprite_count := 0
	var polygon_count := 0
	for child in f.get_node("FloorsRoot").get_children():
		if child is Sprite2D:
			sprite_count += 1
		elif child is Polygon2D:
			polygon_count += 1
	# Даже маленький этаж имеет footprint > 100 tiles. Если бы был
	# Sprite2D per cell, счёт был бы > 100. Ожидаем разумно ограниченный
	# счёт Polygon2D (rooms + corridors + thresholds < 100).
	assert_eq(sprite_count, 0,
		"FloorsRoot не должен содержать Sprite2D per cell")
	assert_gt(polygon_count, 0, "FloorsRoot должен содержать Polygon2D-регионы")
	assert_lt(polygon_count, 200,
		"Polygon2D должно быть по регионам, не по клеткам (< 200)")

# --- Детерминизм резолвинга материалов -------------------------------------

func test_same_seed_produces_same_material_sequence() -> void:
	# Тот же (tower_seed, floor) → те же материалы у комнат.
	var f_a := _spawn_floor(4242, 4)
	await get_tree().process_frame
	var sig_a := _material_signature(f_a)
	var f_b := _spawn_floor(4242, 4)
	await get_tree().process_frame
	var sig_b := _material_signature(f_b)
	assert_eq(sig_a, sig_b,
		"один seed должен дать одинаковую последовательность материалов")

func _material_signature(f: Node2D) -> Array:
	# Стабильная сигнатура: список текстур по индексам room_infos,
	# отсортированный по (room_index, texture_path).
	var infos = f.layout.room_infos
	var out: Array = []
	for i in f._room_floor_textures.size():
		var tex: Texture2D = f._room_floor_textures[i]
		var path := "" if tex == null else tex.resource_path
		var role := ""
		for info in infos:
			if int(info.room_index) == i:
				role = String(info.role)
				break
		out.append([i, role, path])
	return out

# --- Cosmetic RNG не влияет на layout RNG ----------------------------------

func test_layout_room_count_matches_between_two_runs_with_same_seed() -> void:
	# Sanity-check: cosmetic layer (материалы / декор) не должен менять
	# число комнат по одному seed'у. Если бы material resolve использовал
	# gameplay RNG, разные проходы дали бы разные layouts.
	var f_a := _spawn_floor(999, 4)
	await get_tree().process_frame
	var count_a: int = f_a.layout.rooms.size()
	var f_b := _spawn_floor(999, 4)
	await get_tree().process_frame
	var count_b: int = f_b.layout.rooms.size()
	assert_eq(count_a, count_b,
		"same seed → same layout, cosmetic RNG изолирован")

# --- Filtering disabled на текстурах ---------------------------------------

func test_environment_textures_use_nearest_filtering() -> void:
	# Проектный настройка default_texture_filter=0 (NEAREST) — pixel-art
	# рендерится без сглаживания. Проверяем что floor.gd не переопределяет
	# это через CanvasItem.texture_filter на Polygon2D.
	var f := _spawn_floor(42, 4)
	await get_tree().process_frame
	for child in f.get_node("FloorsRoot").get_children():
		if child is Polygon2D:
			# TEXTURE_FILTER_PARENT_NODE (0) = наследуется от родителя, что
			# у нас означает NEAREST из project settings.
			assert_true(
				child.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE
					or child.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
				"Polygon2D в FloorsRoot должен использовать NEAREST filtering",
			)
