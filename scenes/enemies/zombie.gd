extends "res://scenes/enemies/enemy.gd"

# Зомби периодически оставляет за собой облако зловония. Кулдаун
# POISON_CLOUD_COOLDOWN секунд между спавнами; облако живёт LIFETIME
# секунд (см. poison_cloud.gd) и наносит игроку статус «отравлен».
#
# Первый спавн — через POISON_CLOUD_COOLDOWN после появления зомби,
# а не сразу. Иначе зомби, заспавненный рядом с игроком, немедленно
# бросал бы облако у ног игрока без окна на реакцию.

const POISON_CLOUD_SCENE: PackedScene = preload("res://scenes/enemies/poison_cloud.tscn")
const POISON_CLOUD_COOLDOWN: float = 3.0

var _cloud_cooldown_timer: float = POISON_CLOUD_COOLDOWN

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_tick_cloud(delta)

func _tick_cloud(delta: float) -> void:
	_cloud_cooldown_timer -= delta
	if _cloud_cooldown_timer > 0.0:
		return
	_cloud_cooldown_timer = POISON_CLOUD_COOLDOWN
	_spawn_cloud()

func _spawn_cloud() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var cloud = POISON_CLOUD_SCENE.instantiate()
	cloud.global_position = global_position
	parent.add_child(cloud)
