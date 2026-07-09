extends GutTest

# Пауза по ESC — контракт:
# - input action "pause" определён;
# - HUD.process_mode = ALWAYS, иначе первый ESC поставил бы паузу
#   и HUD не смог бы обработать второй ESC (был бы deadlock);
# - _toggle_pause переключает get_tree().paused и visibility панели;
# - двойное переключение возвращает исходное состояние.

const HudScene = preload("res://scenes/ui/hud.tscn")

func after_each() -> void:
	# Не оставляем tree в paused между тестами — иначе следующие
	# тесты с await get_tree().process_frame зависнут.
	get_tree().paused = false

func test_pause_input_action_is_defined() -> void:
	assert_true(InputMap.has_action("pause"),
		"должен быть action 'pause' в project.godot")
	var events := InputMap.action_get_events("pause")
	assert_gt(events.size(), 0, "у action должны быть привязки")

func test_hud_has_process_mode_always() -> void:
	var hud = HudScene.instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	assert_eq(hud.process_mode, Node.PROCESS_MODE_ALWAYS,
		"HUD должен работать во время паузы — иначе второй ESC не снимет её")

func test_toggle_pause_pauses_tree_and_shows_panel() -> void:
	var hud = HudScene.instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	var panel: ColorRect = hud.get_node("PausePanel")
	assert_false(panel.visible, "панель паузы стартует скрытой")
	assert_false(get_tree().paused, "tree не на паузе стартово")
	hud._toggle_pause()
	assert_true(get_tree().paused, "первый toggle ставит паузу")
	assert_true(panel.visible, "панель показывается")
	hud._toggle_pause()
	assert_false(get_tree().paused, "второй toggle снимает паузу")
	assert_false(panel.visible, "панель скрывается")
