extends Area2D

@export var heal_amount: int = 1

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player") or not body.has_method("heal"):
		return
	if body.health >= body.max_health:
		return
	body.heal(heal_amount)
	EventLog.log_heal(heal_amount)
	queue_free()
