extends Node2D

# Инстанс одного этажа подземелья. При _ready:
# 1. Генерирует layout через DungeonGenerator (seed берётся из GameState).
# 2. Резолвит EnvironmentVisualProfile по layout.zone — профиль
#    определяет какие материалы (пол/коридор/стена) применяются.
# 3. Рисует пол: room-по-role → material.floor_texture,
#    corridor → profile.corridor_floor_material. Один Polygon2D
#    на прямоугольник (rect), не Sprite2D per cell.
# 4. Строит стены двух видов через wall face / wall cap текстуры
#    того же профиля. Cap визуально отличается от solid — верхняя
#    часть материала светлее (см. tools/gen_environment_sprites.py).
# 5. Кладёт doorway_threshold поверх каждого corridor'а — визуальное
#    указание, что здесь переход между материалами (порог).
# 6. Строит astar_grid, инстансирует дверь на exit_position,
#    экспортирует player_start / enemy_spawn_positions / chest_positions
#    для потребителей (Main).
#
# Cosmetic-RNG (декор в `_place_decor`) детерминирован от tower_seed *
# 31 + 7 — та же последовательность что и раньше, gameplay RNG в
# DungeonGenerator не затрагивается. Материалы резолвятся из
# (zone, role, is_corridor) без RNG — одинаковый layout всегда даёт
# одинаковую раскладку материалов.

const DungeonGeneratorClass = preload("res://scenes/dungeon/dungeon_generator.gd")
const DOOR_SCENE: PackedScene = preload("res://scenes/rooms/door.tscn")
const MOLD_TEXTURE: Texture2D = preload("res://assets/sprites/environment/mold.png")
const CANDLE_SCENE: PackedScene = preload("res://scenes/dungeon/candle.tscn")
const FLOOR_CRACK_TEXTURE: Texture2D = preload("res://assets/sprites/environment/floor_crack.png")
const FLOOR_BLOOD_TEXTURE: Texture2D = preload("res://assets/sprites/environment/floor_blood.png")
const RoomDecorationPlannerClass = preload("res://scenes/dungeon/room_decoration_planner.gd")
const _DEF := preload("res://scenes/dungeon/environment_prop_definition.gd")
# Gameplay-prop сцены (PR4). Выбор по def.interaction_type в
# _instantiate_placement. Отдельный interaction_scene в самом def
# имеет приоритет — так catalog может подставить кастомную сцену
# без нового interaction_type.
const DAMAGEABLE_PROP_SCENE: PackedScene = preload("res://scenes/dungeon/damageable_environment_prop.tscn")
const EXPLOSIVE_BARREL_SCENE: PackedScene = preload("res://scenes/dungeon/explosive_barrel.tscn")
const LORE_INTERACTABLE_SCENE: PackedScene = preload("res://scenes/dungeon/lore_interactable.tscn")
const HEALTH_PICKUP_SCENE: PackedScene = preload("res://scenes/pickups/health_pickup.tscn")
const _DROP_TABLE := preload("res://scenes/dungeon/environment_drop_table.gd")

const TILE_SIZE: int = 20
# Клетки, зарезервированные вокруг critical anchor'ов (player start,
# exit, chest) — блокирующие props в этот радиус не ставятся.
const ENTRANCE_CLEAR_RADIUS_CELLS: int = 2
const EXIT_CLEAR_RADIUS_CELLS: int = 2
const CHEST_CLEAR_RADIUS_CELLS: int = 1
const ENEMY_SPAWN_CLEAR_RADIUS_CELLS: int = 1

# Шансы декора — те же, что в предыдущей версии; профили меняют только
# материал пола/стен, не влияют на декор-логику.
const CANDLE_CHANCE: float = 0.05
const MOLD_CHANCE: float = 0.14
const CRACK_CHANCE: float = 0.03
const BLOOD_CHANCE: float = 0.015

