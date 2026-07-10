extends Control

# Стартовый экран: заголовок + три кнопки.
# «Играть» — обнуляет состояние забега (GameState.reset_run) и грузит
#            основную сцену игры.
# «Генерить уровни» — визуализатор dungeon-генератора; там же можно
#            крутить новый seed по Space.
# «Выход» — закрывает приложение через get_tree().quit(). Единственный
#            «мирный» способ выйти из десктоп-сборки; ESC на title screen
#            не забинден на quit (это делается только явной кнопкой).
#
# Экран также показывается после смерти игрока — см. player.gd::_die.

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const VISUALIZER_SCENE_PATH: String = "res://scenes/dungeon/level_visualizer.tscn"

func _ready() -> void:
	$VBox/PlayButton.pressed.connect(_on_play_pressed)
	$VBox/GenerateButton.pressed.connect(_on_generate_pressed)
	$VBox/ExitButton.pressed.connect(_on_exit_pressed)
	$VBox/PlayButton.grab_focus()

func _on_play_pressed() -> void:
	# Начало нового забега: обнуляем прогресс. reset_run сам поднимет
	# новый tower_seed через RNG.
	GameState.reset_run()
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)

func _on_generate_pressed() -> void:
	get_tree().change_scene_to_file(VISUALIZER_SCENE_PATH)

func _on_exit_pressed() -> void:
	get_tree().quit()
