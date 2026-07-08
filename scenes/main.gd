extends Node2D

const ROOM_SCENES: Array[PackedScene] = [
	preload("res://scenes/rooms/room.tscn"),
	preload("res://scenes/rooms/room_pillars.tscn"),
	preload("res://scenes/rooms/room_cross.tscn"),
]
const ENEMY_SCENES: Array[PackedScene] = [
	preload("res://scenes/enemies/enemy.tscn"),
	preload("res://scenes/enemies/ranged_enemy.tscn"),
]
const PICKUP_SCENE: PackedScene = preload("res://scenes/pickups/health_pickup.tscn")

const MIN_ENEMIES: int = 3
const MAX_ENEMIES: int = 6

@onready var _enemies_root: Node2D = $Enemies
@onready var _player: CharacterBody2D = $Player
@onready var _hud: CanvasLayer = $HUD

var _room: Node2D
var _door: Area2D
var _alive_enemies: int = 0

func _ready() -> void:
	randomize()
	_spawn_room()
	_place_player()
	_player.health_changed.connect(_hud.set_health)
	_hud.set_health(_player.health, _player.max_health)
	_hud.set_room(GameState.current_room_number)
	_door.player_entered.connect(_on_door_entered)
	_spawn_enemies()

func _spawn_room() -> void:
	var scene: PackedScene = ROOM_SCENES.pick_random()
	_room = scene.instantiate()
	add_child(_room)
	move_child(_room, 0)
	_door = _room.get_node("Door")

func _place_player() -> void:
	var start: Marker2D = _room.get_node("PlayerStart")
	_player.global_position = start.global_position

func _spawn_enemies() -> void:
	var spawn_points: Array = _room.get_node("SpawnPoints").get_children()
	spawn_points.shuffle()
	var target_count := clampi(
		MIN_ENEMIES + GameState.current_room_number - 1,
		MIN_ENEMIES,
		MAX_ENEMIES,
	)
	target_count = mini(target_count, spawn_points.size())
	for i in target_count:
		var point: Node2D = spawn_points[i]
		var scene: PackedScene = ENEMY_SCENES.pick_random()
		var enemy: Node = scene.instantiate()
		enemy.global_position = point.global_position
		if "pickup_scene" in enemy:
			enemy.pickup_scene = PICKUP_SCENE
		enemy.tree_exited.connect(_on_enemy_removed)
		_enemies_root.add_child(enemy)
		_alive_enemies += 1
	if _alive_enemies == 0:
		_open_door()

func _on_enemy_removed() -> void:
	_alive_enemies -= 1
	if _alive_enemies <= 0:
		_open_door()

func _open_door() -> void:
	_door.open()

func _on_door_entered() -> void:
	GameState.next_room()
