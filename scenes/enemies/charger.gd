extends CharacterBody2D

# Charger (Spider): триггерится только когда видит игрока.
# WATCH — стоит, ждёт пока игрок войдёт в perception_radius.
# WAITING — короткая пауза перед рывком (модальный оранжевый).
# CHARGING — рывок в фиксированном направлении к последней виденной
# позиции игрока со скоростью charge_speed на charge_duration секунд.

signal died_at(position: Vector2)

# Паутина стреляется в момент входа в WAITING — до рывка. Летит в
# позицию игрока, зафиксированную на момент выстрела (не хоминг), и
# лежит на месте LANDED_LIFETIME секунд, замедляя игрока в области.
const WEB_SCENE: PackedScene = preload("res://scenes/enemies/spider_web.tscn")

enum State { WATCH, WAITING, CHARGING }

@export var display_name: String = "ENEMY_UNKNOWN"
@export var max_health: int = 1
# monster_level <= 0 → fallback на GameState.current_floor_number.
# Spawn-система задаёт monster_level > 0 через configure_spawn() ДО add_child(),
# чтобы _ready увидел уже финальный уровень и корректно применил Balance.scaled_*.
@export var monster_level: int = 0
# elite_rank прибавляется к effective monster level: champion +1, elite +2.
@export var elite_rank: int = 0
@export var charge_speed: float = 220.0
@export var wait_duration: float = 1.2
@export var charge_duration: float = 0.9
@export var contact_damage: int = 2
@export var contact_cooldown: float = 0.4
@export var pickup_scene: PackedScene
@export var pickup_drop_chance: float = 0.18
@export var xp_reward: int = 8
@export var gold_reward: int = 1
@export var perception_radius: float = 130.0
# В WATCH паук неспешно бродит `move_and_slide` — плавно, без прыжков
# (в отличие от слайма). Скорость сильно ниже charge_speed: WATCH
# читается как «прогуливается», а рывок в CHARGING — как реальная
# атака. Направление меняется по таймеру или при упоре в стену.
@export var wander_speed: float = 25.0
@export var wander_change_interval: float = 2.5
# Темпераменты: ID семейства и явный override (пусто = catalog rolls).
@export var creature_type_id: StringName = &""
@export var temperament_id: StringName = &""

# Множители темпераментов для charger-семейства (spider). Собраны
# в const'ы — правки чисел одной точкой.
const TEMPERAMENT_AGGRESSIVE_WAIT_MULT: float = 0.80
const TEMPERAMENT_AGGRESSIVE_CHARGE_SPEED_MULT: float = 1.10
const TEMPERAMENT_RESTLESS_WANDER_SPEED_MULT: float = 1.35
const TEMPERAMENT_RESTLESS_WANDER_INTERVAL_MULT: float = 0.60
const TEMPERAMENT_WATCHFUL_PERCEPTION_MULT: float = 1.30
const TEMPERAMENT_WATCHFUL_WANDER_SPEED_MULT: float = 0.80

var health: int
var temperament_seed: int = 0
var _has_explicit_seed: bool = false
var _temperament_applied: bool = false
var _state: int = State.WATCH
var _state_timer: float = 0.0
var _charge_direction: Vector2 = Vector2.ZERO
var _target: Node2D
var _contact_timer: float = 0.0
var _wander_direction: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	_apply_temperament()
	var level := get_effective_monster_level()
	max_health = Balance.scaled_hp(max_health, level)
	contact_damage = Balance.scaled_damage(contact_damage, level)
	xp_reward = Balance.scaled_xp_reward(xp_reward, level)
	gold_reward = Balance.scaled_gold_reward(gold_reward, level)
	health = max_health
	modulate = Color(1, 0.85, 0.55)

func get_effective_monster_level() -> int:
	return MonsterLevelUtil.effective_level(monster_level, elite_rank)

func configure_spawn(level: int, elite: int = 0, creature_seed: int = 0) -> void:
	monster_level = maxi(1, level)
	elite_rank = maxi(0, elite)
	temperament_seed = creature_seed
	_has_explicit_seed = true