var player_start: Vector2 = Vector2.ZERO
var enemy_spawn_positions: Array[Vector2] = []
var chest_positions: Array[Vector2] = []
var door: Area2D
var floor_size: Vector2 = Vector2.ZERO
var layout: DungeonLayout
var astar_grid: AStarGrid2D
# Резолвленый профиль зоны — фиксируется в _ready до рендера, чтобы
# все методы отрисовки видели одинаковый набор материалов.
var visual_profile: EnvironmentVisualProfile
# Кэшированные текстуры стен для _create_wall_span. Резолвятся один
# раз из visual_profile.default_wall_material — все стены одного этажа
# используют один материал (per-room override стен не поддерживается
# в этом PR: стены разделяют две комнаты и не имеют однозначной роли).
var _wall_face_texture: Texture2D
var _wall_cap_texture: Texture2D
# Резолвленые материалы пола по индексу комнаты в layout.rooms.
# Заполняется в _resolve_room_materials перед _draw_floor_tiles.
var _room_floor_textures: Array[Texture2D] = []
var _corridor_floor_texture: Texture2D
var _doorway_threshold_texture: Texture2D
# Итог планировщика пропов — array of Placement и blocked_cells для
# AStar. Заполняется в _plan_and_place_props, читается тестами и
# instantiate-логикой.
var floor_plan: RoomDecorationPlannerClass.FloorPlan
# Drop-table для destructible props. Один инстанс на этаж, чтобы
# floor-wide budget пересекал все разрушенные destructibles.
var drop_table: EnvironmentDropTable
# Список placement_index'ов, уже разрушенных на этом этаже. Тесты и
# наблюдатели могут читать. Повторный destroyed сигнал с тем же
# индексом игнорируется — guard от chain-reaction race.
var _destroyed_placement_indices: Dictionary = {}

@onready var _floors_root: Node2D = $FloorsRoot
@onready var _walls_root: Node2D = $WallsRoot
@onready var _decor_root: Node2D = $DecorRoot
@onready var _props_root: Node2D = $PropsRoot
@onready var _markers_root: Node2D = $MarkersRoot

func _ready() -> void:
	add_to_group("floor")
	var seed_value := _pick_seed()
	var generator := DungeonGeneratorClass.new()
	layout = generator.generate(
		seed_value,
		GameState.current_floor_number,
		_is_boss_floor(),
	)
	_resolve_visual_profile()
	_resolve_room_materials()
	_draw_background()
	_draw_floor_tiles()
	_draw_doorway_thresholds()
	_build_walls()
	# Порядок важен: planner собирает reservations из layout (player start,
	# exit, chest, enemy spawns) и определяет какие клетки заняты пропами.
	# _build_astar_grid должен видеть blocked_cells — иначе AI пойдёт через
	# мебель. _place_decor (legacy настенные candles/mold) ставится после,
	# чтобы cave-crack не рисовался поверх blocking prop'а.
	_plan_and_place_props()
	_place_decor(seed_value)
	_build_astar_grid()
	_place_door()
	_populate_marker_positions()
	floor_size = Vector2(layout.floor_bounds.size)

func _pick_seed() -> int:
	# Детерминированно от GameState.tower_seed + номера этажа.
	return GameState.tower_seed * 100003 + GameState.current_floor_number

func _is_boss_floor() -> bool:
	return GameState.current_floor_number % 5 == 0

func _resolve_visual_profile() -> void:
	# layout.zone — String; профили индексируются StringName-ом. Приводим
	# явно, чтобы неизвестные значения падали в FALLBACK_ZONE предсказуемо.
	var zone_key := StringName(layout.zone)
	visual_profile = EnvironmentVisualProfiles.for_zone(zone_key)
	var wall_material := EnvironmentMaterialCatalog.get_material(visual_profile.default_wall_material)
	if wall_material != null:
		_wall_face_texture = wall_material.wall_texture
		_wall_cap_texture = wall_material.wall_cap_texture
	var doorway := EnvironmentMaterialCatalog.get_material(&"doorway_threshold")
	if doorway != null:
		_doorway_threshold_texture = doorway.floor_texture

