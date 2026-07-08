extends Area2D

signal player_entered

@onready var _visual: Polygon2D = $Visual

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_set_closed()

func open() -> void:
	_visual.color = Color(0.95, 0.85, 0.2, 1)
	visible = true
	monitoring = true

func _set_closed() -> void:
	visible = false
	monitoring = false

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_entered.emit()
