extends Node2D

const ROOM_SCENES: Array[PackedScene] = [
	preload("res://scenes/rooms/room.tscn"),
	preload("res://scenes/rooms/room_pillars.tscn"),
	preload("res://scenes/rooms/room_cross.tscn"),
]
const ENEMY_SCENES: Array[PackedScene] = [
	preload("res://scenes/enemies/enemy.tscn"),         # Slime
	preload("res://scenes/enemies/goblin.tscn"),        # Goblin
	preload("res://scenes/enemies/orc.tscn"),           # Orc
	preload("res://scenes/enemies/skeleton.tscn"),      # Skeleton
	preload("res://scenes/enemies/zombie.tscn"),        # Zombie
	preload("res://scenes/enemies/charger.tscn"),       # Spider
	preload("res://scenes/enemies/ranged_enemy.tscn"),  # Skeleton Archer
	preload("res://scenes/enemies/lich.tscn"),          # Lich
]
const BOSS_SCENE: PackedScene = preload("res://scenes/enemies/boss.tscn")
const PICKUP_SCENE: PackedScene = preload("res://scenes/pickups/health_pickup.tscn")
const CHEST_SCENE: PackedScene = preload("res://scenes/pickups/chest.tscn")

const MIN_ENEMIES: int = 3
const MAX_ENEMIES: int = 6
const CHEST_SPAWN_INTERVAL: int = 3
const CHEST_POSITION: Vector2 = Vector2(240, 60)
const BOSS_ROOM_INTERVAL: int = 5
const BOSS_POSITION: Vector2 = Vector2(240, 110)

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
	GameState.xp_changed.connect(_hud.set_xp)
	GameState.leveled_up.connect(_on_leveled_up)
	GameState.gold_changed.connect(_hud.set_gold)
	_hud.set_health(_player.health, _player.max_health)
	_hud.set_room(GameState.current_room_number)
	_hud.set_level(GameState.player_level)
	_hud.set_xp(GameState.player_xp, GameState.XP_PER_LEVEL)
	_hud.set_gold(GameState.total_gold)
	_door.player_entered.connect(_on_door_entered)
	_spawn_enemies()
	_maybe_spawn_chest()

func _on_leveled_up(new_level: int, _new_max_health: int) -> void:
	_hud.set_level(new_level)

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
	if _is_boss_room():
		_spawn_boss()
		return
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

func _is_boss_room() -> bool:
	return GameState.current_room_number % BOSS_ROOM_INTERVAL == 0

func _spawn_boss() -> void:
	var boss: Node = BOSS_SCENE.instantiate()
	boss.global_position = BOSS_POSITION
	boss.tree_exited.connect(_on_enemy_removed)
	_enemies_root.add_child(boss)
	_alive_enemies += 1

func _on_enemy_removed() -> void:
	_alive_enemies -= 1
	if _alive_enemies <= 0:
		_open_door()

func _maybe_spawn_chest() -> void:
	if _is_boss_room():
		return
	if GameState.current_room_number % CHEST_SPAWN_INTERVAL != 0:
		return
	var chest := CHEST_SCENE.instantiate()
	chest.global_position = CHEST_POSITION
	add_child(chest)

func _open_door() -> void:
	_door.open()

func _on_door_entered() -> void:
	GameState.next_room()
