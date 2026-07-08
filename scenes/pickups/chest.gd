extends Area2D

const WEAPON_POOL: Array[WeaponResource] = [
	preload("res://resources/weapons/dagger.tres"),
	preload("res://resources/weapons/pistol.tres"),
	preload("res://resources/weapons/shotgun.tres"),
]
const PICKUP_SCENE: PackedScene = preload("res://scenes/pickups/weapon_pickup.tscn")

@onready var _visual: Polygon2D = $Visual

var _opened: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _opened:
		return
	if not body.is_in_group("player"):
		return
	_opened = true
	if _visual != null:
		_visual.color = Color(0.35, 0.28, 0.18, 1)
	monitoring = false
	_spawn_pickup()

func _spawn_pickup() -> void:
	var chosen: WeaponResource = WEAPON_POOL.pick_random()
	var pickup := PICKUP_SCENE.instantiate()
	pickup.weapon = chosen
	pickup.global_position = global_position + Vector2(0, 14)
	get_tree().current_scene.add_child.call_deferred(pickup)
