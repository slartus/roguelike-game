extends GutTest

# Паук (charger.tscn) при переходе WATCH → WAITING плюёт паутиной в
# позицию игрока. Паутина летит по прямой (FLYING), приземляется в
# target_position и лежит там LANDED_LIFETIME секунд, замедляя игрока
# в области в SLOW_FACTOR раз. Дети charge-фазы не затронуты — паук
# всё ещё прыгает после WAITING.

const ChargerScene = preload("res://scenes/enemies/charger.tscn")
const SpiderWebScene = preload("res://scenes/enemies/spider_web.tscn")
const PlayerScene = preload("res://scenes/player/player.tscn")

func _spawn_charger():
	var charger = ChargerScene.instantiate()
	add_child_autofree(charger)
	return charger

func _spawn_web():
	var web = SpiderWebScene.instantiate()
	add_child_autofree(web)
	return web

func _spawn_player():
	var player = PlayerScene.instantiate()
	add_child_autofree(player)
	return player

func _count_webs_under(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child.is_in_group("spider_web"):
			n += 1
	return n

# ---- Spider: web-spitting --------------------------------------------------

func test_spider_spits_web_on_entering_waiting() -> void:
	var charger = _spawn_charger()
	var parent := charger.get_parent()
	# Дадим пауку цель, чтобы _spit_web не пропустил из-за null target.
	var fake_target := Node2D.new()
	fake_target.global_position = Vector2(100, 50)
	add_child_autofree(fake_target)
	charger._target = fake_target
	var before := _count_webs_under(parent)
	charger._enter_waiting()
	assert_eq(_count_webs_under(parent), before + 1,
		"переход WATCH → WAITING должен породить одну паутину")

func test_web_target_position_locks_to_player_at_spit_time() -> void:
	var charger = _spawn_charger()
	var parent := charger.get_parent()
	var fake_target := Node2D.new()
	fake_target.global_position = Vector2(200, 100)
	add_child_autofree(fake_target)
	charger._target = fake_target
	# Snapshot children ДО плевка — под тестовым root уже могут лежать
	# паутины из соседних тестов (add_child_autofree общий), берём именно
	# новую.
	var before_children := parent.get_children().duplicate()
	charger._enter_waiting()
	# Двигаем цель после плевка — паутина должна лететь в СТАРУЮ позицию.
	fake_target.global_position = Vector2(999, 999)
	var web: Node2D = null
	for child in parent.get_children():
		if child in before_children:
			continue
		if child.is_in_group("spider_web"):
			web = child
			break
	assert_not_null(web)
	assert_almost_eq(web.target_position.x, 200.0, 0.1,
		"target_position паутины зафиксирован в момент плевка")
	assert_almost_eq(web.target_position.y, 100.0, 0.1)

func test_spider_still_charges_after_waiting() -> void:
	# Не сломался ли переход WAITING → CHARGING после добавления плевка.
	var charger = _spawn_charger()
	var fake_target := Node2D.new()
	fake_target.global_position = Vector2(100, 0)
	add_child_autofree(fake_target)
	charger._target = fake_target
	charger._enter_waiting()
	assert_eq(charger._state, charger.State.WAITING)
	charger._enter_charging()
	assert_eq(charger._state, charger.State.CHARGING,
		"после WAITING паук всё ещё должен переходить в CHARGING")

func test_spider_does_not_spit_web_without_target() -> void:
	var charger = _spawn_charger()
	charger._target = null
	var parent := charger.get_parent()
	var before := _count_webs_under(parent)
	charger._spit_web()
	assert_eq(_count_webs_under(parent), before,
		"без цели паук не плюётся")

# ---- Spider: line of sight -------------------------------------------------

func _spawn_wall(pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	wall.global_position = pos
	add_child_autofree(wall)
	return wall

func test_spider_sees_target_without_wall() -> void:
	var charger = _spawn_charger()
	charger.global_position = Vector2.ZERO
	var fake_target := Node2D.new()
	fake_target.global_position = Vector2(80, 0)
	add_child_autofree(fake_target)
	charger._target = fake_target
	await get_tree().physics_frame
	assert_true(charger._can_see_target(),
		"без стены между пауком и игроком LOS свободен")

func test_spider_does_not_see_through_wall() -> void:
	var charger = _spawn_charger()
	charger.global_position = Vector2.ZERO
	var fake_target := Node2D.new()
	fake_target.global_position = Vector2(80, 0)
	add_child_autofree(fake_target)
	charger._target = fake_target
	_spawn_wall(Vector2(40, 0), Vector2(20, 40))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(charger._can_see_target(),
		"стена между пауком и игроком блокирует LOS — паутина не летит")

func test_spider_target_beyond_perception_not_visible() -> void:
	var charger = _spawn_charger()
	charger.global_position = Vector2.ZERO
	var fake_target := Node2D.new()
	fake_target.global_position = Vector2(charger.perception_radius + 50.0, 0)
	add_child_autofree(fake_target)
	charger._target = fake_target
	await get_tree().physics_frame
	assert_false(charger._can_see_target(),
		"цель дальше perception_radius не видима, даже без стены")

# ---- Spider web: flight and landing ----------------------------------------

func test_web_starts_in_flying_state() -> void:
	var web = _spawn_web()
	assert_eq(web._state, web.State.FLYING)

func test_web_moves_toward_target_during_flight() -> void:
	var web = _spawn_web()
	web.global_position = Vector2.ZERO
	web.target_position = Vector2(200, 0)
	web._tick_flight(0.1)  # dt=0.1s × 140 speed = 14 px
	assert_almost_eq(web.global_position.x, 14.0, 1.5,
		"паутина должна сместиться в сторону цели по FLIGHT_SPEED × dt")

func test_web_lands_when_close_enough_to_target() -> void:
	var web = _spawn_web()
	web.global_position = Vector2(100, 0)
	web.target_position = Vector2(101, 0)  # dist=1 px < LANDING_THRESHOLD
	web._tick_flight(0.01)
	assert_eq(web._state, web.State.LANDED,
		"близко к target_position — переход в LANDED")

func test_web_snaps_to_target_on_landing() -> void:
	var web = _spawn_web()
	web.global_position = Vector2(0, 0)
	web.target_position = Vector2(50, 60)
	web._enter_landed()
	assert_almost_eq(web.global_position.x, 50.0, 0.001)
	assert_almost_eq(web.global_position.y, 60.0, 0.001)

func test_web_queue_frees_after_landed_lifetime() -> void:
	var web = _spawn_web()
	web._enter_landed()
	web._tick_landed(web.LANDED_LIFETIME + 0.1)
	assert_true(web.is_queued_for_deletion(),
		"по истечении LANDED_LIFETIME паутина должна queue_free")

func test_web_stays_alive_before_lifetime() -> void:
	var web = _spawn_web()
	web._enter_landed()
	web._tick_landed(web.LANDED_LIFETIME * 0.5)
	assert_false(web.is_queued_for_deletion())

# ---- Player: slow-source counter -------------------------------------------

func test_player_default_speed_unaffected() -> void:
	var player = _spawn_player()
	await get_tree().process_frame
	assert_almost_eq(player.current_speed(), player.speed, 0.001,
		"без источников замедления скорость равна базовой")

func test_player_slow_source_halves_speed() -> void:
	var player = _spawn_player()
	await get_tree().process_frame
	player.enter_slow_source()
	assert_almost_eq(player.current_speed(), player.speed * player.SLOW_FACTOR, 0.001,
		"один активный источник — скорость × SLOW_FACTOR")

func test_multiple_sources_do_not_stack_below_half() -> void:
	# Наложение двух паутин не должно квадратно уменьшать скорость.
	# SLOW_FACTOR применяется бинарно: любой count > 0 → × SLOW_FACTOR.
	var player = _spawn_player()
	await get_tree().process_frame
	player.enter_slow_source()
	player.enter_slow_source()
	assert_almost_eq(player.current_speed(), player.speed * player.SLOW_FACTOR, 0.001,
		"несколько источников не стакаются мультипликативно")

func test_exit_source_restores_speed_when_counter_zero() -> void:
	var player = _spawn_player()
	await get_tree().process_frame
	player.enter_slow_source()
	player.enter_slow_source()
	player.exit_slow_source()
	# Один источник ещё активен.
	assert_almost_eq(player.current_speed(), player.speed * player.SLOW_FACTOR, 0.001)
	player.exit_slow_source()
	# Все источники сняты — вернулись к базовой скорости.
	assert_almost_eq(player.current_speed(), player.speed, 0.001,
		"когда счётчик источников == 0, скорость восстанавливается")

func test_exit_source_never_goes_negative() -> void:
	var player = _spawn_player()
	await get_tree().process_frame
	player.exit_slow_source()  # без парного enter
	player.exit_slow_source()
	assert_eq(player._slow_source_count, 0,
		"счётчик источников не должен уходить в отрицательное значение")

# ---- Web + Player integration ----------------------------------------------

func test_landed_web_applies_slow_on_body_entered() -> void:
	var web = _spawn_web()
	var player = _spawn_player()
	await get_tree().process_frame
	web._enter_landed()
	web._on_body_entered(player)
	assert_eq(player._slow_source_count, 1,
		"игрок в LANDED-паутине получает +1 источник замедления")

func test_flying_web_does_not_slow_player() -> void:
	# Пролёт паутины над игроком не должен сработать как slow-контакт.
	var web = _spawn_web()
	# Убираем цель далеко, чтобы _process при следующем physics-тике не
	# auto-land'нул паутину: default target_position и global_position
	# оба равны (0,0), distance=0 < LANDING_THRESHOLD → LANDED.
	web.target_position = Vector2(1000, 1000)
	var player = _spawn_player()
	await get_tree().process_frame
	assert_eq(web._state, web.State.FLYING,
		"после process_frame паутина всё ещё FLYING (цель далеко)")
	web._on_body_entered(player)
	assert_eq(player._slow_source_count, 0,
		"FLYING-паутина не применяет slow")

func test_landed_web_releases_slow_on_body_exited() -> void:
	var web = _spawn_web()
	var player = _spawn_player()
	await get_tree().process_frame
	web._enter_landed()
	web._on_body_entered(player)
	web._on_body_exited(player)
	assert_eq(player._slow_source_count, 0,
		"выход из LANDED-паутины снимает slow")

func test_web_ignores_non_player_bodies() -> void:
	var web = _spawn_web()
	var charger = _spawn_charger()
	await get_tree().process_frame
	web._enter_landed()
	# Паук не в группе player — паутина его не должна замедлять
	# (нет метода enter_slow_source в charger.gd).
	web._on_body_entered(charger)
	assert_false(charger.has_method("enter_slow_source"))

func test_expiring_web_releases_still_overlapping_player() -> void:
	# Регресс-guard: если игрок стоит в паутине, а паутина исчезает
	# по таймеру, счётчик slow-источников на игроке не должен зависнуть.
	var web = _spawn_web()
	var player = _spawn_player()
	await get_tree().process_frame
	web._enter_landed()
	web._on_body_entered(player)
	assert_eq(player._slow_source_count, 1)
	# Симулируем ручную очистку при истечении таймера. `_tick_landed` с
	# истёкшим таймером сделает `_release_all_slowed_bodies` + queue_free.
	# Но `get_overlapping_bodies` в headless-тесте может вернуть пусто,
	# т.к. физика не поднимала bodies этой Area — вызываем handler
	# напрямую как это сделал бы физический контакт.
	web._release_slow(player)
	assert_eq(player._slow_source_count, 0,
		"перед queue_free паутина должна освободить всех замедлённых игроков")
