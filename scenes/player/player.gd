extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal weapon_changed(weapon: WeaponResource)

@export var speed: float = 90.0

# Статус «отравлен ядом»: пока `_poison_timer > 0`, каждую секунду
# срабатывает `take_damage(POISON_DAMAGE_PER_TICK)`. Повторное
# попадание в облако (apply_poison) обновляет длительность до полного
# значения, но не сбрасывает tick-таймер — иначе игрок мог бы
# избегать урона, ре-заражаясь непосредственно перед каждым тиком.
# Пока отравлен, скорость домножается на POISON_SLOW_FACTOR: тело
# скованно, движение тяжелее — умеренный slow (0.7), не такой жёсткий
# как паутина, но стакается с ней мультипликативно (0.3 × 0.7 = 0.21).
const POISON_TICK_INTERVAL: float = 1.0
const POISON_DAMAGE_PER_TICK: int = 1
const POISON_SLOW_FACTOR: float = 0.7

# Slow-статус (например от паутины паука): скорость игрока умножается
# на SLOW_FACTOR, пока `_slow_source_count > 0`. Считаем именно источники,
# а не bool: несколько накладывающихся паутин не «удваивают» slow, но
# выход из одной не снимает эффект если игрок стоит во второй.
const SLOW_FACTOR: float = 0.3

# Анимация взмаха при атаке. Тот же паттерн что у Skeleton lunge
# (см. skeleton.gd): корпус игрока делает короткий выпад в сторону
# цели, оружие в это же время рубит по дуге. Для projectile-оружия
# (лук, посох) — только выпад, без вращения sprite'а.
const SWING_DISTANCE: float = 6.0
const SWING_OUT_DURATION: float = 0.06
const SWING_BACK_DURATION: float = 0.12
const WEAPON_SWING_ANGLE: float = PI * 0.55

# Weapon в руке игрока. Позиция и rest-поза зависят от направления
# «взгляда» — куда указывает мышь. Смещаем sprite по X в противоположную
# сторону от игрока и наклоняем рукоятью вниз (для melee), так чтобы
# читалось «игрок держит оружие в дальней руке под углом», а не
# «клинок торчит из плеча».
const HAND_X_OFFSET: float = 5.0
const HAND_Y_OFFSET: float = 3.0
# ~20° — слабый наклон от вертикали для меча/кинжала/копья в rest.
# Знак умножается на _facing, чтобы клинок смотрел «наружу» от игрока.
const MELEE_REST_ANGLE: float = 0.35
# Порог по dx до мыши, ниже которого считаем «направление не задано»
# и не переключаем facing — чтобы не дёргалось у самой точки под курсором.
const FACING_DEADZONE_PX: float = 2.0

var max_health: int
var health: int
var equipped_weapon: WeaponResource
var _poison_timer: float = 0.0
var _poison_tick_timer: float = 0.0
var _slow_source_count: int = 0
var _visual_base_position: Vector2 = Vector2.ZERO
var _swing_tween: Tween
# +1 → игрок смотрит вправо, -1 → влево. Обновляется по направлению
# к курсору (aim direction). Определяет сторону, где рендерится
# оружие, и знак rest-угла для melee.
var _facing: int = 1

@onready var _weapon_controller: WeaponController = $WeaponController
@onready var _visual: Sprite2D = $Visual
@onready var _weapon_sprite: Sprite2D = $Weapon

func _ready() -> void:
	add_to_group("player")
	max_health = GameState.player_max_health
	health = clampi(GameState.player_health, 1, max_health)
	equipped_weapon = GameState.equipped_weapon
	GameState.leveled_up.connect(_on_leveled_up)
	_weapon_controller.setup(self)
	if _visual != null:
		_visual_base_position = _visual.position
	_apply_weapon_visual(equipped_weapon)
	health_changed.emit(health, max_health)
	weapon_changed.emit(equipped_weapon)

# Показать модель оружия в руке игрока. Иконка спрайта нарисована как
# «blade вверху PNG, handle внизу PNG» — офсет `-h/2` совмещает pivot
# с handle, чтобы позиция ноды была именно в руке игрока (при вращении
# handle не «убегает» из руки, а клинок описывает дугу над плечом).
# Melee оружие получает rest-наклон ±MELEE_REST_ANGLE через
# `_apply_facing_visuals`, ranged/spell остаются вертикально.
func _apply_weapon_visual(weapon: WeaponResource) -> void:
	if _weapon_sprite == null:
		return
	if weapon == null or weapon.icon_texture == null:
		_weapon_sprite.visible = false
		return
	_weapon_sprite.texture = weapon.icon_texture
	_weapon_sprite.modulate = weapon.icon_modulate
	_weapon_sprite.offset = Vector2(0, -weapon.icon_texture.get_height() * 0.5)
	_weapon_sprite.visible = true
	_apply_facing_visuals()

