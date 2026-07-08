extends GutTest

# Регресс на размер шрифта action-лога в HUD.
# Пользователь просил мелкий шрифт (изначально 10, теперь 8),
# и не хотелось бы вернуть большой значением случайно.

const HudScript = preload("res://scenes/ui/hud.gd")

func test_log_font_size_is_small() -> void:
	assert_lte(HudScript.LOG_FONT_SIZE, 10,
		"Шрифт лога должен оставаться мелким — пользователь просил уменьшить")
	assert_gte(HudScript.LOG_FONT_SIZE, 6,
		"Слишком мелко: 5 и меньше уже нечитаемо на 1080p")

func test_log_max_entries_is_positive() -> void:
	assert_gt(HudScript.LOG_MAX_ENTRIES, 0)
