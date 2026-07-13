class_name EconomyCounters
extends RefCounted

# Per-floor экономика: источники gold, лечение, зелья, сундуки.
# Хранится в RunAnalyticsState.economy, сбрасывается в start_floor.

# Gold sources.
var gold_from_enemies: int = 0
var gold_from_chests: int = 0
var gold_from_props: int = 0
var gold_from_bosses: int = 0

# Potions.
var potions_received: int = 0
var potions_used: int = 0
var potions_remaining_at_floor_end: int = 0
var healing_received: int = 0
var overheal: int = 0
var deaths_with_potion_available: int = 0

# Chests / weapon offers.
var chests_opened: int = 0
var weapons_offered: int = 0
var weapons_picked: int = 0

func total_gold() -> int:
	return gold_from_enemies + gold_from_chests + gold_from_props + gold_from_bosses

func to_dictionary() -> Dictionary:
	return {
		"gold_enemy": gold_from_enemies,
		"gold_chest": gold_from_chests,
		"gold_props": gold_from_props,
		"gold_boss": gold_from_bosses,
		"gold_total": total_gold(),
		"potions_received": potions_received,
		"potions_used": potions_used,
		"potions_remaining": potions_remaining_at_floor_end,
		"healing_received": healing_received,
		"overheal": overheal,
		"deaths_with_potion_available": deaths_with_potion_available,
		"chests_opened": chests_opened,
		"weapons_offered": weapons_offered,
		"weapons_picked": weapons_picked,
	}

func reset() -> void:
	gold_from_enemies = 0
	gold_from_chests = 0
	gold_from_props = 0
	gold_from_bosses = 0
	potions_received = 0
	potions_used = 0
	potions_remaining_at_floor_end = 0
	healing_received = 0
	overheal = 0
	deaths_with_potion_available = 0
	chests_opened = 0
	weapons_offered = 0
	weapons_picked = 0
