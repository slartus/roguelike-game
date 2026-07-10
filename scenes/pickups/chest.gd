extends Area2D

# Классический fantasy-пул. Dagger/Pistol/Shotgun (legacy shooter-стиль)
# остаются в проекте как ресурсы, но выведены из активного chest pool —
# они не должны выпадать в новой RPG-игре.
const WEAPON_POOL: Array[WeaponResource] = [
	preload("res://resources/weapons/short_sword.tres"),
	preload("res://resources/weapons/spear.tres"),
	preload("res://resources/weapons/short_bow.tres"),
	preload("res://resources/weapons/crossbow.tres"),
	preload("res://resources/weapons/apprentice_staff.tres"),
	preload("res://resources/weapons/wand.tres"),
]
const PICKUP_SCENE: PackedScene = preload("res://scenes/pickups/weapon_pickup.tscn")

@export var closed_texture: Texture2D
@export var open_texture: Texture2D

@onready var _visual: Sprite2D = $Visual

var _opened: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if _visual != null and closed_texture != null:
		_visual.texture = closed_texture

func _on_body_entered(body: Node) -> void:
	if _opened:
		return
	if not body.is_in_group("player"):
		return
	_opened = true
	if _visual != null and open_texture != null:
		_visual.texture = open_texture
	# monitoring = false внутри signal callback запрещён — Godot требует
	# set_deferred для Area2D свойств во время in/out сигналов.
	set_deferred("monitoring", false)
	EventLog.log_chest_open()
	_spawn_pickup()

func _spawn_pickup() -> void:
	var chosen: WeaponResource = _choose_weapon()
	var pickup := PICKUP_SCENE.instantiate()
	pickup.weapon = chosen
	pickup.global_position = global_position + Vector2(0, 14)
	get_tree().current_scene.add_child.call_deferred(pickup)

# Не выдаём текущее оружие игрока — сундук всегда даёт что-то новое,
# кроме случая когда альтернатив нет (пул из одного элемента).
# Сравнение по id, а не по ссылке — .tres могут прийти из разных путей
# загрузки (например, save/load).
func _choose_weapon() -> WeaponResource:
	var current := GameState.equipped_weapon
	if current == null or WEAPON_POOL.size() <= 1:
		return WEAPON_POOL.pick_random()
	var alternatives: Array[WeaponResource] = []
	for weapon in WEAPON_POOL:
		if weapon.id != current.id:
			alternatives.append(weapon)
	if alternatives.is_empty():
		return WEAPON_POOL.pick_random()
	return alternatives.pick_random()
