extends GutTest

# HUD.HealthBar — полоса жизни слева вверху, растёт вместе с max_health.
# 1 hp = HEALTH_BAR_PX_PER_HP пикселей ширины. Fill = current px, Background
# (через .size контрола HealthBar) = max_health px + 2*padding.
# Тесты проверяют: базовая ширина, level-up (max_health увеличивается) реально
# растит полосу, current правильно закрашивается, clamp'ы работают.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")

func _spawn_hud():
	var hud = HUD_SCENE.instantiate()
	add_child_autofree(hud)
	return hud

func test_full_hp_fills_bar_completely() -> void:
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_health(5, 5)
	assert_almost_eq(hud._health_bar_fill.size.x,
		5.0 * hud.HEALTH_BAR_PX_PER_HP, 0.001,
		"5/5 hp — fill = 5 * PX_PER_HP")
	assert_almost_eq(hud._health_bar.size.x,
		5.0 * hud.HEALTH_BAR_PX_PER_HP + 2.0 * hud.HEALTH_BAR_PADDING, 0.001,
		"total bar width = max_health * PX_PER_HP + 2 * padding")

func test_half_hp_fills_bar_partially() -> void:
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_health(3, 6)
	assert_almost_eq(hud._health_bar_fill.size.x,
		3.0 * hud.HEALTH_BAR_PX_PER_HP, 0.001,
		"3/6 — fill = 3 * PX_PER_HP")
	assert_almost_eq(hud._health_bar.size.x,
		6.0 * hud.HEALTH_BAR_PX_PER_HP + 2.0 * hud.HEALTH_BAR_PADDING, 0.001,
		"bar width всё равно рассчитан от max=6")

func test_level_up_grows_bar_proportionally() -> void:
	# Пользовательский кейс: level up увеличил max_health с 5 до 10 — полоса
	# должна визуально стать в два раза шире, не остаться прежней.
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_health(5, 5)
	var width_before: float = hud._health_bar.size.x
	hud.set_health(10, 10)
	var width_after: float = hud._health_bar.size.x
	assert_gt(width_after, width_before,
		"после level-up полоса должна вырасти в ширину")
	assert_almost_eq(width_after,
		10.0 * hud.HEALTH_BAR_PX_PER_HP + 2.0 * hud.HEALTH_BAR_PADDING, 0.001,
		"новая ширина = 10 * PX_PER_HP + padding")

func test_zero_hp_collapses_fill() -> void:
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_health(0, 5)
	assert_almost_eq(hud._health_bar_fill.size.x, 0.0, 0.001,
		"0 hp — fill пустой")
	assert_almost_eq(hud._health_bar.size.x,
		5.0 * hud.HEALTH_BAR_PX_PER_HP + 2.0 * hud.HEALTH_BAR_PADDING, 0.001,
		"пустая полоса всё равно имеет background = max_health ширину")

func test_overheal_clamped_to_max() -> void:
	# current > max не должно раздувать fill за пределы Background — clamp.
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_health(999, 5)
	assert_almost_eq(hud._health_bar_fill.size.x,
		5.0 * hud.HEALTH_BAR_PX_PER_HP, 0.001,
		"current > max — fill клэмпится к 5 hp ширине")

func test_zero_maximum_does_not_crash() -> void:
	# Guard от деления/max=0. Полоса минимальная (1 hp width), fill пустой.
	var hud = _spawn_hud()
	await get_tree().process_frame
	hud.set_health(0, 0)
	assert_almost_eq(hud._health_bar_fill.size.x, 0.0, 0.001,
		"maximum=0 — fill пустой, без крашей")
	assert_almost_eq(hud._health_bar.size.x,
		1.0 * hud.HEALTH_BAR_PX_PER_HP + 2.0 * hud.HEALTH_BAR_PADDING, 0.001,
		"maximum=0 — полоса минимальная (guard'нута к 1 hp)")

func test_no_hp_text_label_in_hud() -> void:
	# Пользователь просил убрать текст HP: из хода. HealthLabel не должен
	# существовать; визуальная полоса заменяет текстовое отображение.
	var hud = _spawn_hud()
	await get_tree().process_frame
	assert_null(hud.get_node_or_null("HealthLabel"),
		"HealthLabel должен быть удалён — цифры больше не показываем")
