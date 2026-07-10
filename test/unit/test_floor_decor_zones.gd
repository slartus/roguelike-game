extends GutTest

# Integration регресс: verhние зоны (tower_top/residential/technical)
# не должны использовать cave-only декор (mold/candle/crack/blood) как
# основной профиль. Это ключевой acceptance M3 tower_floor_generation:
# «верхние/жилые этажи визуально перестают выглядеть как пещеры».

const FloorScene = preload("res://scenes/dungeon/floor.tscn")
const MoldTexture = preload("res://assets/sprites/environment/mold.png")
const CandleTexture = preload("res://assets/sprites/environment/candle.png")
const CrackTexture = preload("res://assets/sprites/environment/floor_crack.png")
const BloodTexture = preload("res://assets/sprites/environment/floor_blood.png")

const CAVE_TEXTURES := [MoldTexture, CandleTexture, CrackTexture, BloodTexture]

func _instantiate_floor(tower_seed: int, floor_number: int) -> Node2D:
	GameState.tower_seed = tower_seed
	GameState.current_floor_number = floor_number
	var floor_node: Node2D = FloorScene.instantiate()
	add_child_autofree(floor_node)
	return floor_node

func _count_cave_decor(floor_node: Node2D) -> int:
	var decor_root: Node2D = floor_node.get_node("DecorRoot")
	var count := 0
	for child in decor_root.get_children():
		if child is Sprite2D and CAVE_TEXTURES.has(child.texture):
			count += 1
		# candle.tscn — сложная сцена, не Sprite2D. Проверяем по имени.
		if child.scene_file_path.ends_with("candle.tscn"):
			count += 1
	return count

func test_tower_top_floor_has_no_cave_decor() -> void:
	# Floor 1 → tower_top zone. Cave-декор запрещён.
	var floor_node := _instantiate_floor(4242, 1)
	assert_eq(_count_cave_decor(floor_node), 0,
		"floor 1 (tower_top) НЕ должен иметь mold/candle/crack/blood")

func test_residential_floor_has_no_cave_decor() -> void:
	# Floor 4 → residential zone.
	var floor_node := _instantiate_floor(4243, 4)
	assert_eq(_count_cave_decor(floor_node), 0,
		"floor 4 (residential) НЕ должен иметь cave-декор")

func test_technical_floor_has_at_most_minimal_cave_decor() -> void:
	# Technical zone разрешает pipe в стенах через fallback, но всё ещё
	# не разрешает mold/candle/crack/blood как основной профиль.
	var floor_node := _instantiate_floor(4244, 8)
	assert_eq(_count_cave_decor(floor_node), 0,
		"floor 8 (technical) НЕ должен иметь cave-only декор")

func test_basement_floor_can_have_cave_decor() -> void:
	# Floor 16 → basement zone, cave-декор разрешён.
	var floor_node := _instantiate_floor(4245, 16)
	# basement zone имеет mold/candle в wall fallback, mold/crack на floor.
	# С seed 4245 хотя бы что-то должно выпасть.
	assert_gt(_count_cave_decor(floor_node), 0,
		"floor 16 (basement) может использовать mold/candle/crack")

func test_caves_floor_uses_cave_decor() -> void:
	# Floor 20 → caves zone. Cave-декор — основной.
	var floor_node := _instantiate_floor(4246, 20)
	assert_gt(_count_cave_decor(floor_node), 0,
		"floor 20 (caves) должен активно использовать cave-декор")