# Перевешивает оружие с левой руки на правую (и наоборот), выставляет
# rest-угол и `flip_h` под текущий `_facing`. Вызывается на смене
# оружия и на смене направления взгляда.
func _apply_facing_visuals() -> void:
	if _weapon_sprite == null or not _weapon_sprite.visible:
		return
	_weapon_sprite.position = Vector2(HAND_X_OFFSET * _facing, HAND_Y_OFFSET)
	_weapon_sprite.flip_h = _facing < 0
	_weapon_sprite.rotation = _get_rest_rotation()

func _get_rest_rotation() -> float:
	if equipped_weapon == null:
		return 0.0
	if equipped_weapon.attack_type in ["melee_arc", "melee_thrust"]:
		return MELEE_REST_ANGLE * _facing
	return 0.0

# Публичный хук: тесты не могут удобно эмулировать позицию мыши, а
# `_physics_process` дёргает этот же метод от `get_global_mouse_position`.
# Значения кроме ±1 игнорируются, знак нуля тоже — чтобы не менять facing.
func face(direction: int) -> void:
	if direction == 0 or direction == _facing:
		return
	_facing = 1 if direction > 0 else -1
	_apply_facing_visuals()

# WeaponController зовёт это на успешной атаке. Играет короткий
# выпад корпуса + свинг оружия для melee, только выпад для ranged.
func play_attack_visual(target_position: Vector2, weapon: WeaponResource) -> void:
	if _visual == null:
		return
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	var direction := (target_position - global_position).normalized()
	if direction == Vector2.ZERO:
		return
	var swing_offset := _visual_base_position + direction * SWING_DISTANCE
	_swing_tween = create_tween()
	_swing_tween.tween_property(_visual, "position", swing_offset, SWING_OUT_DURATION)
	# Свинг оружия только для melee — у projectile/spell вращение выглядит
	# странно (лук не должен «резать»). Знак угла завязан на facing:
	# при facing right свинг идёт по часовой (клинок вправо), при left —
	# против (клинок влево), чтобы удар всегда шёл «в сторону цели».
	var is_melee := weapon != null and weapon.attack_type in ["melee_arc", "melee_thrust"]
	var rest_rot := _get_rest_rotation()
	var swing_target := rest_rot + WEAPON_SWING_ANGLE * _facing
	if is_melee and _weapon_sprite != null and _weapon_sprite.visible:
		_swing_tween.parallel().tween_property(_weapon_sprite, "rotation", swing_target, SWING_OUT_DURATION)
	_swing_tween.tween_property(_visual, "position", _visual_base_position, SWING_BACK_DURATION)
	if is_melee and _weapon_sprite != null and _weapon_sprite.visible:
		_swing_tween.parallel().tween_property(_weapon_sprite, "rotation", rest_rot, SWING_BACK_DURATION)

func _on_leveled_up(_new_level: int, new_max_health: int) -> void:
	max_health = new_max_health
	health = new_max_health
	GameState.player_health = health
	health_changed.emit(health, max_health)

func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * current_speed()
	move_and_slide()

	_update_facing_from_aim()

	if Input.is_action_pressed("attack") and equipped_weapon != null:
		_weapon_controller.try_attack(equipped_weapon, get_global_mouse_position())

	_tick_poison(delta)

func _update_facing_from_aim() -> void:
	# Направление «взгляда» = знак dx от игрока до курсора. Deadzone
	# защищает от дрожания сайда, когда курсор ровно над игроком.
	var dx := get_global_mouse_position().x - global_position.x
	if absf(dx) < FACING_DEADZONE_PX:
		return
	face(1 if dx > 0.0 else -1)

func equip(weapon: WeaponResource) -> void:
	if weapon == null:
		return
	equipped_weapon = weapon
	GameState.equipped_weapon = weapon
	_apply_weapon_visual(weapon)
	weapon_changed.emit(weapon)

