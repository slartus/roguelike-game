extends GutTest

# После spawn скелет должен показать оружие в руке (Weapon-нода)
# согласно выпавшему варианту. Безоружный — Weapon скрыт.
# Тест проходит через несколько spawn'ов чтобы поймать оба случая.

const SkeletonScene = preload("res://scenes/enemies/skeleton.tscn")
const Arsenal = preload("res://scenes/enemies/skeleton_arsenal.gd")

func test_weapon_node_reflects_variant() -> void:
	# 30 спавнов покрывают все 5 вариантов с высокой вероятностью
	# (weights от 0.14 до 0.30). Проверяем инвариант: если display_name
	# указывает на вооружённого — Weapon visible + texture из варианта;
	# если безоружного — Weapon hidden.
	var by_key: Dictionary = {}
	for v in Arsenal.MELEE_VARIANTS:
		by_key[v["display_key"]] = v
	for i in 30:
		var skeleton = SkeletonScene.instantiate()
		add_child_autofree(skeleton)
		await get_tree().process_frame
		var variant: Dictionary = by_key[skeleton.display_name]
		var expected_path: String = variant["weapon_sprite"]
		var weapon: Sprite2D = skeleton.get_node("Weapon")
		if expected_path == "":
			assert_false(weapon.visible,
				"безоружный %s: Weapon должен быть скрыт" % skeleton.display_name)
		else:
			assert_true(weapon.visible,
				"%s: Weapon должен быть виден" % skeleton.display_name)
			assert_not_null(weapon.texture,
				"%s: Weapon должен иметь texture" % skeleton.display_name)
			assert_eq(weapon.texture.resource_path, expected_path,
				"%s: Weapon.texture должен соответствовать weapon_sprite" % skeleton.display_name)
