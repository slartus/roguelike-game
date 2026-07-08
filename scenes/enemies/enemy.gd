extends CharacterBody2D

# Общий melee-скрипт (Slime, Goblin, Orc, Skeleton, Zombie).
# State machine: WANDER (не видит игрока — блуждает) → CHASE (видит,
# бежит и наносит контактный урон) → WANDER (потерял из виду).
# Обнаружение — по distance_to_player <= perception_radius. Возврат
# в WANDER — при distance > perception_radius * LOST_RATIO (гистерезис).

enum State { WANDER, CHASE }

const LOST_RATIO: float = 1.6

@export var display_name: String = "ENEMY_UNKNOWN"
@export var speed: float = 40.0
@export var max_health: int = 3
@export var contact_damage: int = 1
@export var contact_cooldown: float = 0.6
@export var pickup_scene: PackedScene
@export var pickup_drop_chance: float = 0.3
@export var xp_reward: int = 5
@export var gold_reward: int = 1
@export var perception_radius: float = 130.0
@export var wander_speed_ratio: float = 0.5
@export var wander_change_interval: float = 2.5

var health: int
var _state: int = State.WANDER
var _target: Node2D
var _contact_timer: float = 0.0
var _wander_direction: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	health = max_health

func _physics_process(delta: float) -> void:
	_contact_timer = maxf(0.0, _contact_timer - delta)
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()
	if _target == null:
		_wander(delta)
		return

	var dist := global_position.distance_to(_target.global_position)
	match _state:
		State.WANDER:
			if dist <= perception_radius:
				_state = State.CHASE
				_chase(delta)
			else:
				_wander(delta)
		State.CHASE:
			if dist > perception_radius * LOST_RATIO:
				_state = State.WANDER
				_pick_wander_direction()
				_wander(delta)
			else:
				_chase(delta)

func _chase(delta: float) -> void:
	var direction := (_target.global_position - global_position).normalized()
	velocity = direction * speed
	var collision := move_and_collide(velocity * delta)
	if collision:
		var collider := collision.get_collider()
		if collider and collider.is_in_group("player") and _contact_timer <= 0.0:
			if collider.has_method("take_damage"):
				collider.take_damage(contact_damage)
			_contact_timer = contact_cooldown

func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0 or _wander_direction == Vector2.ZERO:
		_pick_wander_direction()
	velocity = _wander_direction * speed * wander_speed_ratio
	var collision := move_and_collide(velocity * delta)
	if collision:
		_wander_direction = -_wander_direction.rotated(randf_range(-PI / 3.0, PI / 3.0))

func _pick_wander_direction() -> void:
	var angle := randf() * TAU
	_wander_direction = Vector2.RIGHT.rotated(angle)
	_wander_timer = wander_change_interval

func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

func take_damage(amount: int) -> void:
	health -= amount
	# Урон = игрок близко, «пробуждаем» AI в CHASE даже если был WANDER
	_state = State.CHASE
	modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.08).timeout
	if is_inside_tree():
		modulate = Color.WHITE
	if health <= 0 and is_inside_tree():
		EventLog.log_kill(display_name, xp_reward, gold_reward)
		GameState.award_xp(xp_reward)
		GameState.award_gold(gold_reward)
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
