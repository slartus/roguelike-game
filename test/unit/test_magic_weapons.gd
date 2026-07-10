extends GutTest

# Mage оружия v1: spell_projectile без маны.
# - Apprentice Staff: медленный, damage=3, спокойный snare-cast;
# - Wand: быстрый, damage=1, лёгкий spread;
# - оба mana_cost=0 (в v1 mana ещё не завели);
# - spell_projectile использует тот же projectile-путь, что и archer.

const StaffRes = preload("res://resources/weapons/apprentice_staff.tres")
const WandRes = preload("res://resources/weapons/wand.tres")
const BulletScene = preload("res://scenes/bullets/bullet.tscn")
const WeaponControllerScript = preload("res://scenes/player/weapon_controller.gd")

func test_apprentice_staff_loads_and_is_mage() -> void:
	assert_not_null(StaffRes)
	assert_eq(StaffRes.id, "apprentice_staff")
	assert_eq(StaffRes.style, "mage")
	assert_eq(StaffRes.attack_type, "spell_projectile")
	assert_gt(StaffRes.damage, 0)
	assert_eq(StaffRes.display_name, "WEAPON_APPRENTICE_STAFF")

func test_wand_loads_and_is_mage() -> void:
	assert_not_null(WandRes)
	assert_eq(WandRes.id, "wand")
	assert_eq(WandRes.style, "mage")
	assert_eq(WandRes.attack_type, "spell_projectile")
	assert_eq(WandRes.display_name, "WEAPON_WAND")

func test_mage_weapons_have_zero_mana_cost_in_v1() -> void:
	# M5 не завозит систему маны — mana_cost=0 обязателен, чтобы будущий
	# WeaponController.canCast не заблокировал каст.
	assert_eq(StaffRes.mana_cost, 0)
	assert_eq(WandRes.mana_cost, 0)

func test_wand_faster_than_staff_but_weaker() -> void:
	# Дизайн M5: wand — быстрый лёгкий cast, staff — медленный тяжёлый.
	assert_lt(WandRes.get_attack_interval(), StaffRes.get_attack_interval(),
		"wand стреляет чаще")
	assert_gt(StaffRes.damage, WandRes.damage,
		"staff бьёт сильнее")

func test_spell_projectile_creates_bullet_via_controller() -> void:
	# spell_projectile идёт по тому же _attack_projectile path, что и
	# обычный projectile. Проверим что controller не крешит на mage weapon.
	var owner_player := CharacterBody2D.new()
	add_child_autofree(owner_player)
	var wc = WeaponControllerScript.new()
	wc.default_projectile_scene = BulletScene
	owner_player.add_child(wc)
	wc.setup(owner_player)
	var attacked := wc.try_attack(StaffRes, Vector2(100, 0))
	assert_true(attacked,
		"spell_projectile должен пройти через _attack_projectile")
	# Cleanup bullet чтобы не оставался.
	await get_tree().process_frame

func test_mage_weapons_have_projectile_color_distinct_from_default() -> void:
	# Регресс: мы задавали projectile_color в .tres — должен быть не
	# дефолтным (иначе визуал магии сольётся с обычной пулей).
	var default_color := Color(1.0, 0.9, 0.3, 1.0)
	assert_ne(StaffRes.get_projectile_color(), default_color,
		"staff snaряд должен визуально отличаться (сине-фиолетовый)")
	assert_ne(WandRes.get_projectile_color(), default_color,
		"wand snaряд должен визуально отличаться (пурпурный)")
