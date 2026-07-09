extends Sprite2D

# Мерцание канделябра. Спрайт свечи пульсирует по яркости через
# modulate, дочерний Sprite2D-ореол (additive blend, радиальный
# градиент) синхронно меняет scale и alpha. Каждый экземпляр
# получает случайную фазу в _ready, чтобы соседние канделябры не
# мерцали в унисон и уровень выглядел живым.
#
# Стоимость: два sin() на кадр на каждый канделябр. При типичных
# 20–40 канделябрах на этаж — пренебрежимо. Настоящих 2D-огней
# (PointLight2D + CanvasModulate) намеренно нет: они меняют
# тональность всей игры, что здесь не требуется.

const CANDLE_BASE_COLOR: Color = Color(1.0, 0.95, 0.85)
const CANDLE_BRIGHTNESS_AMPLITUDE: float = 0.15
const HALO_BASE_SCALE: Vector2 = Vector2(1.0, 1.0)
const HALO_BASE_ALPHA: float = 0.55
const HALO_SCALE_AMPLITUDE: float = 0.18
const HALO_ALPHA_AMPLITUDE: float = 0.25
const FLICKER_SLOW_SPEED: float = 3.0
const FLICKER_JITTER_SPEED: float = 13.0
const FLICKER_JITTER_WEIGHT: float = 0.35

@onready var _halo: Sprite2D = $Halo
var _phase: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	_phase = randf() * TAU

func _process(delta: float) -> void:
	_time += delta
	var f := _sample_flicker()
	var brightness := 1.0 + CANDLE_BRIGHTNESS_AMPLITUDE * f
	modulate = Color(
		CANDLE_BASE_COLOR.r * brightness,
		CANDLE_BASE_COLOR.g * brightness,
		CANDLE_BASE_COLOR.b * brightness,
		1.0,
	)
	_halo.scale = HALO_BASE_SCALE * (1.0 + HALO_SCALE_AMPLITUDE * f)
	var alpha := clampf(HALO_BASE_ALPHA + HALO_ALPHA_AMPLITUDE * f, 0.0, 1.0)
	_halo.modulate = Color(1.0, 1.0, 1.0, alpha)

func _sample_flicker() -> float:
	# Медленная синусоида + быстрый мелкий джиттер → неровное
	# «живое» мерцание вместо ровного sin. Итог в диапазоне ~[-1, 1].
	var slow := sin(_time * FLICKER_SLOW_SPEED + _phase)
	var jitter := sin(_time * FLICKER_JITTER_SPEED + _phase * 1.7) * FLICKER_JITTER_WEIGHT
	return clampf(slow + jitter, -1.0, 1.0)
