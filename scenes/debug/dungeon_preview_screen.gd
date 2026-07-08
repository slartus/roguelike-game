extends Control

# Дебаг-экран генератора башни. Показывает превьюхи всех этажей
# сверху вниз для заданного seed. Позволяет ввести seed вручную,
# сгенерировать случайный, скопировать или сразу начать забег.

const DungeonGeneratorClass = preload("res://scenes/dungeon/dungeon_generator.gd")
const FloorPreviewScene: PackedScene = preload("res://scenes/debug/floor_preview.tscn")

const PREVIEW_FLOOR_COUNT: int = 12    # первые 12 этажей забега
const PRIME: int = 100003              # тот же, что в Floor._pick_seed
const BOSS_FLOOR_INTERVAL: int = 5

@onready var _seed_input: LineEdit = $VBox/Controls/SeedRow/SeedInput
@onready var _preview_root: VBoxContainer = $VBox/Scroll/PreviewList
@onready var _status_label: Label = $VBox/Controls/StatusLabel

func _ready() -> void:
	_seed_input.text = str(GameState.tower_seed)
	_regenerate()

func _regenerate() -> void:
	var seed_value := _current_seed()
	# Убираем старые превью
	for child in _preview_root.get_children():
		child.queue_free()
	var generator := DungeonGeneratorClass.new()
	for floor_num in range(1, PREVIEW_FLOOR_COUNT + 1):
		var floor_seed: int = seed_value * PRIME + floor_num
		var is_boss: bool = floor_num % BOSS_FLOOR_INTERVAL == 0
		var layout: DungeonLayout = generator.generate(floor_seed, floor_num, is_boss)
		var preview: Control = FloorPreviewScene.instantiate()
		_preview_root.add_child(preview)
		preview.set_data(layout, floor_num)
	_status_label.text = "Seed: %d" % seed_value

func _current_seed() -> int:
	var text := _seed_input.text.strip_edges()
	if text.is_empty() or not text.is_valid_int():
		return GameState.tower_seed
	return int(text)

func _on_generate_pressed() -> void:
	_regenerate()

func _on_random_pressed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var new_seed := rng.randi_range(0, 2147483647)
	_seed_input.text = str(new_seed)
	_regenerate()

func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_seed_input.text)
	_status_label.text = "Copied: %s" % _seed_input.text

func _on_play_pressed() -> void:
	# Записать seed в GameState, обнулить забег и перейти в main.
	GameState.reset_run()
	GameState.tower_seed = _current_seed()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