func _resolve_room_materials() -> void:
	# RoomRoles.assign_roles гарантирует room_infos[i].room_index == i
	# (см. dungeon_layout.gd). Пустой room_infos → default material для
	# всех rooms (backward compat с layouts, где роли не проставлены).
	_room_floor_textures.clear()
	_room_floor_textures.resize(layout.rooms.size())
	var zone_key := StringName(layout.zone)
	# Инициализируем всё дефолтом; известные роли перезаписываются ниже.
	var default_id := EnvironmentVisualProfiles.resolve_floor_material(
		zone_key, &"", false,
	)
	var default_texture := _material_floor_texture(default_id)
	for i in layout.rooms.size():
		_room_floor_textures[i] = default_texture
	for info in layout.room_infos:
		var idx := int(info.room_index)
		if idx < 0 or idx >= _room_floor_textures.size():
			continue
		var role_key := StringName(String(info.role))
		var material_id := EnvironmentVisualProfiles.resolve_floor_material(
			zone_key, role_key, false,
		)
		_room_floor_textures[idx] = _material_floor_texture(material_id)
	var corridor_material_id := EnvironmentVisualProfiles.resolve_floor_material(
		zone_key, &"", true,
	)
	_corridor_floor_texture = _material_floor_texture(corridor_material_id)

func _material_floor_texture(id: StringName) -> Texture2D:
	var material := EnvironmentMaterialCatalog.get_material(id)
	if material == null:
		return null
	return material.floor_texture

func _draw_background() -> void:
	var bg := Polygon2D.new()
	var size := layout.floor_bounds.size
	bg.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0),
		Vector2(size.x, size.y),
		Vector2(0, size.y),
	])
	bg.color = visual_profile.background_color
	_floors_root.add_child(bg)

func _draw_floor_tiles() -> void:
	for i in layout.rooms.size():
		var texture: Texture2D = _room_floor_textures[i]
		if texture == null:
			continue
		_draw_tiled_rect(layout.rooms[i], texture)
	for corridor in layout.corridors:
		if _corridor_floor_texture == null:
			continue
		_draw_tiled_rect(corridor, _corridor_floor_texture)

func _draw_doorway_thresholds() -> void:
	# Порог поверх каждого corridor'а — визуально маркирует переход между
	# room material и corridor material. Кладём в тот же FloorsRoot после
	# всех обычных floor rects, чтобы threshold рисовался поверх пола, но
	# под стенами. Alpha текстуры контролируется UV — рисуем как есть.
	if _doorway_threshold_texture == null:
		return
	for corridor in layout.corridors:
		_draw_stretched_rect(corridor, _doorway_threshold_texture)

func _draw_tiled_rect(rect: Rect2i, texture: Texture2D) -> void:
	var poly := Polygon2D.new()
	var origin := Vector2(rect.position)
	var size := Vector2(rect.size)
	var points := PackedVector2Array([
		origin,
		origin + Vector2(size.x, 0),
		origin + size,
		origin + Vector2(0, size.y),
	])
	poly.polygon = points
	# UV = абсолютные координаты этажа → соседние rects дают бесшовный
	# tiling без «прыжков» текстуры на стыках комнат и коридоров.
	poly.uv = points
	poly.texture = texture
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_floors_root.add_child(poly)

func _draw_stretched_rect(rect: Rect2i, texture: Texture2D) -> void:
	# Растягивает одну текстуру на весь rect (без tiling). Использует
	# UV [0..tex_size] — Godot сам масштабирует под polygon.
	var poly := Polygon2D.new()
	var origin := Vector2(rect.position)
	var size := Vector2(rect.size)
	poly.polygon = PackedVector2Array([
		origin,
		origin + Vector2(size.x, 0),
		origin + size,
		origin + Vector2(0, size.y),
	])
	var tex_size := Vector2(texture.get_size())
	poly.uv = PackedVector2Array([
		Vector2.ZERO,
		Vector2(tex_size.x, 0),
		tex_size,
		Vector2(0, tex_size.y),
	])
	poly.texture = texture
	_floors_root.add_child(poly)

