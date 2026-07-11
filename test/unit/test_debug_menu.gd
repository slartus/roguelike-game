extends GutTest

# Хаб дебаг-инструментов (открывается по кнопке «Дебаг» с title screen).
# Проверяем структурный контракт: три кнопки (Generate/Character/Back),
# каждая с непустым label, каждая с подключённым сигналом. Path'ы,
# которые кнопки открывают, должны указывать на реально существующие
# сцены — иначе кнопки в игре тихо ничего не сделают.

const DebugMenuScene = preload("res://scenes/ui/debug_menu.tscn")
const DebugMenuScript = preload("res://scenes/ui/debug_menu.gd")

func test_debug_menu_has_generate_character_and_back_buttons() -> void:
	var menu = DebugMenuScene.instantiate()
	add_child_autofree(menu)
	await get_tree().process_frame
	var gen_btn: Button = menu.get_node_or_null("VBox/GenerateButton")
	var char_btn: Button = menu.get_node_or_null("VBox/CharacterButton")
	var back_btn: Button = menu.get_node_or_null("VBox/BackButton")
	assert_not_null(gen_btn, "должна быть кнопка GenerateButton")
	assert_not_null(char_btn, "должна быть кнопка CharacterButton")
	assert_not_null(back_btn, "должна быть кнопка BackButton")
	assert_ne(gen_btn.text, "", "GenerateButton должна иметь label")
	assert_ne(char_btn.text, "", "CharacterButton должна иметь label")
	assert_ne(back_btn.text, "", "BackButton должна иметь label")

func test_debug_menu_buttons_are_wired() -> void:
	var menu = DebugMenuScene.instantiate()
	add_child_autofree(menu)
	await get_tree().process_frame
	for path in ["VBox/GenerateButton", "VBox/CharacterButton", "VBox/BackButton"]:
		var btn: Button = menu.get_node(path)
		var connections := btn.pressed.get_connections()
		assert_gt(connections.size(), 0,
			"%s.pressed должен быть подключён" % path)
	assert_true(menu.has_method("_on_generate_pressed"))
	assert_true(menu.has_method("_on_character_pressed"))
	assert_true(menu.has_method("_on_back_pressed"))

func test_debug_menu_target_scene_paths_exist() -> void:
	# Разошёлся path и фактическое расположение → регрессия.
	assert_true(ResourceLoader.exists(DebugMenuScript.TITLE_SCENE_PATH),
		"TITLE_SCENE_PATH должен существовать: %s" % DebugMenuScript.TITLE_SCENE_PATH)
	assert_true(ResourceLoader.exists(DebugMenuScript.DUNGEON_PREVIEW_SCENE_PATH),
		"DUNGEON_PREVIEW_SCENE_PATH должен существовать: %s"
			% DebugMenuScript.DUNGEON_PREVIEW_SCENE_PATH)
	assert_true(ResourceLoader.exists(DebugMenuScript.WEAPON_TEST_SCENE_PATH),
		"WEAPON_TEST_SCENE_PATH должен существовать: %s"
			% DebugMenuScript.WEAPON_TEST_SCENE_PATH)

func test_debug_menu_restores_viewport_stretch_mode() -> void:
	# dungeon_preview_screen отключает viewport-stretch. Если вернуться
	# через debug_menu — режим должен быть восстановлен, иначе следующие
	# сцены будут мелкими.
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var menu = DebugMenuScene.instantiate()
	add_child_autofree(menu)
	await get_tree().process_frame
	assert_eq(
		get_tree().root.content_scale_mode,
		Window.CONTENT_SCALE_MODE_VIEWPORT,
		"debug_menu._ready() должен восстанавливать VIEWPORT-режим",
	)
