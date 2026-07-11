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
		"current_weapon_attack_type": _current_weapon_attack_type(),
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
	_record_offer_analytics(level, offer)

func _record_offer_analytics(level: int, offer: Array) -> void:
	# Собираем payload для upgrade_offer_shown: список offered_ids,
	# позиции, текущие стеки, current weapon state, HP.
	var offered_ids: Array = []
	var offered_positions: Dictionary = {}
	var current_stacks: Dictionary = {}
	for i in offer.size():
		var upgrade: PlayerUpgradeResource = offer[i]
		offered_ids.append(upgrade.id)
		offered_positions[upgrade.id] = i
		current_stacks[upgrade.id] = GameState.get_upgrade_stack(upgrade.id)
	var current_weapon_id := "unknown"
	if GameState.equipped_weapon != null:
		current_weapon_id = GameState.equipped_weapon.resource_path.get_file().get_basename()
	Analytics.record_upgrade_offer_shown({
		"choice_level": level,
		"current_weapon_id": current_weapon_id,
		"current_weapon_style": _current_weapon_style(),
		"current_attack_type": _current_weapon_attack_type(),
		"offered_ids": offered_ids,
		"offered_positions": offered_positions,
		"current_stacks": current_stacks,
		"player_health": GameState.player_health,
		"player_max_health": GameState.player_max_health,
	})

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
	# Analytics до add_player_upgrade — stack_before/after корректно
	# читаются из GameState.
	var stack_before := GameState.get_upgrade_stack(upgrade.id)
	var offer_position := -1
	for i in _current_offer.size():
		if _current_offer[i] == upgrade:
			offer_position = i
			break
	GameState.add_player_upgrade(upgrade)
	Analytics.record_upgrade_selected({
		"selected_id": upgrade.id,
		"offer_position": offer_position,
		"stack_before": stack_before,
		"stack_after": GameState.get_upgrade_stack(upgrade.id),
	})
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

func _current_weapon_attack_type() -> String:
	if GameState.equipped_weapon == null:
		return ""
	return GameState.equipped_weapon.attack_type
