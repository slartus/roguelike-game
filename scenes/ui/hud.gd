extends CanvasLayer

@onready var _health_label: Label = $HealthLabel
@onready var _room_label: Label = $RoomLabel

func set_health(current: int, maximum: int) -> void:
	_health_label.text = "HP: %d / %d" % [current, maximum]

func set_room(number: int) -> void:
	_room_label.text = "Room %d" % number
