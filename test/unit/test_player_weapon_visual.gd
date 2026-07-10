extends GutTest

# Модель оружия и анимация взмаха у игрока:
# - при equip() Weapon-нода получает icon_texture и icon_modulate;
# - без weapon — Weapon-нода скрыта;
# - play_attack_visual играет tween без крешей;
# - для projectile-оружия свинг оружия не играется, только выпад тела.

const PlayerScene = preload("res://scenes/player/player.tscn")
const ShortSwordRes = preload("res://resources/weapons/short_sword.tres")
const ShortBowRes = preload("res://resources/weapons/short_bow.tres")
const DaggerRes = preload("res://resources/weapons/dagger.tres")

var _snapshot: Dictionary

func before_each() -> void:
	_snapshot = {
		"weapon": GameState.equipped_weapon,
	}

func after_each() -> void:
	GameState.equipped_weapon = _snapshot.weapon

func _make_player() -> Node:
	# Player при _ready берёт stat из GameState — снаружи ничего специально
	# настраивать не нужно.
	var player: Node = PlayerScene.instantiate()
	add_child_autofree(player)
	return player

func test_weapon_sprite_hidden_when_no_weapon() -> void:
	# Регресс: если игрок стартует без оружия (edge case reset), Weapon-нода
	# не должна показывать placeholder-текстуру.
	GameState.equipped_weapon = null
	var player := _make_player()
	await get_tree().process_frame
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_false(weapon_sprite.visible,
		"без equipped weapon Weapon-нода скрыта")

func test_weapon_sprite_visible_after_equip() -> void:
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_true(weapon_sprite.visible,
		"с equipped weapon Weapon-нода видна")
	assert_not_null(weapon_sprite.texture)

func test_weapon_sprite_modulate_matches_icon_modulate() -> void:
	# Регресс: mage/warrior/archer оружия отличаются в мире и в руке
	# именно через icon_modulate (пока placeholder-иконка одинаковая).
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_eq(weapon_sprite.modulate, ShortSwordRes.icon_modulate,
		"Weapon sprite modulate = weapon.icon_modulate")

func test_equip_updates_weapon_sprite_texture() -> void:
	# Смена оружия в игре: pickup → equip → Weapon-нода перерисовывается.
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	var before_modulate := weapon_sprite.modulate
	player.equip(ShortBowRes)
	# equip → _apply_weapon_visual → modulate обновлён.
	assert_ne(weapon_sprite.modulate, before_modulate,
		"после equip другого оружия icon_modulate обновляется")
	assert_eq(weapon_sprite.modulate, ShortBowRes.icon_modulate)

func test_play_attack_visual_does_not_crash_for_melee() -> void:
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	# Не крешит и создаёт tween.
	player.play_attack_visual(Vector2(100, 0), ShortSwordRes)
	# Дадим кадр чтобы tween инициализировался, но не ждём завершения.
	await get_tree().process_frame
	assert_true(is_instance_valid(player), "player жив, tween не крешит")

func test_play_attack_visual_does_not_swing_weapon_for_projectile() -> void:
	# Для projectile-оружия свинг оружия не запускается — только выпад
	# тела. Weapon-нода остаётся с rotation = 0.
	GameState.equipped_weapon = ShortBowRes
	var player := _make_player()
	await get_tree().process_frame
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	player.play_attack_visual(Vector2(50, 0), ShortBowRes)
	await get_tree().process_frame
	assert_almost_eq(weapon_sprite.rotation, 0.0, 0.001,
		"для лука Weapon-нода не вращается")

func test_play_attack_visual_zero_direction_is_safe() -> void:
	# Регресс: клик в текущую позицию игрока → direction Vector2.ZERO,
	# tween не создаётся, ошибок нет.
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	player.play_attack_visual(player.global_position, ShortSwordRes)
	assert_true(is_instance_valid(player),
		"nulled direction — safe no-op, player не крешит")

func test_legacy_dagger_still_shows_weapon_sprite() -> void:
	# Backward compat: legacy Dagger имеет icon_texture — должна отображаться.
	GameState.equipped_weapon = DaggerRes
	var player := _make_player()
	await get_tree().process_frame
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_true(weapon_sprite.visible,
		"legacy Dagger рисуется в руке игрока")
