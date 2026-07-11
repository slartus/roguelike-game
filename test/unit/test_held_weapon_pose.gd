extends GutTest

# PR 3: Held weapon visuals and attack presentation.
#
# WeaponResource получает held-metadata (held_texture, held_scale,
# held_aim_aligned, held_rest_rotation, held_aim_rotation_offset).
# Player._update_weapon_pose(aim_direction) следует курсору для
# aim-aligned оружий (лук, арбалет, копьё, жезл, посох); side-rest
# оружия (меч, кинжал) держатся под rest-углом.
# Z-order: при aim вверх оружие уходит за спину игрока.
# Attack visual: melee_arc → swing, melee_thrust → thrust,
# projectile → recoil, spell_projectile → cast pulse.

const PlayerScene = preload("res://scenes/player/player.tscn")
const DaggerRes = preload("res://resources/weapons/dagger.tres")
const ShortSwordRes = preload("res://resources/weapons/short_sword.tres")
const SpearRes = preload("res://resources/weapons/spear.tres")
const ShortBowRes = preload("res://resources/weapons/short_bow.tres")
const CrossbowRes = preload("res://resources/weapons/crossbow.tres")
const WandRes = preload("res://resources/weapons/wand.tres")
const StaffRes = preload("res://resources/weapons/apprentice_staff.tres")

var _snapshot: Dictionary

func before_each() -> void:
	_snapshot = {"weapon": GameState.equipped_weapon}

func after_each() -> void:
	GameState.equipped_weapon = _snapshot.weapon

func _make_player() -> Node:
	var player: Node = PlayerScene.instantiate()
	add_child_autofree(player)
	return player

# --- Held texture fallback ---

func test_get_held_texture_returns_icon_when_held_not_set() -> void:
	# Все текущие 7 .tres не задают held_texture — get_held_texture()
	# должен возвращать icon_texture (backward compat).
	for weapon in [DaggerRes, ShortSwordRes, SpearRes, ShortBowRes,
			CrossbowRes, WandRes, StaffRes]:
		assert_eq(weapon.get_held_texture(), weapon.icon_texture,
			"%s: get_held_texture должен фолбэкнуться на icon_texture" % weapon.display_name)

func test_get_held_texture_returns_held_when_set() -> void:
	# Синтетический weapon с явным held_texture — helper возвращает его.
	var w := WeaponResource.new()
	w.icon_texture = DaggerRes.icon_texture
	w.held_texture = ShortSwordRes.icon_texture  # любой отличный texture
	assert_eq(w.get_held_texture(), ShortSwordRes.icon_texture)

# --- Aim-aligned rotation ---

func test_bow_aim_aligned_true_by_default() -> void:
	# Bow нарисован «вверх», но при aim направляется на цель.
	assert_true(ShortBowRes.held_aim_aligned, "short_bow — aim-aligned")

func test_crossbow_aim_aligned_true_by_default() -> void:
	assert_true(CrossbowRes.held_aim_aligned, "crossbow — aim-aligned")

func test_spear_aim_aligned_true_by_default() -> void:
	assert_true(SpearRes.held_aim_aligned, "spear — aim-aligned (thrust смотрит на цель)")

func test_wand_aim_aligned_true_by_default() -> void:
	assert_true(WandRes.held_aim_aligned)

func test_sword_and_dagger_are_side_rest() -> void:
	# Меч и кинжал держатся под rest-углом от facing, не следуют курсору.
	assert_false(ShortSwordRes.held_aim_aligned, "sword — side-rest")
	assert_false(DaggerRes.held_aim_aligned, "dagger — side-rest")

func test_aim_right_rotates_bow_to_horizontal_right() -> void:
	# aim direction (1,0) → angle 0 → rotation = 0 + PI/2 = PI/2 (sprite
	# нарисован «вверх», offset +PI/2 разворачивает к правой стороне).
	GameState.equipped_weapon = ShortBowRes
	var player := _make_player()
	await get_tree().process_frame
	player.face(1)
	player._update_weapon_pose(Vector2.RIGHT)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_almost_eq(weapon_sprite.rotation, PI / 2, 0.001,
		"bow aim right → rotation ≈ PI/2 (blade вправо)")

