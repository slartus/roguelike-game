class_name LoreInteractable
extends StaticBody2D

# Lore-объект (interactive bookshelf, wall map, rune tablet). Игрок
# входит в детектор → показывается prompt (см. HUD.set_interaction_prompt).
# По клавише "interact" (E) — эмиттится сигнал `read`, HUD показывает
# локализованный snippet. Одноразовый: повторное чтение того же lore
# в одном забеге не даёт снова эмиттить `read`.
#
# Physics: StaticBody2D (не Area2D), чтобы игрок не проходил сквозь
# книжный шкаф. Детекция «в диапазоне» — через отдельный child Area2D
# DetectionArea с большим radius'ом.

signal read(lore_key: String)
signal prompt_shown(prompt_key: String)
signal prompt_hidden()

var prop_id: StringName = &""
var lore_prompt_key: String = ""
var lore_text_key: String = ""
var footprint_cells: Vector2i = Vector2i.ONE

var _player_in_range: bool = false
var _already_read: bool = false

@onready var _detection_area: Area2D = $DetectionArea

func configure(
	p_prop_id: StringName,
	p_lore_prompt_key: String,
	p_lore_text_key: String,
	p_footprint_cells: Vector2i,
) -> void:
	prop_id = p_prop_id
	lore_prompt_key = p_lore_prompt_key
	lore_text_key = p_lore_text_key
	footprint_cells = p_footprint_cells

func _ready() -> void:
	add_to_group("lore_interactable")
	if _detection_area != null:
		_detection_area.body_entered.connect(_on_body_entered)
		_detection_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	if not _already_read and not lore_prompt_key.is_empty():
		prompt_shown.emit(lore_prompt_key)

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	# Симметрично с _on_body_entered: prompt_hidden эмиттим только если
	# _on_body_entered показал бы prompt — иначе HUD получит «скрыть
	# то что не показывали».
	if not _already_read and not lore_prompt_key.is_empty():
		prompt_hidden.emit()

func _unhandled_input(event: InputEvent) -> void:
	if _already_read:
		return
	if not _player_in_range:
		return
	if not event.is_action_pressed("interact"):
		return
	if lore_text_key.is_empty():
		return
	_already_read = true
	# Prompt больше не нужен — snippet сам покажется. HUD может остановить
	# отображение prompt'а по read-сигналу.
	prompt_hidden.emit()
	read.emit(lore_text_key)

func has_been_read() -> bool:
	return _already_read

func player_in_range() -> bool:
	return _player_in_range
