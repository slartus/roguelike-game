extends Area2D

var weapon: WeaponResource

@onready var _visual: Sprite2D = $Visual

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if weapon != null and _visual != null:
		if weapon.icon_texture != null:
			_visual.texture = weapon.icon_texture
			# icon_modulate по default'у WHITE — не искажает уже покрашенный
			# спрайт (Dagger/Pistol/Shotgun имеют полноцветные icon_texture).
			_visual.modulate = weapon.icon_modulate
		else:
			# Fallback: без иконки — красим placeholder в icon_modulate.
			# Раньше падало в bullet_color, но у новых v2 weapons тот
			# дефолтный жёлтый — все выглядели одинаково.
			_visual.modulate = weapon.icon_modulate

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("equip"):
		body.equip(weapon)
		if weapon != null:
			EventLog.log_weapon_pickup(weapon.display_name)
		queue_free()
