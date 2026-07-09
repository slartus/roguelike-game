extends CanvasLayer

const LOG_MAX_ENTRIES: int = 6
const LOG_ENTRY_LIFETIME: float = 5.0
const LOG_FADE_DURATION: float = 0.4
const LOG_FONT_SIZE: int = 8

@onready var _health_label: Label = $HealthLabel
@onready var _floor_label: Label = $FloorLabel
@onready var _level_label: Label = $LevelLabel
@onready var _xp_label: Label = $XpLabel
@onready var _gold_label: Label = $GoldLabel
@onready var _potion_slot_label: Label = $InventoryPanel/PotionSlot
@onready var _log_box: VBoxContainer = $CombatLog

func _ready() -> void:
	EventLog.entry_added.connect(_on_log_entry)
	GameState.health_potions_changed.connect(set_potion_count)
	set_potion_count(GameState.health_potions)

func set_potion_count(count: int) -> void:
	_potion_slot_label.text = tr("UI_POTION_SLOT") % count

func set_health(current: int, maximum: int) -> void:
	_health_label.text = tr("UI_HEALTH") % [current, maximum]

func set_floor(number: int) -> void:
	_floor_label.text = tr("UI_FLOOR") % number

func set_level(level: int) -> void:
	_level_label.text = tr("UI_LEVEL") % level

func set_xp(current: int, needed: int) -> void:
	_xp_label.text = tr("UI_XP") % [current, needed]

func set_gold(total: int) -> void:
	_gold_label.text = tr("UI_GOLD") % total

func _on_log_entry(text: String, tint: Color) -> void:
	var entry := Label.new()
	entry.text = text
	entry.add_theme_color_override("font_color", tint)
	entry.add_theme_font_size_override("font_size", LOG_FONT_SIZE)
	entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_box.add_child(entry)
	# queue_free() не уменьшает get_child_count() до конца кадра,
	# поэтому обрезаем через синхронный remove_child — иначе цикл
	# крутится бесконечно на первом же ребёнке (был hard freeze
	# при открытии сундука на 3-м этаже, когда лог накопил >6 строк).
	while _log_box.get_child_count() > LOG_MAX_ENTRIES:
		var oldest := _log_box.get_child(0)
		_log_box.remove_child(oldest)
		oldest.queue_free()
	get_tree().create_timer(LOG_ENTRY_LIFETIME).timeout.connect(_fade_and_remove.bind(entry))

func _fade_and_remove(entry: Label) -> void:
	if not is_instance_valid(entry):
		return
	var tween := create_tween()
	tween.tween_property(entry, "modulate:a", 0.0, LOG_FADE_DURATION)
	tween.tween_callback(entry.queue_free)
