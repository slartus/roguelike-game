extends Control

# ESC на title screen намеренно не забинден на quit — из десктоп-сборки
# выйти можно только явной кнопкой «Выход», чтобы случайное нажатие Esc
# на экране «Итоги забега» не выкидывало игрока из приложения.

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const DEBUG_MENU_SCENE_PATH: String = "res://scenes/ui/debug_menu.tscn"

@onready var _run_stats_panel: PanelContainer = $VBox/RunStatsPanel
@onready var _run_stats_title: Label = $VBox/RunStatsPanel/RunStatsBox/RunStatsTitle
@onready var _run_stats_floor: Label = $VBox/RunStatsPanel/RunStatsBox/RunStatsFloor
@onready var _run_stats_level: Label = $VBox/RunStatsPanel/RunStatsBox/RunStatsLevel
@onready var _run_stats_kills: Label = $VBox/RunStatsPanel/RunStatsBox/RunStatsKills
@onready var _run_stats_gold: Label = $VBox/RunStatsPanel/RunStatsBox/RunStatsGold

func _ready() -> void:
	$VBox/PlayButton.pressed.connect(_on_play_pressed)
	$VBox/DebugButton.pressed.connect(_on_debug_pressed)
	$VBox/ExitButton.pressed.connect(_on_exit_pressed)
	$VBox/DebugButton.text = tr("UI_TITLE_DEBUG")
	$VBox/PlayButton.grab_focus()
	_refresh_run_stats_panel()

func _refresh_run_stats_panel() -> void:
	# Панель показывается только после смерти игрока (finish_run фиксирует
	# has_last_run_stats). При первом запуске игры или после клика «Играть»
	# скрыта.
	_run_stats_panel.visible = GameState.has_last_run_stats
	if not GameState.has_last_run_stats:
		return
	_run_stats_title.text = tr("UI_RUN_STATS_TITLE")
	_run_stats_floor.text = tr("UI_RUN_STATS_FLOOR") % GameState.last_run_floor
	_run_stats_level.text = tr("UI_RUN_STATS_LEVEL") % GameState.last_run_level
	_run_stats_kills.text = tr("UI_RUN_STATS_KILLS") % GameState.last_run_enemies_killed
	_run_stats_gold.text = tr("UI_RUN_STATS_GOLD") % GameState.last_run_gold

func _on_play_pressed() -> void:
	# Начало нового забега: убираем snapshot прошлого run (show-once) и
	# обнуляем прогресс. reset_run сам поднимет новый tower_seed через RNG.
	GameState.clear_last_run_stats()
	GameState.reset_run()
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)

func _on_debug_pressed() -> void:
	get_tree().change_scene_to_file(DEBUG_MENU_SCENE_PATH)

func _on_exit_pressed() -> void:
	get_tree().quit()
