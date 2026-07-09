extends GutTest

# Зомби периодически спавнит ядовитое облако у своей позиции; облако
# наносит игроку статус «отравлен ядом» — 1 hp/сек в течение 3 сек с
# refresh'ем длительности при повторном попадании.

const ZombieScene = preload("res://scenes/enemies/zombie.tscn")
const PoisonCloudScene = preload("res://scenes/enemies/poison_cloud.tscn")
const PlayerScene = preload("res://scenes/player/player.tscn")

func _spawn_zombie():
	var zombie = ZombieScene.instantiate()
	add_child_autofree(zombie)
	return zombie

func _spawn_cloud():
	var cloud = PoisonCloudScene.instantiate()
	add_child_autofree(cloud)
	return cloud

func _spawn_player():
	var player = PlayerScene.instantiate()
	add_child_autofree(player)
	return player

func _count_clouds_under(node: Node) -> int:
	# poison_cloud.gd::_ready добавляет облако в группу "poison_cloud".
	# Матчим по группе — устойчиво к любым другим Area2D в тесте.
	var n := 0
	for child in node.get_children():
		if child.is_in_group("poison_cloud"):
			n += 1
	return n

# ---- Zombie: cloud spawning ------------------------------------------------

func test_zombie_starts_with_full_cooldown() -> void:
	var zombie = _spawn_zombie()
	assert_almost_eq(zombie._cloud_cooldown_timer, zombie.POISON_CLOUD_COOLDOWN, 0.001,
		"первый спавн — только через POISON_CLOUD_COOLDOWN после появления")

func test_zombie_spawns_cloud_after_cooldown() -> void:
	var zombie = _spawn_zombie()
	var parent := zombie.get_parent()
	var before := _count_clouds_under(parent)
	zombie._cloud_cooldown_timer = 0.01
	zombie._tick_cloud(0.05)
	assert_eq(_count_clouds_under(parent), before + 1,
		"по истечении кулдауна должно появиться облако")

func test_zombie_resets_cooldown_after_spawn() -> void:
	var zombie = _spawn_zombie()
	zombie._cloud_cooldown_timer = 0.01
	zombie._tick_cloud(0.05)
	assert_almost_eq(zombie._cloud_cooldown_timer, zombie.POISON_CLOUD_COOLDOWN, 0.001,
		"после спавна кулдаун снова полный")

func test_zombie_does_not_spawn_before_cooldown() -> void:
	var zombie = _spawn_zombie()
	var parent := zombie.get_parent()
	var before := _count_clouds_under(parent)
	zombie._cloud_cooldown_timer = 1.0
	zombie._tick_cloud(0.05)
	assert_eq(_count_clouds_under(parent), before,
		"кулдаун ещё не истёк — облако не появляется")

func test_cloud_spawns_at_zombie_position() -> void:
	var zombie = _spawn_zombie()
	zombie.global_position = Vector2(150, 250)
	var parent := zombie.get_parent()
	var before_children := parent.get_children().duplicate()
	zombie._cloud_cooldown_timer = 0.01
	zombie._tick_cloud(0.05)
	var new_cloud: Node2D = null
	for child in parent.get_children():
		if child in before_children:
			continue
		new_cloud = child
		break
	assert_not_null(new_cloud)
	assert_almost_eq(new_cloud.global_position.x, 150.0, 0.5)
	assert_almost_eq(new_cloud.global_position.y, 250.0, 0.5)

# ---- Poison cloud: lifecycle -----------------------------------------------

func test_cloud_queue_frees_after_lifetime() -> void:
	var cloud = _spawn_cloud()
	assert_true(is_instance_valid(cloud), "облако существует сразу после спавна")
	# Пропускаем один _process с delta = LIFETIME + margin.
	cloud._process(cloud.LIFETIME + 0.1)
	assert_true(cloud.is_queued_for_deletion(),
		"облако должно уйти в queue_free по истечении LIFETIME")

func test_cloud_alive_before_lifetime() -> void:
	var cloud = _spawn_cloud()
	cloud._process(cloud.LIFETIME * 0.5)
	assert_false(cloud.is_queued_for_deletion(),
		"облако живо в первой половине своей жизни")

# ---- Player: poison status -------------------------------------------------

