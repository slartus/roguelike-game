extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal weapon_changed(weapon: WeaponResource)

@export var speed: float = 90.0
@export var bullet_scene: PackedScene

var max_health: int
var health: int
var equipped_weapon: WeaponResource
var _fire_cooldown: float = 0.0

func _ready() -> void:
	add_to_group("player")
	max_health = GameState.player_max_health
	health = clampi(GameState.player_health, 1, max_health)
	equipped_weapon = GameState.equipped_weapon
	GameState.leveled_up.connect(_on_leveled_up)
	health_changed.emit(health, max_health)
	weapon_changed.emit(equipped_weapon)

func _on_leveled_up(_new_level: int, new_max_health: int) -> void:
	max_health = new_max_health
	health = new_max_health
	GameState.player_health = health
	health_changed.emit(health, max_health)

func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * speed
	move_and_slide()

	_fire_cooldown = max(0.0, _fire_cooldown - delta)
	if Input.is_action_pressed("attack") and _fire_cooldown <= 0.0 and equipped_weapon != null:
		_shoot_towards_mouse()
		_fire_cooldown = equipped_weapon.fire_interval

func _shoot_towards_mouse() -> void:
	if bullet_scene == null or equipped_weapon == null:
		return
	var base_direction := (get_global_mouse_position() - global_position).normalized()
	if base_direction == Vector2.ZERO:
		return
	var count := maxi(1, equipped_weapon.bullets_per_shot)
	var spread := deg_to_rad(equipped_weapon.spread_angle_deg)
	for i in count:
		var offset := 0.0
		if count > 1:
			offset = lerp(-spread * 0.5, spread * 0.5, float(i) / float(count - 1))
		elif spread > 0.0:
			offset = randf_range(-spread * 0.5, spread * 0.5)
		var bullet := bullet_scene.instantiate()
		bullet.global_position = global_position
		bullet.direction = base_direction.rotated(offset)
		bullet.apply_weapon(equipped_weapon)
		get_tree().current_scene.add_child(bullet)

func equip(weapon: WeaponResource) -> void:
	if weapon == null:
		return
	equipped_weapon = weapon
	GameState.equipped_weapon = weapon
	weapon_changed.emit(weapon)

func take_damage(amount: int) -> void:
	health = max(0, health - amount)
	GameState.player_health = health
	health_changed.emit(health, max_health)
	modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.1).timeout
	if is_inside_tree():
		modulate = Color.WHITE
	if health == 0:
		_die()

func heal(amount: int) -> void:
	health = min(max_health, health + amount)
	GameState.player_health = health
	health_changed.emit(health, max_health)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory_slot_1"):
		_try_use_health_potion()

func _try_use_health_potion() -> void:
	# Зелье не тратится, если HP уже максимальный — иначе игрок случайно
	# сжигает запас у полного здоровья. Пустой инвентарь тоже тихо no-op.
	if health >= max_health:
		return
	if not GameState.consume_health_potion():
		return
	heal(1)
	EventLog.log_heal(1)

func _die() -> void:
	GameState.reset_run()
	# reload_current_scene из physics callback (Bullet.body_entered или
	# Enemy.move_and_collide → take_damage → _die) запрещён — оборачиваем.
	get_tree().call_deferred("reload_current_scene")
