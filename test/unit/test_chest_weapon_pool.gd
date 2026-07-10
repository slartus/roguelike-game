extends GutTest

# Пул сундука после M6:
# - 6 классических оружий, по 2 на style (warrior/archer/mage);
# - Dagger/Pistol/Shotgun выведены из активного пула;
# - _choose_weapon НЕ возвращает текущее оружие если есть альтернатива;
# - стартовое оружие игрока = short_sword (fantasy start, не shooter).

const ChestScript = preload("res://scenes/pickups/chest.gd")

var _weapon_snapshot: WeaponResource

func before_each() -> void:
	_weapon_snapshot = GameState.equipped_weapon

func after_each() -> void:
	GameState.equipped_weapon = _weapon_snapshot

func test_pool_contains_six_classical_weapons() -> void:
	assert_eq(ChestScript.WEAPON_POOL.size(), 6,
		"6 классических оружий по 2 на стиль")

func test_pool_scenes_all_load() -> void:
	for weapon in ChestScript.WEAPON_POOL:
		assert_not_null(weapon, "все .tres должны быть валидны")
		assert_ne(weapon.display_name, "",
			"каждое оружие имеет i18n display_name")

func test_pool_covers_all_three_styles() -> void:
	var styles: Dictionary = {}
	for weapon in ChestScript.WEAPON_POOL:
		styles[weapon.style] = true
	assert_true(styles.has("warrior"), "pool содержит warrior weapon")
	assert_true(styles.has("archer"), "pool содержит archer weapon")
	assert_true(styles.has("mage"), "pool содержит mage weapon")

func test_pool_excludes_legacy_dagger_pistol_shotgun() -> void:
	# Классический fantasy — старые shooter-оружия не выпадают.
	var pool_paths: Array = []
	for weapon in ChestScript.WEAPON_POOL:
		pool_paths.append(weapon.resource_path)
	for legacy in [
		"res://resources/weapons/dagger.tres",
		"res://resources/weapons/pistol.tres",
		"res://resources/weapons/shotgun.tres",
	]:
		assert_false(pool_paths.has(legacy),
			"legacy %s не должен быть в активном пуле" % legacy)

func test_choose_weapon_does_not_return_current() -> void:
	# Игрок держит short_sword (default стартовое) — сундук не выдаст его же.
	var chest = ChestScript.new()
	# _choose_weapon читает GameState.equipped_weapon.
	GameState.equipped_weapon = preload("res://resources/weapons/short_sword.tres")
	# Гоняем много выборов — ни один не должен быть short_sword.
	for _i in 40:
		var picked = chest._choose_weapon()
		assert_ne(picked.id, "short_sword",
			"сундук не должен выдавать текущее оружие если есть 5 альтернатив")
	chest.free()

func test_choose_weapon_returns_any_when_current_null() -> void:
	# Пограничный случай: если equipped_weapon = null (загрузка сломалась),
	# сундук всё равно должен что-то дать.
	var chest = ChestScript.new()
	GameState.equipped_weapon = null
	var picked = chest._choose_weapon()
	assert_not_null(picked, "даже без current должен вернуть что-то")
	chest.free()

func test_default_weapon_is_short_sword() -> void:
	# Стартовое оружие — short_sword. Подчёркивает переход к fantasy/RPG.
	assert_eq(GameState.DEFAULT_WEAPON.id, "short_sword")
	assert_eq(GameState.DEFAULT_WEAPON.style, "warrior")
	assert_eq(GameState.DEFAULT_WEAPON.attack_type, "melee_arc")
