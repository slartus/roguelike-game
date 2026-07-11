extends Area2D

# Зелье лечения. Раньше срабатывало мгновенным лечением при контакте
# (и не тратилось при полном HP). Теперь всегда подбирается в
# инвентарь (`GameState.health_potions`) — активация через клавишу
# «1» в слоте инвентаря (см. player.gd::_unhandled_input).

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	GameState.add_health_potion()
	Analytics.record_potion_received()
	EventLog.log_potion_pickup()
	queue_free()
