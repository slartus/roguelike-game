extends Area2D

@export var speed: float = 220.0
@export var lifetime: float = 1.5
@export var damage: int = 1
# pierce > 0 → пуля пробивает N дополнительных целей до queue_free.
# Каждая цель уменьшает счётчик; когда pierce_remaining уходит в 0,
# следующее попадание уничтожает пулю как раньше.
@export var pierce: int = 0
# Вытянутые снаряды (стрелы, болты) поворачиваются вдоль direction, чтобы
# наконечник смотрел в сторону полёта. Круглые (orbs) держат rotation = 0.
@export var rotate_with_direction: bool = false
# Смещение rotation для случаев, когда исходный sprite нарисован не «вправо».
# В радианах.
@export var rotation_offset: float = 0.0

var direction: Vector2 = Vector2.RIGHT
var _pierce_remaining: int = 0
var _hit_bodies: Dictionary = {}
# Analytics attribution: source weapon для damage_dealt на enemy.
# Заполняется в apply_weapon() / apply_weapon_stats(). Пустое → source_id="unknown".
var source_weapon_id: StringName = &""
var source_attack_id: StringName = &"projectile"
# Track уникальных попаданий (targets_hit != projectiles_fired при pierce).
var _analytics_registered_hit: bool = false
# WeaponController выставляет direction и apply_weapon_stats(...) ДО
# add_child, но @onready _visual ещё не существует — modulate тогда падает
# на null visual, и на экран прилетает исходный цвет спрайта, а не
# projectile_color. Кешируем цвет, применяем в _ready.
var _pending_visual_color: Color = Color.WHITE

@onready var _visual: Sprite2D = $Visual

func _ready() -> void:
	_pierce_remaining = pierce
	if _visual != null:
		_visual.modulate = _pending_visual_color
	if rotate_with_direction:
		rotation = direction.angle() + rotation_offset
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_end)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func apply_weapon(weapon: WeaponResource) -> void:
	if weapon == null:
		return
	# Читаем через get_* helper'ы — они остаются стабильным API после удаления
	# legacy fallback fields, чтобы не менять callsite'ы разом со схемой.
	damage = weapon.damage
	speed = weapon.get_projectile_speed()
	lifetime = weapon.get_projectile_lifetime()
	pierce = weapon.pierce
	_pierce_remaining = pierce
	_pending_visual_color = weapon.get_projectile_color()
	source_weapon_id = StringName(weapon.resource_path.get_file().get_basename())
	source_attack_id = StringName(weapon.attack_type)
	# Если сцена уже в дереве (тестовый путь: add_child перед apply) —
	# _visual уже разрешился через @onready, modulate можно применить сразу.
	if _visual != null:
		_visual.modulate = _pending_visual_color

# Новый путь через WeaponStats — учитывает upgrade modifiers.
# WeaponController предпочитает его над apply_weapon, если метод есть.
func apply_weapon_stats(stats: WeaponStats) -> void:
	if stats == null:
		return
	damage = stats.damage
	speed = stats.projectile_speed
	lifetime = stats.projectile_lifetime
	pierce = stats.pierce
	_pierce_remaining = pierce
	_pending_visual_color = stats.projectile_color
	if _visual != null:
		_visual.modulate = _pending_visual_color
	# WeaponStats знает weapon_id + attack_type — используем для attribution.
	if "source_weapon_id" in stats and stats.source_weapon_id != &"":
		source_weapon_id = stats.source_weapon_id
	if "attack_type" in stats and stats.attack_type != "":
		source_attack_id = StringName(stats.attack_type)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		return
	# Один и тот же враг не должен получать урон дважды от одной пирсующей
	# пули — Area2D может слать body_entered повторно если body сдвинулся.
	if _hit_bodies.has(body):
		return
	# Стена (StaticBody2D) и любые не-урон-цели гасят пулю независимо от
	# pierce. Иначе pierce-пуля (арбалет, upgrade) пробивала стену, тратя
	# один заряд, и летела дальше в следующего врага сквозь неё.
	if not body.has_method("take_damage"):
		queue_free()
		return
	# Attribution: собираем DamageContext от source weapon → target enemy.
	var ctx := DamageContext.new()
	ctx.source_type = &"player_weapon"
	ctx.source_id = source_weapon_id
	ctx.attack_id = source_attack_id
	ctx.target_type = &"enemy"
	if body.scene_file_path != "":
		ctx.target_id = StringName(body.scene_file_path.get_file().get_basename())
	if "temperament_id" in body:
		ctx.temperament_id = StringName(str(body.temperament_id))
	if "elite_rank" in body:
		ctx.elite_rank = int(body.elite_rank)
	# source_level = уровень источника (weapon), НЕ target'а — оставляем 0.
	body.take_damage(damage, ctx)
	# projectile_hit каунтер: один раз на выстрел, независимо от pierce.
	# targets_hit каунтер: инкрементится через add_damage_dealt (внутри
	# enemy.take_damage → Analytics.record_damage_dealt).
	if not _analytics_registered_hit:
		Analytics.record_projectile_hit(source_weapon_id)
		_analytics_registered_hit = true
	_hit_bodies[body] = true
	if _pierce_remaining > 0:
		_pierce_remaining -= 1
		return
	queue_free()

func _on_lifetime_end() -> void:
	if is_inside_tree():
		queue_free()