func test_aim_down_rotates_bow_to_vertical_down() -> void:
	GameState.equipped_weapon = ShortBowRes
	var player := _make_player()
	await get_tree().process_frame
	player.face(1)
	player._update_weapon_pose(Vector2.DOWN)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	# angle(0,1) = PI/2, +PI/2 offset = PI
	assert_almost_eq(weapon_sprite.rotation, PI, 0.001,
		"bow aim down → rotation ≈ PI")

func test_aim_up_rotates_bow_to_vertical_up_zero() -> void:
	GameState.equipped_weapon = ShortBowRes
	var player := _make_player()
	await get_tree().process_frame
	player.face(1)
	player._update_weapon_pose(Vector2.UP)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	# angle(0,-1) = -PI/2, +PI/2 offset = 0 → sprite вверх
	assert_almost_eq(weapon_sprite.rotation, 0.0, 0.001,
		"bow aim up → rotation ≈ 0 (blade вверх)")

func test_sword_rotation_not_affected_by_aim_direction() -> void:
	# Side-rest sword держится под rest-углом даже при разных aim.
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	player.face(1)
	var rest_rotation := ShortSwordRes.held_rest_rotation
	player._update_weapon_pose(Vector2.RIGHT)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_almost_eq(weapon_sprite.rotation, rest_rotation, 0.001,
		"sword rest под aim right — тот же rest angle")
	player._update_weapon_pose(Vector2.UP)
	assert_almost_eq(weapon_sprite.rotation, rest_rotation, 0.001,
		"sword rest под aim up — тот же rest angle")

# --- Z-order layering ---

func test_weapon_goes_behind_body_when_aiming_up() -> void:
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	player._update_weapon_pose(Vector2.UP)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_true(weapon_sprite.show_behind_parent,
		"aim вверх → оружие уходит за спрайт игрока")

func test_weapon_in_front_when_aiming_down() -> void:
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	player._update_weapon_pose(Vector2.DOWN)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_false(weapon_sprite.show_behind_parent,
		"aim вниз → оружие перед игроком")

func test_weapon_in_front_when_aiming_right() -> void:
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	player._update_weapon_pose(Vector2.RIGHT)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_false(weapon_sprite.show_behind_parent,
		"aim вправо → оружие перед игроком")

func test_layering_transitions_at_threshold() -> void:
	# Порог -0.25 y-компоненты: aim (1, -0.2).normalized() → y ≈ -0.196,
	# всё ещё «перед». aim (1, -0.5).normalized() → y ≈ -0.447, «сзади».
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	player._update_weapon_pose(Vector2(1, -0.2).normalized())
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_false(weapon_sprite.show_behind_parent,
		"aim y=-0.196 (выше threshold -0.25) → всё ещё перед")
	player._update_weapon_pose(Vector2(1, -0.5).normalized())
	assert_true(weapon_sprite.show_behind_parent,
		"aim y=-0.447 (ниже threshold -0.25) → за спрайтом")

# --- Attack animation dispatch по attack_type ---

func test_melee_thrust_does_not_swing_weapon() -> void:
	# Spear (melee_thrust) не должен вращать оружие как sword — он тычет.
	# Rotation остаётся близкой к rest после старта thrust'а.
	# Spear aim-aligned — вырубаем physics_process для детерминизма.
	GameState.equipped_weapon = SpearRes
	var player := _make_player()
	await get_tree().process_frame
	player.set_physics_process(false)
	player.face(1)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	var pre_rotation := weapon_sprite.rotation
	player.play_attack_visual(player.global_position + Vector2(50, 0), SpearRes)
	await get_tree().process_frame
	# Thrust не крутит; rotation почти совпадает с pre (может слегка
	# отличаться из-за tween start-frame — 0.02 rad терпимо).
	assert_almost_eq(weapon_sprite.rotation, pre_rotation, 0.05,
		"melee_thrust не крутит оружие, только сдвигает вперёд")

func test_projectile_recoil_does_not_swing_weapon() -> void:
	# Bow (projectile) не крутит оружие при выстреле — только recoil (сдвиг
	# назад). Aim-aligned bow крутится через _update_weapon_pose в
	# physics_process — вырубаем физику для детерминизма.
	GameState.equipped_weapon = ShortBowRes
	var player := _make_player()
	await get_tree().process_frame
	player.set_physics_process(false)
	player.face(1)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	var pre_rotation := weapon_sprite.rotation
	player.play_attack_visual(player.global_position + Vector2(50, 0), ShortBowRes)
	await get_tree().process_frame
	assert_almost_eq(weapon_sprite.rotation, pre_rotation, 0.05,
		"projectile не крутит оружие")

