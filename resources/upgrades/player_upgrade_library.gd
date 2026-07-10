class_name PlayerUpgradeLibrary
extends RefCounted

# Реестр всех upgrade cards. Загружает .tres файлы из UPGRADE_PATHS и
# предоставляет API для offer generator (M4) и валидации (M1).
#
# Библиотека stateless и загружается лениво — при первом обращении.
# GameState держит собственный run-state; library только справочник.

const UPGRADE_PATHS := []  # Заполнится в M6/M7 при добавлении карт.

const VALID_RARITIES := ["common", "uncommon", "rare"]
const VALID_STYLES := ["", "warrior", "archer", "mage"]
# Известные effect_type. Расширяется по мере добавления карт (M6/M7).
const KNOWN_EFFECT_TYPES := [
	"max_health_bonus",
	"speed_multiplier",
	"potion_heal_bonus",
	"slow_resistance",
	"poison_resistance",
	"second_wind",
	"style_damage_bonus",
	"melee_range_multiplier",
	"melee_arc_multiplier",
	"knockback_bonus",
	"style_attack_interval_multiplier",
	"pierce_bonus",
	"spread_multiplier",
	"projectile_speed_multiplier",
	"projectile_lifetime_multiplier",
	"area_radius_multiplier",
]

static var _cache: Array = []

# Возвращает все загруженные upgrade resources. Кеш заполняется один раз.
static func get_all_upgrades() -> Array:
	if _cache.is_empty():
		_cache = _load_all()
	return _cache

# Только для тестов: сбрасывает кеш, чтобы можно было проверить fresh load.
static func clear_cache_for_testing() -> void:
	_cache = []

static func get_upgrade_by_id(upgrade_id: String) -> PlayerUpgradeResource:
	for upgrade in get_all_upgrades():
		if upgrade.id == upgrade_id:
			return upgrade
	return null

# Валидация. Возвращает Array[String] — список ошибок. Пусто = OK.
static func validate_all() -> Array:
	var errors: Array = []
	var seen_ids := {}
	for upgrade in get_all_upgrades():
		if upgrade.id.is_empty() or upgrade.id == "unknown":
			errors.append("upgrade без явного id")
			continue
		if seen_ids.has(upgrade.id):
			errors.append("duplicate id: %s" % upgrade.id)
		seen_ids[upgrade.id] = true
		if not upgrade.display_name.begins_with("UPGRADE_"):
			errors.append("%s: display_name должен быть UPPER_SNAKE_CASE ключ (UPGRADE_*)" % upgrade.id)
		if not upgrade.description.begins_with("UPGRADE_"):
			errors.append("%s: description должен быть UPGRADE_* ключ" % upgrade.id)
		if upgrade.max_stacks < 1:
			errors.append("%s: max_stacks должен быть >= 1" % upgrade.id)
		if not VALID_RARITIES.has(upgrade.rarity):
			errors.append("%s: unknown rarity '%s'" % [upgrade.id, upgrade.rarity])
		if not VALID_STYLES.has(upgrade.style):
			errors.append("%s: unknown style '%s'" % [upgrade.id, upgrade.style])
		if not KNOWN_EFFECT_TYPES.has(upgrade.effect_type):
			errors.append("%s: unknown effect_type '%s'" % [upgrade.id, upgrade.effect_type])
	return errors

# Возвращает карточки, которые ещё можно предложить (не max stacks,
# style поддерживается).
# `current_stacks`: Dictionary { upgrade_id: int }.
static func get_eligible_upgrades(current_stacks: Dictionary) -> Array:
	var eligible: Array = []
	for upgrade in get_all_upgrades():
		var stacks: int = int(current_stacks.get(upgrade.id, 0))
		if stacks >= upgrade.max_stacks:
			continue
		eligible.append(upgrade)
	return eligible

static func _load_all() -> Array:
	var loaded: Array = []
	for path in UPGRADE_PATHS:
		var res := load(path) as PlayerUpgradeResource
		if res != null:
			loaded.append(res)
	return loaded
