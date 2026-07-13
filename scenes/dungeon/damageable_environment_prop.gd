class_name DamageableEnvironmentProp
extends StaticBody2D

# База для gameplay-props, которые могут получать урон и разрушаться:
# destructible_crate / destructible_barrel / urn. Также используется как
# наследник для explosive_barrel (там же добавляется explosion pipeline).
#
# Physics: StaticBody2D на дефолтном layer'е — melee hitbox и bullet
# видят prop через `body_entered` (то же поведение, что у walls). Bullet
# self-destroy'ит на первом попадании (стандартное bullet.gd), melee
# hitbox фильтрует по `has_method("take_damage")` — оба контракта
# ловят этот класс.
#
# Инварианты:
# - take_damage(amount, faction) idempotent: повторный вызов после
#   destroy() ничего не делает;
# - destroy() эмиттит `destroyed` РОВНО ОДИН РАЗ до queue_free;
# - collision отключается set_deferred("collision_layer", 0) — Godot
#   запрещает менять физику из physics_process callback синхронно;
# - слушатель `destroyed` (floor.gd) может освободить AStar cells до
#   того как узел ушёл из дерева.
#
# Сцены-наследники (explosive_barrel) переопределяют `_on_destroyed()`,
# который вызывается ровно один раз в конце destroy() до queue_free.

signal destroyed(prop_id: StringName, world_position: Vector2)

# Props ставятся floor.gd::_instantiate_placement.  configure() задаёт
# id / max_health / damage_factions ДО add_child(), чтобы _ready видел
# уже финальные поля.
var prop_id: StringName = &""
var max_health: int = 1
var damage_factions: Array[StringName] = []
var footprint_cells: Vector2i = Vector2i.ONE

var _health: int = 1
var _destroyed: bool = false

func configure(
	p_prop_id: StringName,
	p_max_health: int,
	p_damage_factions: Array[StringName],
	p_footprint_cells: Vector2i,
) -> void:
	prop_id = p_prop_id
	max_health = maxi(1, p_max_health)
	damage_factions = p_damage_factions.duplicate()
	footprint_cells = p_footprint_cells
	_health = max_health

func _ready() -> void:
	add_to_group("damageable_prop")
	# Если configure не был вызван (тесты, ручной инстанс), _health = 0 —
	# инициализируем безопасным дефолтом чтобы избежать «мгновенно мёртв».
	if _health <= 0:
		_health = max_health

# Player melee hitbox и bullet вызывают body.take_damage(amount) без
# знания про фракцию — сигнатура должна принимать один аргумент, как
# у enemy.gd. Для контроля фракции есть take_damage_from(faction, amount)
# ниже — hazards используют его при chain reaction.
func take_damage(amount: int) -> void:
	take_damage_from(EnvironmentPropDefinition.FACTION_PLAYER, amount)

func take_damage_from(faction: StringName, amount: int) -> void:
	if _destroyed:
		return
	if not _accepts_damage_from(faction):
		return
	if amount <= 0:
		return
	_health -= amount
	if _health <= 0:
		_destroy()

func _accepts_damage_from(faction: StringName) -> bool:
	if damage_factions.is_empty():
		return true
	return damage_factions.has(faction)

func is_destroyed() -> bool:
	return _destroyed

func current_health() -> int:
	return _health

# Публичный вход для внешнего триггера (тест / explosion chain). Guard
# по _destroyed — повторный destroy() безопасен, эффектов не будет.
func destroy() -> void:
	_destroy()

func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	# collision отключаем через set_deferred: физика может быть в разгаре
	# body_entered callback (bullet.take_damage → prop._destroy), где
	# менять layer/monitoring синхронно нельзя.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	# Emit ДО queue_free — floor.gd должен освободить AStar cell пока
	# узел ещё в дереве и мы можем читать global_position/footprint.
	destroyed.emit(prop_id, global_position)
	_on_destroyed()
	# Cleanup: если наследник (explosive_barrel) сам решает когда
	# исчезнуть (после explosion), он вернёт false из _keep_alive_after_destroy.
	if not _keep_alive_after_destroy():
		queue_free()

# Наследники переопределяют для custom-эффекта (explosion, debris),
# но обязаны сами вызвать queue_free по завершении, если возвращают
# `true` из `_keep_alive_after_destroy`.
func _on_destroyed() -> void:
	pass

func _keep_alive_after_destroy() -> bool:
	return false
