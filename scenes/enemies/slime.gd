extends "res://scenes/enemies/enemy.gd"

# Слайм передвигается прыжками, а не равномерным ходом.
# Цикл REST → JUMP → REST … запускается сразу в _ready и никогда
# не останавливается — фаза меняется по таймеру, независимо от того,
# видит слайм цель или нет (пусть даже в WANDER он рывками смещается).
#
# REST: `speed = 0` → super._physics_process не даёт слайму двигаться.
# JUMP: `speed = _base_speed * JUMP_SPEED_MULTIPLIER` → пока фаза
#       активна, слайм рвётся к цели с сильно повышенной скоростью.
# Visual синхронно «подпрыгивает»: во время JUMP scale раздувается по Y
# и слегка сжимается по X через sin(t*PI) — стандартный squash-and-stretch.

const REST_DURATION: float = 0.55
const JUMP_DURATION: float = 0.35
const JUMP_SPEED_MULTIPLIER: float = 2.4
const BOUNCE_STRETCH_Y: float = 0.35
const BOUNCE_SQUASH_X: float = 0.15

enum JumpPhase { REST, JUMP }

var _jump_phase: int = JumpPhase.REST
var _phase_timer: float = 0.0
var _base_speed: float = 0.0
var _visual: Sprite2D
var _visual_base_scale: Vector2 = Vector2.ONE

func _ready() -> void:
	super._ready()
	_base_speed = speed
	_visual = get_node_or_null("Visual") as Sprite2D
	if _visual != null:
		_visual_base_scale = _visual.scale
	# Стартуем с рандомного момента REST-фазы — группа слаймов не
	# прыгает в унисон, каждый по-своему.
	_phase_timer = randf() * REST_DURATION

func _physics_process(delta: float) -> void:
	_tick_phase(delta)
	_apply_visual_bounce()
	# Меняем speed до вызова super: super._chase_direct умножает
	# direction на speed, поэтому speed=0 полностью «замораживает»
	# слайма в REST, а x2.4 даёт заметный рывок в JUMP.
	if _jump_phase == JumpPhase.REST:
		speed = 0.0
	else:
		speed = _base_speed * JUMP_SPEED_MULTIPLIER
	super._physics_process(delta)
	# Восстанавливаем базу — потребители через `.speed` не увидят
	# временного значения.
	speed = _base_speed

func _tick_phase(delta: float) -> void:
	_phase_timer -= delta
	if _phase_timer > 0.0:
		return
	if _jump_phase == JumpPhase.REST:
		_jump_phase = JumpPhase.JUMP
		_phase_timer = JUMP_DURATION
	else:
		_jump_phase = JumpPhase.REST
		_phase_timer = REST_DURATION

func _apply_visual_bounce() -> void:
	if _visual == null:
		return
	if _jump_phase == JumpPhase.REST:
		_visual.scale = _visual_base_scale
		return
	# t: 0 → 1 → 0 за время JUMP_DURATION, sin(t*PI) даёт плавный пик.
	var t := clampf(1.0 - (_phase_timer / JUMP_DURATION), 0.0, 1.0)
	var bounce := sin(t * PI)
	_visual.scale = Vector2(
		_visual_base_scale.x * (1.0 - BOUNCE_SQUASH_X * bounce),
		_visual_base_scale.y * (1.0 + BOUNCE_STRETCH_Y * bounce),
	)
