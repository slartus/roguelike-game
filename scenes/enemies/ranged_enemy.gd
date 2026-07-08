extends CharacterBody2D

@export var max_health: int = 2
@export var fire_interval: float = 1.5
@export var bullet_scene: PackedScene
@export var pickup_scene: PackedScene
@export var pickup_drop_chance: float = 0.3

var health: int
var _target: Node2D
var _fire_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	health = max_health
	_fire_timer = randf() * fire_interval

func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()
	if _target == null:
		return
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = fire_interval
		_shoot()

func _shoot() -> void:
	if bullet_scene == null or _target == null:
		return
	var direction := (_target.global_position - global_position).normalized()
	if direction == Vector2.ZERO:
		return
	var bullet := bullet_scene.instantiate()
	bullet.global_position = global_position
	bullet.direction = direction
	get_tree().current_scene.add_child(bullet)

func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

func take_damage(amount: int) -> void:
	health -= amount
	modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.08).timeout
	if is_inside_tree():
		modulate = Color.WHITE
	if health <= 0 and is_inside_tree():
		_drop_pickup()
		queue_free()

func _drop_pickup() -> void:
	if pickup_scene == null:
		return
	if randf() > pickup_drop_chance:
		return
	var pickup := pickup_scene.instantiate()
	pickup.global_position = global_position
	get_tree().current_scene.add_child.call_deferred(pickup)