func test_player_apply_poison_sets_timer() -> void:
	var player = _spawn_player()
	await get_tree().process_frame
	var hp_before: int = player.health
	player.apply_poison(3.0)
	# Между apply_poison и assert могут отработать фоновые physics
	# tick'и (проверяли — до 3 штук), поэтому проверяем не точные
	# значения, а инварианты: (1) урон НЕ мгновенный, (2) длительность
	# и tick-таймер в разумных границах после старта.
	assert_eq(player.health, hp_before,
		"apply_poison НЕ должен наносить урон мгновенно")
	assert_gt(player._poison_timer, 2.5,
		"длительность близка к 3с (учёт возможных фоновых тиков)")
	assert_gt(player._poison_tick_timer, 0.5,
		"первый тик ещё не сработал — таймер около POISON_TICK_INTERVAL")

func test_player_poison_deals_1hp_per_second() -> void:
	var player = _spawn_player()
	await get_tree().process_frame
	var hp_before: int = player.health
	player.apply_poison(3.0)
	# Проматываем секунду в один тик — tick-таймер уходит в 0,
	# должен сработать один урон.
	player._tick_poison(1.0)
	assert_eq(player.health, hp_before - player.POISON_DAMAGE_PER_TICK,
		"через 1 сек должен снятья 1 hp")

func test_player_poison_refresh_extends_duration() -> void:
	var player = _spawn_player()
	await get_tree().process_frame
	player.apply_poison(3.0)
	player._tick_poison(2.0)  # 1 сек осталась, 2 тика уже прошли (у нас 1 тик потому что _tick вызван один раз)
	# После первого apply: _poison_timer = 3.0, потом -2.0 = 1.0.
	# Refresh — снова 3.0.
	player.apply_poison(3.0)
	assert_almost_eq(player._poison_timer, 3.0, 0.001,
		"refresh обновляет длительность до полной")

func test_player_poison_refresh_does_not_reset_tick_timer() -> void:
	# Ключевой инвариант: если бы refresh сбрасывал tick-таймер,
	# игрок мог бы избегать урона, ре-заражаясь непосредственно перед
	# каждым тиком. Проверяем что tick_timer сохраняется.
	var player = _spawn_player()
	await get_tree().process_frame
	player.apply_poison(3.0)
	player._tick_poison(0.5)  # tick_timer теперь ~0.5
	var tick_before_refresh: float = player._poison_tick_timer
	player.apply_poison(3.0)  # refresh
	assert_almost_eq(player._poison_tick_timer, tick_before_refresh, 0.001,
		"refresh не должен сбрасывать tick-таймер")

func test_player_poison_expires_after_duration() -> void:
	var player = _spawn_player()
	await get_tree().process_frame
	player.apply_poison(3.0)
	# 4 секунды суммарно — таймер уходит в 0.
	player._tick_poison(4.0)
	assert_eq(player._poison_timer, 0.0,
		"по истечении 3 сек статус пропадает")

func test_player_poison_stops_ticking_after_expiration() -> void:
	var player = _spawn_player()
	await get_tree().process_frame
	player.apply_poison(3.0)
	player._tick_poison(4.0)  # exhausted
	var hp_after_expiration: int = player.health
	player._tick_poison(1.0)  # ещё секунда — не должно быть урона
	assert_eq(player.health, hp_after_expiration,
		"без активного статуса урона больше нет")

func test_cloud_body_entered_applies_poison_to_player() -> void:
	var cloud = _spawn_cloud()
	var player = _spawn_player()
	await get_tree().process_frame
	# Симулируем event напрямую — это интеграционный смоук.
	cloud._on_body_entered(player)
	assert_almost_eq(player._poison_timer, cloud.POISON_DURATION, 0.001,
		"вход в облако триггерит apply_poison(POISON_DURATION)")

func test_cloud_ignores_non_player_bodies() -> void:
	var cloud = _spawn_cloud()
	var zombie = _spawn_zombie()
	await get_tree().process_frame
	# Зомби не в группе player → ноль эффекта. Проверяем что не крашится
	# и не имеет apply_poison → просто return без raise.
	cloud._on_body_entered(zombie)
	assert_false(zombie.has_method("apply_poison"),
		"у зомби нет apply_poison — облако его игнорирует")
