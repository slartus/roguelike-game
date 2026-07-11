extends Area2D

@export var speed: float = 110.0
@export var lifetime: float = 3.0
@export var damage: int = 1

var direction: Vector2 = Vector2.RIGHT
# Attribution: кто стрелял. Аналитика записывает damage_history и
# floor_enemy_summary.damage_to_player по source_enemy_id / temperament /
# elite_rank. Enemy spawner (ranged_enemy / lich / boss) выставляет
# перед add_child. Значение null → source_type="unknown".
var source_enemy: Node = null
# attack_id атаки, из которой пуля родилась ("projectile", "aimed_shot",
# "volley", "summon_projectile"). Опционально.
var attack_id: StringName = &"projectile"

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_end)
	# Разворачиваем весь снаряд в направлении полёта: спрайт (стрела /
	# сгусток) смотрит в цель, коллизия — тоже (важно для узкой arrow).
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy"):
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		var ctx := DamageContext.from_enemy_projectile(source_enemy, attack_id)
		body.take_damage(damage, ctx)
	queue_free()

func _on_lifetime_end() -> void:
	if is_inside_tree():
		queue_free()