func _apply_temperament() -> void:
	if _temperament_applied:
		return
	_temperament_applied = true
	var seed_value: int
	if _has_explicit_seed:
		seed_value = temperament_seed
	else:
		seed_value = CreatureTemperament.compute_fallback_seed(
			creature_type_id, global_position)
	temperament_id = CreatureTemperament.resolve_id(
		temperament_id, creature_type_id, seed_value)
	if temperament_id == &"":
		return
	_apply_temperament_modifiers()

func _apply_temperament_modifiers() -> void:
	match temperament_id:
		CreatureTemperament.AGGRESSIVE:
			wait_duration *= TEMPERAMENT_AGGRESSIVE_WAIT_MULT
			charge_speed *= TEMPERAMENT_AGGRESSIVE_CHARGE_SPEED_MULT
		CreatureTemperament.RESTLESS:
			wander_speed *= TEMPERAMENT_RESTLESS_WANDER_SPEED_MULT
			wander_change_interval *= TEMPERAMENT_RESTLESS_WANDER_INTERVAL_MULT
		CreatureTemperament.WATCHFUL:
			perception_radius *= TEMPERAMENT_WATCHFUL_PERCEPTION_MULT
			wander_speed *= TEMPERAMENT_WATCHFUL_WANDER_SPEED_MULT
		# CAUTIOUS, PERSISTENT — spider их не получает.
		_:
			pass

func _physics_process(delta: float) -> void:
	_contact_timer = maxf(0.0, _contact_timer - delta)
	_state_timer -= delta
	if _target == null or not is_instance_valid(_target):
		_target = _find_player()

	match _state:
		State.WATCH:
			if _target != null and _can_see_target():
				_enter_waiting()
			else:
				_wander(delta)
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
				_enter_watch()

func _can_see_target() -> bool:
	if _target == null:
		return false
	if global_position.distance_to(_target.global_position) > perception_radius:
		return false
	return _has_line_of_sight_to(_target)

func _has_line_of_sight_to(target: Node2D) -> bool:
	# Через общий LineOfSight-хелпер: если между пауком и игроком стена,
	# паук не переходит в WAITING и не плюётся паутиной сквозь неё.
	if not is_instance_valid(target):
		return false
	return LineOfSight.is_clear(get_world_2d(), global_position, target.global_position, [get_rid()])

func _enter_watch() -> void:
	_state = State.WATCH
	_state_timer = 0.0
	modulate = Color(1, 0.85, 0.55)
	# Свежий вход в WATCH — сбрасываем таймер направления, чтобы паук
	# сразу «оглянулся» и выбрал новое направление блуждания.
	_wander_timer = 0.0

func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0 or _wander_direction == Vector2.ZERO:
		_pick_wander_direction()
	velocity = _wander_direction * wander_speed
	move_and_slide()
	# Упёрлись в стену — крутим направление в сторону и обнуляем таймер,
	# следующий тик выберет новое.
	if velocity.length() < 1.0:
		_wander_direction = -_wander_direction.rotated(randf_range(-PI / 3.0, PI / 3.0))
		_wander_timer = 0.0

func _pick_wander_direction() -> void:
	var angle := randf() * TAU
	_wander_direction = Vector2.RIGHT.rotated(angle)
	_wander_timer = wander_change_interval

func _enter_waiting() -> void:
	_state = State.WAITING
	_state_timer = wait_duration
	modulate = Color(1, 0.75, 0.35)
	_spit_web()

func _spit_web() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var parent := get_parent()
	if parent == null:
		return
	var web = WEB_SCENE.instantiate()
	web.global_position = global_position
	web.target_position = _target.global_position
	parent.add_child(web)

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
		died_at.emit(global_position)
		EventLog.log_kill(display_name, xp_reward, gold_reward)
		GameState.award_xp(xp_reward)
		GameState.award_gold(gold_reward)
		GameState.award_enemy_kill()
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
