extends "res://scenes/enemies/ranged_enemy.gd"

# Lich расширяет ranged_enemy.gd способностью призывать
# скелета-миньона. Правила:
# - в один момент времени активен максимум один призванный скелет;
# - если миньон убит — через SUMMON_COOLDOWN секунд призывается новый;
# - первый призыв случается через SUMMON_COOLDOWN после спавна лича
#   (даём игроку время реагировать на лича до появления «свиты»).
#
# Призванный скелет не даёт XP/золота и не роняет пикапы —
# это ходячее раздражение, не источник прогресса. Иначе игрок
# просто пасётся возле лича и фармит призванных.

const SkeletonScene: PackedScene = preload("res://scenes/enemies/skeleton.tscn")

const SUMMON_COOLDOWN: float = 5.0
const SUMMON_OFFSET_MIN: float = 24.0
const SUMMON_OFFSET_MAX: float = 40.0
const SPAWN_ATTEMPTS: int = 12
const FLOOR_TILE_SIZE: int = 20

var _summoned_minion: Node = null
var _summon_cooldown_timer: float = SUMMON_COOLDOWN

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_summon(delta)

func _update_summon(delta: float) -> void:
	# WeakRef не используем — Node ссылки достаточно, а
	# is_instance_valid ловит freed / queue_freed случай.
	if _summoned_minion != null and not is_instance_valid(_summoned_minion):
		_summoned_minion = null
	if _summoned_minion != null:
		return
	_summon_cooldown_timer -= delta
	if _summon_cooldown_timer > 0.0:
		return
	# Если не нашли валидную клетку для спавна — не сбрасываем
	# кулдаун (он уже < 0), следующий тик снова попробует.
	_summon_skeleton()

func _summon_skeleton() -> bool:
	# Родитель лича — обычно Main._enemies_root; сиблинг-скелет
	# попадает туда же, автоматически в группу enemy через _ready.
	# get_parent() безопаснее чем get_tree().current_scene — в тестах
	# current_scene может быть null.
	var parent := get_parent()
	if parent == null:
		return false
	var spawn_pos := _pick_valid_spawn_position()
	if spawn_pos == Vector2.INF:
		return false
	var skeleton = SkeletonScene.instantiate()
	skeleton.global_position = spawn_pos
	parent.add_child(skeleton)
	# Обнуляем награды ПОСЛЕ add_child. В _ready родительский
	# enemy.gd прогоняет xp/gold через Balance.scaled_*_reward, где
	# `maxi(1, …)` превращает 0 в 1 — обнулять до add_child
	# бесполезно. Отдельно: pickup_scene читается только в _drop_pickup
	# (уже при смерти), тоже безопасно назначать сейчас.
	skeleton.xp_reward = 0
	skeleton.gold_reward = 0
	skeleton.pickup_scene = null
	_summoned_minion = skeleton
	_summon_cooldown_timer = SUMMON_COOLDOWN
	return true

func _pick_valid_spawn_position() -> Vector2:
	# Пробуем SPAWN_ATTEMPTS случайных точек в кольце вокруг лича;
	# берём первую, чья ячейка в AStarGrid2D не solid (не стена).
	# Без этой проверки спавн иногда попадал внутрь стены — скелет
	# застревал в геометрии и был неубиваемым.
	var floor_node := get_tree().get_first_node_in_group("floor")
	# В тестах / автономно (без Main + Floor) деградируем к простому
	# спавну без валидации — тесты живут без dungeon.
	if floor_node == null or floor_node.astar_grid == null:
		var angle := randf() * TAU
		var distance := randf_range(SUMMON_OFFSET_MIN, SUMMON_OFFSET_MAX)
		return global_position + Vector2(cos(angle), sin(angle)) * distance
	for i in SPAWN_ATTEMPTS:
		var angle := randf() * TAU
		var distance := randf_range(SUMMON_OFFSET_MIN, SUMMON_OFFSET_MAX)
		var candidate := global_position + Vector2(cos(angle), sin(angle)) * distance
		var cell := Vector2i(int(candidate.x / FLOOR_TILE_SIZE), int(candidate.y / FLOOR_TILE_SIZE))
		if not floor_node.astar_grid.is_in_boundsv(cell):
			continue
		if floor_node.astar_grid.is_point_solid(cell):
			continue
		return candidate
	return Vector2.INF
