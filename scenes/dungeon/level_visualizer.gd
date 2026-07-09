extends Node2D

# Визуализатор dungeon-генератора. Показывает сгенерированный этаж
# без игрока и врагов. Клавиши:
# - Space / Enter — перегенерировать с новым seed (сдвигает tower_seed);
# - ESC — вернуться на title screen.
#
# Camera2D центрируется на floor и держит zoom так, чтобы весь этаж
# помещался в viewport.

const FLOOR_SCENE: PackedScene = preload("res://scenes/dungeon/floor.tscn")
const TITLE_SCENE_PATH: String = "res://scenes/ui/title_screen.tscn"

@onready var _floor_root: Node2D = $FloorRoot
@onready var _camera: Camera2D = $Camera2D
@onready var _seed_label: Label = $HUD/SeedLabel
@onready var _hint_label: Label = $HUD/HintLabel

var _floor: Node

func _ready() -> void:
	_hint_label.text = "Space — новый seed  |  ESC — назад"
	_regenerate()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		# Новый seed и полностью новая раскладка.
		GameState.tower_seed = randi()
		_regenerate()
	elif event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(TITLE_SCENE_PATH)

func _regenerate() -> void:
	# Показываем только первый этаж — для превью-навигатора этого
	# достаточно, все остальные строятся тем же алгоритмом.
	GameState.current_floor_number = 1
	if _floor != null and is_instance_valid(_floor):
		_floor.queue_free()
	_floor = FLOOR_SCENE.instantiate()
	_floor_root.add_child(_floor)
	# После _ready floor.floor_size уже посчитан.
	_fit_camera_to_floor()
	_seed_label.text = "seed: %d" % GameState.tower_seed

func _fit_camera_to_floor() -> void:
	# Zoom подбирается так, чтобы этаж поместился в viewport целиком
	# с небольшим бордюром. Godot 4: чем МЕНЬШЕ Camera2D.zoom, тем
	# БОЛЬШЕ область попадает в кадр — обратная логика по сравнению с 3D.
	var viewport_size := get_viewport_rect().size
	var floor_size: Vector2 = _floor.floor_size
	if floor_size.x <= 0 or floor_size.y <= 0:
		return
	var margin := 1.15
	var zoom_x := viewport_size.x / (floor_size.x * margin)
	var zoom_y := viewport_size.y / (floor_size.y * margin)
	var zoom := minf(zoom_x, zoom_y)
	_camera.zoom = Vector2(zoom, zoom)
	_camera.position = floor_size * 0.5
