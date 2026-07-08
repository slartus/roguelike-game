extends CharacterBody2D

enum State { WAITING, CHARGING }

@export var max_health: int = 1
@export var charge_speed: float = 220.0
@export var wait_duration: float = 1.2
@export var charge_duration: float = 0.9
@export var contact_damage: int = 1
@export var contact_cooldown: float = 0.4
@export var pickup_scene: PackedScene
@export var pickup_drop_chance: float = 0.35
@export var xp_reward: int = 8
@export var gold_reward: int = 1

var health: int
var _state: int = State.WAITING
var _state_timer: float = 0.0
var _charge_direction: Vector2 = Vector2.ZERO
var _target: Node2D
var _contact_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	health = max_health
	_enter_waiting()

func _physics_process(delta: float) -> void:
	_contact_timer = max(0.0, _contact_timer - delta)
	_state_timer -= delta
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()

	match _state:
		State.WAITING:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0 and _target != null:
				_enter_charging()
		State.CHARGING:
			velocity = _charge_direction * charge_speed
			var collision := move_and_collide(velocity * delta)
			if collision:
				var collider := collision.get_collider()
				if collider and collider.is_in_group("player") and _contact_timer <= 0.0:
					if collider.has_method("take_damage"):
						collider.take_damage(contact_damage)
					_contact_timer = contact_cooldown
			if _state_timer <= 0.0:
				_enter_waiting()

func _enter_waiting() -> void:
	_state = State.WAITING
	_state_timer = wait_duration
	modulate = Color(1, 0.85, 0.55)

func _enter_charging() -> void:
	_state = State.CHARGING
	_state_timer = charge_duration
	_charge_direction = (_target.global_position - global_position).normalized()
	modulate = Color(1, 0.6, 0.2)

func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

func take_damage(amount: int) -> void:
	health -= amount
	var current_state_color := modulate
	modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.08).timeout
	if is_inside_tree():
		modulate = current_state_color
	if health <= 0 and is_inside_tree():
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
