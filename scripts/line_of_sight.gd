class_name LineOfSight
extends RefCounted

# Общая проверка «видит ли A точку B напрямую, или между ними стена».
# Стены в этом проекте — единственные StaticBody2D (см. floor.gd::_build_walls).
# Если появится другой StaticBody2D (разрушаемый ящик, дверь-body) — фильтр
# придётся ужесточить: группа/слой стен вместо `is StaticBody2D`.
#
# Используется:
# - MeleeHitbox — не наносим урон врагу за стеной, даже если он в геометрической арке;
# - Enemy.reach — reach-удар (skeleton'ий меч) не достаёт игрока через стену;
# - Bullet — стена уничтожает пулю независимо от pierce;
# - Charger — уже проверял LoS перед плевком паутиной, теперь через тот же хелпер.
#
# Fail-open: если world_2d/space_state недоступны (нода вне дерева, тест без
# физики) — считаем «видно». Иначе тесты, изначально работавшие без мира,
# начнут ложно проваливать damage-контракт.

static func is_clear(world_2d: World2D, from: Vector2, to: Vector2, exclude: Array = []) -> bool:
	if world_2d == null:
		return true
	var space_state := world_2d.direct_space_state
	if space_state == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = exclude
	# collide_with_areas = false: pickup'ы, hitbox'ы и другие Area2D не считаются
	# препятствиями. Урон блокируют только физические стены (StaticBody2D).
	query.collide_with_areas = false
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return true
	return not (result.collider is StaticBody2D)
