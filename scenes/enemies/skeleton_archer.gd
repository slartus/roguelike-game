extends "res://scenes/enemies/ranged_enemy.gd"

# Скелет-лучник со стрелами разного tier'а: wooden / iron. Iron даёт
# +1 к damage выстрела, подкрашивает лучника серо-стальным tint'ом и
# использует спрайт стрелы с металлическим древком (arrow_iron.png)
# вместо деревянного (arrow_wood.png).

const SkeletonArsenal = preload("res://scenes/enemies/skeleton_arsenal.gd")

var _arrow_damage_bonus: int = 0
var _arrow_texture: Texture2D

func _ready() -> void:
	var pool: Array = SkeletonArsenal.ARROW_VARIANTS
	if _summon_profile != null and not _summon_profile.arsenal_pool.is_empty():
		pool = _summon_profile.arsenal_pool
	var variant: Dictionary = SkeletonArsenal.pick(pool)
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
	# Hard cap на damage стрелы: даже wooden+iron bonus'ы не должны
	# случайно превысить cap профиля (текущий: 2 у necromancer_ranged).
	# Проверяем «bullet имеет field damage» через get() → null-check,
	# т.к. базовые Godot Node2D не имеют такого свойства.
	if _summon_profile != null and _summon_profile.max_damage > 0 and bullet.get("damage") != null:
		bullet.damage = mini(bullet.damage, _summon_profile.max_damage)
	if _arrow_texture != null:
		var bullet_visual: Sprite2D = bullet.get_node_or_null("Visual") as Sprite2D
		if bullet_visual != null:
			bullet_visual.texture = _arrow_texture
