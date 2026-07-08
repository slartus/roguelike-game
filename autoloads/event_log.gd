extends Node

# Combat log event bus. HUD подписывается на entry_added и отрисовывает
# сообщения с автоматическим fade-out. Сущности вызывают типизированные
# log_* методы; строки берутся из TranslationServer через tr(KEY).

signal entry_added(text: String, tint: Color)

const KILL_TINT: Color = Color(1.0, 0.85, 0.45)
const HEAL_TINT: Color = Color(0.55, 1.0, 0.65)
const WEAPON_TINT: Color = Color(0.75, 0.85, 1.0)
const CHEST_TINT: Color = Color(0.95, 0.75, 0.30)
const ROOM_TINT: Color = Color(0.95, 0.95, 0.70)
const BOSS_TINT: Color = Color(1.0, 0.50, 0.50)
const LEVEL_TINT: Color = Color(1.0, 0.65, 0.85)

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

func log_weapon_pickup(weapon_key: String) -> void:
	var name := tr(weapon_key)
	entry_added.emit(tr("LOG_WEAPON_PICKUP") % name, WEAPON_TINT)

func log_chest_open() -> void:
	entry_added.emit(tr("LOG_CHEST_OPEN"), CHEST_TINT)

func log_room(number: int) -> void:
	entry_added.emit(tr("LOG_ROOM") % number, ROOM_TINT)

func log_boss_room(number: int) -> void:
	entry_added.emit(tr("LOG_BOSS_ROOM") % number, BOSS_TINT)

func log_level_up(new_level: int) -> void:
	entry_added.emit(tr("LOG_LEVEL_UP") % new_level, LEVEL_TINT)