func test_spell_cast_pulses_scale_but_not_rotation() -> void:
	# Wand aim-aligned — same трюк с отключением physics_process.
	GameState.equipped_weapon = WandRes
	var player := _make_player()
	await get_tree().process_frame
	player.set_physics_process(false)
	player.face(1)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	var pre_rotation := weapon_sprite.rotation
	player.play_attack_visual(player.global_position + Vector2(50, 0), WandRes)
	await get_tree().process_frame
	assert_almost_eq(weapon_sprite.rotation, pre_rotation, 0.05,
		"spell cast не крутит оружие, только pulse scale")

func test_melee_arc_swings_weapon() -> void:
	GameState.equipped_weapon = ShortSwordRes
	var player := _make_player()
	await get_tree().process_frame
	player.face(1)
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	var pre_rotation := weapon_sprite.rotation
	player.play_attack_visual(player.global_position + Vector2(50, 0), ShortSwordRes)
	# После нескольких frame'ов tween успевает изменить rotation значительно.
	for _i in 5:
		await get_tree().process_frame
	assert_true(absf(weapon_sprite.rotation - pre_rotation) > 0.3,
		"melee_arc должен крутить оружие по дуге (rotation изменился на >0.3)")

# --- face() убивает tween для всех attack types ---

func _assert_face_kills_tween(weapon: WeaponResource) -> void:
	# Регресс: face() должен убить _swing_tween при смене facing —
	# иначе back-фаза анимации восстановит pose под старый facing.
	# Проверяем для каждого attack_type: thrust/recoil/cast/arc идут через
	# один и тот же _swing_tween, но контракт стоит закрепить тестом.
	GameState.equipped_weapon = weapon
	var player := _make_player()
	await get_tree().process_frame
	player.set_physics_process(false)
	player.face(1)
	player.play_attack_visual(player.global_position + Vector2(50, 0), weapon)
	# Активный tween должен быть валиден сразу после play_attack_visual.
	assert_true(player._swing_tween != null and player._swing_tween.is_valid(),
		"tween должен быть валиден после play_attack_visual (%s)" % weapon.id)
	# Смена facing → tween убивается.
	player.face(-1)
	assert_true(player._swing_tween == null or not player._swing_tween.is_valid(),
		"face() должен убить tween для %s" % weapon.id)

func test_face_kills_tween_for_melee_thrust() -> void:
	await _assert_face_kills_tween(SpearRes)

func test_face_kills_tween_for_projectile() -> void:
	await _assert_face_kills_tween(ShortBowRes)

func test_face_kills_tween_for_spell_cast() -> void:
	await _assert_face_kills_tween(WandRes)

func test_face_kills_tween_for_melee_arc() -> void:
	# Existing test уже покрывает через test_face_change_during_swing_kills_tween_and_resets_rest,
	# но дублируем ради полноты dispatch-матрицы.
	await _assert_face_kills_tween(ShortSwordRes)

# --- Held scale (dagger smaller than sword) ---

func test_dagger_held_scale_smaller_than_sword() -> void:
	assert_lt(DaggerRes.held_scale.x, ShortSwordRes.held_scale.x,
		"Dagger должен быть визуально меньше меча (held_scale.x)")
	assert_lt(DaggerRes.held_scale.y, ShortSwordRes.held_scale.y)

func test_dagger_held_scale_applied_to_sprite() -> void:
	GameState.equipped_weapon = DaggerRes
	var player := _make_player()
	await get_tree().process_frame
	var weapon_sprite: Sprite2D = player.get_node("Weapon")
	assert_eq(weapon_sprite.scale, DaggerRes.held_scale,
		"Weapon sprite scale должен взять held_scale ресурса")

# --- Hand offset backward compat ---

func test_hand_offset_defaults_match_original_constants() -> void:
	# WeaponResource дефолт (5, 3) должен совпадать с бывшими
	# HAND_X/Y_OFFSET константами в player.gd.
	var w := WeaponResource.new()
	assert_eq(w.held_hand_offset, Vector2(5, 3),
		"дефолт held_hand_offset совместим со старым HAND_X/Y_OFFSET")
