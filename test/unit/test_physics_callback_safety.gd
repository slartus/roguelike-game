extends GutTest

# Regression-тесты для freeze fix (commit 9675cc3).
#
# Godot 4 запрещает reload_current_scene и Area2D.monitoring = ...
# синхронно из physics-signal callback. Мы обернули эти операции в
# call_deferred / set_deferred. Если кто-то случайно снимет обёртку,
# игра снова начнёт зависать при заходе в портал / сундук / смерти.
#
# Тесты grep-based: читают файлы и проверяют что call_deferred /
# set_deferred присутствуют в опасных местах, а прямые вызовы —
# отсутствуют.

func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "cannot open %s" % path)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text

# --- GameState.next_floor ------------------------------------------------

func test_game_state_next_floor_uses_call_deferred() -> void:
	var src := _read("res://autoloads/game_state.gd")
	assert_string_contains(src, "call_deferred(\"reload_current_scene\")",
		"GameState.next_floor должен использовать call_deferred для reload")
	assert_false(_has_synchronous_reload_in_next_floor(src),
		"GameState.next_floor не должен вызывать reload_current_scene() напрямую")

func _has_synchronous_reload_in_next_floor(src: String) -> bool:
	# Ищем синхронный вызов reload_current_scene() без предыдущего "call_deferred".
	var lines := src.split("\n")
	var inside_next_floor := false
	for line in lines:
		if line.begins_with("func next_floor"):
			inside_next_floor = true
			continue
		if inside_next_floor and line.begins_with("func "):
			inside_next_floor = false
			continue
		if inside_next_floor and "reload_current_scene()" in line and not "call_deferred" in line:
			return true
	return false

# --- Player._die ---------------------------------------------------------

func test_player_die_uses_call_deferred() -> void:
	# После добавления title screen _die переключает сцену на title,
	# а не перезагружает текущую. Оба варианта смены сцены запрещены
	# синхронно из physics — обёртка call_deferred обязательна.
	var src := _read("res://scenes/player/player.gd")
	assert_string_contains(src, "call_deferred(\"change_scene_to_file\"",
		"Player._die должен использовать call_deferred для смены сцены (вызывается из physics)")

# --- Chest.monitoring ---------------------------------------------------

func test_chest_uses_set_deferred_for_monitoring() -> void:
	var src := _read("res://scenes/pickups/chest.gd")
	assert_string_contains(src, "set_deferred(\"monitoring\"",
		"Chest должен использовать set_deferred для monitoring в signal callback")
	assert_false(_has_direct_monitoring_assign_in_handler(src),
		"Chest._on_body_entered не должен присваивать monitoring = ... напрямую")

func _has_direct_monitoring_assign_in_handler(src: String) -> bool:
	var lines := src.split("\n")
	var inside_handler := false
	for line in lines:
		var stripped: String = line.strip_edges()
		if line.begins_with("func _on_body_entered"):
			inside_handler = true
			continue
		if inside_handler and line.begins_with("func "):
			inside_handler = false
			continue
		if inside_handler and (stripped.begins_with("monitoring =") or stripped.begins_with("monitoring=")):
			return true
	return false
