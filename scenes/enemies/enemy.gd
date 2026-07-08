extends CharacterBody2D

# Общий melee-скрипт (Slime, Goblin, Orc, Skeleton, Zombie).
# State machine: WANDER → CHASE → WANDER.
#
# CHASE двухфазный:
# - если игрок в radius perception_radius → идёт прямо на него,
#   запоминает last_seen_position;
# - если игрок вышел из радиуса → идёт к last_seen_position и каждые
#   memory_check_interval секунд «бросает кубик»: randf() > memory →
#   забыл, уходит в WANDER. Чем выше memory (0..1), тем упорнее
#   монстр помнит и преследует.
#
# WANDER — случайное блуждание со сниженной скоростью.

signal died_at(position: Vector2)

enum State { WANDER, CHASE }

const LOST_RATIO: float = 1.6
const REACHED_LAST_SEEN_DISTANCE: float = 8.0
const PATH_RECALC_INTERVAL: float = 0.25
const PATH_TARGET_STALE_DISTANCE: float = 24.0
const WAYPOINT_REACHED_DISTANCE: float = 6.0
const FLOOR_TILE_SIZE: int = 20
# Stuck detection: если после slide реальная скорость < speed * ratio,
# значит враг упёрся в стену. Через STUCK_TIMEOUT включаем escape —
# идём перпендикулярно к цели ESCAPE_DURATION секунд, чтобы обогнуть
# угол. Без этого враг мог намертво прижаться к стене (A* start_cell
# solid → fallback на direct chase → упор в стену → повтор каждый tick).
const STUCK_VELOCITY_RATIO: float = 0.15
const STUCK_TIMEOUT: float = 0.25
const ESCAPE_DURATION: float = 0.4

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
@export_range(0.0, 1.0) var memory: float = 0.65
@export var memory_check_interval: float = 1.0

var health: int
var _state: int = State.WANDER
var _target: Node2D
var _contact_timer: float = 0.0
var _wander_direction: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _last_seen_position: Vector2 = Vector2.ZERO
var _memory_timer: float = 0.0
var _floor: Node                       # Ссылка на Floor (для astar_grid)
var _path: PackedVector2Array          # Waypoints в пиксельных координатах
var _path_recalc_timer: float = 0.0
var _path_target: Vector2 = Vector2.INF
var _stuck_timer: float = 0.0
var _escape_timer: float = 0.0
var _escape_direction: Vector2 = Vector2.ZERO
var _last_escape_side: float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	var floor_num := GameState.current_floor_number
	max_health = Balance.scaled_hp(max_health, floor_num)
	contact_damage = Balance.scaled_damage(contact_damage, floor_num)
	xp_reward = Balance.scaled_xp_reward(xp_reward, floor_num)
	gold_reward = Balance.scaled_gold_reward(gold_reward, floor_num)
	health = max_health
	_floor = get_tree().get_first_node_in_group("floor")

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
				_enter_chase()
				_chase_toward(_target.global_position, delta)
			else:
				_wander(delta)
		State.CHASE:
			if dist <= perception_radius:
				# Видим цель — обновляем last_seen и таймер памяти.
				_last_seen_position = _target.global_position
				_memory_timer = memory_check_interval
				_chase_toward(_target.global_position, delta)
			elif dist > perception_radius * LOST_RATIO:
				# Игрок вне радиуса даже с учётом гистерезиса — тестируем память.
				_memory_timer -= delta
				if _memory_timer <= 0.0:
					_memory_timer = memory_check_interval
					if randf() > memory:
						_state = State.WANDER
						_pick_wander_direction()
						return
				# Помним — идём к последней виденной позиции.
				if global_position.distance_to(_last_seen_position) < REACHED_LAST_SEEN_DISTANCE:
					_state = State.WANDER
					_pick_wander_direction()
				else:
					_chase_toward(_last_seen_position, delta)
			else:
				# В зоне гистерезиса — держим CHASE к last_seen.
				_chase_toward(_last_seen_position, delta)

func _enter_chase() -> void:
	_state = State.CHASE
	_last_seen_position = _target.global_position
	_memory_timer = memory_check_interval

func _chase_toward(target_pos: Vector2, delta: float) -> void:
	# Если Floor + AStarGrid2D доступны — идём по A*-пути, иначе fallback
	# на прямую линию (совместимо со сценами без Floor, напр. тестами).
	if _floor != null and _floor.astar_grid != null:
		_chase_via_path(target_pos, delta)
	else:
		_chase_direct(target_pos, delta)

func _chase_via_path(target_pos: Vector2, delta: float) -> void:
	# Recalc ТОЛЬКО по таймеру — иначе пустой path триггерил бы пересчёт
	# каждый кадр (60 fps × 50 enemies × A* → burn CPU и зависание).
	_path_recalc_timer -= delta
	if _path_recalc_timer <= 0.0:
		_recalc_path(target_pos)
		_path_recalc_timer = PATH_RECALC_INTERVAL

	# Если path пуст (target недоступен) — fallback на прямую.
	if _path.is_empty():
		_chase_direct(target_pos, delta)
		return

	# Съедаем waypoint'ы, до которых уже дошли.
	while _path.size() > 0 and global_position.distance_to(_path[0]) < WAYPOINT_REACHED_DISTANCE:
		_path.remove_at(0)
	if _path.is_empty():
		_chase_direct(target_pos, delta)
		return
	_chase_direct(_path[0], delta)

