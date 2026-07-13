extends Area2D

var weapon: WeaponResource

@onready var _visual: Sprite2D = $Visual

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if weapon != null and _visual != null:
		if weapon.icon_texture != null:
			_visual.texture = weapon.icon_texture
			# У всех оружий default icon_modulate = WHITE — рендерят свой
			# полноцветный спрайт как есть. Кастомный оттенок применится
			# поверх, если задан в .tres.
			_visual.modulate = weapon.icon_modulate
		else:
			# Fallback без icon_texture: пустой Sprite2D, только modulate.
			# По факту не даёт визуал, но не крешит.
			_visual.modulate = weapon.icon_modulate

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("equip"):
		# source=pickup — оружие лежало в комнате или выпало из сундука.
		# equip() внутри вызовет Analytics.record_weapon_equipped.
		body.equip(weapon, Analytics.WEAPON_SOURCE_PICKUP)
		if weapon != null:
			EventLog.log_weapon_pickup(weapon.display_name)
		queue_free()
