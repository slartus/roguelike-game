extends Area2D

@export var speed: float = 220.0
@export var lifetime: float = 1.5
@export var damage: int = 1
# pierce > 0 → пуля пробивает N дополнительных целей до queue_free.
# Каждая цель уменьшает счётчик; когда pierce_remaining уходит в 0,
# следующее попадание уничтожает пулю как раньше.
@export var pierce: int = 0

var direction: Vector2 = Vector2.RIGHT
var _pierce_remaining: int = 0
var _hit_bodies: Dictionary = {}

@onready var _visual: Sprite2D = $Visual

func _ready() -> void:
	_pierce_remaining = pierce
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_end)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func apply_weapon(weapon: WeaponResource) -> void:
	if weapon == null:
		return
	# Читаем через get_* helper'ы — они остаются стабильным API после удаления
	# legacy fallback fields, чтобы не менять callsite'ы разом со схемой.
	damage = weapon.damage
	speed = weapon.get_projectile_speed()
	lifetime = weapon.get_projectile_lifetime()
	pierce = weapon.pierce
	_pierce_remaining = pierce
	if _visual != null:
		_visual.modulate = weapon.get_projectile_color()

# Новый путь через WeaponStats — учитывает upgrade modifiers.
# WeaponController предпочитает его над apply_weapon, если метод есть.
func apply_weapon_stats(stats: WeaponStats) -> void:
	if stats == null:
		return
	damage = stats.damage
	speed = stats.projectile_speed
	lifetime = stats.projectile_lifetime
	pierce = stats.pierce
	_pierce_remaining = pierce
	if _visual != null:
		_visual.modulate = stats.projectile_color

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		return
	# Один и тот же враг не должен получать урон дважды от одной пирсующей
	# пули — Area2D может слать body_entered повторно если body сдвинулся.
	if _hit_bodies.has(body):
		return
	# Стена (StaticBody2D) и любые не-урон-цели гасят пулю независимо от
	# pierce. Иначе pierce-пуля (арбалет, upgrade) пробивала стену, тратя
	# один заряд, и летела дальше в следующего врага сквозь неё.
	if not body.has_method("take_damage"):
		queue_free()
		return
	body.take_damage(damage)
	_hit_bodies[body] = true
	if _pierce_remaining > 0:
		_pierce_remaining -= 1
		return
	queue_free()

func _on_lifetime_end() -> void:
	if is_inside_tree():
		queue_free()
