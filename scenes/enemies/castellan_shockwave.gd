extends Area2D

# Ортогональный shockwave от ground_slam Кастеляна. Летит по прямой,
# наносит damage игроку при overlap, исчезает у стены или по lifetime.
# Простая независимая нода — сам босс не должен tick'ать волны.
#
# Дизайн-инвариант: damage <= 1 (см. план PR 2). Boss выставляет damage
# перед add_child; хардкодить здесь нельзя, иначе тест на damage cap
# станет ложно-положительным.

@export var speed: float = 140.0
@export var lifetime: float = 1.4
@export var damage: int = 1

var direction: Vector2 = Vector2.RIGHT
var source_enemy: Node = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_end)
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func _on_body_entered(body: Node) -> void:
	# Bosses / enemies не должны получать damage от собственных волн.
	if body.is_in_group("enemy"):
		return
	# StaticBody2D стен пометит нас "исчерпал путь" — исчезаем, а не
	# скользим сквозь.
	if body is StaticBody2D:
		queue_free()
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		var ctx := DamageContext.from_enemy_ability(source_enemy, &"ground_slam_shockwave")
		body.take_damage(damage, ctx)
	queue_free()

func _on_lifetime_end() -> void:
	if is_inside_tree():
		queue_free()
