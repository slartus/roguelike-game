extends RefCounted

# Реестр вариантов оружия для скелетов. Расширяется добавлением
# новых записей в MELEE_VARIANTS / ARROW_VARIANTS — новые «улучшалки»
# просто кладутся сюда с нужными damage_bonus / weight / tint.
#
# Формат одной записи (Dictionary):
#   display_key : String — i18n-ключ для UI/log
#   damage_bonus: int    — прибавка к contact_damage / bullet damage
#   weight      : float  — вес в weighted-random выборе
#   tint        : Color  — modulate спрайта, чтобы визуально различать
#   sprite_path : String — путь к спрайту снаряда (только для ARROW_VARIANTS;
#                          у MELEE_VARIANTS не используется, снаряда нет)
#   attack_radius: float — extended melee-reach в пикселях (только для
#                          MELEE_VARIANTS). 0 = только touch-контакт
#                          (кулаки, кинжал). >0 = меч с досягаемостью.

const MELEE_VARIANTS: Array = [
	{
		"display_key": "ENEMY_SKELETON_UNARMED",
		"damage_bonus": 0,
		"weight": 0.30,
		"tint": Color(1.0, 1.0, 1.0),
		"attack_radius": 0.0,
	},
	{
		"display_key": "ENEMY_SKELETON_DAGGER_WOOD",
		"damage_bonus": 1,
		"weight": 0.22,
		"tint": Color(0.85, 0.65, 0.4),
		"attack_radius": 0.0,
	},
	{
		"display_key": "ENEMY_SKELETON_DAGGER_IRON",
		"damage_bonus": 2,
		"weight": 0.18,
		"tint": Color(0.78, 0.85, 0.95),
		"attack_radius": 0.0,
	},
	{
		"display_key": "ENEMY_SKELETON_SWORD_WOOD",
		"damage_bonus": 2,
		"weight": 0.16,
		"tint": Color(0.75, 0.55, 0.3),
		"attack_radius": 22.0,
	},
	{
		"display_key": "ENEMY_SKELETON_SWORD_IRON",
		"damage_bonus": 3,
		"weight": 0.14,
		"tint": Color(0.68, 0.78, 0.9),
		"attack_radius": 26.0,
	},
]

const ARROW_VARIANTS: Array = [
	{
		"display_key": "ENEMY_SKELETON_ARCHER_WOOD",
		"damage_bonus": 0,
		"weight": 0.6,
		"tint": Color(0.85, 0.65, 0.4),
		"sprite_path": "res://assets/sprites/bullets/arrow_wood.png",
	},
	{
		"display_key": "ENEMY_SKELETON_ARCHER_IRON",
		"damage_bonus": 1,
		"weight": 0.4,
		"tint": Color(0.78, 0.85, 0.95),
		"sprite_path": "res://assets/sprites/bullets/arrow_iron.png",
	},
]

static func pick(variants: Array) -> Dictionary:
	assert(variants.size() > 0, "pick() from empty arsenal")
	var total: float = 0.0
	for v in variants:
		total += v["weight"]
	var roll: float = randf() * total
	var acc: float = 0.0
	for v in variants:
		acc += v["weight"]
		if roll <= acc:
			return v
	return variants[variants.size() - 1]
