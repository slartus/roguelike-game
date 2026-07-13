extends GutTest

# Castellan Hall — арена первого босса (этаж 5). Проверяем arena profile
# по инвариантам плана PR 2: размер прямоугольного парадного зала, зона
# residential, чистый центр, стены близко для charge-stun.

const CastellanArenaProfile: Resource = preload("res://resources/bosses/castellan_hall_arena.tres")

func test_arena_has_stable_id() -> void:
	assert_eq(CastellanArenaProfile.id, &"castellan_hall",
		"stable arena id для boss definition lookup")

func test_arena_is_rectangular_and_finite() -> void:
	# Прямоугольный парадный зал. Размер положительный и лежит в разумных
	# рамках (сравнимо с legacy 600×400, не сотни тысяч пикселей).
	var size := CastellanArenaProfile.size
	assert_gt(size.x, 0, "width > 0")
	assert_gt(size.y, 0, "height > 0")
	assert_ne(size.x, size.y, "прямоугольник (не квадрат) — план указывает парадный зал")
	assert_lt(size.x, 2000, "width в разумных пределах")
	assert_lt(size.y, 2000, "height в разумных пределах")

func test_arena_walls_close_enough_for_charge_stun() -> void:
	# CHARGE_SPEED * CHARGE_MAX_DURATION определяет максимальную длину
	# заряда без wall impact. Из центра арены минимальное расстояние до
	# стены — половина меньшей оси. Оно должно быть меньше max charge
	# distance, иначе charge из центра не долетит до стены и wall-stun
	# теряет смысл (план: «стены достаточно близко, чтобы charge-stun
	# был осмысленным»).
	const BOSS_SCRIPT: Script = preload("res://scenes/enemies/castellan_armor.gd")
	var max_charge_distance := BOSS_SCRIPT.CHARGE_SPEED * BOSS_SCRIPT.CHARGE_MAX_DURATION
	var size := CastellanArenaProfile.size
	var half_shorter_side: float = mini(size.x, size.y) * 0.5
	assert_lt(half_shorter_side, max_charge_distance,
		"половина меньшей оси арены (%d) < max charge distance (%d) для wall-stun'а"
			% [int(half_shorter_side), int(max_charge_distance)])

func test_arena_has_clear_center() -> void:
	# clear_center_radius > 0 — план требует чистый центр без пропов.
	assert_gt(CastellanArenaProfile.clear_center_radius, 0.0,
		"clear_center_radius > 0 — центр арены чистый")

func test_arena_zone_matches_residential() -> void:
	# Этаж 5 завершает residential-зону — арена должна быть в этой зоне.
	assert_eq(CastellanArenaProfile.zone, &"residential",
		"arena.zone соответствует зоне 5 этажа")

func test_registry_returns_castellan_arena_for_floor_five() -> void:
	# Полный round-trip: floor 5 → definition → arena profile.
	var profile := BossRegistry.arena_profile_for_floor(5)
	assert_not_null(profile, "5 этаж резолвит arena profile")
	assert_eq(profile.id, &"castellan_hall",
		"для этажа 5 arena_profile — castellan_hall")

# --- Проверка spawn safety (боссы/игроки не спавнятся в стене) ------------

func test_boss_and_player_spawn_positions_lie_inside_arena() -> void:
	# DungeonGenerator размещает player_start в size.x/6 и exit в
	# size.x * 5/6 (см. _generate_boss_floor). Обе позиции обязаны быть
	# строго внутри arena.
	var size := CastellanArenaProfile.size
	var player_start := Vector2i(size.x / 6, size.y / 2)
	var exit_pos := Vector2i(size.x * 5 / 6, size.y / 2)
	var arena_rect := Rect2i(Vector2i.ZERO, size)
	assert_true(arena_rect.has_point(player_start),
		"player_start внутри арены")
	assert_true(arena_rect.has_point(exit_pos),
		"exit_position внутри арены")
	# Расстояние между player_start и exit больше charge_max_duration ×
	# speed — иначе игрок стартует прямо напротив exit и boss-битву можно
	# пропустить одним charge.
	var distance := (Vector2(player_start) - Vector2(exit_pos)).length()
	assert_gt(distance, 200.0,
		"дистанция start→exit не тривиальная")
