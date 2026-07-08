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
	damage = weapon.damage
	speed = weapon.bullet_speed
	lifetime = weapon.bullet_lifetime
	if _visual != null:
		_visual.modulate = weapon.bullet_color

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()

func _on_lifetime_end() -> void:
	if is_inside_tree():
		queue_free()
