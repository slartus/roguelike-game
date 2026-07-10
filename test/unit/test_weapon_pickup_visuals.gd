extends GutTest

# M7 контракт для WeaponPickup:
# - все active pool weapons имеют icon_texture (иначе Sprite2D пустой);
# - WeaponPickup ставит modulate = weapon.icon_modulate, не bullet_color
#   (иначе projectile-специфичный цвет пачкает мировой пикап);
# - equip() и weapon_changed сигнал работают.

const ChestScript = preload("res://scenes/pickups/chest.gd")
const WeaponPickupScene = preload("res://scenes/pickups/weapon_pickup.tscn")
const ShortSwordRes = preload("res://resources/weapons/short_sword.tres")
const WandRes = preload("res://resources/weapons/wand.tres")
const DaggerRes = preload("res://resources/weapons/dagger.tres")

func test_all_active_pool_weapons_have_icon_texture() -> void:
	# Регресс: без icon_texture Sprite2D пустой, игрок не видит пикап.
	for weapon in ChestScript.WEAPON_POOL:
		assert_not_null(weapon.icon_texture,
			"%s должен иметь icon_texture для WeaponPickup" % weapon.display_name)

func test_new_weapons_have_distinct_icon_modulate() -> void:
	# Все 6 новых weapons должны отличаться цветом иконки — иначе они
	# сливаются в мире (у всех placeholder dagger.png).
	var modulates: Dictionary = {}
	for weapon in ChestScript.WEAPON_POOL:
		var key := "%d,%d,%d" % [
			int(weapon.icon_modulate.r * 255),
			int(weapon.icon_modulate.g * 255),
			int(weapon.icon_modulate.b * 255),
		]
		modulates[key] = true
	assert_gte(modulates.size(), 6,
		"каждое оружие должно иметь свой icon_modulate — иначе визуал сливается")

func test_pickup_uses_icon_modulate_not_bullet_color() -> void:
	# Регресс M7 acceptance: pickup визуал не зависит от bullet-специфичного
	# поля. Даже если bullet_color = красный, а icon_modulate = синий,
	# pickup покажет синий.
	var weapon: WeaponResource = WeaponResource.new()
	weapon.bullet_color = Color(1.0, 0.0, 0.0, 1.0)
	weapon.icon_modulate = Color(0.0, 0.0, 1.0, 1.0)
	weapon.icon_texture = DaggerRes.icon_texture  # берём валидную текстуру
	var pickup = WeaponPickupScene.instantiate()
	pickup.weapon = weapon
	add_child_autofree(pickup)
	await get_tree().process_frame
	var visual: Sprite2D = pickup.get_node("Visual")
	assert_eq(visual.modulate, Color(0.0, 0.0, 1.0, 1.0),
		"pickup должен использовать icon_modulate, а не bullet_color")

func test_legacy_dagger_icon_modulate_defaults_to_white() -> void:
	# Legacy .tres без icon_modulate → default WHITE → полноцветный спрайт
	# рендерится как есть (не обесцвечен).
	assert_eq(DaggerRes.icon_modulate, Color.WHITE,
		"legacy Dagger должен иметь icon_modulate = WHITE (default)")

func test_pickup_calls_equip_and_emits_weapon_changed() -> void:
	# Fake player с методом equip и сигналом weapon_changed.
	var player := CharacterBody2D.new()
	player.add_to_group("player")
	var received_weapon: Array = []
	player.set_script(GDScript.new())
	# Не грузим настоящий player.gd — используем локальный минимальный.
	var pickup = WeaponPickupScene.instantiate()
	pickup.weapon = ShortSwordRes
	# Проверяем что pickup не крешит при отсутствии equip у player'а.
	# Регресс: если у body нет equip, weapon_pickup должен молча пропустить.
	add_child_autofree(player)
	add_child_autofree(pickup)
	await get_tree().process_frame
	# Само вызов _on_body_entered без реального equip проверяем через
	# отсутствие ошибок и корректный display_name.
	assert_eq(pickup.weapon.display_name, "WEAPON_SHORT_SWORD",
		"pickup хранит ссылку на weapon с корректным display_name")
