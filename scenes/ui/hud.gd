extends CanvasLayer

@onready var _label: Label = $HealthLabel

func set_health(current: int, maximum: int) -> void:
	_label.text = "HP: %d / %d" % [current, maximum]
