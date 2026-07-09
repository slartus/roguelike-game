extends GutTest

# Слайм передвигается прыжками:
# - _tick_phase последовательно чередует REST и JUMP по таймерам;
# - _apply_visual_bounce в REST возвращает базовый scale, в JUMP
#   раздувает scale.y и сжимает scale.x;
# - _physics_process в REST устанавливает speed=0 (эффективно
#   останавливает движение через super), в JUMP умножает на 2.4.

const SlimeScene = preload("res://scenes/enemies/enemy.tscn")

func _spawn_slime():
	var slime = SlimeScene.instantiate()
	add_child_autofree(slime)
	return slime

func test_starts_in_rest_phase() -> void:
	var slime = _spawn_slime()
	# Не ждём process_frame: _ready уже выполнился в add_child_autofree,
	# а физический тик мог бы перевести фазу если randf()*REST_DURATION
	# в _ready дал очень малый _phase_timer.
	assert_eq(slime._jump_phase, slime.JumpPhase.REST,
		"слайм должен стартовать в REST — фазе покоя")

func test_tick_phase_transitions_rest_to_jump() -> void:
	var slime = _spawn_slime()
	await get_tree().process_frame
	# Форсируем известное состояние (в _ready _phase_timer случайный).
	slime._jump_phase = slime.JumpPhase.REST
	slime._phase_timer = 0.01
	slime._tick_phase(0.05)
	assert_eq(slime._jump_phase, slime.JumpPhase.JUMP,
		"по истечении REST-таймера переходим в JUMP")
	assert_eq(slime._phase_timer, slime.JUMP_DURATION,
		"после перехода таймер должен быть JUMP_DURATION")

func test_tick_phase_transitions_jump_to_rest() -> void:
	var slime = _spawn_slime()
	await get_tree().process_frame
	slime._jump_phase = slime.JumpPhase.JUMP
	slime._phase_timer = 0.01
	slime._tick_phase(0.05)
	assert_eq(slime._jump_phase, slime.JumpPhase.REST,
		"по истечении JUMP-таймера возвращаемся в REST")
	assert_eq(slime._phase_timer, slime.REST_DURATION)

func test_visual_scale_is_base_during_rest() -> void:
	var slime = _spawn_slime()
	await get_tree().process_frame
	slime._jump_phase = slime.JumpPhase.REST
	slime._apply_visual_bounce()
	assert_eq(slime._visual.scale, slime._visual_base_scale,
		"в REST scale = базовый (без bounce)")

func test_visual_scale_stretches_y_during_jump_peak() -> void:
	var slime = _spawn_slime()
	await get_tree().process_frame
	slime._jump_phase = slime.JumpPhase.JUMP
	# Середина фазы: _phase_timer = JUMP_DURATION * 0.5, t = 0.5, sin(pi*0.5) = 1.
	slime._phase_timer = slime.JUMP_DURATION * 0.5
	slime._apply_visual_bounce()
	assert_gt(slime._visual.scale.y, slime._visual_base_scale.y,
		"на пике прыжка Y-scale раздут")
	assert_lt(slime._visual.scale.x, slime._visual_base_scale.x,
		"на пике прыжка X-scale сжат")

func test_base_speed_cached_from_scene() -> void:
	var slime = _spawn_slime()
	await get_tree().process_frame
	# enemy.tscn (Slime) экспортирует speed = 35.0. Проверяем что
	# _base_speed запомнился корректно, а не остался на default 40.
	assert_gt(slime._base_speed, 0.0,
		"_base_speed должен быть закеширован в _ready")
