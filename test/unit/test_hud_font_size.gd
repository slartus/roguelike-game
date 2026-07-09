extends GutTest

# HUD-лейблы игрока (HP, floor, level, xp, gold) должны иметь
# уменьшенный font_size, иначе они перекрывают игровое поле.
# Дефолт Godot — 16; проектный target — 12.

const HudScene = preload("res://scenes/ui/hud.tscn")
const EXPECTED_FONT_SIZE: int = 12
const STAT_LABEL_NAMES: Array[String] = [
	"HealthLabel", "FloorLabel", "LevelLabel", "XpLabel", "GoldLabel",
]

func test_all_stat_labels_have_reduced_font_size() -> void:
	var hud = HudScene.instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	for name in STAT_LABEL_NAMES:
		var label: Label = hud.get_node_or_null(name)
		assert_not_null(label, "HUD должен содержать %s" % name)
		var override: int = label.get_theme_font_size("font_size")
		assert_eq(override, EXPECTED_FONT_SIZE,
			"%s.font_size должен быть %d, а не дефолтный 16" % [name, EXPECTED_FONT_SIZE])