func _build_walls() -> void:
	# Каждая wall-tile может быть двух видов, различаются только текстурой:
	# - solid — обычная стена; рисуется _wall_face_texture.
	# - cap — верхний ряд толстой (2+ tile) горизонтальной стены; рисуется
	#   _wall_cap_texture (визуальный «козырёк над кромкой»).
	# Коллизия одинаковая — оба варианта StaticBody2D + CollisionShape2D,
	# чтобы игрок и мобы не могли зайти в нижние стены снизу. Merge
	# горизонтальных span'ов идёт отдельно для каждого вида, чтобы у span'а
	# была одна текстура.
	var bounds := layout.floor_bounds
	var cols := int(ceil(float(bounds.size.x) / TILE_SIZE))
	var rows := int(ceil(float(bounds.size.y) / TILE_SIZE))
	for row in rows:
		_build_wall_row(row, cols, "solid")
		_build_wall_row(row, cols, "cap")

func _build_wall_row(row: int, cols: int, kind: String) -> void:
	var span_start := -1
	for col in cols:
		if _wall_kind_at(col, row) == kind:
			if span_start == -1:
				span_start = col
		else:
			if span_start >= 0:
				_create_wall_span(span_start, col, row, kind)
				span_start = -1
	if span_start >= 0:
		_create_wall_span(span_start, cols, row, kind)

func _wall_kind_at(col: int, row: int) -> String:
	# "solid" — обычная стена. "cap" — верхний ряд толстой стены (сверху
	# комната/коридор, снизу ещё wall). Оба вида дают коллизию, отличаются
	# только текстурой. "" (пустая строка) — не wall (пол).
	var center := Vector2i(col * TILE_SIZE + TILE_SIZE / 2, row * TILE_SIZE + TILE_SIZE / 2)
	if not _is_wall_at(center):
		return ""
	var above := center + Vector2i(0, -TILE_SIZE)
	var below := center + Vector2i(0, TILE_SIZE)
	var bounds := layout.floor_bounds
	var above_is_floor := above.y >= 0 and not _is_wall_at(above)
	var below_is_wall := below.y < bounds.size.y and _is_wall_at(below)
	if above_is_floor and below_is_wall:
		return "cap"
	return "solid"

func _is_wall_at(point: Vector2i) -> bool:
	for room in layout.rooms:
		if room.has_point(point):
			return false
	for corridor in layout.corridors:
		if corridor.has_point(point):
			return false
	return true

func _create_wall_span(col_start: int, col_end: int, row: int, kind: String) -> void:
	var span_width := TILE_SIZE * (col_end - col_start)
	var shape_size := Vector2(span_width, TILE_SIZE)
	var origin_pos := Vector2(col_start * TILE_SIZE + span_width / 2.0, row * TILE_SIZE + TILE_SIZE / 2.0)
	var half := shape_size / 2.0
	var points := PackedVector2Array([
		-half,
		Vector2(half.x, -half.y),
		half,
		Vector2(-half.x, half.y),
	])
	# UV на основе абсолютной позиции стены — соседние span-ы бесшовно
	# продолжают кладку/панели материала.
	var abs_origin := origin_pos - half
	var uv := PackedVector2Array([
		abs_origin,
		abs_origin + Vector2(shape_size.x, 0),
		abs_origin + shape_size,
		abs_origin + Vector2(0, shape_size.y),
	])
	var visual := Polygon2D.new()
	visual.polygon = points
	visual.uv = uv
	if kind == "cap":
		visual.texture = _wall_cap_texture if _wall_cap_texture != null else _wall_face_texture
	else:
		visual.texture = _wall_face_texture
	visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# И solid, и cap оборачиваются в StaticBody2D + CollisionShape2D. Отличие
	# только в текстуре Polygon2D — cap рисует «козырёк», но физически это
	# всё равно стена: игрок и мобы не должны заходить в неё сверху вниз.
	var body := StaticBody2D.new()
	body.position = origin_pos
	var collision := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = shape_size
	collision.shape = rect_shape
	body.add_child(collision)
	body.add_child(visual)
	_walls_root.add_child(body)

