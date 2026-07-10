extends GutTest

# Декор пола/стен (плесень, канделябры, трещины, кровяные пятна)
# добавляется в отдельный узел DecorRoot как Sprite2D без коллизии.
#
# С M3 tower_floor_generation: cave-декор ставится только там, где
# зона/роль его разрешает. Тесты используют глубокие этажи (basement
# zone, floor 15) — на них mold/crack/candle обязаны появляться.
# Верхние residential/technical этажи — под тем же декор-путём, но
# профиль пустой, поэтому декор не спавнится (см. test_decor_profiles.gd
# и test_floor_decor_zones.gd).
#
# Контракт:
# 1. на deep этаже хотя бы один cave-декор появляется;
# 2. размещение детерминировано от seed — тот же tower_seed / floor
#    даёт то же самое расположение;
# 3. декор не пересекается с проходимой геометрией: floor-декали лежат
#    только на floor-тайлах, wall-декали — на стенах, обращённых в
#    комнату (пиксельная точность визуала не тестируется).

const FloorScene = preload("res://scenes/dungeon/floor.tscn")
const MoldTexture = preload("res://assets/sprites/environment/mold.png")
const CandleTexture = preload("res://assets/sprites/environment/candle.png")
const CrackTexture = preload("res://assets/sprites/environment/floor_crack.png")
const BloodTexture = preload("res://assets/sprites/environment/floor_blood.png")

func _instantiate_floor(tower_seed: int, floor_number: int) -> Node2D:
	# Floor читает seed из GameState — подменяем его перед инстансом.
	GameState.tower_seed = tower_seed
	GameState.current_floor_number = floor_number
	var floor_node: Node2D = FloorScene.instantiate()
	add_child_autofree(floor_node)
	return floor_node

func _decor_root(floor_node: Node2D) -> Node2D:
	return floor_node.get_node("DecorRoot")

func _decor_textures(floor_node: Node2D) -> Array:
	var textures: Array = []
	for child in _decor_root(floor_node).get_children():
		textures.append(child.texture)
	return textures

func _decor_signature(floor_node: Node2D) -> Array:
	# Стабильная сигнатура: (texture_path, position) для каждой декали,
	# отсортированная по позиции. Позволяет сравнить два прогона с
	# одинаковым seed.
	var items: Array = []
	for child in _decor_root(floor_node).get_children():
		var sprite: Sprite2D = child
		items.append([sprite.texture.resource_path, sprite.position.x, sprite.position.y])
	items.sort()
	return items

func test_decor_root_exists_and_populates_for_deep_floor() -> void:
	# Basement zone (floor 15-18) — mold/candle/crack разрешены.
	# Взято floor 16 чтобы точно попасть в basement, не boss.
	var floor_node := _instantiate_floor(123456, 16)
	assert_gt(_decor_root(floor_node).get_child_count(), 0,
		"на deep этаже (basement) должен быть хотя бы один декор")

func test_decor_placement_is_deterministic_for_same_seed() -> void:
	var floor_a := _instantiate_floor(987654, 16)
	var sig_a := _decor_signature(floor_a)
	var floor_b := _instantiate_floor(987654, 16)
	var sig_b := _decor_signature(floor_b)
	assert_eq(sig_a, sig_b,
		"один и тот же seed должен давать одинаковую раскладку декора")

func test_decor_differs_between_seeds() -> void:
	# Разные seed'ы должны давать хотя бы немного разную раскладку —
	# иначе декор ощущается статичным.
	var floor_a := _instantiate_floor(111, 16)
	var floor_b := _instantiate_floor(222, 16)
	assert_ne(_decor_signature(floor_a), _decor_signature(floor_b),
		"разные seed'ы должны давать разные раскладки декора")

func test_decor_uses_only_expected_textures() -> void:
	# Floor 4 — обычный этаж с достаточным числом candidate-тайлов;
	# boss-этаж (кратный 5) даёт слишком мало стен «в комнату», и
	# whitelist прошёл бы вакуумно на пустом наборе декалей.
	var floor_node := _instantiate_floor(42, 16)
	var expected := [
		MoldTexture, CandleTexture, CrackTexture, BloodTexture,
	]
	var textures := _decor_textures(floor_node)
	assert_gt(textures.size(), 0,
		"тест теряет смысл, если декор не выпал вообще")
	for tex in textures:
		assert_true(expected.has(tex),
			"декор должен использовать только предопределённые текстуры")
