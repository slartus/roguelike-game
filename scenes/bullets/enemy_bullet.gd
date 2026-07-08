extends Area2D

@export var speed: float = 110.0
@export var lifetime: float = 3.0
@export var damage: int = 1

var direction: Vector2 = Vector2.RIGHT

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_end)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy"):
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()

func _on_lifetime_end() -> void:
	if is_inside_tree():
		queue_free()