func _plan_and_place_props() -> void:
	# Собираем reservations — клетки, где planner не должен ставить
	# блокирующий prop: doorways, точка входа/выхода, сундуки, спавны
	# врагов, обязательный корридор внутри стартовой/выходной комнаты.
	# Seed — та же комбинация (tower_seed, floor_number), что использует
	# gameplay-путь; RoomDecorationPlanner делает из неё собственный
	# room-level поток через `_seed_for_room` (см. planner) и не сдвигает
	# gameplay RNG.
	var reservations := _collect_reservations()
	floor_plan = RoomDecorationPlannerClass.plan_floor(
		layout,
		reservations,
		GameState.tower_seed,
		GameState.current_floor_number,
	)
	drop_table = _DROP_TABLE.new_for_floor(
		GameState.tower_seed,
		GameState.current_floor_number,
	)
	for i in floor_plan.placements.size():
		_instantiate_placement(floor_plan.placements[i], i)

func _collect_reservations() -> Dictionary:
	# Возвращает Dictionary Vector2i(col, row) → true. Все критичные
	# anchor'ы + clear radius. Corridor cells тоже помечаем, чтобы
	# planner уважал границы doorway-корридора между комнатами.
	var reserved: Dictionary = {}
	_reserve_around(reserved, layout.player_start, ENTRANCE_CLEAR_RADIUS_CELLS)
	_reserve_around(reserved, layout.exit_position, EXIT_CLEAR_RADIUS_CELLS)
	for chest_pos in layout.chest_positions:
		_reserve_around(reserved, chest_pos, CHEST_CLEAR_RADIUS_CELLS)
	for spawn_pos in layout.enemy_spawns:
		_reserve_around(reserved, spawn_pos, ENEMY_SPAWN_CLEAR_RADIUS_CELLS)
	# Corridor cells сами по себе — planner не заходит в corridor rects
	# (они не входят в room_cells), но door_cells внутри room берутся из
	# смежных corridor. Резервировать corridor cells не нужно.
	return reserved

func _reserve_around(reserved: Dictionary, pixel_pos: Vector2i, radius_cells: int) -> void:
	var center := Vector2i(pixel_pos.x / TILE_SIZE, pixel_pos.y / TILE_SIZE)
	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			reserved[center + Vector2i(dx, dy)] = true

func _instantiate_placement(
	placement: RoomDecorationPlannerClass.Placement,
	placement_index: int,
) -> void:
	var def: EnvironmentPropDefinition = placement.def
	# Gameplay props (PR4): destructible / hazard / lore инстанцируются
	# через свою scene (DamageableEnvironmentProp / ExplosiveBarrel /
	# LoreInteractable), а не через generic sprite+body. Пропы получают
	# configure() до add_child(), чтобы _ready видел финальные поля.
	if def.is_gameplay_prop():
		_instantiate_gameplay_prop(placement, placement_index)
		return
	# Опциональный override сцены для сложных декоративных пропов —
	# используется если catalog задаст def.scene.
	if def.scene != null:
		var node: Node2D = def.scene.instantiate()
		node.position = placement.center_pixel()
		_props_root.add_child(node)
		return
	if def.texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = def.texture
	# Спрайт центрируется в bbox'е: floor.gd берёт center_pixel() из
	# Placement, который учитывает footprint. Origin спрайта — левый
	# верх текстуры, поэтому Sprite2D.centered=true работает как есть.
	sprite.centered = true
	sprite.position = placement.center_pixel()
	if def.blocks_movement:
		var body := StaticBody2D.new()
		body.position = sprite.position
		sprite.position = Vector2.ZERO
		var collision := CollisionShape2D.new()
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = Vector2(def.footprint_cells * TILE_SIZE)
		collision.shape = rect_shape
		body.add_child(collision)
		body.add_child(sprite)
		_props_root.add_child(body)
	else:
		_props_root.add_child(sprite)

