extends Node2D

const FLOOR_SCENE: PackedScene = preload("res://scenes/dungeon/floor.tscn")
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

const BOSS_FLOOR_INTERVAL: int = 5

@onready var _enemies_root: Node2D = $Enemies
@onready var _pickups_root: Node2D = $Pickups
@onready var _player: CharacterBody2D = $Player
@onready var _hud: CanvasLayer = $HUD

var _floor: Node2D
var _door: Area2D
var _alive_enemies: int = 0

func _ready() -> void:
	randomize()
	_spawn_floor()
	_place_player()
	_configure_camera_limits()
	_player.health_changed.connect(_hud.set_health)
	GameState.xp_changed.connect(_hud.set_xp)
	GameState.leveled_up.connect(_on_leveled_up)
	GameState.gold_changed.connect(_hud.set_gold)
	_hud.set_health(_player.health, _player.max_health)
	_hud.set_floor(GameState.current_floor_number)
	_hud.set_level(GameState.player_level)
	_hud.set_xp(GameState.player_xp, Balance.xp_to_next_level(GameState.player_level))
	_hud.set_gold(GameState.total_gold)
	_door.player_entered.connect(_on_door_entered)
	if _is_boss_floor():
		EventLog.log_boss_floor(GameState.current_floor_number)
	else:
		EventLog.log_floor(GameState.current_floor_number)
	_spawn_enemies()
	_spawn_chests()

func _spawn_floor() -> void:
	_floor = FLOOR_SCENE.instantiate()
	add_child(_floor)
	move_child(_floor, 0)
	_door = _floor.door

func _place_player() -> void:
	_player.global_position = _floor.player_start

func _configure_camera_limits() -> void:
	var camera: Camera2D = _player.get_node("Camera2D")
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(_floor.floor_size.x)
	camera.limit_bottom = int(_floor.floor_size.y)

func _spawn_enemies() -> void:
	if _is_boss_floor():
		_spawn_boss()
		return
	for spawn_pos in _floor.enemy_spawn_positions:
		var scene: PackedScene = ENEMY_SCENES.pick_random()
		var enemy: Node = scene.instantiate()
		enemy.global_position = spawn_pos
		if "pickup_scene" in enemy:
			enemy.pickup_scene = PICKUP_SCENE
		enemy.tree_exited.connect(_on_enemy_removed)
		_enemies_root.add_child(enemy)
		_alive_enemies += 1
	if _alive_enemies == 0:
		_open_door()

func _spawn_chests() -> void:
	for chest_pos in _floor.chest_positions:
		var chest: Node = CHEST_SCENE.instantiate()
		chest.global_position = chest_pos
		_pickups_root.add_child(chest)

func _is_boss_floor() -> bool:
	return GameState.current_floor_number % BOSS_FLOOR_INTERVAL == 0

func _spawn_boss() -> void:
	var boss: Node = BOSS_SCENE.instantiate()
	# В boss-этаже одна большая комната; берём её центр
	boss.global_position = _floor.layout.rooms[0].get_center()
	boss.tree_exited.connect(_on_enemy_removed)
	_enemies_root.add_child(boss)
	_alive_enemies += 1

func _on_enemy_removed() -> void:
	_alive_enemies -= 1
	if _alive_enemies <= 0:
		_open_door()

func _open_door() -> void:
	_door.open()

func _on_door_entered() -> void:
	GameState.next_floor()

func _on_leveled_up(new_level: int, _new_max_health: int) -> void:
	_hud.set_level(new_level)
