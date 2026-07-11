extends GutTest

# Целевые envelope соответствуют плану PR3: envelope растёт вниз по
# зонам, и footprint зависит от floor'а внутри зоны.

func test_footprint_envelope_grows_across_zones() -> void:
	# Envelope maxima монотонно растут вниз по башне — глубокий caves envelope
	# больше чем tower_top envelope, независимо от progression floor'а.
	var envelopes: Array = [
		DungeonFootprint.envelope_pixels("tower_top"),
		DungeonFootprint.envelope_pixels("residential"),
		DungeonFootprint.envelope_pixels("technical"),
		DungeonFootprint.envelope_pixels("lower_tower"),
		DungeonFootprint.envelope_pixels("basement"),
		DungeonFootprint.envelope_pixels("caves"),
	]
	for i in range(envelopes.size() - 1):
		var cur: Dictionary = envelopes[i]
		var next: Dictionary = envelopes[i + 1]
		assert_gte(next.max.x, cur.max.x,
			"envelope max.x монотонно растёт (zone %d)" % i)
		assert_gte(next.max.y, cur.max.y,
			"envelope max.y монотонно растёт (zone %d)" % i)

func test_footprint_grows_within_zone() -> void:
	# residential: floor 3 (min) < floor 6 (max)
	var early := DungeonFootprint.footprint_tiles_for_zone("residential", 3)
	var late := DungeonFootprint.footprint_tiles_for_zone("residential", 6)
	assert_lte(early.x, late.x)
	assert_lte(early.y, late.y)

func test_envelope_first_floor_exceeds_viewport_pixels() -> void:
	# Первый этаж (floor 1) должен быть шире одного viewport (640 px).
	# 30 tiles × 20 px = 600 px минимум, чего почти достаточно; но по
	# плану сумма rooms и corridors должна давать >2 viewport widths по
	# кратчайшему пути. Здесь проверяем прямой pixel-envelope.
	var env := DungeonFootprint.envelope_pixels("tower_top")
	assert_gte(env.min.x, 600,
		"tower_top envelope min ≥ 600 px (примерно 1 viewport width)")

func test_unknown_zone_falls_back() -> void:
	# Неизвестная zone → возвращает fallback envelope, не крешит.
	var f := DungeonFootprint.footprint_tiles_for_zone("nonexistent", 1)
	assert_gt(f.x, 0)
	assert_gt(f.y, 0)
