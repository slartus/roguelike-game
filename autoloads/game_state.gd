extends Node

const DEFAULT_MAX_HEALTH: int = 5
const DEFAULT_WEAPON: WeaponResource = preload("res://resources/weapons/dagger.tres")

var current_room_number: int = 1
var player_max_health: int = DEFAULT_MAX_HEALTH
var player_health: int = DEFAULT_MAX_HEALTH
var equipped_weapon: WeaponResource = DEFAULT_WEAPON

func next_room() -> void:
	current_room_number += 1
	get_tree().reload_current_scene()

func reset_run() -> void:
	current_room_number = 1
	player_max_health = DEFAULT_MAX_HEALTH
	player_health = DEFAULT_MAX_HEALTH
	equipped_weapon = DEFAULT_WEAPON
