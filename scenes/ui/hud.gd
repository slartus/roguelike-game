extends CanvasLayer

const LOG_MAX_ENTRIES: int = 6
const LOG_ENTRY_LIFETIME: float = 5.0
const LOG_FADE_DURATION: float = 0.4
const LOG_FONT_SIZE: int = 8

# Полоса жизни слева вверху растёт вместе с max_health: 1 hp = HEALTH_BAR_PX_PER_HP
# пикселей ширины. Fill — свободные px (current), Background — total = max_health.
# Padding 1 px с каждой стороны внутри Background, поэтому Fill.size.x =
# current * HEALTH_BAR_PX_PER_HP, а HealthBar.size.x = max_health * HEALTH_BAR_PX_PER_HP + 2.
const HEALTH_BAR_PX_PER_HP: float = 12.0
const HEALTH_BAR_PADDING: float = 1.0

@onready var _floor_label: Label = $FloorLabel
@onready var _level_label: Label = $LevelLabel
@onready var _xp_label: Label = $XpLabel
@onready var _gold_label: Label = $GoldLabel
@onready var _potion_icon: TextureRect = $InventoryPanel/PotionSlot/PotionIcon
@onready var _potion_count_label: Label = $InventoryPanel/PotionSlot/PotionCount
@onready var _pause_panel: ColorRect = $PausePanel
@onready var _pause_stats_floor: Label = $PausePanel/PauseBox/PauseStatsFloor
@onready var _pause_stats_level: Label = $PausePanel/PauseBox/PauseStatsLevel
@onready var _pause_stats_kills: Label = $PausePanel/PauseBox/PauseStatsKills
@onready var _pause_stats_gold: Label = $PausePanel/PauseBox/PauseStatsGold
@onready var _pause_stats_seed: Label = $PausePanel/PauseBox/PauseStatsSeed
@onready var _log_box: VBoxContainer = $CombatLog
@onready var _health_bar: Control = $HealthBar
@onready var _health_bar_fill: ColorRect = $HealthBar/Fill

func _ready() -> void:
	EventLog.entry_added.connect(_on_log_entry)
	GameState.health_potions_changed.connect(set_potion_count)
	set_potion_count(GameState.health_potions)
	# HUD.process_mode = ALWAYS (см. tscn), поэтому _unhandled_input
	# работает даже когда весь остальной tree на паузе — иначе повторный
	# ESC не мог бы снять паузу.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()

func _toggle_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_pause_panel.visible = paused
	if paused:
		_refresh_pause_stats()

func _refresh_pause_stats() -> void:
	# Показываем прогресс текущего забега (не last_run_* — они заполняются
	# только при смерти игрока). Ключи tr() shared с title screen'ом:
	# UI_RUN_STATS_* — одна семантика «Итоги забега».
	_pause_stats_floor.text = tr("UI_RUN_STATS_FLOOR") % GameState.current_floor_number
	_pause_stats_level.text = tr("UI_RUN_STATS_LEVEL") % GameState.player_level
	_pause_stats_kills.text = tr("UI_RUN_STATS_KILLS") % GameState.run_enemies_killed
	_pause_stats_gold.text = tr("UI_RUN_STATS_GOLD") % GameState.run_gold
	# Seed башни показываем на паузе — игрок может скопировать/поделиться
	# конкретной башней. Ключ LOG_TOWER_SEED переиспользуется — та же
	# семантика, что и в первом логе на floor 1.
	_pause_stats_seed.text = tr("LOG_TOWER_SEED") % GameState.tower_seed

func set_potion_count(count: int) -> void:
	# Пустой слот — только рамка ячейки, без иконки и числа
	# (пользователь: «если зелий нет — пустой квадратик без количества»).
	# С непустым — показываем иконку зелья и счётчик "×N" в углу.
	var has_potions := count > 0
	_potion_icon.visible = has_potions
	_potion_count_label.visible = has_potions
	if has_potions:
		_potion_count_label.text = "×%d" % count

func set_health(current: int, maximum: int) -> void:
	# Полоса и её fill пересчитываются от текущего max_health, поэтому level up
	# (который расширяет max_health) визуально растит саму полосу, а не только
	# пропорцию заполнения. clampi защищает от отрицательных значений и current > max.
	var safe_max := maxi(maximum, 1)
	var safe_current := clampi(current, 0, safe_max)
	var bar_size := _health_bar.size
	bar_size.x = safe_max * HEALTH_BAR_PX_PER_HP + 2.0 * HEALTH_BAR_PADDING
	_health_bar.size = bar_size
	var fill_size := _health_bar_fill.size
	fill_size.x = safe_current * HEALTH_BAR_PX_PER_HP
	_health_bar_fill.size = fill_size

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
