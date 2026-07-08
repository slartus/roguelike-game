extends GutTest

# Босс каждый второй залп разворачивает звёздочку на половину угла
# между лучами. Проверяем pure-функцию расчёта углов, без spawn'а
# bullet'ов через current_scene (в GUT current_scene = null).

const BossScene = preload("res://scenes/enemies/boss.tscn")

func test_first_volley_starts_at_zero() -> void:
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	var angles: Array = boss._compute_volley_angles(0)
	assert_eq(angles.size(), boss.volley_count,
		"volley_count лучей")
	assert_almost_eq(angles[0], 0.0, 0.001,
		"первый залп: первый луч под углом 0")

func test_second_volley_is_offset_by_half_step() -> void:
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	var step := TAU / float(boss.volley_count)
	var angles: Array = boss._compute_volley_angles(1)
	assert_almost_eq(angles[0], step * 0.5, 0.001,
		"второй залп сдвинут на step/2")

func test_third_volley_returns_to_zero() -> void:
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	var angles: Array = boss._compute_volley_angles(2)
	assert_almost_eq(angles[0], 0.0, 0.001,
		"третий залп (index=2) снова без offset")

func test_volleys_alternate_over_many_shots() -> void:
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	var step := TAU / float(boss.volley_count)
	for i in 6:
		var angles: Array = boss._compute_volley_angles(i)
		var expected_first := 0.0 if i % 2 == 0 else step * 0.5
		assert_almost_eq(angles[0], expected_first, 0.001,
			"индекс %d: чётные — 0, нечётные — step/2" % i)

func test_volley_covers_full_circle() -> void:
	# Все углы должны быть равномерно распределены по step,
	# сумма индексов через шаг = TAU / volley_count.
	var boss = BossScene.instantiate()
	add_child_autofree(boss)
	var step := TAU / float(boss.volley_count)
	var angles: Array = boss._compute_volley_angles(0)
	for i in range(1, angles.size()):
		var diff: float = angles[i] - angles[i - 1]
		assert_almost_eq(diff, step, 0.001,
			"соседние лучи расстояние = step")
