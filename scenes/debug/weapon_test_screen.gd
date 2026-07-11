extends Node2D

# Дебаг-песочница персонажа с оружием. Открывается из debug_menu.
# Показывает пустую комнату 480×270 с игроком в центре и рядом из
# всех доступных `WeaponResource` вдоль верхней стены. Игрок начинает
# без оружия — можно последовательно подходить, подбирать и бить.
# Врагов и HUD-логики нет: сцена нужна только чтобы посмотреть анимацию
# каждого оружия в руках без танцев с main.tscn.

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const WeaponPickupScene: PackedScene = preload("res://scenes/pickups/weapon_pickup.tscn")

const WEAPON_ROSTER: Array[WeaponResource] = [
	preload("res://resources/weapons/short_sword.tres"),
	preload("res://resources/weapons/dagger.tres"),
	preload("res://resources/weapons/spear.tres"),
	preload("res://resources/weapons/short_bow.tres"),
	preload("res://resources/weapons/crossbow.tres"),
	preload("res://resources/weapons/pistol.tres"),
	preload("res://resources/weapons/shotgun.tres"),
	preload("res://resources/weapons/apprentice_staff.tres"),
	preload("res://resources/weapons/wand.tres"),
]

const DEBUG_MENU_SCENE_PATH: String = "res://scenes/ui/debug_menu.tscn"

# Комната совпадает с viewport'ом 480×270. Стены — 12 пикселей толщины
# по периметру, чтобы у игрока и пикапов был явный «пол» и camera limits
# упирались в них. Внутренний прямоугольник: (12,12) — (468,258).
const ROOM_WIDTH: int = 480
const ROOM_HEIGHT: int = 270
const WALL_THICKNESS: int = 12

# Ряд оружия — по центру внутреннего room-inner-top, чуть ниже верхней
# стены. Игрок стартует под рядом ближе к центру комнаты — так за один
# шаг вверх касается любого пикапа.
const WEAPONS_ROW_Y: int = 48
const PLAYER_SPAWN_POSITION: Vector2 = Vector2(240, 190)

# Цвета в тон title screen'а: тёмно-фиолетовый фон + чуть светлее пол,
# ещё светлее стены. Не подтягиваем текстуры floor.gd — тестовой сцене
# достаточно контраста, чтобы визуально отделить пол от стены.
const BACKGROUND_COLOR: Color = Color(0.03, 0.02, 0.05, 1.0)
const FLOOR_COLOR: Color = Color(0.10, 0.08, 0.14, 1.0)
const WALL_COLOR: Color = Color(0.22, 0.18, 0.28, 1.0)

@onready var _room_root: Node2D = $Room
@onready var _weapons_root: Node2D = $Weapons
@onready var _player_root: Node2D = $PlayerRoot
@onready var _hint_label: Label = $HUD/HintLabel

func _ready() -> void:
	# dungeon_preview_screen отключает viewport-stretch. Если игрок прошёл
	# через него → debug_menu → сюда, мы уже находимся в VIEWPORT-режиме
	# (debug_menu восстанавливает), но перестраховываемся ещё раз.
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	# Чистим run-state перед стартом дебаг-сцены и снимаем стартовое
	# оружие: игрок должен реально его подобрать, а не бить дефолтным
	# коротким мечом. reset_run поднимает новое tower_seed и обнуляет
	# level/xp/gold — для песочницы это нейтральное состояние.
	GameState.reset_run()
	GameState.equipped_weapon = null
	_hint_label.text = tr("UI_DEBUG_WEAPON_HINT")
	_build_room()
	_spawn_player()
	_spawn_weapon_row()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(DEBUG_MENU_SCENE_PATH)

func _build_room() -> void:
	# Фон-пол — один ColorRect на всю комнату. Стены рисуем поверх
	# отдельными ColorRect'ами + StaticBody2D для коллизии.
	var background := ColorRect.new()
	background.color = BACKGROUND_COLOR
	background.position = Vector2.ZERO
	background.size = Vector2(ROOM_WIDTH, ROOM_HEIGHT)
	_room_root.add_child(background)

	var floor_rect := ColorRect.new()
	floor_rect.color = FLOOR_COLOR
	floor_rect.position = Vector2(WALL_THICKNESS, WALL_THICKNESS)
	floor_rect.size = Vector2(
		ROOM_WIDTH - WALL_THICKNESS * 2,
		ROOM_HEIGHT - WALL_THICKNESS * 2,
	)
	_room_root.add_child(floor_rect)

	# Периметр из 4 стен: сверху и снизу — полная ширина, слева и справа —
	# без углов (уже перекрыты горизонтальными).
	_add_wall(Vector2(0, 0), Vector2(ROOM_WIDTH, WALL_THICKNESS))
	_add_wall(Vector2(0, ROOM_HEIGHT - WALL_THICKNESS), Vector2(ROOM_WIDTH, WALL_THICKNESS))
	_add_wall(Vector2(0, WALL_THICKNESS), Vector2(WALL_THICKNESS, ROOM_HEIGHT - WALL_THICKNESS * 2))
	_add_wall(
		Vector2(ROOM_WIDTH - WALL_THICKNESS, WALL_THICKNESS),
		Vector2(WALL_THICKNESS, ROOM_HEIGHT - WALL_THICKNESS * 2),
	)

func _add_wall(top_left: Vector2, size: Vector2) -> void:
	# StaticBody2D с RectangleShape2D сидит в центре rect'а — так проще
	# считать `position + shape_size/2`. Полигональный визуал (ColorRect)
	# отдельным child'ом позиционируется в top-left координаты.
	var body := StaticBody2D.new()
	body.position = top_left + size * 0.5
	var collision := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = size
	collision.shape = rect_shape
	body.add_child(collision)
	_room_root.add_child(body)

	var visual := ColorRect.new()
	visual.color = WALL_COLOR
	visual.position = top_left
	visual.size = size
	_room_root.add_child(visual)

func _spawn_player() -> void:
	var player: CharacterBody2D = PlayerScene.instantiate()
	player.position = PLAYER_SPAWN_POSITION
	_player_root.add_child(player)
	var camera: Camera2D = player.get_node("Camera2D")
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = ROOM_WIDTH
	camera.limit_bottom = ROOM_HEIGHT

func _spawn_weapon_row() -> void:
	# Равномерная раскладка вдоль верхней стены: делим внутреннюю ширину
	# на n слотов и ставим пикап в центр каждого. Порядок совпадает с
	# WEAPON_ROSTER — читать слева направо, легче искать оружие глазами.
	var inner_left := float(WALL_THICKNESS)
	var inner_width := float(ROOM_WIDTH - WALL_THICKNESS * 2)
	var slot_width := inner_width / float(WEAPON_ROSTER.size())
	for i in WEAPON_ROSTER.size():
		var weapon: WeaponResource = WEAPON_ROSTER[i]
		var pickup: Area2D = WeaponPickupScene.instantiate()
		pickup.weapon = weapon
		pickup.position = Vector2(
			inner_left + slot_width * (float(i) + 0.5),
			float(WEAPONS_ROW_Y),
		)
		_weapons_root.add_child(pickup)
