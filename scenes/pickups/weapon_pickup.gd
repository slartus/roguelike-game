extends Area2D

var weapon: WeaponResource

@onready var _visual: Polygon2D = $Visual

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if weapon != null and _visual != null:
		_visual.color = weapon.bullet_color

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("equip"):
		body.equip(weapon)
		if weapon != null:
			EventLog.log_weapon_pickup(weapon.display_name)
		queue_free()
