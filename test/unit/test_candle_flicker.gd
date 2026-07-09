extends GutTest

# Канделябр: Sprite2D свечи + дочерний Sprite2D-ореол (additive blend,
# радиальный градиент). Оба мерцают через _process — modulate свечи
# пульсирует по яркости, ореол синхронно меняет scale и alpha.
# Каждый канделябр получает случайную фазу в _ready — соседние
# канделябры не должны мерцать в унисон.

const CandleScene = preload("res://scenes/dungeon/candle.tscn")

func _make_candle():
	# Возвращаем без типа: `_process` — виртуал, статическая проверка
	# на `Sprite2D` не найдёт его. Так же сделано в door-тесте.
	var candle = CandleScene.instantiate()
	add_child_autofree(candle)
	return candle

func test_candle_has_halo_child_behind_with_additive_blend() -> void:
	var candle = _make_candle()
	await get_tree().process_frame
	var halo: Sprite2D = candle.get_node("Halo")
	assert_not_null(halo, "у канделябра должен быть дочерний Halo")
	assert_true(halo.show_behind_parent,
		"ореол рендерится за спрайтом свечи — свет 'из-за' канделябра")
	var mat: CanvasItemMaterial = halo.material
	assert_not_null(mat, "у ореола должен быть CanvasItemMaterial")
	assert_eq(mat.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD,
		"ореол рендерится с additive blend — читается как свет, не как спрайт")
	assert_not_null(halo.texture, "у ореола должна быть текстура градиента")

func test_flicker_changes_modulate_and_halo_over_time() -> void:
	var candle = _make_candle()
	await get_tree().process_frame
	# Форсируем детерминированную фазу и стартовое время — иначе тест
	# зависит от глобального randf() и флейкает, когда фаза попадает
	# в район экстремума sin (где два соседних кадра дают почти
	# одинаковые значения).
	candle._phase = 0.0
	candle._time = 0.0
	var halo: Sprite2D = candle.get_node("Halo")
	# Delta 0.2 * FLICKER_SLOW_SPEED = 0.6 рад — четверть периода slow-sin.
	# Гарантирует существенное изменение sin между сэмплами.
	candle._process(0.2)
	var mod_a: Color = candle.modulate
	var scale_a: Vector2 = halo.scale
	var alpha_a: float = halo.modulate.a
	candle._process(0.2)
	var mod_b: Color = candle.modulate
	var scale_b: Vector2 = halo.scale
	var alpha_b: float = halo.modulate.a
	assert_true(
		not is_equal_approx(mod_a.r, mod_b.r) or not is_equal_approx(mod_a.g, mod_b.g),
		"modulate свечи должен меняться между кадрами — мерцание работает")
	assert_true(
		not is_equal_approx(scale_a.x, scale_b.x) or not is_equal_approx(alpha_a, alpha_b),
		"scale или alpha ореола должны меняться между кадрами")

func test_candle_keeps_alpha_full_while_brightness_pulses() -> void:
	# Пульсация яркости не должна утаскивать alpha самой свечи —
	# иначе спрайт станет прозрачным в такт мерцанию.
	var candle = _make_candle()
	await get_tree().process_frame
	for i in range(6):
		candle._process(0.033)
		assert_eq(candle.modulate.a, 1.0,
			"alpha modulate свечи должна оставаться 1.0 при любом кадре мерцания")

func test_each_candle_gets_independent_phase() -> void:
	# Контракт: `_ready` присваивает `_phase = randf() * TAU`. Проверяем
	# напрямую что у двух экземпляров фазы разошлись — так уровень не
	# мерцает в унисон. Проверять через `modulate` было бы флейково:
	# при близких фазах два кадра дают почти одинаковые значения.
	var candle_a = _make_candle()
	var candle_b = _make_candle()
	await get_tree().process_frame
	assert_ne(candle_a._phase, candle_b._phase,
		"два канделябра должны получить разные случайные фазы в _ready")
