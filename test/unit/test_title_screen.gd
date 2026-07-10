extends GutTest

# Стартовый экран title_screen.tscn — вход в игру и в визуализатор
# генерации. Также появляется после смерти игрока (см. player.gd::_die).
#
# Здесь тестируем только структурный контракт:
# - сцена грузится и имеет три кнопки Play/Generate/Exit;
# - script имеет соответствующие обработчики;
# - main scene проекта настроен на title screen;
# - GameState.reset_run вызывается при play.

const TitleScene = preload("res://scenes/ui/title_screen.tscn")
const VisualizerScene = preload("res://scenes/dungeon/level_visualizer.tscn")

func test_title_scene_has_play_generate_and_exit_buttons() -> void:
	var screen = TitleScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var play_btn: Button = screen.get_node_or_null("VBox/PlayButton")
	var gen_btn: Button = screen.get_node_or_null("VBox/GenerateButton")
	var exit_btn: Button = screen.get_node_or_null("VBox/ExitButton")
	assert_not_null(play_btn, "должна быть кнопка PlayButton")
	assert_not_null(gen_btn, "должна быть кнопка GenerateButton")
	assert_not_null(exit_btn, "должна быть кнопка ExitButton")
	assert_ne(play_btn.text, "", "кнопка Играть должна иметь label")
	assert_ne(gen_btn.text, "", "кнопка Генерить уровни должна иметь label")
	assert_ne(exit_btn.text, "", "кнопка Выход должна иметь label")

func test_exit_button_signal_wired_to_handler() -> void:
	# Не вызываем _on_exit_pressed напрямую — иначе get_tree().quit()
	# завалит тестовый прогон. Проверяем что сигнал подключён к скрипту.
	var screen = TitleScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var exit_btn: Button = screen.get_node("VBox/ExitButton")
	var connections := exit_btn.pressed.get_connections()
	assert_gt(connections.size(), 0,
		"ExitButton.pressed должен быть подключён (к _on_exit_pressed)")
	assert_true(screen.has_method("_on_exit_pressed"),
		"скрипт должен содержать обработчик _on_exit_pressed")

func test_project_main_scene_is_title_screen() -> void:
	# После добавления title screen точка входа — он, а не сразу main.
	# Иначе игра всё ещё стартует прямо в подземелье.
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	assert_eq(main_scene, "res://scenes/ui/title_screen.tscn",
		"main_scene в project.godot должен указывать на title screen")

func test_play_button_resets_run_state() -> void:
	# Прямой вызов _on_play_pressed эквивалентен клику Play.
	# change_scene_to_file будет выполнен на next frame — GameState
	# должен быть уже обнулён в момент вызова.
	var screen = TitleScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	GameState.current_floor_number = 42
	GameState.player_level = 7
	GameState.player_xp = 999
	GameState.health_potions = 5
	# Не даём реально сменить сцену — только проверяем что reset случился.
	# В GUT нельзя тривиально перехватить get_tree().change_scene_to_file,
	# поэтому дожидаемся process_frame ПОСЛЕ вызова, чтобы next scene
	# успела инициализироваться в отдельном автотесте.
	# Оборачиваем в try: если change scene ломает test tree, ловим.
	screen._on_play_pressed()
	assert_eq(GameState.current_floor_number, 1,
		"reset_run должен обнулить floor")
	assert_eq(GameState.player_level, 1)
	assert_eq(GameState.player_xp, 0)
	assert_eq(GameState.health_potions, 0)

func test_visualizer_scene_loads_and_has_floor_root() -> void:
	# Визуализатор — Node2D с FloorRoot, Camera2D и HUD-лейблами.
	var viz = VisualizerScene.instantiate()
	add_child_autofree(viz)
	await get_tree().process_frame
	assert_not_null(viz.get_node_or_null("FloorRoot"),
		"должен быть FloorRoot для инстанса Floor")
	assert_not_null(viz.get_node_or_null("Camera2D"))
	assert_not_null(viz.get_node_or_null("HUD/SeedLabel"))
	assert_not_null(viz.get_node_or_null("HUD/HintLabel"))
