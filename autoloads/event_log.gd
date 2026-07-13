extends Node

# Combat log event bus. HUD подписывается на entry_added и отрисовывает
# сообщения с автоматическим fade-out. Сущности вызывают типизированные
# log_* методы; строки берутся из TranslationServer через tr(KEY).

signal entry_added(text: String, tint: Color)

const KILL_TINT: Color = Color(1.0, 0.85, 0.45)
const HEAL_TINT: Color = Color(0.55, 1.0, 0.65)
const WEAPON_TINT: Color = Color(0.75, 0.85, 1.0)
const CHEST_TINT: Color = Color(0.95, 0.75, 0.30)
const FLOOR_TINT: Color = Color(0.95, 0.95, 0.70)
const BOSS_TINT: Color = Color(1.0, 0.50, 0.50)
const LEVEL_TINT: Color = Color(1.0, 0.65, 0.85)
const SEED_TINT: Color = Color(0.70, 0.85, 0.95)

const DEFAULT_LOCALE: String = "ru"

func _ready() -> void:
	TranslationServer.set_locale(DEFAULT_LOCALE)

func log_kill(enemy_key: String, xp: int, gold: int) -> void:
	var name := tr(enemy_key)
	var text: String
	if xp > 0 and gold > 0:
		text = tr("LOG_KILL_WITH_GOLD") % [name, xp, gold]
	elif xp > 0:
		text = tr("LOG_KILL_XP_ONLY") % [name, xp]
	else:
		text = tr("LOG_KILL_PLAIN") % [name]
	entry_added.emit(text, KILL_TINT)

func log_heal(amount: int) -> void:
	entry_added.emit(tr("LOG_HEAL") % amount, HEAL_TINT)

func log_potion_pickup() -> void:
	entry_added.emit(tr("LOG_POTION_PICKUP"), HEAL_TINT)

func log_weapon_pickup(weapon_key: String) -> void:
	var name := tr(weapon_key)
	entry_added.emit(tr("LOG_WEAPON_PICKUP") % name, WEAPON_TINT)

func log_chest_open() -> void:
	entry_added.emit(tr("LOG_CHEST_OPEN"), CHEST_TINT)

func log_floor(number: int) -> void:
	entry_added.emit(tr("LOG_FLOOR") % number, FLOOR_TINT)

func log_boss_floor(number: int) -> void:
	entry_added.emit(tr("LOG_BOSS_FLOOR") % number, BOSS_TINT)

func log_level_up(new_level: int) -> void:
	entry_added.emit(tr("LOG_LEVEL_UP") % new_level, LEVEL_TINT)

func log_tower_seed(seed_value: int) -> void:
	entry_added.emit(tr("LOG_TOWER_SEED") % seed_value, SEED_TINT)

func log_upgrade_selected(display_name: String) -> void:
	# Тот же tint что у level-up — семантически связано.
	entry_added.emit(tr("LOG_UPGRADE_SELECTED") % display_name, LEVEL_TINT)

# --- Environment interactions (PR4) ---
const LORE_TINT: Color = Color(0.80, 0.85, 0.65)
const PROP_DROP_TINT: Color = Color(0.95, 0.80, 0.50)
const HAZARD_TINT: Color = Color(1.0, 0.60, 0.40)

# Prompt отображается один раз, пока игрок в диапазоне lore prop'а.
# HUD.combat log просто печатает строку с fade-out — этого хватит для
# MVP без специальной UI-панели.
func log_lore_prompt(prompt_key: String) -> void:
	if prompt_key.is_empty():
		return
	entry_added.emit(tr(prompt_key), LORE_TINT)

func log_lore_text(text_key: String) -> void:
	if text_key.is_empty():
		return
	entry_added.emit(tr(text_key), LORE_TINT)

func log_prop_drop(result: StringName, amount: int) -> void:
	var key := "LOG_PROP_DROP_%s" % String(result).to_upper()
	entry_added.emit(tr(key) % amount, PROP_DROP_TINT)

func log_hazard_explosion() -> void:
	entry_added.emit(tr("LOG_HAZARD_EXPLOSION"), HAZARD_TINT)
