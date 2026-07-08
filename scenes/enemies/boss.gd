extends CharacterBody2D

signal died_at(position: Vector2)

@export var display_name: String = "ENEMY_UNKNOWN"
@export var max_health: int = 30
@export var speed: float = 25.0
@export var perception_radius: float = 3000.0
@export var contact_damage: int = 3
@export var contact_cooldown: float = 0.8
@export var bullet_scene: PackedScene
@export var volley_interval: float = 2.0
@export var volley_count: int = 8
@export var xp_reward: int = 40
@export var gold_reward: int = 20

var health: int
var _target: Node2D
var _contact_timer: float = 0.0
var _volley_timer: float = 0.0
# Между залпами разворачиваем звёздочку на половину угла между лучами,
# чтобы визуально паттерн вращался и игрок не мог заучить статичные
# коридоры между пулями.
var _volley_index: int = 0

func _ready() -> void:
	add_to_group("enemy")
	var floor_num := GameState.current_floor_number
	max_health = Balance.scaled_hp(max_health, floor_num)
	contact_damage = Balance.scaled_damage(contact_damage, floor_num)
	xp_reward = Balance.scaled_xp_reward(xp_reward, floor_num)
	gold_reward = Balance.scaled_gold_reward(gold_reward, floor_num)
	health = max_health
	_volley_timer = volley_interval

func _physics_process(delta: float) -> void:
	_contact_timer = max(0.0, _contact_timer - delta)
	_volley_timer -= delta
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()
	if _target == null:
		velocity = Vector2.ZERO
		return

	var dir := (_target.global_position - global_position).normalized()
	velocity = dir * speed
	var collision := move_and_collide(velocity * delta)
	if collision:
		var collider := collision.get_collider()
		if collider and collider.is_in_group("player") and _contact_timer <= 0.0:
			if collider.has_method("take_damage"):
				collider.take_damage(contact_damage)
			_contact_timer = contact_cooldown

	if _volley_timer <= 0.0:
		_volley_timer = volley_interval
		_fire_volley()

func _fire_volley() -> void:
	if bullet_scene == null:
		return
	for angle in _compute_volley_angles(_volley_index):
		var bullet := bullet_scene.instantiate()
		bullet.global_position = global_position
		bullet.direction = Vector2.RIGHT.rotated(angle)
		get_tree().current_scene.add_child(bullet)
	_volley_index += 1

# Углы залпа: каждый второй раз сдвиг на step/2, чтобы звёздочка
# вращалась между кадрами. Выделено в pure-функцию ради тестов.
func _compute_volley_angles(index: int) -> Array:
	var step := TAU / float(volley_count)
	var offset := step * 0.5 if index % 2 == 1 else 0.0
	var angles: Array = []
	for i in volley_count:
		angles.append(step * float(i) + offset)
	return angles

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
		died_at.emit(global_position)
		EventLog.log_kill(display_name, xp_reward, gold_reward)
		GameState.award_xp(xp_reward)
		GameState.award_gold(gold_reward)
		queue_free()
