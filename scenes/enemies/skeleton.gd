extends "res://scenes/enemies/enemy.gd"

# Скелет-меле с рандомным оружием: unarmed / dagger (wood, iron) /
# sword (wood, iron). Разные оружия дают bonus к contact_damage,
# подкрашивают спрайт tint'ом и меч даёт extended attack_radius.
# При успешном ударе играется короткая lunge-анимация (скачок
# спрайта вперёд-назад) — визуальный feedback замаха.

const SkeletonArsenal = preload("res://scenes/enemies/skeleton_arsenal.gd")

const LUNGE_DISTANCE: float = 10.0
const LUNGE_OUT_DURATION: float = 0.08
const LUNGE_BACK_DURATION: float = 0.14
# Свинг оружия — Weapon-нода поворачивается на угол «замаха».
# Пивот у Weapon в hilt (см. _apply_weapon_sprite offset), поэтому
# положительный угол вращает клинок вправо-вниз, читаемо как удар.
const WEAPON_SWING_ANGLE: float = PI * 0.55

var _visual_base_position: Vector2 = Vector2.ZERO
var _lunge_tween: Tween
# Профиль вызова свиты. Задаётся боссом через configure_summon() ДО
# add_child(). Если null — скелет спавнится обычным путём (floor mob).
var _summon_profile: SummonedCreatureProfile

func configure_summon(profile: SummonedCreatureProfile) -> void:
	# Вызвать ДО add_child(). После add_child() Godot запускает _ready(),
	# где стоит super._ready() → Balance.scaled_damage / temperament
	# resolve, и «поздний» override уже не подхватится.
	_summon_profile = profile
	monster_level = maxi(1, profile.monster_level)
	elite_rank = maxi(0, profile.elite_rank)
	# `configure_spawn`-семантика (детерминированный seed для темперамента
	# всё равно нужен, даже если override будет применён — resolve_id
	# проверяет override первым).
	temperament_seed = 0
	_has_explicit_seed = true
	if profile.temperament_id != &"":
		temperament_id = profile.temperament_id

func _ready() -> void:
	var pool: Array = SkeletonArsenal.MELEE_VARIANTS
	if _summon_profile != null and not _summon_profile.arsenal_pool.is_empty():
		pool = _summon_profile.arsenal_pool
	var variant: Dictionary = SkeletonArsenal.pick(pool)
	display_name = variant["display_key"]
	# Bonus применяется ДО super._ready(), чтобы Balance.scaled_damage
	# в базовом _ready увидел уже увеличенный contact_damage и умножил
	# по этажу правильно.
	contact_damage += variant["damage_bonus"]
	attack_radius = variant.get("attack_radius", 0.0)
	super._ready()
	# --- Summon guard: применяется ПОСЛЕ Balance.scaled_* и temperament,
	# чтобы окончательные значения не превысили заявленный cap даже
	# при будущих изменениях Balance. Cм. plans/necromancer-minion-rebalance.
	if _summon_profile != null:
		if not _summon_profile.grants_xp:
			xp_reward = 0
		if not _summon_profile.grants_gold:
			gold_reward = 0
		if not _summon_profile.grants_drops:
			pickup_scene = null
		if _summon_profile.max_damage > 0:
			contact_damage = mini(contact_damage, _summon_profile.max_damage)
	var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
	if visual != null:
		visual.modulate = variant["tint"]
		_visual_base_position = visual.position
	_apply_weapon_sprite(variant.get("weapon_sprite", ""))
	attack_played.connect(_play_lunge_animation)

# Роль миньона в свите босса. Используется boss.gd для раздельного
# учёта живых minion'ов по квоте (3 melee / 2 ranged). Возвращает
# пустой StringName для обычного скелета вне boss-summon'а.
func get_summon_role() -> StringName:
	return _summon_profile.summon_role if _summon_profile != null else &""

func _apply_weapon_sprite(sprite_path: String) -> void:
	# Weapon-нода в skeleton.tscn стартует со `visible = false` — она
	# либо получает нужную текстуру и «включается» (для варианта с
	# оружием), либо остаётся скрытой (безоружный).
	var weapon: Sprite2D = get_node_or_null("Weapon") as Sprite2D
	if weapon == null:
		return
	if sprite_path.is_empty():
		weapon.visible = false
		return
	var tex := load(sprite_path) as Texture2D
	if tex == null:
		weapon.visible = false
		return
	weapon.texture = tex
	# Смещаем sprite вниз на пол-высоты — визуальный центр остаётся
	# на месте, но Node2D.position теперь совпадает с hilt (верх
	# клинка). При Node2D.rotation оружие вращается вокруг рукояти,
	# а не вокруг середины клинка (последнее выглядело бы как «летит»
	# вокруг ниоткуда).
	weapon.offset = Vector2(0, tex.get_height() * 0.5)
	weapon.visible = true

func _play_lunge_animation(target_position: Vector2) -> void:
	var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
	if visual == null:
		return
	# Отменяем предыдущий tween, чтобы новый удар прервал старую
	# анимацию — иначе визуал может «застрять» в промежуточной точке.
	if _lunge_tween != null and _lunge_tween.is_valid():
		_lunge_tween.kill()
	var direction := (target_position - global_position).normalized()
	if direction == Vector2.ZERO:
		return
	var lunge_offset := _visual_base_position + direction * LUNGE_DISTANCE
	_lunge_tween = create_tween()
	# Параллельные треки: тело делает рывок вперёд-назад, оружие в это
	# же время рубит по дуге. Через .set_parallel(true) следующие
	# tween_property идут одновременно с предыдущим.
	_lunge_tween.tween_property(visual, "position", lunge_offset, LUNGE_OUT_DURATION)
	var weapon: Sprite2D = get_node_or_null("Weapon") as Sprite2D
	if weapon != null and weapon.visible:
		_lunge_tween.parallel().tween_property(weapon, "rotation", WEAPON_SWING_ANGLE, LUNGE_OUT_DURATION)
	_lunge_tween.tween_property(visual, "position", _visual_base_position, LUNGE_BACK_DURATION)
	if weapon != null and weapon.visible:
		_lunge_tween.parallel().tween_property(weapon, "rotation", 0.0, LUNGE_BACK_DURATION)
