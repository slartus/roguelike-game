extends CanvasLayer

# Модальная панель выбора upgrade card. Работает во время pause через
# process_mode = ALWAYS. HUD или Main.gd открывает панель при
# GameState.upgrade_choice_requested. Клик по карточке или клавиши 1/2/3
# выбирают карту, применяют её (GameState.add_player_upgrade) и, если
# в очереди есть ещё уровни — показывают следующий offer, иначе
# снимают паузу.

signal upgrade_selected(upgrade_id: String)

@onready var _root: Control = $Root
@onready var _title_label: Label = $Root/Panel/VBox/Title
@onready var _cards_container: HBoxContainer = $Root/Panel/VBox/Cards

var _current_offer: Array = []

func _ready() -> void:
	# UI должен обрабатывать input даже когда SceneTree.paused=true —
	# иначе панель никогда не сможет закрыться (весь tree на паузе).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	# Подписка на GameState — панель сама реагирует на level-up event.
	# Main/HUD не обязаны координировать: если панель есть в scene tree,
	# она откроется автоматически. Проверяем что не подписаны дважды —
	# в тестах GameState (autoload) переживает свежий инстанс панели.
	if not GameState.upgrade_choice_requested.is_connected(_on_upgrade_choice_requested):
		GameState.upgrade_choice_requested.connect(_on_upgrade_choice_requested)

func _exit_tree() -> void:
	# Отписываемся, чтобы предыдущий инстанс не «съедал» signal у следующего
	# в тестах.
	if GameState.upgrade_choice_requested.is_connected(_on_upgrade_choice_requested):
		GameState.upgrade_choice_requested.disconnect(_on_upgrade_choice_requested)

func _on_upgrade_choice_requested(_level: int) -> void:
	# Уровень уже в pending_upgrade_levels. Забираем и генерируем offer.
	_show_next_pending_offer()

func _show_next_pending_offer() -> void:
	if not GameState.has_pending_upgrade_choice():
		_close_and_resume()
		return
	var level: int = GameState.pop_next_pending_upgrade_level()
	var context := {
		"tower_seed": GameState.tower_seed,
		"player_level": level,
		"current_floor_number": GameState.current_floor_number,
		"offer_counter": GameState.upgrade_offer_counter,
		"current_weapon_style": _current_weapon_style(),
	}
	var offer: Array = UpgradeOfferGenerator.generate_offer(
		context, GameState.player_upgrade_stacks
	)
	GameState.upgrade_offer_counter += 1
	if offer.is_empty():
		# Нет eligible cards (например все maxed) — тихо пропускаем, не
		# оставляем игрока в замороженном pause'е.
		_show_next_pending_offer()
		return
	_open_panel(offer)

func _open_panel(offer: Array) -> void:
	_current_offer = offer
	_render_cards(offer)
	_title_label.text = tr("UI_CHOOSE_UPGRADE")
	_root.visible = true
	get_tree().paused = true

func _close_and_resume() -> void:
	_root.visible = false
	_current_offer = []
	# Если больше нет очереди — снимаем паузу.
	if not GameState.has_pending_upgrade_choice():
		get_tree().paused = false

func _render_cards(offer: Array) -> void:
	# Очищаем старые.
	for child in _cards_container.get_children():
		child.queue_free()
	for i in offer.size():
		var upgrade: PlayerUpgradeResource = offer[i]
		var card := _build_card(upgrade, i)
		_cards_container.add_child(card)

func _build_card(upgrade: PlayerUpgradeResource, index: int) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(120, 140)
	card.text = "[%d] %s\n\n%s" % [
		index + 1,
		tr(upgrade.display_name),
		tr(upgrade.description),
	]
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.pressed.connect(_on_card_pressed.bind(upgrade))
	return card

func _on_card_pressed(upgrade: PlayerUpgradeResource) -> void:
	_select(upgrade)

func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		var index: int = -1
		match key:
			KEY_1: index = 0
			KEY_2: index = 1
			KEY_3: index = 2
		if index >= 0 and index < _current_offer.size():
			_select(_current_offer[index])
			get_viewport().set_input_as_handled()

func _select(upgrade: PlayerUpgradeResource) -> void:
	if upgrade == null:
		return
	GameState.add_player_upgrade(upgrade)
	EventLog.log_upgrade_selected(tr(upgrade.display_name))
	upgrade_selected.emit(upgrade.id)
	_current_offer = []
	# Ещё pending уровни? Показываем следующий offer сразу.
	if GameState.has_pending_upgrade_choice():
		_show_next_pending_offer()
	else:
		_close_and_resume()

func _current_weapon_style() -> String:
	if GameState.equipped_weapon == null:
		return ""
	return GameState.equipped_weapon.style
