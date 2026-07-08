extends CharacterBody2D

@export var display_name: String = "ENEMY_UNKNOWN"
@export var speed: float = 40.0
@export var max_health: int = 3
@export var contact_damage: int = 1
@export var contact_cooldown: float = 0.6
@export var pickup_scene: PackedScene
@export var pickup_drop_chance: float = 0.3
@export var xp_reward: int = 5
@export var gold_reward: int = 1

var health: int
var _target: Node2D
var _contact_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	health = max_health

func _physics_process(delta: float) -> void:
	_contact_timer = max(0.0, _contact_timer - delta)
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()

	if _target == null:
		velocity = Vector2.ZERO
		return

	var direction := (_target.global_position - global_position).normalized()
	velocity = direction * speed
	var collision := move_and_collide(velocity * delta)
	if collision:
		var collider := collision.get_collider()
		if collider and collider.is_in_group("player") and _contact_timer <= 0.0:
			if collider.has_method("take_damage"):
				collider.take_damage(contact_damage)
			_contact_timer = contact_cooldown

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