func _instantiate_gameplay_prop(
	placement: RoomDecorationPlannerClass.Placement,
	placement_index: int,
) -> void:
	var def: EnvironmentPropDefinition = placement.def
	var scene: PackedScene = def.interaction_scene
	if scene == null:
		scene = _gameplay_prop_scene_for(def.interaction_type)
	if scene == null:
		return
	var node: Node2D = scene.instantiate()
	# Настраиваем visual (texture) сразу — большинство gameplay-props
	# берут спрайт из def.texture, так же как декоративные.
	var visual: Sprite2D = node.get_node_or_null("Visual") as Sprite2D
	if visual != null and def.texture != null:
		visual.texture = def.texture
	# CollisionShape2D по footprint. Стандартный размер сцены = 20x20 —
	# для не-1x1 пропов расширяем shape через RectangleShape2D.
	_resize_prop_collision(node, def.footprint_cells)
	# Инстансу передаём typed configure. Ветка по interaction_type
	# гарантирует, что каждой сцене прилетают именно те поля, которые
	# она умеет читать — без лишних if'ов внутри самой сцены.
	# placement_index связывается прямо с сигналом destroyed через bind()
	# — handler получает индекс без O(N) поиска по позиции.
	match def.interaction_type:
		_DEF.INTERACTION_DESTRUCTIBLE:
			_configure_destructible(node, def, placement_index)
		_DEF.INTERACTION_HAZARD_EXPLOSIVE:
			_configure_explosive(node, def, placement_index)
		_DEF.INTERACTION_LORE:
			_configure_lore(node, def)
	node.position = placement.center_pixel()
	_props_root.add_child(node)

func _gameplay_prop_scene_for(interaction_type: StringName) -> PackedScene:
	match interaction_type:
		_DEF.INTERACTION_DESTRUCTIBLE:
			return DAMAGEABLE_PROP_SCENE
		_DEF.INTERACTION_HAZARD_EXPLOSIVE:
			return EXPLOSIVE_BARREL_SCENE
		_DEF.INTERACTION_LORE:
			return LORE_INTERACTABLE_SCENE
		_:
			return null

func _resize_prop_collision(node: Node2D, footprint_cells: Vector2i) -> void:
	var collision: CollisionShape2D = node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return
	if collision.shape is RectangleShape2D:
		(collision.shape as RectangleShape2D).size = Vector2(footprint_cells * TILE_SIZE)

func _configure_destructible(
	node: Node2D,
	def: EnvironmentPropDefinition,
	placement_index: int,
) -> void:
	if node is DamageableEnvironmentProp:
		var prop := node as DamageableEnvironmentProp
		prop.configure(def.id, def.destructible_max_health, def.damage_factions, def.footprint_cells)
		# bind(placement_index) — handler получает индекс O(1) без
		# поиска по позиции.
		prop.destroyed.connect(_on_damageable_prop_destroyed.bind(placement_index))

func _configure_explosive(
	node: Node2D,
	def: EnvironmentPropDefinition,
	placement_index: int,
) -> void:
	if not (node is DamageableEnvironmentProp):
		return
	var prop := node as DamageableEnvironmentProp
	prop.configure(def.id, def.destructible_max_health, def.damage_factions, def.footprint_cells)
	if node.has_method("configure_hazard"):
		node.call("configure_hazard", def.explosion_radius, def.explosion_damage, def.explosion_telegraph_time)
	prop.destroyed.connect(_on_hazard_destroyed.bind(placement_index))

func _configure_lore(node: Node2D, def: EnvironmentPropDefinition) -> void:
	if node is LoreInteractable:
		var lore := node as LoreInteractable
		lore.configure(def.id, def.lore_prompt_key, def.lore_text_key, def.footprint_cells)
		lore.prompt_shown.connect(EventLog.log_lore_prompt)
		lore.read.connect(EventLog.log_lore_text)

func _on_damageable_prop_destroyed(
	prop_id: StringName,
	world_position: Vector2,
	placement_index: int,
) -> void:
	_handle_prop_destroyed(prop_id, world_position, placement_index, false)

