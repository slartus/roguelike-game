extends GutTest

# Тесты проверяют русские переводы (default locale в EventLog._ready).
# Локаль явно фиксируется в before_each на случай изоляции между тестами.

var _texts: Array = []
var _tints: Array = []
var _saved_locale: String

func before_each() -> void:
	_saved_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	_texts = []
	_tints = []
	EventLog.entry_added.connect(_on_entry)

func after_each() -> void:
	if EventLog.entry_added.is_connected(_on_entry):
		EventLog.entry_added.disconnect(_on_entry)
	TranslationServer.set_locale(_saved_locale)

func _on_entry(text: String, tint: Color) -> void:
	_texts.append(text)
	_tints.append(tint)

func test_log_kill_includes_xp_and_gold() -> void:
	EventLog.log_kill("ENEMY_SLIME", 5, 1)
	assert_eq(_texts[0], "Убит Слизень (+5 XP, +1 золото)")
	assert_eq(_tints[0], EventLog.KILL_TINT)

func test_log_kill_without_gold_omits_gold_suffix() -> void:
	EventLog.log_kill("ENEMY_SPIDER", 8, 0)
	assert_eq(_texts[0], "Убит Паук (+8 XP)")

func test_log_kill_with_zero_rewards_still_reports() -> void:
	EventLog.log_kill("ENEMY_GOBLIN", 0, 0)
	assert_eq(_texts[0], "Убит Гоблин")

func test_log_heal_format() -> void:
	EventLog.log_heal(1)
	assert_eq(_texts[0], "+1 HP")
	assert_eq(_tints[0], EventLog.HEAL_TINT)

func test_log_weapon_pickup_format() -> void:
	EventLog.log_weapon_pickup("WEAPON_SHOTGUN")
	assert_eq(_texts[0], "Взято оружие: Дробовик")
	assert_eq(_tints[0], EventLog.WEAPON_TINT)

func test_log_chest_open_format() -> void:
	EventLog.log_chest_open()
	assert_eq(_texts[0], "Открыт сундук")
	assert_eq(_tints[0], EventLog.CHEST_TINT)

func test_log_floor_format() -> void:
	EventLog.log_floor(3)
	assert_eq(_texts[0], "Этаж 3")
	assert_eq(_tints[0], EventLog.FLOOR_TINT)

func test_log_boss_floor_format() -> void:
	EventLog.log_boss_floor(5)
	assert_eq(_texts[0], "Босс — этаж 5!")
	assert_eq(_tints[0], EventLog.BOSS_TINT)

func test_log_level_up_format() -> void:
	EventLog.log_level_up(2)
	assert_eq(_texts[0], "Уровень 2!")
	assert_eq(_tints[0], EventLog.LEVEL_TINT)

func test_english_locale_translates_correctly() -> void:
	TranslationServer.set_locale("en")
	EventLog.log_kill("ENEMY_SLIME", 5, 1)
	assert_eq(_texts[0], "Killed Slime (+5 XP, +1 gold)")
	EventLog.log_heal(2)
	assert_eq(_texts[1], "+2 HP")
	EventLog.log_floor(3)
	assert_eq(_texts[2], "Floor 3")

func test_multiple_entries_are_reported_in_order() -> void:
	EventLog.log_floor(1)
	EventLog.log_kill("ENEMY_GOBLIN", 6, 2)
	EventLog.log_heal(1)
	assert_eq(_texts.size(), 3)
	assert_eq(_texts[0], "Этаж 1")
	assert_eq(_texts[1], "Убит Гоблин (+6 XP, +2 золото)")
	assert_eq(_texts[2], "+1 HP")
