extends GutTest

# Регресс для skeleton_arsenal.gd — таблиц weapon-вариантов и
# weighted-random выбора.

const Arsenal = preload("res://scenes/enemies/skeleton_arsenal.gd")

func test_melee_variants_include_all_five_kinds() -> void:
	var variants: Array = Arsenal.MELEE_VARIANTS
	assert_eq(variants.size(), 5,
		"должно быть 5 вариантов: unarmed + dagger×2 + sword×2")
	var keys: Array = []
	for v in variants:
		keys.append(v["display_key"])
	assert_true(keys.has("ENEMY_SKELETON_UNARMED"))
	assert_true(keys.has("ENEMY_SKELETON_DAGGER_WOOD"))
	assert_true(keys.has("ENEMY_SKELETON_DAGGER_IRON"))
	assert_true(keys.has("ENEMY_SKELETON_SWORD_WOOD"))
	assert_true(keys.has("ENEMY_SKELETON_SWORD_IRON"))

func test_melee_variants_have_visible_weapon_sprites() -> void:
	# Раньше варианты отличались только tint'ом самого скелета и
	# выглядели одинаково. Теперь у каждого вооружённого варианта
	# есть отдельный спрайт клинка/рукояти, а безоружный — пустая
	# строка (Weapon-нода прячется).
	var by_key: Dictionary = {}
	for v in Arsenal.MELEE_VARIANTS:
		by_key[v["display_key"]] = v
	assert_eq(by_key["ENEMY_SKELETON_UNARMED"]["weapon_sprite"], "",
		"безоружный не должен иметь weapon_sprite")
	for key in [
		"ENEMY_SKELETON_DAGGER_WOOD",
		"ENEMY_SKELETON_DAGGER_IRON",
		"ENEMY_SKELETON_SWORD_WOOD",
		"ENEMY_SKELETON_SWORD_IRON",
	]:
		var path: String = by_key[key]["weapon_sprite"]
		assert_ne(path, "", "%s должен иметь weapon_sprite" % key)
		assert_true(ResourceLoader.exists(path),
			"weapon_sprite должен резолвиться: %s" % path)
		var tex: Texture2D = load(path) as Texture2D
		assert_not_null(tex,
			"weapon_sprite должен грузиться как Texture2D: %s" % path)

func test_dagger_and_sword_sprites_are_distinct_per_material() -> void:
	# Проверяем что все 4 боевых варианта используют РАЗНЫЕ файлы,
	# иначе fallback на один default превратит фичу в декорацию.
	var paths: Array = []
	for v in Arsenal.MELEE_VARIANTS:
		var p: String = v["weapon_sprite"]
		if p != "":
			paths.append(p)
	var unique: Dictionary = {}
	for p in paths:
		unique[p] = true
	assert_eq(unique.size(), paths.size(),
		"каждое вооружение должно иметь уникальный sprite_path: " + str(paths))

func test_melee_variants_have_attack_radius_zero_for_touch_weapons() -> void:
	# Кулаки и кинжалы бьют только впритык — attack_radius = 0.
	# Меч должен иметь ощутимый reach, иначе фича «у меча дальше»
	# не читается на практике.
	var by_key: Dictionary = {}
	for v in Arsenal.MELEE_VARIANTS:
		by_key[v["display_key"]] = v
	assert_eq(by_key["ENEMY_SKELETON_UNARMED"]["attack_radius"], 0.0)
	assert_eq(by_key["ENEMY_SKELETON_DAGGER_WOOD"]["attack_radius"], 0.0)
	assert_eq(by_key["ENEMY_SKELETON_DAGGER_IRON"]["attack_radius"], 0.0)
	assert_gt(by_key["ENEMY_SKELETON_SWORD_WOOD"]["attack_radius"], 0.0,
		"меч wood должен иметь положительный attack_radius")
	assert_gt(by_key["ENEMY_SKELETON_SWORD_IRON"]["attack_radius"],
		by_key["ENEMY_SKELETON_SWORD_WOOD"]["attack_radius"],
		"iron меч длиннее, чем wood меч")

