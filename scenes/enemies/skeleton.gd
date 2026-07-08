extends "res://scenes/enemies/enemy.gd"

# Скелет-меле с рандомным оружием: unarmed / dagger (wood, iron) /
# sword (wood, iron). Разные оружия дают bonus к contact_damage
# и подкрашивают спрайт tint'ом из SkeletonArsenal.

const SkeletonArsenal = preload("res://scenes/enemies/skeleton_arsenal.gd")

func _ready() -> void:
	var variant: Dictionary = SkeletonArsenal.pick(SkeletonArsenal.MELEE_VARIANTS)
	display_name = variant["display_key"]
	# Bonus применяется ДО super._ready(), чтобы Balance.scaled_damage
	# в базовом _ready увидел уже увеличенный contact_damage и умножил
	# по этажу правильно.
	contact_damage += variant["damage_bonus"]
	super._ready()
	var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
	if visual != null:
		visual.modulate = variant["tint"]
