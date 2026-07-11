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
	# Регресс: _apply_weapon_visual пробрасывает icon_modulate из ресурса
	# в Sprite2D.modulate. У всех 9 оружий сейчас icon_modulate = WHITE
	# (каждое имеет свой цветной icon_texture), но контракт «modulate идёт
	# из ресурса» должен продолжать работать для будущих кастомных случаев.
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_eq(weapon_sprite.modulate, ShortSwordRes.icon_modulate,
		"Weapon sprite modulate = weapon.icon_modulate")

func test_equip_updates_weapon_sprite_texture() -> void:
	# Смена оружия в игре: pickup → equip → Weapon-нода перерисовывается
	# с новой текстурой. Раньше проверяли modulate (для placeholder-эры
	# когда все использовали dagger.png), теперь у каждого свой спрайт —
	# сравниваем именно texture.
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	var before_texture := weapon_sprite.texture
	player.equip(ShortBowRes)
	assert_ne(weapon_sprite.texture, before_texture,
		"после equip другого оружия texture обновляется")
	assert_eq(weapon_sprite.texture, ShortBowRes.icon_texture)

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

func test_melee_weapon_has_rest_tilt() -> void:
	# Меч/кинжал/копьё в rest pose наклонены под небольшим углом —
	# читается как «оружие в руке», а не «клинок торчит из плеча».
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_ne(weapon_sprite.rotation, 0.0,
		"melee weapon в rest должен быть наклонён (rotation != 0)")

func test_projectile_weapon_has_no_rest_tilt() -> void:
	# Лук/арбалет/пистолет в rest — вертикально, наклон только у melee.
	GameState.equipped_weapon = ShortBowRes
	var player := _make_player()
	await get_tree().process_frame
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_almost_eq(weapon_sprite.rotation, 0.0, 0.001,
		"projectile weapon в rest не наклоняется")

func test_face_right_puts_weapon_on_right_side() -> void:
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	player.face(1)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_gt(weapon_sprite.position.x, 0.0,
		"при facing right оружие рендерится справа от игрока")
	assert_false(weapon_sprite.flip_h,
		"facing right — sprite не отражён")

func test_face_left_puts_weapon_on_left_side() -> void:
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	player.face(-1)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_lt(weapon_sprite.position.x, 0.0,
		"при facing left оружие рендерится слева от игрока")
	assert_true(weapon_sprite.flip_h,
		"facing left — sprite отражён по горизонтали")

func test_face_left_flips_melee_rest_rotation_sign() -> void:
	# Rest-угол умножается на _facing: при взгляде вправо клинок наклонён
	# вправо-вверх, при взгляде влево — влево-вверх. Симметрично.
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	player.face(1)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	var rot_right := weapon_sprite.rotation
	player.face(-1)
	assert_almost_eq(weapon_sprite.rotation, -rot_right, 0.001,
		"rest rotation симметричен при смене facing")

func test_face_change_during_swing_kills_tween_and_resets_rest() -> void:
	# Регресс: `_apply_facing_visuals` пишет rotation напрямую. Если facing
	# меняется посреди активного swing tween (out+back = 180ms), tween
	# захватит старый rest_rot как back-target и вернёт rotation в чужой
	# знак. Фикс: face() убивает активный swing и мгновенно ставит sprite
	# в свежую rest-позу под новый facing.
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	player.face(1)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	var rest_right := weapon_sprite.rotation
	# Запускаем swing → tween живёт ~180ms.
	player.play_attack_visual(Vector2(100, 0), ShortSwordRes)
	# Игрок в этот момент разворачивается влево — свинг должен оборваться,
	# rotation мгновенно уйти к rest под facing left (симметричный знак).
	player.face(-1)
	assert_almost_eq(weapon_sprite.rotation, -rest_right, 0.001,
		"смена facing во время swing мгновенно ставит новый rest_rotation")
