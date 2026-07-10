extends GutTest

# Пауза по ESC — контракт:
# - input action "pause" определён;
# - HUD.process_mode = ALWAYS, иначе первый ESC поставил бы паузу
#   и HUD не смог бы обработать второй ESC (был бы deadlock);
# - _toggle_pause переключает get_tree().paused и visibility панели;
# - двойное переключение возвращает исходное состояние.

const HudScene = preload("res://scenes/ui/hud.tscn")

var _tower_seed_snapshot: int

var _player_xp_snapshot: int

func before_each() -> void:
	_tower_seed_snapshot = GameState.tower_seed
	_player_xp_snapshot = GameState.player_xp

func after_each() -> void:
	# Не оставляем tree в paused между тестами — иначе следующие
	# тесты с await get_tree().process_frame зависнут. GameState —
	# autoload, любые правки полей ниже (для теста pause stats) тоже
	# восстанавливаем, чтобы соседние тесты не наследовали dirty state.
	get_tree().paused = false
	GameState.current_floor_number = 1
	GameState.player_level = 1
	GameState.run_gold = 0
	GameState.run_enemies_killed = 0
	GameState.player_xp = _player_xp_snapshot
	GameState.tower_seed = _tower_seed_snapshot

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

func test_pause_panel_shows_current_run_stats() -> void:
	# При паузе отображаем прогресс ТЕКУЩЕГО забега (current_floor_number,
	# player_level, run_gold, run_enemies_killed), не last_run_* — те
	# заполняются только при смерти.
	GameState.current_floor_number = 5
	GameState.player_level = 3
	GameState.run_gold = 27
	GameState.run_enemies_killed = 11
	var hud = HudScene.instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	hud._toggle_pause()
	var floor_lbl: Label = hud.get_node("PausePanel/PauseBox/PauseStatsFloor")
	var level_lbl: Label = hud.get_node("PausePanel/PauseBox/PauseStatsLevel")
	var kills_lbl: Label = hud.get_node("PausePanel/PauseBox/PauseStatsKills")
	var gold_lbl: Label = hud.get_node("PausePanel/PauseBox/PauseStatsGold")
	assert_true(floor_lbl.text.contains("5"),
		"floor label содержит текущий этаж, actual='%s'" % floor_lbl.text)
	assert_true(level_lbl.text.contains("3"),
		"level label содержит текущий уровень, actual='%s'" % level_lbl.text)
	assert_true(kills_lbl.text.contains("11"),
		"kills label содержит run_enemies_killed, actual='%s'" % kills_lbl.text)
	assert_true(gold_lbl.text.contains("27"),
		"gold label содержит run_gold, actual='%s'" % gold_lbl.text)
	# cleanup — снять паузу перед тестами дальше. GameState restore —
	# в after_each.
	hud._toggle_pause()

func test_pause_panel_shows_xp() -> void:
	# XP убран из основного HUD и показывается только на паузе. Проверяем,
	# что _refresh_pause_stats заполняет PauseStatsXp текущим XP игрока.
	GameState.player_level = 2
	GameState.player_xp = 7
	var hud = HudScene.instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	hud._toggle_pause()
	var xp_lbl: Label = hud.get_node("PausePanel/PauseBox/PauseStatsXp")
	assert_not_null(xp_lbl, "на паузе должен быть PauseStatsXp — XP переехал сюда из HUD")
	assert_true(xp_lbl.text.contains("7"),
		"xp label содержит текущий player_xp, actual='%s'" % xp_lbl.text)
	hud._toggle_pause()

func test_pause_panel_shows_tower_seed() -> void:
	# Игрок должен видеть seed текущей башни, чтобы скопировать/поделиться.
	GameState.tower_seed = 424242
	var hud = HudScene.instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	hud._toggle_pause()
	var seed_lbl: Label = hud.get_node("PausePanel/PauseBox/PauseStatsSeed")
	assert_true(seed_lbl.text.contains("424242"),
		"seed label содержит tower_seed, actual='%s'" % seed_lbl.text)
	hud._toggle_pause()
