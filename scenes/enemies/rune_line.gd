extends Area2D

# Rune line hazard от Rune Golem. Прямоугольная стационарная зона на полу,
# проходит три фазы: WARNING (только визуал) → ACTIVE (damage) → LINGERING
# (визуал остаточной опасности, damage не применяется). После LINGERING
# нода сама себя удаляет.
#
# Дизайн-инварианты (см. план 03_rune_golem_second_boss):
# - damage применяется строго один раз за activation на цель (per-lane cap);
# - warning всегда предшествует активации (никаких «damage без телеграфа»);
# - lingering не тикает damage'ем — исключает burst-кейс, когда игрок стоит
#   в пересечении двух lanes и получает урон на каждом physics-frame;
# - inactive rune (warning / lingering) не наносит урона.

const PHASE_WARNING: StringName = &"warning"
const PHASE_ACTIVE: StringName = &"active"
const PHASE_LINGERING: StringName = &"lingering"
const PHASE_DONE: StringName = &"done"

# Длительности фаз (плановые числа из PR 3).
@export var warning_duration: float = 0.8
@export var active_duration: float = 0.35
@export var lingering_duration: float = 1.2
# Damage тик — 1 на цель за весь activation. Boss выставляет перед add_child.
@export var damage: int = 1

# Геометрия lane. Rectangle-shape ориентирован по `direction`; длина по
# `length`, ширина по `width`. Boss рассчитывает позицию центра + direction
# перед add_child, здесь только применение к CollisionShape2D / Visual.
@export var length: float = 200.0
@export var width: float = 40.0
var direction: Vector2 = Vector2.RIGHT
var source_enemy: Node = null

var _phase: StringName = PHASE_WARNING
var _phase_timer: float = 0.0
# Set игроков, уже получивших damage за текущий activation. Ключ —
# get_instance_id(), значение — bool. Инвариант single-hit-per-activation.
var _hit_this_cycle: Dictionary = {}

# Визуальные компоненты — обновляются в зависимости от фазы. Warning
# использует пульсирующее свечение, active — насыщенный fill, lingering —
# тусклый residual.
@onready var _visual: ColorRect = get_node_or_null("Visual") as ColorRect
@onready var _collision: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

const WARNING_COLOR: Color = Color(1.0, 0.55, 0.15, 0.35)
const ACTIVE_COLOR: Color = Color(1.0, 0.85, 0.35, 0.85)
const LINGERING_COLOR: Color = Color(0.9, 0.5, 0.2, 0.25)
const WARNING_PULSE_FREQ: float = PI * 4.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_geometry()
	_apply_phase_visual()
	rotation = direction.angle()

func _process(delta: float) -> void:
	if _phase == PHASE_DONE:
		return
	_phase_timer += delta
	match _phase:
		PHASE_WARNING:
			_apply_warning_pulse()
			if _phase_timer >= warning_duration:
				_enter_active_phase()
		PHASE_ACTIVE:
			if _phase_timer >= active_duration:
				_enter_lingering_phase()
		PHASE_LINGERING:
			if _phase_timer >= lingering_duration:
				_enter_done_phase()

func is_warning() -> bool:
	return _phase == PHASE_WARNING

func is_active() -> bool:
	return _phase == PHASE_ACTIVE

func is_lingering() -> bool:
	return _phase == PHASE_LINGERING

func is_finished() -> bool:
	return _phase == PHASE_DONE

func current_phase() -> StringName:
	return _phase

# Прямой damage-check — используется боссом для validated hit'а в момент
# активации (когда игрок мог быть внутри lane ещё до телеграфа). Не multi-
# hit: повторный вызов на ту же цель за одну activation не проходит.
# Используется в тестах через direct call.
func try_damage_target(target: Node) -> bool:
	if _phase != PHASE_ACTIVE:
		return false
	if target == null or not is_instance_valid(target):
		return false
	var id := target.get_instance_id()
	if _hit_this_cycle.has(id):
		return false
	_hit_this_cycle[id] = true
	if target.has_method("take_damage"):
		var ctx := DamageContext.from_enemy_ability(source_enemy, &"rune_line")
		target.take_damage(damage, ctx)
	return true

# --- Внутреннее -----------------------------------------------------------

func _apply_geometry() -> void:
	if _collision != null:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(length, width)
		_collision.shape = shape
	if _visual != null:
		_visual.offset_left = -length * 0.5
		_visual.offset_right = length * 0.5
		_visual.offset_top = -width * 0.5
		_visual.offset_bottom = width * 0.5

func _enter_active_phase() -> void:
	_phase = PHASE_ACTIVE
	_phase_timer = 0.0
	_apply_phase_visual()
	# Damage сейчас находящимся телам. body_entered будет ловить будущие.
	# Используем overlapping_bodies, но через try_damage_target — dedupe по
	# _hit_this_cycle.
	for body in get_overlapping_bodies():
		if body != null and body.is_in_group("player"):
			try_damage_target(body)

func _enter_lingering_phase() -> void:
	_phase = PHASE_LINGERING
	_phase_timer = 0.0
	_apply_phase_visual()

func _enter_done_phase() -> void:
	_phase = PHASE_DONE
	_phase_timer = 0.0
	if is_inside_tree():
		queue_free()

func _apply_phase_visual() -> void:
	if _visual == null:
		return
	match _phase:
		PHASE_ACTIVE:
			_visual.color = ACTIVE_COLOR
		PHASE_LINGERING:
			_visual.color = LINGERING_COLOR
		_:
			_visual.color = WARNING_COLOR

func _apply_warning_pulse() -> void:
	if _visual == null:
		return
	var progress := clampf(_phase_timer / max(0.001, warning_duration), 0.0, 1.0)
	var pulse := (sin(progress * WARNING_PULSE_FREQ) + 1.0) * 0.5
	var mix := clampf(0.35 + progress * 0.45 + pulse * 0.15, 0.0, 1.0)
	_visual.color = WARNING_COLOR.lerp(ACTIVE_COLOR, mix)

func _on_body_entered(body: Node) -> void:
	# Никаких effects на боссов / врагов — rune lines это hazard для игрока.
	if body == null:
		return
	if body.is_in_group("enemy"):
		return
	if not body.is_in_group("player"):
		return
	# Единственный damage entry-point — try_damage_target. Он проверит phase
	# и dedupe. Ни в warning, ни в lingering damage не проходит.
	try_damage_target(body)
