extends "res://scenes/enemies/enemy.gd"

# Скелет-меле с рандомным оружием: unarmed / dagger (wood, iron) /
# sword (wood, iron). Разные оружия дают bonus к contact_damage,
# подкрашивают спрайт tint'ом и меч даёт extended attack_radius.
# При успешном ударе играется короткая lunge-анимация (скачок
# спрайта вперёд-назад) — визуальный feedback замаха.

const SkeletonArsenal = preload("res://scenes/enemies/skeleton_arsenal.gd")

const LUNGE_DISTANCE: float = 4.0
const LUNGE_OUT_DURATION: float = 0.06
const LUNGE_BACK_DURATION: float = 0.10

var _visual_base_position: Vector2 = Vector2.ZERO
var _lunge_tween: Tween

func _ready() -> void:
	var variant: Dictionary = SkeletonArsenal.pick(SkeletonArsenal.MELEE_VARIANTS)
	display_name = variant["display_key"]
	# Bonus применяется ДО super._ready(), чтобы Balance.scaled_damage
	# в базовом _ready увидел уже увеличенный contact_damage и умножил
	# по этажу правильно.
	contact_damage += variant["damage_bonus"]
	attack_radius = variant.get("attack_radius", 0.0)
	super._ready()
	var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
	if visual != null:
		visual.modulate = variant["tint"]
		_visual_base_position = visual.position
	_apply_weapon_sprite(variant.get("weapon_sprite", ""))
	attack_played.connect(_play_lunge_animation)

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
	_lunge_tween.tween_property(visual, "position", lunge_offset, LUNGE_OUT_DURATION)
	_lunge_tween.tween_property(visual, "position", _visual_base_position, LUNGE_BACK_DURATION)
