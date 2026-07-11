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
@onready var _info_empty_label: Label = $HUD/WeaponInfoPanel/EmptyLabel
@onready var _info_stats_box: VBoxContainer = $HUD/WeaponInfoPanel/StatsBox
@onready var _info_name_label: Label = $HUD/WeaponInfoPanel/StatsBox/NameLabel
@onready var _info_damage_label: Label = $HUD/WeaponInfoPanel/StatsBox/DamageLabel
@onready var _info_range_label: Label = $HUD/WeaponInfoPanel/StatsBox/RangeLabel
@onready var _info_angle_label: Label = $HUD/WeaponInfoPanel/StatsBox/AngleLabel
@onready var _info_speed_label: Label = $HUD/WeaponInfoPanel/StatsBox/SpeedLabel
@onready var _preview_visual: Sprite2D = $PlayerPreview/PreviewVisual
@onready var _preview_weapon: Sprite2D = $PlayerPreview/PreviewWeapon

var _player: CharacterBody2D
var _player_visual: Sprite2D
var _player_weapon: Sprite2D

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
	_info_empty_label.text = tr("UI_DEBUG_WEAPON_INFO_EMPTY")
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
	# Подписываемся ДО add_child: Player._ready эмиттит weapon_changed(null),
	# и мы хотим поймать этот initial-сигнал, чтобы панель сразу встала в
	# состояние «оружие не взято» без ручного вызова после add_child.
	player.weapon_changed.connect(_refresh_weapon_info)
	player.position = PLAYER_SPAWN_POSITION
	_player_root.add_child(player)
	var camera: Camera2D = player.get_node("Camera2D")
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = ROOM_WIDTH
	camera.limit_bottom = ROOM_HEIGHT
	_player = player
	_player_visual = player.get_node("Visual")
	_player_weapon = player.get_node("Weapon")

# Каждый кадр обновляем 3× превью игрока слева-снизу: перекидываем
# текстуры/поворот/flip'ы с реального Player.Visual и Player.Weapon.
# Дублировать node'ы через duplicate() было бы дороже (перенос сигналов
# и скриптов); нам нужна только визуальная зеркальная копия.
func _process(_delta: float) -> void:
	# is_instance_valid не только для Player, но и для его child'ов: teardown
	# может освободить Sprite2D'шки раньше самого Player (порядок tree exit),
	# и tree_exited на _player пришёл бы уже после падения на dangling ref.
	if not is_instance_valid(_player) or not is_instance_valid(_player_visual) \
			or not is_instance_valid(_player_weapon):
		return
	_preview_visual.texture = _player_visual.texture
	_preview_visual.flip_h = _player_visual.flip_h
	_preview_visual.modulate = _player_visual.modulate * _player.modulate
	_preview_visual.position = _player_visual.position
	_preview_weapon.visible = _player_weapon.visible
	if not _player_weapon.visible:
		return
	_preview_weapon.texture = _player_weapon.texture
	_preview_weapon.modulate = _player_weapon.modulate
	_preview_weapon.offset = _player_weapon.offset
	_preview_weapon.position = _player_weapon.position
	_preview_weapon.rotation = _player_weapon.rotation
	_preview_weapon.flip_h = _player_weapon.flip_h

# Обновляет панель справа-снизу под текущее оружие игрока. weapon == null →
# скрываем 5 stat-строк, показываем placeholder «оружие не взято». Иначе —
# читаем damage/range/arc/interval прямо с WeaponResource: WeaponStats.compute
# применяет style-модификаторы, но у нас в песочнице нет upgrade cards, так
# что raw поля адекватно отражают то, что реально почувствует игрок при ударе.
# Для «угла» берём arc_degrees у melee_arc/melee_thrust и spread_angle_deg
# у projectile/spell — эти поля семантически заменяют друг друга.
func _refresh_weapon_info(weapon: WeaponResource) -> void:
	if weapon == null:
		_info_empty_label.visible = true
		_info_stats_box.visible = false
		return
	_info_empty_label.visible = false
	_info_stats_box.visible = true
	_info_name_label.text = tr(weapon.display_name)
	_info_damage_label.text = tr("UI_DEBUG_WEAPON_DAMAGE") % weapon.damage
	_info_range_label.text = tr("UI_DEBUG_WEAPON_RANGE") % int(round(weapon.attack_range))
	var angle_deg: float = weapon.arc_degrees if weapon.attack_type in ["melee_arc", "melee_thrust"] else weapon.spread_angle_deg
	_info_angle_label.text = tr("UI_DEBUG_WEAPON_ANGLE") % int(round(angle_deg))
	var interval: float = weapon.get_attack_interval()
	if interval > 0.0:
		_info_speed_label.text = tr("UI_DEBUG_WEAPON_SPEED") % (1.0 / interval)
	else:
		# Guard от нулевого интервала. Все .tres задают положительный
		# get_attack_interval (fallback на legacy fire_interval), но если
		# ресурс сломан — честнее показать «—», чем `Speed: 0.0/s`, будто
		# оружие никогда не бьёт.
		_info_speed_label.text = "—"

func _spawn_weapon_row() -> void:
	for i in WEAPON_ROSTER.size():
		_spawn_pickup_at_slot(i)

# Кладёт пикап в конкретный слот и подписывается на его снятие: при
# каждом body_entered пикап делает queue_free, что дёргает tree_exited
# → мы тут же спавним новый экземпляр того же оружия в той же позиции.
# Так дебаг-песочница остаётся полной: игрок может подбирать одно и то
# же оружие много раз, тестировать смены между несколькими подряд, а
# также визуально видеть, что ряд не редеет.
func _spawn_pickup_at_slot(slot_index: int) -> void:
	var weapon: WeaponResource = WEAPON_ROSTER[slot_index]
	var pickup: Area2D = WeaponPickupScene.instantiate()
	pickup.weapon = weapon
	pickup.position = _slot_position(slot_index)
	pickup.tree_exited.connect(_on_pickup_taken.bind(slot_index))
	_weapons_root.add_child(pickup)

# Равномерная раскладка вдоль верхней стены: делим внутреннюю ширину на
# n слотов и берём центр каждого. Порядок соответствует WEAPON_ROSTER —
# читается слева направо, глаза быстро находят нужное оружие.
func _slot_position(slot_index: int) -> Vector2:
	var inner_left := float(WALL_THICKNESS)
	var inner_width := float(ROOM_WIDTH - WALL_THICKNESS * 2)
	var slot_width := inner_width / float(WEAPON_ROSTER.size())
	return Vector2(
		inner_left + slot_width * (float(slot_index) + 0.5),
		float(WEAPONS_ROW_Y),
	)

func _on_pickup_taken(slot_index: int) -> void:
	# tree_exited эмиттится и при обычном выходе игрока на debug_menu:
	# change_scene_to_file рушит всю сцену — самих себя тоже. В этот
	# момент мы уже вне дерева, спавнить нового ребёнка нет смысла и
	# небезопасно.
	if not is_inside_tree():
		return
	_spawn_pickup_at_slot(slot_index)
