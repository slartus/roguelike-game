extends Area2D

const WEAPON_POOL: Array[WeaponResource] = [
	preload("res://resources/weapons/dagger.tres"),
	preload("res://resources/weapons/pistol.tres"),
	preload("res://resources/weapons/shotgun.tres"),
]
const PICKUP_SCENE: PackedScene = preload("res://scenes/pickups/weapon_pickup.tscn")

@export var closed_texture: Texture2D
@export var open_texture: Texture2D

@onready var _visual: Sprite2D = $Visual

var _opened: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if _visual != null and closed_texture != null:
		_visual.texture = closed_texture

func _on_body_entered(body: Node) -> void:
	if _opened:
		return
	if not body.is_in_group("player"):
		return
	_opened = true
	if _visual != null and open_texture != null:
		_visual.texture = open_texture
	monitoring = false
	EventLog.log_chest_open()
	_spawn_pickup()

func _spawn_pickup() -> void:
	var chosen: WeaponResource = WEAPON_POOL.pick_random()
	var pickup := PICKUP_SCENE.instantiate()
	pickup.weapon = chosen
	pickup.global_position = global_position + Vector2(0, 14)
	get_tree().current_scene.add_child.call_deferred(pickup)