func take_damage(amount: int) -> void:
	var new_health: int = max(0, health - amount)
	# Second Wind: если этот удар был бы летальным и карта взята и её заряд
	# ещё не потрачен на этом этаже — переживаем удар и восстанавливаем HP
	# до параметра "heal".
	if new_health == 0 and _try_trigger_second_wind():
		health_changed.emit(health, max_health)
		modulate = Color(1, 0.5, 0.5)
		await get_tree().create_timer(0.1).timeout
		if is_inside_tree():
			modulate = Color.WHITE
		return
	health = new_health
	GameState.player_health = health
	health_changed.emit(health, max_health)
	modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.1).timeout
	if is_inside_tree():
		modulate = Color.WHITE
	if health == 0:
		_die()

# Возвращает true если Second Wind сработал — take_damage должен пропустить
# death path и оставить игрока живым. Charge потрачен, до next_floor() /
# reset_run() снова не сработает.
func _try_trigger_second_wind() -> bool:
	if GameState.second_wind_used_this_floor:
		return false
	var stacks := GameState.get_upgrade_stack("second_wind")
	if stacks <= 0:
		return false
	var upgrade := PlayerUpgradeLibrary.get_upgrade_by_id("second_wind")
	if upgrade == null:
		return false
	var heal_amount: int = int(upgrade.parameters.get("heal", 2))
	health = clampi(heal_amount, 1, max_health)
	GameState.player_health = health
	GameState.second_wind_used_this_floor = true
	return true

func current_speed() -> float:
	var mods := GameState.get_player_upgrade_modifiers()
	var multiplier := float(mods.speed_multiplier)
	# Sure Footing уменьшает slow: 1.0 → 1.0, но SLOW_FACTOR становится
	# менее жёстким за счёт bonus.
	var slow_bonus := float(mods.slow_resistance_bonus)
	if _slow_source_count > 0:
		var effective_slow: float = clampf(SLOW_FACTOR + slow_bonus, SLOW_FACTOR, 0.9)
		multiplier *= effective_slow
	if _poison_timer > 0.0:
		multiplier *= POISON_SLOW_FACTOR
	return speed * multiplier

func enter_slow_source() -> void:
	_slow_source_count += 1

func exit_slow_source() -> void:
	# maxi guard: если облако успело queue_free до того как игрок в него
	# вошёл (edge-case initial-overlap race), _release_slow может прийти
	# без парного enter'а — не хотим ронять счётчик в отрицательное.
	_slow_source_count = maxi(0, _slow_source_count - 1)

func apply_poison(duration: float) -> void:
	# Свежая инфекция — заводим tick-таймер на полный интервал, чтобы
	# первый урон случился через POISON_TICK_INTERVAL, а не мгновенно.
	# Refresh (уже отравлен) — не трогаем tick-таймер: игрок должен
	# продолжать получать урон по расписанию, даже если ре-заходит в
	# облако.
	if _poison_timer <= 0.0:
		_poison_tick_timer = POISON_TICK_INTERVAL
	# Antidote Blood — poison_duration_multiplier < 1.0 сокращает длительность.
	var mods := GameState.get_player_upgrade_modifiers()
	_poison_timer = duration * float(mods.poison_duration_multiplier)

func _tick_poison(delta: float) -> void:
	if _poison_timer <= 0.0:
		return
	_poison_timer = maxf(0.0, _poison_timer - delta)
	_poison_tick_timer -= delta
	if _poison_tick_timer > 0.0:
		return
	_poison_tick_timer = POISON_TICK_INTERVAL
	if health > 0:
		take_damage(POISON_DAMAGE_PER_TICK)

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
	# Potion Mastery увеличивает heal.
	var mods := GameState.get_player_upgrade_modifiers()
	var heal_amount: int = 1 + int(mods.potion_heal_bonus)
	heal(heal_amount)
	EventLog.log_heal(heal_amount)

func _die() -> void:
	# finish_run фиксирует snapshot текущего забега (этаж, уровень, убийства,
	# золото) и обнуляет run state — title screen прочитает его и покажет
	# окно «Итоги забега». Если бы мы звали reset_run напрямую, snapshot
	# потерялся бы.
	GameState.finish_run()
	# После смерти всегда уходим на title screen (стартовый экран).
	# call_deferred: change_scene_to_file из physics callback
	# (Bullet.body_entered или Enemy.move_and_collide → take_damage → _die)
	# запрещён — обёртка через deferred переводит вызов на idle-frame.
	get_tree().call_deferred("change_scene_to_file", "res://scenes/ui/title_screen.tscn")