func _recalc_path(target_pos: Vector2) -> void:
	_path = PackedVector2Array()
	_path_target = target_pos
	var start_cell := _pixel_to_cell(global_position)
	var end_cell := _pixel_to_cell(target_pos)
	if not _floor.astar_grid.is_in_boundsv(start_cell):
		return
	if not _floor.astar_grid.is_in_boundsv(end_cell):
		return
	# Если start клетка solid (враг стоит на стене — не должно быть, но
	# safe fallback), путь не найдётся.
	if _floor.astar_grid.is_point_solid(start_cell):
		return
	# Если end клетка solid (target внутри стены — например игрок за
	# краем этажа), возвращаем прямую линию через fallback.
	if _floor.astar_grid.is_point_solid(end_cell):
		return
	_path = _floor.astar_grid.get_point_path(start_cell, end_cell)
	# get_point_path возвращает от start_cell до end_cell включительно;
	# первую точку выкидываем — мы уже в start_cell.
	if _path.size() > 0:
		_path.remove_at(0)

func _pixel_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / FLOOR_TILE_SIZE), int(pos.y / FLOOR_TILE_SIZE))

func _chase_direct(_target_pos: Vector2, _delta: float) -> void:
	var to_target := (_target_pos - global_position).normalized()
	var direction: Vector2
	if _escape_timer > 0.0:
		_escape_timer -= _delta
		direction = _escape_direction
	else:
		direction = to_target
	if direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		return
	velocity = direction * speed
	# move_and_slide вместо move_and_collide: враг скользит вдоль стен
	# при перекошенном waypoint, а не застревает у неё намертво.
	move_and_slide()
	_handle_player_contact()
	_update_stuck_state(to_target, _delta)

func _update_stuck_state(to_target: Vector2, delta: float) -> void:
	# Если после slide velocity почти обнулилась — прижались к стене.
	# Копим таймер; по истечении STUCK_TIMEOUT включаем escape в
	# перпендикулярном направлении, чтобы попытаться обогнуть угол.
	if velocity.length() < speed * STUCK_VELOCITY_RATIO:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_TIMEOUT and _escape_timer <= 0.0:
			_escape_direction = _pick_escape_direction(to_target)
			_escape_timer = ESCAPE_DURATION
			_stuck_timer = 0.0
			# Стёрли устаревший A*-путь: он мог указывать на waypoint у
			# той самой стены, к которой только что прижались.
			_path = PackedVector2Array()
	else:
		_stuck_timer = 0.0
		# Успешно двигаемся — предыдущий выбранный side «сработал»,
		# на будущее снова разрешаем случайный выбор.
		_last_escape_side = 0.0

func _pick_escape_direction(toward_target: Vector2) -> Vector2:
	var base := toward_target if toward_target != Vector2.ZERO else Vector2.RIGHT
	# Если только что уже пробовали одну сторону и снова застряли —
	# берём противоположную, чтобы не циклиться в тот же угол.
	var side: float
	if _last_escape_side != 0.0:
		side = -_last_escape_side
	else:
		side = 1.0 if randf() > 0.5 else -1.0
	_last_escape_side = side
	return base.rotated(side * PI / 2.0)

func _handle_player_contact() -> void:
	if _contact_timer > 0.0:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider and collider.is_in_group("player") and collider.has_method("take_damage"):
			collider.take_damage(contact_damage)
			_contact_timer = contact_cooldown
			return

func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0 or _wander_direction == Vector2.ZERO:
		_pick_wander_direction()
	velocity = _wander_direction * speed * wander_speed_ratio
	move_and_slide()
	# Если после slide реальное движение = 0 (упёрся в угол), сменить
	# направление в следующем tick'е.
	if velocity.length() < 1.0:
		_wander_direction = -_wander_direction.rotated(randf_range(-PI / 3.0, PI / 3.0))
		_wander_timer = 0.0

func _pick_wander_direction() -> void:
	var angle := randf() * TAU
	_wander_direction = Vector2.RIGHT.rotated(angle)
	_wander_timer = wander_change_interval
	# Переход в WANDER = свежий старт AI. Сбрасываем stuck-state, иначе
	# сохранённый _escape_direction/_escape_timer с прошлого CHASE может
	# «выстрелить» устаревшим рывком при возврате в CHASE через N секунд.
	_stuck_timer = 0.0
	_escape_timer = 0.0
	_last_escape_side = 0.0
	_path = PackedVector2Array()

func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

func take_damage(amount: int) -> void:
	health -= amount
	# Урон = игрок близко, «пробуждаем» AI в CHASE даже если был WANDER.
	if _target != null and is_instance_valid(_target):
		_enter_chase()
	modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.08).timeout
	if is_inside_tree():
		modulate = Color.WHITE
	if health <= 0 and is_inside_tree():
		# Emit до queue_free — иначе слушатели увидят freed node.
		died_at.emit(global_position)
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
