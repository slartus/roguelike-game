extends Area2D

var weapon: WeaponResource

@onready var _visual: Sprite2D = $Visual

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if weapon != null and _visual != null:
		if weapon.icon_texture != null:
			_visual.texture = weapon.icon_texture
			# Реалистичный спрайт уже покрашен — modulate оставляем WHITE,
			# иначе оранжевый bullet_color шотгана «ржавит» металл.
			_visual.modulate = Color.WHITE
		else:
			# Fallback: без иконки — красим placeholder в bullet_color.
			_visual.modulate = weapon.bullet_color

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("equip"):
		body.equip(weapon)
		if weapon != null:
			EventLog.log_weapon_pickup(weapon.display_name)
		queue_free()
