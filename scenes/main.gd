extends Node2D

const FLOOR_SCENE: PackedScene = preload("res://scenes/dungeon/floor.tscn")
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
var _last_kill_position: Vector2 = Vector2.INF   # позиция смерти последнего убитого врага

func _ready() -> void:
	# Breadcrumbs для диагностики зависаний: если между двумя строками
	# в godot.log есть пропуск — hang произошёл ровно в этом шаге.
	# Работает потому что project.godot: run/flush_stdout_on_print=true.
	print("[main] _ready begin floor=%d" % GameState.current_floor_number)
	randomize()
	_spawn_floor()
	print("[main] floor spawned, exit=", _floor.exit_position if _floor.get("exit_position") != null else "?")
	_place_player()
	_configure_camera_limits()
	_player.health_changed.connect(_hud.set_health)
	GameState.leveled_up.connect(_on_leveled_up)
	GameState.gold_changed.connect(_hud.set_gold)
	_hud.set_health(_player.health, _player.max_health)
	_hud.set_floor(GameState.current_floor_number)
	_hud.set_level(GameState.player_level)
	_hud.set_gold(GameState.total_gold)
	_door.player_entered.connect(_on_door_entered)
	if GameState.current_floor_number == 1:
		EventLog.log_tower_seed(GameState.tower_seed)
	if _is_boss_floor():
		EventLog.log_boss_floor(GameState.current_floor_number)
	else:
		EventLog.log_floor(GameState.current_floor_number)
	_spawn_enemies()
	print("[main] enemies spawned: %d" % _alive_enemies)
	_spawn_chests()
	print("[main] _ready done")

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
	# Детерминированный RNG на основе tower_seed × floor. Одинаковый seed
	# и floor → одинаковый набор spawn'ов (важно для «поделиться башней»).
	# Не используем глобальный randi/randf — они несовместимы с shared RNG
	# из других мест (`randomize()` в _ready сдвигает глобальный state).
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.tower_seed * 100003 + GameState.current_floor_number * 9176 + 1337
	var floor_num := GameState.current_floor_number
	for spawn_pos in _floor.enemy_spawn_positions:
		var defs := MonsterSpawnTable.get_eligible_defs(floor_num, ["generic"])
		var def: Dictionary = MonsterSpawnTable.choose_weighted(defs, rng)
		if def.is_empty():
			continue
		var level := MonsterSpawnTable.roll_monster_level(floor_num, def, 0, rng)
		var elite := MonsterSpawnTable.roll_elite_rank(floor_num, def, 0, rng)
		var enemy: Node = def.scene.instantiate()
		if enemy.has_method("configure_spawn"):
			enemy.configure_spawn(level, elite)
		enemy.global_position = spawn_pos
		if "pickup_scene" in enemy:
			enemy.pickup_scene = PICKUP_SCENE
		enemy.tree_exited.connect(_on_enemy_removed)
		if enemy.has_signal("died_at"):
			enemy.died_at.connect(_on_enemy_died_at)
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
	if boss.has_signal("died_at"):
		boss.died_at.connect(_on_enemy_died_at)
	_enemies_root.add_child(boss)
	_alive_enemies += 1

func _on_enemy_died_at(death_position: Vector2) -> void:
	# Rename `position` -> `death_position` чтобы не шейдовить Node2D.position.
	_last_kill_position = death_position

func _on_enemy_removed() -> void:
	_alive_enemies -= 1
	if _alive_enemies <= 0:
		_open_door()

func _open_door() -> void:
	# Портал открывается в точке смерти последнего убитого врага —
	# игроку явно указывает "куда идти дальше" в момент зачистки.
	# Если ни один враг не умер (пустой этаж) — оставляем позицию,
	# заданную генератором (exit_position).
	if _last_kill_position != Vector2.INF:
		_door.global_position = _last_kill_position
	_door.open()

func _on_door_entered() -> void:
	GameState.next_floor()

func _on_leveled_up(new_level: int, _new_max_health: int) -> void:
	_hud.set_level(new_level)
