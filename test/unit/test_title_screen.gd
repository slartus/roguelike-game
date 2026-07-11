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
const DebugMenuScene = preload("res://scenes/ui/debug_menu.tscn")
const VisualizerScene = preload("res://scenes/dungeon/level_visualizer.tscn")

func test_title_scene_has_play_debug_and_exit_buttons() -> void:
	# «Генерить уровни» перенесена на debug_menu — на title остались только
	# три верхнеуровневые кнопки. Отсутствие DebugButton или наличие
	# устаревшего GenerateButton считаем регрессией.
	var screen = TitleScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var play_btn: Button = screen.get_node_or_null("VBox/PlayButton")
	var debug_btn: Button = screen.get_node_or_null("VBox/DebugButton")
	var exit_btn: Button = screen.get_node_or_null("VBox/ExitButton")
	assert_not_null(play_btn, "должна быть кнопка PlayButton")
	assert_not_null(debug_btn, "должна быть кнопка DebugButton")
	assert_not_null(exit_btn, "должна быть кнопка ExitButton")
	assert_null(screen.get_node_or_null("VBox/GenerateButton"),
		"GenerateButton должен уехать на debug_menu, а не остаться на title")
	assert_ne(play_btn.text, "", "кнопка Играть должна иметь label")
	assert_ne(debug_btn.text, "", "кнопка Дебаг должна иметь label")
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
	# change_scene_to_file запланируется на idle, но нас интересует только
	# reset_run(), который отрабатывает синхронно ДО планирования смены —
	# assert'ы ниже читают уже обнулённые поля.
	screen._on_play_pressed()
	assert_eq(GameState.current_floor_number, 1,
		"reset_run должен обнулить floor")
	assert_eq(GameState.player_level, 1)
	assert_eq(GameState.player_xp, 0)
	assert_eq(GameState.health_potions, 0)

func test_debug_button_signal_wired_to_handler() -> void:
	# Прямой вызов _on_debug_pressed сломал бы тест — change_scene_to_file
	# уронит текущее дерево. Проверяем только контракт: сигнал подключён и
	# обработчик существует.
	var screen = TitleScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var debug_btn: Button = screen.get_node("VBox/DebugButton")
	var connections := debug_btn.pressed.get_connections()
	assert_gt(connections.size(), 0,
		"DebugButton.pressed должен быть подключён (к _on_debug_pressed)")
	assert_true(screen.has_method("_on_debug_pressed"),
		"скрипт должен содержать обработчик _on_debug_pressed")

func test_debug_menu_scene_loads_from_title_target_path() -> void:
	# Кнопка «Дебаг» должна указывать на реальный файл debug_menu.tscn.
	# Если path в скрипте разошёлся с фактическим расположением сцены —
	# в игре кнопка тихо ничего не сделает.
	var TitleScript = preload("res://scenes/ui/title_screen.gd")
	assert_true(ResourceLoader.exists(TitleScript.DEBUG_MENU_SCENE_PATH),
		"DEBUG_MENU_SCENE_PATH должен существовать: %s" % TitleScript.DEBUG_MENU_SCENE_PATH)
	var menu = DebugMenuScene.instantiate()
	add_child_autofree(menu)
	await get_tree().process_frame
	assert_not_null(menu.get_node_or_null("VBox"),
		"debug_menu.tscn должен быть готовым к использованию Control'ом")

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
