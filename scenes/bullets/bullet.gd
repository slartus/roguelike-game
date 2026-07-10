extends Area2D

@export var speed: float = 220.0
@export var lifetime: float = 1.5
@export var damage: int = 1

var direction: Vector2 = Vector2.RIGHT

@onready var _visual: Sprite2D = $Visual

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_end)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func apply_weapon(weapon: WeaponResource) -> void:
	if weapon == null:
		return
	# Читаем через get_* helper'ы — так пуля одинаково работает и с legacy
	# оружием (Dagger/Pistol), и с новыми v2 ресурсами (short_bow, wand).
	damage = weapon.damage
	speed = weapon.get_projectile_speed()
	lifetime = weapon.get_projectile_lifetime()
	if _visual != null:
		_visual.modulate = weapon.get_projectile_color()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()

func _on_lifetime_end() -> void:
	if is_inside_tree():
		queue_free()
