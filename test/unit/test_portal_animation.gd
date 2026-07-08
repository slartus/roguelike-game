extends GutTest

# Портал (door.tscn) при открытии показывает CPUParticles2D-пыль
# и запускает shimmer через _process. При закрытии — эмиссия off,
# process off. Проверяем оба состояния и то, что modulate реально
# меняется между кадрами.

const DoorScene = preload("res://scenes/rooms/door.tscn")

func test_portal_starts_closed_no_dust_no_process() -> void:
	var door = DoorScene.instantiate()
	add_child_autofree(door)
	await get_tree().process_frame
	assert_false(door.visible, "закрытый портал невидим")
	assert_false(door.monitoring, "закрытый портал не мониторит контакт")
	assert_not_null(door._dust, "CPUParticles2D создан в _ready")
	assert_false(door._dust.emitting, "закрытый портал не эмиттит пыль")
	assert_false(door.is_processing(), "_process off у закрытого")

func test_portal_open_enables_dust_and_process() -> void:
	var door = DoorScene.instantiate()
	add_child_autofree(door)
	await get_tree().process_frame
	door.open()
	assert_true(door.visible)
	assert_true(door.monitoring)
	assert_true(door._dust.emitting, "открытый портал эмиттит пыль")
	assert_true(door.is_processing(), "открытый портал крутит shimmer")

func test_shimmer_modulate_changes_over_time() -> void:
	var door = DoorScene.instantiate()
	add_child_autofree(door)
	await get_tree().process_frame
	door.open()
	# Симулируем два кадра с разными delta — modulate должен измениться.
	door._process(0.05)
	var first: Color = door._visual.modulate
	door._process(0.05)
	var second: Color = door._visual.modulate
	assert_true(
		not is_equal_approx(first.r, second.r) or not is_equal_approx(first.g, second.g),
		"modulate между кадрами должен меняться (shimmer работает)")

func test_dust_color_is_purple() -> void:
	# Цвет пыли — фиолетовый (r + b доминируют над g).
	var door = DoorScene.instantiate()
	add_child_autofree(door)
	await get_tree().process_frame
	var c: Color = door._dust.color
	assert_gt(c.b, c.g, "пыль должна быть фиолетовой: blue > green")
	assert_gt(c.r, c.g, "пыль должна быть фиолетовой: red > green")
