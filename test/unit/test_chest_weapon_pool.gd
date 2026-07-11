extends GutTest

# Fantasy weapon pool после roster overhaul:
# - 7 fantasy-оружий: warrior×3 (dagger/sword/spear), archer×2 (bow/crossbow),
#   mage×2 (wand/staff);
# - Pistol/Shotgun удалены из проекта — legacy shooter-контент срезан;
# - Dagger теперь melee_arc warrior-оружие, входит в общий пул;
# - _choose_weapon НЕ возвращает текущее оружие если есть альтернатива;
# - стартовое оружие игрока = short_sword.

const ChestScript = preload("res://scenes/pickups/chest.gd")

var _weapon_snapshot: WeaponResource

func before_each() -> void:
	_weapon_snapshot = GameState.equipped_weapon

func after_each() -> void:
	GameState.equipped_weapon = _weapon_snapshot

func test_pool_contains_seven_fantasy_weapons() -> void:
	assert_eq(ChestScript.WEAPON_POOL.size(), 7,
		"7 fantasy оружий: warrior×3 + archer×2 + mage×2")

func test_pool_scenes_all_load() -> void:
	for weapon in ChestScript.WEAPON_POOL:
		assert_not_null(weapon, "все .tres должны быть валидны")
		assert_ne(weapon.display_name, "",
			"каждое оружие имеет i18n display_name")

func test_pool_covers_all_three_styles_with_expected_counts() -> void:
	var counts: Dictionary = {"warrior": 0, "archer": 0, "mage": 0}
	for weapon in ChestScript.WEAPON_POOL:
		counts[weapon.style] = counts.get(weapon.style, 0) + 1
	assert_eq(counts["warrior"], 3, "3 warrior weapons")
	assert_eq(counts["archer"], 2, "2 archer weapons")
	assert_eq(counts["mage"], 2, "2 mage weapons")

func test_pool_excludes_removed_firearms() -> void:
	# Pistol/Shotgun удалены из проекта — соответствующие .tres в pool
	# ссылаться не должны, а их id больше нигде не мелькает.
	var pool_ids: Array = []
	for weapon in ChestScript.WEAPON_POOL:
		pool_ids.append(weapon.id)
	for removed in ["pistol", "shotgun"]:
		assert_false(pool_ids.has(removed),
			"removed weapon '%s' не должен быть в pool" % removed)

func test_pool_contains_dagger_as_warrior_melee_arc() -> void:
	# Регресс: после миграции Dagger обязан быть в пуле как melee_arc.
	var dagger: WeaponResource = null
	for weapon in ChestScript.WEAPON_POOL:
		if weapon.id == "dagger":
			dagger = weapon
			break
	assert_not_null(dagger, "Dagger должен быть в pool")
	assert_eq(dagger.style, "warrior", "Dagger — warrior style")
	assert_eq(dagger.attack_type, "melee_arc", "Dagger — melee_arc")

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
