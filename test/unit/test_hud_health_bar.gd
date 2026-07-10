extends GutTest

# HUD.HealthBar — полоса жизни справа вверху. Fill.size.x ресайзится
# пропорционально current/maximum, максимальная ширина
# HEALTH_BAR_FILL_MAX_WIDTH. Тесты проверяют full-hp / low-hp / zero-hp /
# guard от нулевого maximum.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")

func _spawn_hud():
	var hud = HUD_SCENE.instantiate()
	add_child_autofree(hud)
	return hud

func test_full_hp_fills_bar_to_max_width() -> void:
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_health(5, 5)
	assert_almost_eq(hud._health_bar_fill.size.x,
		hud.HEALTH_BAR_FILL_MAX_WIDTH, 0.001,
		"full hp — fill во всю доступную ширину")

func test_half_hp_fills_bar_to_half_width() -> void:
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_health(5, 10)
	assert_almost_eq(hud._health_bar_fill.size.x,
		hud.HEALTH_BAR_FILL_MAX_WIDTH * 0.5, 0.001,
		"5/10 hp — половина ширины")

func test_zero_hp_collapses_fill() -> void:
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_health(0, 5)
	assert_almost_eq(hud._health_bar_fill.size.x, 0.0, 0.001,
		"0 hp — fill ширины 0 (пустая полоса)")

func test_overheal_clamped_to_max_width() -> void:
	# Технически take_damage/heal не должны давать current > maximum,
	# но guard в set_health важен: даже если callsite ошибся, полоса
	# не вылезет за пределы Background.
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_health(999, 5)
	assert_almost_eq(hud._health_bar_fill.size.x,
		hud.HEALTH_BAR_FILL_MAX_WIDTH, 0.001,
		"current > maximum — fill клэмпится к max ширине")

func test_zero_maximum_does_not_crash_and_collapses_fill() -> void:
	# Не должно быть в проде, но guard от деления на ноль обязателен.
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_health(0, 0)
	assert_almost_eq(hud._health_bar_fill.size.x, 0.0, 0.001,
		"maximum == 0 — fill collapse, без крашей")
