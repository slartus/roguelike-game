extends Area2D

@export var heal_amount: int = 1

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("heal"):
		body.heal(heal_amount)
		queue_free()
