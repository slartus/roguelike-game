extends GutTest

# LoreInteractable + i18n keys.

const _LORE_SCENE: PackedScene = preload("res://scenes/dungeon/lore_interactable.tscn")

func test_lore_configures_from_definition_fields() -> void:
	var lore: LoreInteractable = _LORE_SCENE.instantiate()
	lore.configure(&"lore_bookshelf", "LORE_PROMPT_READ", "LORE_BOOKSHELF", Vector2i(2, 1))
	add_child_autofree(lore)
	assert_eq(lore.prop_id, &"lore_bookshelf")
	assert_eq(lore.lore_prompt_key, "LORE_PROMPT_READ")
	assert_eq(lore.lore_text_key, "LORE_BOOKSHELF")
	assert_eq(lore.footprint_cells, Vector2i(2, 1))

func test_lore_prompt_emitted_on_player_entry() -> void:
	var lore: LoreInteractable = _LORE_SCENE.instantiate()
	lore.configure(&"lore_bookshelf", "LORE_PROMPT_READ", "LORE_BOOKSHELF", Vector2i.ONE)
	add_child_autofree(lore)
	await get_tree().process_frame
	watch_signals(lore)
	# Симулируем body_entered напрямую — тест не хочет зависеть от
	# physics overlap; сигнал же зовётся Godot'ом при реальном overlap'е.
	var fake_player := Node2D.new()
	fake_player.add_to_group("player")
	add_child_autofree(fake_player)
	lore._on_body_entered(fake_player)
	# assert_signal_emitted_with_parameters(obj, signal, params, index_optional)
	# — не принимает assertion message; проверяем через emit_count + get_signal_parameters.
	assert_signal_emitted(lore, "prompt_shown",
		"при входе игрока эмиттится prompt_shown")
	var params: Array = get_signal_parameters(lore, "prompt_shown")
	assert_eq(params, ["LORE_PROMPT_READ"], "prompt_key должен совпадать")

func test_lore_read_is_one_shot() -> void:
	var lore: LoreInteractable = _LORE_SCENE.instantiate()
	lore.configure(&"lore_bookshelf", "LORE_PROMPT_READ", "LORE_BOOKSHELF", Vector2i.ONE)
	add_child_autofree(lore)
	await get_tree().process_frame
	var fake_player := Node2D.new()
	fake_player.add_to_group("player")
	add_child_autofree(fake_player)
	lore._on_body_entered(fake_player)
	watch_signals(lore)
	# Симулируем "interact" input дважды. Второй раз — уже прочитано,
	# read эмиттиться не должен.
	var evt := InputEventAction.new()
	evt.action = "interact"
	evt.pressed = true
	lore._unhandled_input(evt)
	assert_true(lore.has_been_read(), "после первого interact — read=true")
	lore._unhandled_input(evt)
	assert_signal_emit_count(lore, "read", 1,
		"повторный interact не должен эмиттить read")

func test_lore_prompt_ignored_when_non_player_body_enters() -> void:
	var lore: LoreInteractable = _LORE_SCENE.instantiate()
	lore.configure(&"lore_bookshelf", "LORE_PROMPT_READ", "LORE_BOOKSHELF", Vector2i.ONE)
	add_child_autofree(lore)
	watch_signals(lore)
	# Non-player body — не должно триггерить prompt.
	var non_player := Node2D.new()
	non_player.add_to_group("enemy")
	add_child_autofree(non_player)
	lore._on_body_entered(non_player)
	assert_signal_emit_count(lore, "prompt_shown", 0,
		"prompt только для группы player")

func test_lore_prompt_hidden_on_player_exit() -> void:
	var lore: LoreInteractable = _LORE_SCENE.instantiate()
	lore.configure(&"lore_bookshelf", "LORE_PROMPT_READ", "LORE_BOOKSHELF", Vector2i.ONE)
	add_child_autofree(lore)
	var fake_player := Node2D.new()
	fake_player.add_to_group("player")
	add_child_autofree(fake_player)
	lore._on_body_entered(fake_player)
	watch_signals(lore)
	lore._on_body_exited(fake_player)
	assert_signal_emit_count(lore, "prompt_hidden", 1,
		"при выходе игрока эмиттится prompt_hidden")

func test_interact_outside_range_is_noop() -> void:
	var lore: LoreInteractable = _LORE_SCENE.instantiate()
	lore.configure(&"lore_bookshelf", "LORE_PROMPT_READ", "LORE_BOOKSHELF", Vector2i.ONE)
	add_child_autofree(lore)
	watch_signals(lore)
	# Игрок не входил → _player_in_range=false.
	var evt := InputEventAction.new()
	evt.action = "interact"
	evt.pressed = true
	lore._unhandled_input(evt)
	assert_signal_emit_count(lore, "read", 0,
		"interact вне диапазона не должен эмиттить read")

func test_i18n_keys_exist_for_lore_and_prompts() -> void:
	# tr() возвращает key как есть, если перевода нет. Проверяем что оба
	# keys переведены (i.e. tr(key) != key).
	assert_ne(tr("LORE_PROMPT_READ"), "LORE_PROMPT_READ",
		"LORE_PROMPT_READ должен быть в strings.csv")
	assert_ne(tr("LORE_BOOKSHELF"), "LORE_BOOKSHELF",
		"LORE_BOOKSHELF должен быть в strings.csv")
	assert_ne(tr("LOG_HAZARD_EXPLOSION"), "LOG_HAZARD_EXPLOSION",
		"LOG_HAZARD_EXPLOSION должен быть в strings.csv")
	assert_ne(tr("LOG_PROP_DROP_GOLD_SMALL"), "LOG_PROP_DROP_GOLD_SMALL",
		"LOG_PROP_DROP_GOLD_SMALL должен быть в strings.csv")
	assert_ne(tr("LOG_PROP_DROP_POTION"), "LOG_PROP_DROP_POTION",
		"LOG_PROP_DROP_POTION должен быть в strings.csv")
