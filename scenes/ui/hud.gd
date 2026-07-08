extends CanvasLayer

@onready var _health_label: Label = $HealthLabel
@onready var _room_label: Label = $RoomLabel
@onready var _level_label: Label = $LevelLabel
@onready var _xp_label: Label = $XpLabel
@onready var _gold_label: Label = $GoldLabel

func set_health(current: int, maximum: int) -> void:
	_health_label.text = "HP: %d / %d" % [current, maximum]

func set_room(number: int) -> void:
	_room_label.text = "Room %d" % number

func set_level(level: int) -> void:
	_level_label.text = "LVL %d" % level

func set_xp(current: int, needed: int) -> void:
	_xp_label.text = "XP: %d / %d" % [current, needed]

func set_gold(total: int) -> void:
	_gold_label.text = "Gold: %d" % total