func _on_hazard_destroyed(
	prop_id: StringName,
	world_position: Vector2,
	placement_index: int,
) -> void:
	# Hazard тоже освобождает AStar cell (иначе после взрыва враги
	# считают что там всё ещё стена). Drop у hazard'а не роллим — план
	# явно говорит «hazard damages, а не rewards».
	_handle_prop_destroyed(prop_id, world_position, placement_index, true)
	EventLog.log_hazard_explosion()

func _handle_prop_destroyed(
	prop_id: StringName,
	world_position: Vector2,
	placement_index: int,
	is_hazard: bool,
) -> void:
	if placement_index < 0:
		return
	if _destroyed_placement_indices.has(placement_index):
		return
	_destroyed_placement_indices[placement_index] = true
	# Освобождаем клетки в AStar — AI перестроит путь на следующем recalc'е.
	_release_prop_cells(placement_index)
	# Drop rolling только для чистых destructibles, не hazards.
	if not is_hazard:
		_roll_and_spawn_drop(prop_id, placement_index, world_position)

func _release_prop_cells(placement_index: int) -> void:
	if floor_plan == null or astar_grid == null:
		return
	if placement_index < 0 or placement_index >= floor_plan.placements.size():
		return
	var placement: RoomDecorationPlannerClass.Placement = floor_plan.placements[placement_index]
	for offset_x in placement.footprint_cells.x:
		for offset_y in placement.footprint_cells.y:
			var cell: Vector2i = placement.cell_origin + Vector2i(offset_x, offset_y)
			floor_plan.blocked_cells.erase(cell)
			if astar_grid.region.has_point(cell):
				# Только если клетка вообще не wall (ни solid, ни cap —
				# первоначальный wall из _build_walls). Иначе AI сможет
				# пройти сквозь стену после того, как рядом разбили проп.
				if _wall_kind_at(cell.x, cell.y) == "":
					astar_grid.set_point_solid(cell, false)

func _roll_and_spawn_drop(prop_id: StringName, placement_index: int, world_position: Vector2) -> void:
	if drop_table == null:
		return
	var result := drop_table.roll(prop_id, placement_index)
	if result == _DROP_TABLE.RESULT_NONE:
		return
	match result:
		_DROP_TABLE.RESULT_GOLD_SMALL:
			GameState.award_gold(_DROP_TABLE.VALUE_GOLD_SMALL)
			EventLog.log_prop_drop(result, _DROP_TABLE.VALUE_GOLD_SMALL)
		_DROP_TABLE.RESULT_GOLD_LARGE:
			GameState.award_gold(_DROP_TABLE.VALUE_GOLD_LARGE)
			EventLog.log_prop_drop(result, _DROP_TABLE.VALUE_GOLD_LARGE)
		_DROP_TABLE.RESULT_POTION:
			# Спавним потион как pickup на floor'е — floor.gd не может
			# инжектировать его в inventory без коллизии с save/load
			# invariant'ом (game_state.gd не сохраняет потионы между
			# floor'ами; spawn через pickup даёт игроку возможность
			# сначала подойти и подобрать, если inventory не полон).
			# Parent = _markers_root (тот же, что для door) — position
			# в координатах Floor'а, независимо от transform current_scene.
			var pickup := HEALTH_PICKUP_SCENE.instantiate()
			pickup.position = world_position
			_markers_root.add_child.call_deferred(pickup)
			EventLog.log_prop_drop(result, 1)

