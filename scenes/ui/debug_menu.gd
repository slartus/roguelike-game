extends Control

# Хаб дебаг-инструментов. Открывается по кнопке «Дебаг» на title screen.
# Отсюда идут:
#  «Генерить уровни» — визуализатор dungeon-генератора (dungeon_preview_screen).
#  «Персонаж» — песочница персонажа с оружием (weapon_test_screen).
#  «Назад» — обратно на title screen.
#
# dungeon_preview_screen отключает viewport-stretch (нужен резкий UI); если
# мы попадаем на debug_menu после него — восстанавливаем VIEWPORT-режим,
# чтобы кнопки не оставались микроскопическими.

const TITLE_SCENE_PATH: String = "res://scenes/ui/title_screen.tscn"
const DUNGEON_PREVIEW_SCENE_PATH: String = "res://scenes/debug/dungeon_preview_screen.tscn"
const WEAPON_TEST_SCENE_PATH: String = "res://scenes/debug/weapon_test_screen.tscn"

func _ready() -> void:
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	$VBox/GenerateButton.pressed.connect(_on_generate_pressed)
	$VBox/CharacterButton.pressed.connect(_on_character_pressed)
	$VBox/BackButton.pressed.connect(_on_back_pressed)
	$VBox/TitleLabel.text = tr("UI_DEBUG_TITLE")
	$VBox/GenerateButton.text = tr("UI_DEBUG_GENERATE")
	$VBox/CharacterButton.text = tr("UI_DEBUG_CHARACTER")
	$VBox/BackButton.text = tr("UI_DEBUG_BACK")
	$VBox/GenerateButton.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()

func _on_generate_pressed() -> void:
	get_tree().change_scene_to_file(DUNGEON_PREVIEW_SCENE_PATH)

func _on_character_pressed() -> void:
	get_tree().change_scene_to_file(WEAPON_TEST_SCENE_PATH)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE_PATH)
