class_name BossSpawnContext
extends RefCounted

# Typed context, который `Main` передаёт боссу перед `add_child()`.
# Заменяет ad-hoc dictionary + прямые обращения к GameState из boss-сцены:
# теперь boss можно тестировать и переиспользовать без autoload'а.
#
# Ни одно из полей не является обязательным для BossBase — конкретный
# босс сам решает, что читать. BossBase.apply_spawn_context() дефолтно
# читает floor_number для scaling.

var floor_number: int = 0
var zone: StringName = &""
var tower_seed: int = 0
var arena_rect: Rect2 = Rect2()
var player: Node2D = null