func _place_decor(seed_value: int) -> void:
	# Декор — чисто визуальные Sprite2D без коллизии. Раскладывается
	# детерминированно по seed этажа: тот же tower_seed → тот же декор
	# при повторном забеге. Cosmetic RNG (multiplier 31, offset 7) не
	# затрагивает layout/gameplay RNG — это остаётся инвариантом M3.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	var bounds := layout.floor_bounds
	var cols := int(ceil(float(bounds.size.x) / TILE_SIZE))
	var rows := int(ceil(float(bounds.size.y) / TILE_SIZE))
	for row in rows:
		for col in cols:
			var tile_center := Vector2i(col * TILE_SIZE + TILE_SIZE / 2, row * TILE_SIZE + TILE_SIZE / 2)
			# Пропускаем клетки, где planner уже поставил блокирующий prop —
			# иначе legacy floor_crack рисуется поверх мебели.
			if _is_cell_blocked_by_prop(col, row):
				continue
			var profile := _decor_profile_at(tile_center)
			var wall_types: Array = profile.get("wall", [])
			var floor_types: Array = profile.get("floor", [])
			if _is_wall_at(tile_center):
				var below_center := tile_center + Vector2i(0, TILE_SIZE)
				var below_is_floor := below_center.y < bounds.size.y and not _is_wall_at(below_center)
				if not below_is_floor:
					continue
				var roll := rng.randf()
				if wall_types.has(DecorProfiles.DECOR_CANDLE) and roll < CANDLE_CHANCE:
					_spawn_candle(Vector2(tile_center) + Vector2(0, -1))
				elif wall_types.has(DecorProfiles.DECOR_MOLD) and roll < CANDLE_CHANCE + MOLD_CHANCE:
					_spawn_decor(MOLD_TEXTURE, Vector2(tile_center) + Vector2(0, 2))
			else:
				var roll := rng.randf()
				if floor_types.has(DecorProfiles.DECOR_CRACK) and roll < CRACK_CHANCE:
					_spawn_decor(FLOOR_CRACK_TEXTURE, Vector2(tile_center))
				elif floor_types.has(DecorProfiles.DECOR_BLOOD) and roll < CRACK_CHANCE + BLOOD_CHANCE:
					_spawn_decor(FLOOR_BLOOD_TEXTURE, Vector2(tile_center))

func _is_cell_blocked_by_prop(col: int, row: int) -> bool:
	return floor_plan != null and floor_plan.blocked_cells.has(Vector2i(col, row))

func _decor_profile_at(tile_center: Vector2i) -> Dictionary:
	if layout.room_infos.is_empty():
		return DecorProfiles.decor_profile_for_zone(layout.zone)
	for info in layout.room_infos:
		var room: Rect2i = layout.rooms[info.room_index]
		if room.has_point(tile_center):
			return DecorProfiles.decor_profile_for_room(info.role, info.zone)
	return DecorProfiles.decor_profile_for_zone(layout.zone)

func _spawn_decor(texture: Texture2D, at: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = at
	_decor_root.add_child(sprite)

func _spawn_candle(at: Vector2) -> void:
	var candle: Sprite2D = CANDLE_SCENE.instantiate()
	candle.position = at
	_decor_root.add_child(candle)

func _build_astar_grid() -> void:
	var bounds := layout.floor_bounds
	var cols := int(ceil(float(bounds.size.x) / TILE_SIZE))
	var rows := int(ceil(float(bounds.size.y) / TILE_SIZE))
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(Vector2i.ZERO, Vector2i(cols, rows))
	astar_grid.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	astar_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar_grid.update()
	for row in rows:
		for col in cols:
			# Обе wall-разновидности (solid и cap) блокируют pathfinding —
			# у cap теперь тоже коллизия, AI и физика должны совпадать.
			if _wall_kind_at(col, row) != "":
				astar_grid.set_point_solid(Vector2i(col, row), true)
	# Пропы, помеченные blocks_movement, тоже solid — иначе AI (и pathing
	# summon fallback) уйдёт сквозь мебель. Список приходит от planner'а;
	# gameplay совместим — floor.gd раньше блокировал только стены.
	if floor_plan != null:
		for cell in floor_plan.blocked_cells.keys():
			var col: int = cell.x
			var row: int = cell.y
			if col < 0 or row < 0 or col >= cols or row >= rows:
				continue
			astar_grid.set_point_solid(cell, true)

func _place_door() -> void:
	door = DOOR_SCENE.instantiate()
	door.position = Vector2(layout.exit_position)
	_markers_root.add_child(door)

func _populate_marker_positions() -> void:
	player_start = Vector2(layout.player_start)
	enemy_spawn_positions.clear()
	for point in layout.enemy_spawns:
		enemy_spawn_positions.append(Vector2(point))
	chest_positions.clear()
	for point in layout.chest_positions:
		chest_positions.append(Vector2(point))
