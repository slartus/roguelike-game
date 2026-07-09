extends "res://scenes/enemies/ranged_enemy.gd"

# Скелет-лучник со стрелами разного tier'а: wooden / iron. Iron даёт
# +1 к damage выстрела, подкрашивает лучника серо-стальным tint'ом и
# использует спрайт стрелы с металлическим древком (arrow_iron.png)
# вместо деревянного (arrow_wood.png).

const SkeletonArsenal = preload("res://scenes/enemies/skeleton_arsenal.gd")

var _arrow_damage_bonus: int = 0
var _arrow_texture: Texture2D

func _ready() -> void:
	var variant: Dictionary = SkeletonArsenal.pick(SkeletonArsenal.ARROW_VARIANTS)
	display_name = variant["display_key"]
	_arrow_damage_bonus = variant["damage_bonus"]
	_arrow_texture = load(variant["sprite_path"]) as Texture2D
	super._ready()
	var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
	if visual != null:
		visual.modulate = variant["tint"]

func _configure_bullet(bullet: Node) -> void:
	if _arrow_damage_bonus != 0 and bullet.get("damage") != null:
		bullet.damage += _arrow_damage_bonus
	if _arrow_texture != null:
		var bullet_visual: Sprite2D = bullet.get_node_or_null("Visual") as Sprite2D
		if bullet_visual != null:
			bullet_visual.texture = _arrow_texture
