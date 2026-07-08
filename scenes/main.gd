extends Node2D

@onready var _player: CharacterBody2D = $Player
@onready var _hud: CanvasLayer = $HUD

func _ready() -> void:
	_player.health_changed.connect(_hud.set_health)
	_hud.set_health(_player.health, _player.max_health)
