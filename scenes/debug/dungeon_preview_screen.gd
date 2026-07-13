extends Control

# Дебаг-экран генератора башни. Показывает превьюхи всех этажей
# сверху вниз для заданного seed. Позволяет ввести seed вручную,
# сгенерировать случайный, скопировать или сразу начать забег.

const DungeonGeneratorClass = preload("res://scenes/dungeon/dungeon_generator.gd")
const FloorPreviewScene: PackedScene = preload("res://scenes/debug/floor_preview.tscn")

const PREVIEW_FLOOR_COUNT: int = 12    # первые 12 этажей забега
const PRIME: int = 100003              # тот же, что в Floor._pick_seed

@onready var _seed_input: LineEdit = $VBox/Controls/SeedRow/SeedInput
@onready var _preview_root: VBoxContainer = $VBox/Scroll/PreviewList
@onready var _status_label: Label = $VBox/Controls/StatusLabel

func _ready() -> void:
	# Отключаем project.godot viewport-stretch (480×270 → окно), иначе
	# debug UI ужимается и кнопки уезжают за экран. Возвращаем режим
	# при запуске игры через Play.
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
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
		# Boss detection через BossRegistry — единый источник истины, тот
		# же, что использует Main. Иначе PR 2–5 (боссы на не-mod5 этажах)
		# начнут врать в debug preview.
		var is_boss: bool = BossRegistry.definition_for_floor(floor_num) != null
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
	# Восстанавливаем viewport stretch чтобы main.tscn рисовался в
	# правильном pixel-perfect 480×270.
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	GameState.reset_run()
	GameState.tower_seed = _current_seed()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
