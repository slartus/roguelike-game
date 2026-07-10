extends GutTest

# HUD-реорганизация (пользовательский запрос):
# - уровень персонажа отображается НА полосе HP (по центру, поверх Fill);
# - золото и этаж — в правом-нижнем углу, каждый в HBox с иконкой (монета/башня);
# - XP убран из основного HUD (виден только в pause панели).
#
# Здесь проверяем структуру сцены и то, что set_* методы обновляют
# ровно те лейблы, которые ожидаются игроком.

const HudScene = preload("res://scenes/ui/hud.tscn")
const CoinIcon = preload("res://scenes/ui/coin_icon.gd")
const TowerIcon = preload("res://scenes/ui/tower_icon.gd")

func _spawn_hud():
	var hud = HudScene.instantiate()
	add_child_autofree(hud)
	return hud

func test_level_label_is_child_of_health_bar() -> void:
	# Пользовательский запрос: уровень персонажа — на полоске HP слева.
	# Значит LevelLabel живёт в поддереве HealthBar, а не как top-level HUD-нода.
	var hud = _spawn_hud()
	await get_tree().process_frame
	var lvl: Label = hud.get_node_or_null("HealthBar/LevelLabel")
	assert_not_null(lvl, "LevelLabel должен быть дочерним HealthBar")
	# И его не должно быть на старом top-level пути.
	assert_null(hud.get_node_or_null("LevelLabel"),
		"top-level LevelLabel убран — уровень теперь на полосе HP")
	# font_size 10 — компактнее чем 12 для стат-лейблов, чтобы влезал в
	# узкую полосу HP (60 px при max_health=5).
	assert_eq(lvl.get_theme_font_size("font_size"), 10,
		"LevelLabel на HP-баре должен иметь font_size 10")
	# Тень + outline для читаемости на красном Fill — визуал критичен.
	assert_gt(lvl.get_theme_constant("shadow_outline_size"), 0,
		"LevelLabel должен иметь shadow outline для читаемости на цветном фоне")

func test_set_level_writes_to_health_bar_label() -> void:
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_level(7)
	var lvl: Label = hud.get_node("HealthBar/LevelLabel")
	assert_true(lvl.text.contains("7"),
		"set_level(7) должен обновить текст LevelLabel на HealthBar, actual='%s'" % lvl.text)

func test_gold_row_has_coin_icon_and_label() -> void:
	# Пользовательский запрос: золото справа внизу — монетка и правее цифры.
	var hud = _spawn_hud()
	await get_tree().process_frame
	var row := hud.get_node_or_null("BottomRightStats/GoldRow")
	assert_not_null(row, "должен быть BottomRightStats/GoldRow — контейнер для монетки и золота")
	var icon: Control = hud.get_node_or_null("BottomRightStats/GoldRow/CoinIcon")
	assert_not_null(icon, "CoinIcon отсутствует")
	assert_true(icon.get_script() == CoinIcon,
		"CoinIcon должен использовать скрипт coin_icon.gd")
	var label: Label = hud.get_node_or_null("BottomRightStats/GoldRow/GoldLabel")
	assert_not_null(label, "GoldLabel в GoldRow отсутствует")
	# Иконка идёт перед лейблом в HBox — «монетка и правее цифры».
	assert_lt(icon.get_index(), label.get_index(),
		"CoinIcon должен быть левее GoldLabel в HBox")

func test_floor_row_has_tower_icon_and_label() -> void:
	# Пользовательский запрос: этаж рядом с золотом — иконка башни и число.
	var hud = _spawn_hud()
	await get_tree().process_frame
	var row := hud.get_node_or_null("BottomRightStats/FloorRow")
	assert_not_null(row, "должен быть BottomRightStats/FloorRow — контейнер для башни и этажа")
	var icon: Control = hud.get_node_or_null("BottomRightStats/FloorRow/TowerIcon")
	assert_not_null(icon, "TowerIcon отсутствует")
	assert_true(icon.get_script() == TowerIcon,
		"TowerIcon должен использовать скрипт tower_icon.gd")
	var label: Label = hud.get_node_or_null("BottomRightStats/FloorRow/FloorLabel")
	assert_not_null(label, "FloorLabel в FloorRow отсутствует")
	assert_lt(icon.get_index(), label.get_index(),
		"TowerIcon должен быть левее FloorLabel в HBox")

func test_set_gold_writes_only_number() -> void:
	# Иконка монеты уже даёт контекст → лейбл содержит только число, без «Gold: ».
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_gold(42)
	var label: Label = hud.get_node("BottomRightStats/GoldRow/GoldLabel")
	assert_eq(label.text, "42",
		"GoldLabel должен содержать только число, actual='%s'" % label.text)

func test_set_floor_writes_only_number() -> void:
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_floor(3)
	var label: Label = hud.get_node("BottomRightStats/FloorRow/FloorLabel")
	assert_eq(label.text, "3",
		"FloorLabel должен содержать только число, actual='%s'" % label.text)

func test_top_left_stat_labels_removed() -> void:
	# Пользовательский запрос убрать XP из HUD, а Floor/Level/Gold переместить.
	# Значит старые top-level лейблы FloorLabel/LevelLabel/XpLabel/GoldLabel
	# больше не существуют в HUD.
	var hud = _spawn_hud()
	await get_tree().process_frame
	assert_null(hud.get_node_or_null("FloorLabel"),
		"top-level FloorLabel убран — этаж переехал в BottomRightStats")
	assert_null(hud.get_node_or_null("XpLabel"),
		"XpLabel убран — XP теперь виден только в pause панели")
	assert_null(hud.get_node_or_null("GoldLabel"),
		"top-level GoldLabel убран — золото переехало в BottomRightStats")

func test_hud_has_no_public_set_xp_method() -> void:
	# XP не пробрасывается в основной HUD — set_xp удалён,
	# main.gd больше не должен коннектить xp_changed на HUD.
	var hud = _spawn_hud()
	await get_tree().process_frame
	assert_false(hud.has_method("set_xp"),
		"hud.set_xp удалён — XP отображается только в pause панели")
