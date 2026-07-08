extends Node

const SAVE_PATH: String = "user://save.cfg"

const DEFAULT_MAX_HEALTH: int = 5
const DEFAULT_WEAPON: WeaponResource = preload("res://resources/weapons/dagger.tres")
const HEALTH_PER_LEVEL: int = 1

signal xp_changed(current: int, max_for_level: int)
signal leveled_up(new_level: int, new_max_health: int)
signal gold_changed(total: int)

var current_floor_number: int = 1
var player_max_health: int = DEFAULT_MAX_HEALTH
var player_health: int = DEFAULT_MAX_HEALTH
var equipped_weapon: WeaponResource = DEFAULT_WEAPON
var player_level: int = 1
var player_xp: int = 0

# Master seed забега. Один raw int определяет весь layout всех этажей.
# Floor использует tower_seed для формулы seed(floor) = tower_seed * PRIME + floor.
# Reset_run генерирует новый случайный tower_seed.
var tower_seed: int = 0

var total_gold: int = 0

func _ready() -> void:
	tower_seed = _pick_random_tower_seed()
	_load()

func _pick_random_tower_seed() -> int:
	# Uniform в [0, 2^31 - 1]. Достаточно широкий диапазон для практики,
	# и легко копируется/вводится игроком.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(0, 2147483647)

func next_floor() -> void:
	current_floor_number += 1
	get_tree().reload_current_scene()

func reset_run() -> void:
	current_floor_number = 1
	player_max_health = DEFAULT_MAX_HEALTH
	player_health = DEFAULT_MAX_HEALTH
	equipped_weapon = DEFAULT_WEAPON
	player_level = 1
	player_xp = 0
	tower_seed = _pick_random_tower_seed()

func award_xp(amount: int) -> void:
	if amount <= 0:
		return
	player_xp += amount
	while player_xp >= Balance.xp_to_next_level(player_level):
		player_xp -= Balance.xp_to_next_level(player_level)
		_level_up()
	xp_changed.emit(player_xp, Balance.xp_to_next_level(player_level))

func _level_up() -> void:
	player_level += 1
	player_max_health += HEALTH_PER_LEVEL
	player_health = player_max_health
	EventLog.log_level_up(player_level)
	leveled_up.emit(player_level, player_max_health)

func award_gold(amount: int) -> void:
	if amount <= 0:
		return
	total_gold += amount
	gold_changed.emit(total_gold)
	_save()

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "total_gold", total_gold)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Failed to save game state: %s" % err)

func _load() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	total_gold = cfg.get_value("meta", "total_gold", 0)
