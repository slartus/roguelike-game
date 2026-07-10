extends GutTest

# UpgradeChoicePanel (M5):
# - scene загружается;
# - process_mode = ALWAYS (панель обрабатывает input во время pause);
# - при вызове показа с offer'ом рендерятся 3 кнопки-карточки;
# - выбор карты вызывает add_player_upgrade + закрывает панель;
# - если pending уровней больше — показывается следующий offer.

const PanelScene = preload("res://scenes/ui/upgrade_choice_panel.tscn")

var _snapshot: Dictionary

func before_each() -> void:
	_snapshot = {
		"stacks": GameState.player_upgrade_stacks.duplicate(),
		"pending": GameState.pending_upgrade_levels.duplicate(),
		"offer_counter": GameState.upgrade_offer_counter,
		"paused": get_tree().paused,
	}
	GameState.player_upgrade_stacks = {}
	GameState.pending_upgrade_levels = []
	GameState.upgrade_offer_counter = 0

func after_each() -> void:
	get_tree().paused = false
	GameState.player_upgrade_stacks = _snapshot.stacks
	GameState.pending_upgrade_levels = _snapshot.pending
	GameState.upgrade_offer_counter = _snapshot.offer_counter
	get_tree().paused = _snapshot.paused
	PlayerUpgradeLibrary.clear_cache_for_testing()

func _make_upgrade(id: String) -> PlayerUpgradeResource:
	var u := PlayerUpgradeResource.new()
	u.id = id
	u.display_name = "UPGRADE_%s" % id.to_upper()
	u.description = "UPGRADE_%s_DESC" % id.to_upper()
	u.effect_type = "speed_multiplier"
	u.parameters = {"multiplier": 1.1}
	return u

func _instantiate_panel() -> Node:
	var panel: Node = PanelScene.instantiate()
	add_child_autofree(panel)
	return panel

func test_scene_loads() -> void:
	var panel := _instantiate_panel()
	assert_not_null(panel)
	assert_eq(panel.process_mode, Node.PROCESS_MODE_ALWAYS,
		"panel должна работать во время pause")

func test_panel_hidden_by_default() -> void:
	var panel := _instantiate_panel()
	await get_tree().process_frame
	var root: Control = panel.get_node("Root")
	assert_false(root.visible, "стартовая видимость — false")

func test_upgrade_choice_requested_opens_panel_with_cards() -> void:
	PlayerUpgradeLibrary._cache = [
		_make_upgrade("a"),
		_make_upgrade("b"),
		_make_upgrade("c"),
		_make_upgrade("d"),
	]
	var panel := _instantiate_panel()
	await get_tree().process_frame
	GameState.pending_upgrade_levels = [3]
	# Триггерим signal вручную — так же как это сделает _level_up.
	# Вызываем метод напрямую — если в scene tree есть другой инстанс
	# панели (из соседнего теста), signal может достаться ему.
	panel._show_next_pending_offer()
	await get_tree().process_frame
	var root: Control = panel.get_node("Root")
	assert_true(root.visible, "панель показана")
	var cards: Node = panel.get_node("Root/Panel/VBox/Cards")
	assert_eq(cards.get_child_count(), 3,
		"3 карточки отрисованы")
	# cleanup pause
	get_tree().paused = false

func test_selecting_card_applies_upgrade_and_closes_panel() -> void:
	PlayerUpgradeLibrary._cache = [
		_make_upgrade("a"),
		_make_upgrade("b"),
		_make_upgrade("c"),
	]
	var panel := _instantiate_panel()
	await get_tree().process_frame
	GameState.pending_upgrade_levels = [3]
	# Вызываем метод напрямую — если в scene tree есть другой инстанс
	# панели (из соседнего теста), signal может достаться ему.
	panel._show_next_pending_offer()
	await get_tree().process_frame
	# Симулируем клик по первой карте.
	var cards: Node = panel.get_node("Root/Panel/VBox/Cards")
	var first_card: Button = cards.get_child(0)
	first_card.pressed.emit()
	await get_tree().process_frame
	# Проверяем что stack увеличился ровно на одну карту.
	var total_stacks: int = 0
	for stack_val in GameState.player_upgrade_stacks.values():
		total_stacks += int(stack_val)
	assert_eq(total_stacks, 1,
		"ровно одна карта выбрана")
	var root: Control = panel.get_node("Root")
	assert_false(root.visible, "панель закрыта после выбора")

func test_pending_queue_shows_next_offer_after_selection() -> void:
	PlayerUpgradeLibrary._cache = [
		_make_upgrade("a"),
		_make_upgrade("b"),
		_make_upgrade("c"),
	]
	var panel := _instantiate_panel()
	await get_tree().process_frame
	GameState.pending_upgrade_levels = [3, 5]  # два подряд
	# Вызываем метод напрямую — если в scene tree есть другой инстанс
	# панели (из соседнего теста), signal может достаться ему.
	panel._show_next_pending_offer()
	await get_tree().process_frame
	var cards: Node = panel.get_node("Root/Panel/VBox/Cards")
	# Выбираем первую карту.
	var first_card: Button = cards.get_child(0)
	first_card.pressed.emit()
	await get_tree().process_frame
	# Следующий offer должен показаться автоматически.
	var root: Control = panel.get_node("Root")
	assert_true(root.visible,
		"следующий offer из очереди показан автоматически")
	get_tree().paused = false

func test_offer_counter_increments_on_show() -> void:
	PlayerUpgradeLibrary._cache = [_make_upgrade("a"), _make_upgrade("b"), _make_upgrade("c")]
	var panel := _instantiate_panel()
	await get_tree().process_frame
	var counter_before := GameState.upgrade_offer_counter
	GameState.pending_upgrade_levels = [3]
	# Вызываем метод напрямую — если в scene tree есть другой инстанс
	# панели (из соседнего теста), signal может достаться ему.
	panel._show_next_pending_offer()
	await get_tree().process_frame
	assert_eq(GameState.upgrade_offer_counter, counter_before + 1,
		"offer_counter инкрементируется при показе — для detем M4")
	get_tree().paused = false