func test_melee_variants_have_ascending_damage_by_tier() -> void:
	var by_key: Dictionary = {}
	for v in Arsenal.MELEE_VARIANTS:
		by_key[v["display_key"]] = v
	assert_eq(by_key["ENEMY_SKELETON_UNARMED"]["damage_bonus"], 0)
	assert_gt(
		by_key["ENEMY_SKELETON_DAGGER_IRON"]["damage_bonus"],
		by_key["ENEMY_SKELETON_DAGGER_WOOD"]["damage_bonus"])
	assert_gt(
		by_key["ENEMY_SKELETON_SWORD_IRON"]["damage_bonus"],
		by_key["ENEMY_SKELETON_SWORD_WOOD"]["damage_bonus"])

func test_arrow_variants_wood_and_iron_only() -> void:
	var variants: Array = Arsenal.ARROW_VARIANTS
	assert_eq(variants.size(), 2)
	var by_key: Dictionary = {}
	for v in variants:
		by_key[v["display_key"]] = v
	assert_true(by_key.has("ENEMY_SKELETON_ARCHER_WOOD"))
	assert_true(by_key.has("ENEMY_SKELETON_ARCHER_IRON"))
	assert_eq(by_key["ENEMY_SKELETON_ARCHER_WOOD"]["damage_bonus"], 0)
	assert_gt(by_key["ENEMY_SKELETON_ARCHER_IRON"]["damage_bonus"], 0)

func test_arrow_variants_have_distinct_loadable_sprites() -> void:
	# Разные материалы стрел должны использовать разные спрайты, иначе
	# фича «wooden vs iron» читается только по tint лучника, а сама
	# стрела в полёте выглядит одинаково.
	var by_key: Dictionary = {}
	for v in Arsenal.ARROW_VARIANTS:
		by_key[v["display_key"]] = v
	var wood_path: String = by_key["ENEMY_SKELETON_ARCHER_WOOD"]["sprite_path"]
	var iron_path: String = by_key["ENEMY_SKELETON_ARCHER_IRON"]["sprite_path"]
	assert_ne(wood_path, iron_path,
		"wood и iron стрелы должны использовать разные sprite_path")
	assert_true(ResourceLoader.exists(wood_path),
		"sprite_path wooden arrow должен резолвиться: %s" % wood_path)
	assert_true(ResourceLoader.exists(iron_path),
		"sprite_path iron arrow должен резолвиться: %s" % iron_path)
	var wood_tex: Texture2D = load(wood_path) as Texture2D
	var iron_tex: Texture2D = load(iron_path) as Texture2D
	assert_not_null(wood_tex, "wood arrow sprite грузится как Texture2D")
	assert_not_null(iron_tex, "iron arrow sprite грузится как Texture2D")

func test_pick_always_returns_a_variant() -> void:
	for i in 30:
		var v: Dictionary = Arsenal.pick(Arsenal.MELEE_VARIANTS)
		assert_gt(v["weight"], 0.0)
		assert_true(v.has("display_key"))
		assert_true(v.has("damage_bonus"))
		assert_true(v.has("tint"))

func test_all_weights_positive() -> void:
	for arsenal in [Arsenal.MELEE_VARIANTS, Arsenal.ARROW_VARIANTS]:
		for v in arsenal:
			assert_gt(v["weight"], 0.0, "%s weight" % v["display_key"])

func test_every_display_key_has_a_translation() -> void:
	# Гарантия что при добавлении нового варианта разработчик
	# не забыл положить перевод в resources/translations/strings.csv:
	# tr(unknown_key) в Godot возвращает сам ключ.
	for arsenal in [Arsenal.MELEE_VARIANTS, Arsenal.ARROW_VARIANTS]:
		for v in arsenal:
			var key: String = v["display_key"]
			assert_ne(tr(key), key,
				"нет перевода для %s — добавь строку в strings.csv" % key)
