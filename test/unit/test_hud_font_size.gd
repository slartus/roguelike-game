extends GutTest

# HUD-лейблы игрока (gold, floor в BottomRightStats) должны иметь
# уменьшенный font_size, иначе они перекрывают игровое поле.
# Дефолт Godot — 16; проектный target — 12.
# LevelLabel на полосе HP использует более мелкий font_size 10 — проверяется
# в test_hud_layout_reorg.gd::test_level_label_is_child_of_health_bar.
# XpLabel убран из HUD — XP видно только на паузе.
# HealthLabel убран — HP отображается визуальной полосой (см. test_hud_health_bar).

const HudScene = preload("res://scenes/ui/hud.tscn")
const EXPECTED_FONT_SIZE: int = 12
const STAT_LABEL_PATHS: Array[String] = [
	"BottomRightStats/GoldRow/GoldLabel",
	"BottomRightStats/FloorRow/FloorLabel",
]

func test_all_stat_labels_have_reduced_font_size() -> void:
	var hud = HudScene.instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	for label_path in STAT_LABEL_PATHS:
		var label: Label = hud.get_node_or_null(label_path)
		assert_not_null(label, "HUD должен содержать %s" % label_path)
		var override: int = label.get_theme_font_size("font_size")
		assert_eq(override, EXPECTED_FONT_SIZE,
			"%s.font_size должен быть %d, а не дефолтный 16" % [label_path, EXPECTED_FONT_SIZE])
