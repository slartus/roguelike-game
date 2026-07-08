extends Area2D

signal player_entered

const SHIMMER_MIN: float = 0.75
const SHIMMER_MAX: float = 1.15
const SHIMMER_SPEED: float = 4.0        # рад/сек (примерно 2 пульсации/сек)
const DUST_COLOR: Color = Color(0.75, 0.4, 1.0, 1.0)  # фиолетовый
const DUST_AMOUNT: int = 24
const DUST_LIFETIME: float = 1.8

@onready var _visual: Sprite2D = $Visual
var _dust: CPUParticles2D
var _shimmer_time: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_dust = _make_dust()
	add_child(_dust)
	_set_closed()

func open() -> void:
	visible = true
	monitoring = true
	_dust.emitting = true
	set_process(true)

func _set_closed() -> void:
	visible = false
	monitoring = false
	if _dust != null:
		_dust.emitting = false
	set_process(false)

func _process(delta: float) -> void:
	# Мерцание пространства внутри портала — плавная синус-пульсация
	# яркости в фиолетовой палитре.
	_shimmer_time += delta * SHIMMER_SPEED
	var t: float = (sin(_shimmer_time) + 1.0) * 0.5
	var brightness: float = lerpf(SHIMMER_MIN, SHIMMER_MAX, t)
	var r: float = lerpf(0.85, 1.0, t) * brightness
	var g: float = lerpf(0.7, 1.0, t) * brightness
	var b: float = 1.0 * brightness
	_visual.modulate = Color(r, g, b, 1.0)

func _make_dust() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = DUST_AMOUNT
	p.lifetime = DUST_LIFETIME
	p.emitting = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 12.0
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 22.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.color = DUST_COLOR
	# Fade к концу жизни: alpha из 1 → 0 через встроенный ramp
	var ramp := Gradient.new()
	ramp.add_point(0.0, Color(DUST_COLOR.r, DUST_COLOR.g, DUST_COLOR.b, 1.0))
	ramp.add_point(1.0, Color(DUST_COLOR.r, DUST_COLOR.g, DUST_COLOR.b, 0.0))
	p.color_ramp = ramp
	return p

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_entered.emit()
