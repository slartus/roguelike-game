class_name MeleeHitbox
extends Area2D

# Прямоугольный hitbox для ближнего боя. Создаётся WeaponController'ом
# в момент атаки, живёт `active_time` секунд, наносит damage всем врагам
# внутри (через body_entered + сразу overlap-снапшот), не бьёт одного и
# того же врага несколько раз за один swing, потом queue_free.
#
# MVP: sword и spear отличаются только размером box'а — не идеальная дуга,
# но читается визуально (short/wide для меча, long/narrow для копья).

var damage: int = 1
var knockback: float = 0.0
var active_time: float = 0.08

var _shape: CollisionShape2D
var _hit_targets: Dictionary = {}
var _life_timer: float = 0.0
var _did_initial_scan: bool = false

func _ready() -> void:
	# configure() создаёт CollisionShape2D через add_child до того как сам
	# hitbox добавлен в дерево. Godot автоименует его @CollisionShape2D@ /
	# похоже — get_node("CollisionShape2D") не найдёт, ищем по типу через
	# children. Если shape нет — забыли configure(), это dev-error.
	for child in get_children():
		if child is CollisionShape2D:
			_shape = child
			break
	assert(_shape != null, "MeleeHitbox: configure() должен быть вызван до add_child")
	body_entered.connect(_on_body_entered)

# Настраивается ДО add_child, чтобы _ready увидел уже финальный box.
func configure(
	source: Node2D,
	direction: Vector2,
	dmg: int,
	length: float,
	width: float,
	life: float,
	kb: float,
) -> void:
	damage = dmg
	knockback = kb
	active_time = life
	var angle := direction.angle()
	# Ставим hitbox в позицию источника, ориентируем rotation на direction,
	# смещаем на length/2 вперёд — чтобы box лежал перед игроком, а не
	# был центрирован на нём.
	global_position = source.global_position + direction * (length * 0.5)
	rotation = angle
	# CollisionShape ещё нет в дереве, создаём rect до _ready.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(length, width)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

func _physics_process(delta: float) -> void:
	# Первый physics tick — враги, стоявшие внутри hitbox'а на момент
	# spawn'а, ещё не выдали body_entered (сигнал шлётся только на новом
	# overlap). Сканируем текущий snapshot сами. На последующих кадрах —
	# только body_entered, чтобы не дублировать удары.
	if not _did_initial_scan:
		_did_initial_scan = true
		for body in get_overlapping_bodies():
			_try_hit(body)
	_life_timer += delta
	if _life_timer >= active_time:
		queue_free()

func _on_body_entered(body: Node) -> void:
	_try_hit(body)

func _try_hit(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("player"):
		return
	if _hit_targets.has(body):
		return
	if not body.has_method("take_damage"):
		return
	_hit_targets[body] = true
	body.take_damage(damage)
	# Knockback пока опциональный: если у target есть метод apply_knockback,
	# зовём его. Иначе тихо игнорируем — M3 задокументировано как "если
	# легко сделать". Сложный knockback остаётся на будущее.
	if knockback > 0.0 and body.has_method("apply_knockback"):
		var direction_to_body: Vector2 = (body.global_position - global_position).normalized()
		body.apply_knockback(direction_to_body * knockback)
