extends DamageableEnvironmentProp

# Explosive alchemical barrel: наследуется от DamageableEnvironmentProp.
# При разрушении запускается telegraph (визуальное предупреждение) на
# `telegraph_time` секунд, затем случается radial explosion в радиусе
# `explosion_radius` пикселей.
#
# Chain reaction guard: другие explosive_barrel внутри радиуса получают
# take_damage_from(FACTION_ENVIRONMENT, damage). Каталог задаёт
# damage_factions = [FACTION_PLAYER] для барреля, поэтому environment-урон
# отсекается — вложенные бочки НЕ взрываются от соседа. Это специальное
# правило безопасности: игрок хочет предсказуемости, бесконечный chain
# делает уровень непроходимым.
#
# Для damage-контракта: игрок и враги получают take_damage(damage) без
# фракций (у них single-arg signature). LoS check не нужен — телеграф
# уже дал шанс убежать.

const _DEF := preload("res://scenes/dungeon/environment_prop_definition.gd")

# Задаются configure_hazard() до add_child(). Дефолты — safety fallback,
# если сцена инстанцирована руками без configure.
var explosion_radius: float = 40.0
var explosion_damage: int = 3
var telegraph_time: float = 0.5

# Не free-им узел сразу в _destroy() — сначала показываем telegraph.
var _pending_explosion: bool = false
var _telegraph_timer: float = 0.0

@onready var _visual: Sprite2D = $Visual

func configure_hazard(
	p_explosion_radius: float,
	p_explosion_damage: int,
	p_telegraph_time: float,
) -> void:
	explosion_radius = maxf(1.0, p_explosion_radius)
	explosion_damage = maxi(1, p_explosion_damage)
	telegraph_time = maxf(0.0, p_telegraph_time)

func _keep_alive_after_destroy() -> bool:
	# Держим ноду в дереве до конца telegraph → explosion. Base-класс
	# уже эмиттил `destroyed`, отключил collision (deferred). Мы
	# продолжаем в _process pulsing telegraph, потом взрываем.
	return true

func _on_destroyed() -> void:
	_pending_explosion = true
	_telegraph_timer = telegraph_time
	# Красная тональность как визуальный маркер telegraph.
	if _visual != null:
		_visual.modulate = Color(1.6, 0.6, 0.5)
	# Мгновенный взрыв без telegraph — редкий edge (telegraph_time = 0):
	# processing ниже сработает уже в следующем tick'е.

func _process(delta: float) -> void:
	if not _pending_explosion:
		return
	# Пульсация scale для telegraph — визуальный «набухающий» баррель.
	if _visual != null and telegraph_time > 0.0:
		var t: float = 1.0 - clampf(_telegraph_timer / telegraph_time, 0.0, 1.0)
		var pulse: float = 1.0 + 0.35 * sin(t * TAU * 3.0)
		_visual.scale = Vector2(pulse, pulse)
	_telegraph_timer -= delta
	if _telegraph_timer <= 0.0:
		_pending_explosion = false
		_explode()
		queue_free()

func _explode() -> void:
	# Собираем всех потенциальных target'ов в радиусе через group-search —
	# просто и без physics-query. Расстояние проверяем сами.
	var world_pos: Vector2 = global_position
	var radius_sq: float = explosion_radius * explosion_radius
	# Игрок.
	for player in get_tree().get_nodes_in_group("player"):
		if not (player is Node2D):
			continue
		if world_pos.distance_squared_to(player.global_position) > radius_sq:
			continue
		if player.has_method("take_damage"):
			player.take_damage(explosion_damage)
	# Враги.
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not (enemy is Node2D):
			continue
		if world_pos.distance_squared_to(enemy.global_position) > radius_sq:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(explosion_damage)
	# Другие damageable props (например, urn/crate/barrel рядом). Chain
	# на explosive_barrel фильтруется через damage_factions.
	for prop in get_tree().get_nodes_in_group("damageable_prop"):
		if prop == self:
			continue
		if not (prop is Node2D):
			continue
		if world_pos.distance_squared_to(prop.global_position) > radius_sq:
			continue
		if prop.has_method("take_damage_from"):
			# FACTION_ENVIRONMENT — соседние explosive_barrel отфильтруют
			# (у них damage_factions = [FACTION_PLAYER]). Обычные
			# destructibles (crate/urn) в MVP тоже принимают только
			# FACTION_PLAYER, поэтому environment-урон не разрушит их
			# в chain — консервативная политика без ломающих сюрпризов.
			prop.take_damage_from(_DEF.FACTION_ENVIRONMENT, explosion_damage)
