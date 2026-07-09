extends GutTest

# Регресс на hard freeze при открытии сундука.
#
# Инцидент: игра зависала на 3-м этаже при открытии сундука. Root cause —
# HUD._on_log_entry обрезал переполненный лог через
#   while _log_box.get_child_count() > LOG_MAX_ENTRIES:
#       _log_box.get_child(0).queue_free()
# `queue_free()` не уменьшает `get_child_count()` до конца кадра, поэтому
# как только в логе оказывалось >LOG_MAX_ENTRIES записей (легко: seed +
# несколько LOG_FLOOR + kills на 3-м этаже + log_chest_open), цикл вечно
# вызывал queue_free на одном и том же ребёнке.
#
# Контракт: после добавления N > LOG_MAX_ENTRIES записей `_on_log_entry`
# синхронно оставляет ровно LOG_MAX_ENTRIES и не зависает.

const HudScene = preload("res://scenes/ui/hud.tscn")

func _make_hud() -> CanvasLayer:
	var hud: CanvasLayer = HudScene.instantiate()
	add_child_autofree(hud)
	return hud

func test_log_trim_completes_and_keeps_exactly_max_entries() -> void:
	var hud := _make_hud()
	var log_box: VBoxContainer = hud.get_node("CombatLog")
	var max_entries: int = hud.LOG_MAX_ENTRIES
	var extras: int = 5

	# Двойная защита от бесконечного цикла: если фикс regressed, тест
	# зависнет в _on_log_entry и GUT покажет timeout, а не бесконечный
	# зелёный/красный вердикт.
	for i in max_entries + extras:
		hud._on_log_entry("entry %d" % i, Color.WHITE)

	assert_eq(log_box.get_child_count(), max_entries,
		"после overflow в логе должно остаться ровно LOG_MAX_ENTRIES записей")

func test_log_trim_removes_oldest_first() -> void:
	# Если бы обрезали новейшие вместо старейших, «entry 0» оставался бы,
	# а «entry 6» уходил — визуально старые сообщения не пропадали бы, и
	# лог перестал быть FIFO.
	var hud := _make_hud()
	var log_box: VBoxContainer = hud.get_node("CombatLog")
	var max_entries: int = hud.LOG_MAX_ENTRIES

	for i in max_entries + 3:
		hud._on_log_entry("entry %d" % i, Color.WHITE)

	var first_remaining: Label = log_box.get_child(0)
	assert_eq(first_remaining.text, "entry 3",
		"после overflow должны уходить старейшие записи, а не новейшие")
