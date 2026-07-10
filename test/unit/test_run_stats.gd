extends GutTest

# Окно «Итоги забега» на title screen. Пайплайн:
# 1. Во время run — GameState.award_gold / award_enemy_kill копят run_gold /
#    run_enemies_killed.
# 2. При смерти игрока (Player._die) вызывается GameState.finish_run(),
#    который снимает snapshot (last_run_*) и сбрасывает run state.
# 3. Title screen читает GameState.has_last_run_stats и отображает панель.
#
# Тесты покрывают: подсчёт кила, capture snapshot, clear после клика Play,
# отображение панели на title screen.

const TitleScene = preload("res://scenes/ui/title_screen.tscn")

var _total_gold_saved: int = 0

func before_each() -> void:
	# GameState — autoload, живёт между тестами. Явно чистим, чтобы тесты
	# не наследовали state друг от друга. total_gold сохраняем и
	# восстанавливаем в after_each — это meta-поле, менять его в тестах
	# нельзя (могут упасть тесты save/load, которые зависят от значения).
	_total_gold_saved = GameState.total_gold
	GameState.has_last_run_stats = false
	GameState.last_run_floor = 0
	GameState.last_run_level = 0
	GameState.last_run_gold = 0
	GameState.last_run_enemies_killed = 0
	GameState.run_gold = 0
	GameState.run_enemies_killed = 0
	GameState.current_floor_number = 1
	GameState.player_level = 1

func after_each() -> void:
	GameState.total_gold = _total_gold_saved

# ---- Counters -----------------------------------------------------------

func test_award_enemy_kill_increments_run_counter() -> void:
	GameState.award_enemy_kill()
	GameState.award_enemy_kill()
	GameState.award_enemy_kill()
	assert_eq(GameState.run_enemies_killed, 3,
		"три вызова award_enemy_kill = 3 в run counter")

# ---- Death handlers всех enemy-типов дёргают counter -------------------
# Регрессионный guard: наследники enemy.gd и ranged_enemy.gd (Lich,
# Skeleton Archer) должны вызывать award_enemy_kill при смерти. Проверяем
# на реальных сценах — mock мешал бы обнаружить регрессию.

const EnemyScene = preload("res://scenes/enemies/enemy.tscn")
const RangedEnemyScene = preload("res://scenes/enemies/ranged_enemy.tscn")
const ChargerScene = preload("res://scenes/enemies/charger.tscn")

func _kill_enemy_and_wait(enemy: Node) -> void:
	# take_damage делает await на flash-timer 0.08 s перед queue_free.
	enemy.take_damage(9999)
	await get_tree().create_timer(0.15).timeout

func test_enemy_death_increments_kill_counter() -> void:
	var enemy = EnemyScene.instantiate()
	add_child(enemy)
	await get_tree().process_frame
	await _kill_enemy_and_wait(enemy)
	assert_eq(GameState.run_enemies_killed, 1,
		"смерть обычного enemy → +1 kill")

func test_ranged_enemy_death_increments_kill_counter() -> void:
	# Lich и Skeleton Archer extends ranged_enemy — единый death path.
	var enemy = RangedEnemyScene.instantiate()
	add_child(enemy)
	await get_tree().process_frame
	await _kill_enemy_and_wait(enemy)
	assert_eq(GameState.run_enemies_killed, 1,
		"смерть ranged enemy → +1 kill")

func test_charger_death_increments_kill_counter() -> void:
	var enemy = ChargerScene.instantiate()
	add_child(enemy)
	await get_tree().process_frame
	await _kill_enemy_and_wait(enemy)
	assert_eq(GameState.run_enemies_killed, 1,
		"смерть charger (Spider) → +1 kill")

func test_award_gold_increments_both_total_and_run() -> void:
	var total_before: int = GameState.total_gold
	GameState.award_gold(10)
	GameState.award_gold(5)
	assert_eq(GameState.run_gold, 15,
		"run_gold накапливается за забег")
	assert_eq(GameState.total_gold, total_before + 15,
		"total_gold растёт независимо (meta)")

# ---- finish_run captures snapshot ---------------------------------------

func test_finish_run_captures_snapshot_of_current_state() -> void:
	GameState.current_floor_number = 7
	GameState.player_level = 4
	GameState.run_gold = 123
	GameState.run_enemies_killed = 42
	GameState.finish_run()
	assert_true(GameState.has_last_run_stats,
		"finish_run поднимает флаг has_last_run_stats")
	assert_eq(GameState.last_run_floor, 7)
	assert_eq(GameState.last_run_level, 4)
	assert_eq(GameState.last_run_gold, 123)
	assert_eq(GameState.last_run_enemies_killed, 42)

func test_finish_run_resets_current_run_state() -> void:
	# После снятия snapshot'а run state должен обнулиться.
	GameState.current_floor_number = 7
	GameState.player_level = 4
	GameState.run_gold = 123
	GameState.run_enemies_killed = 42
	GameState.finish_run()
	assert_eq(GameState.current_floor_number, 1)
	assert_eq(GameState.player_level, 1)
	assert_eq(GameState.run_gold, 0)
	assert_eq(GameState.run_enemies_killed, 0)

func test_reset_run_alone_does_not_capture_snapshot() -> void:
	# reset_run — чистое обнуление, без capture. Так title screen не
	# показывает «пустое» окно после клика «Играть» на свежий запуск.
	GameState.current_floor_number = 5
	GameState.run_gold = 50
	GameState.reset_run()
	assert_false(GameState.has_last_run_stats,
		"reset_run сам по себе не выставляет has_last_run_stats")

func test_clear_last_run_stats_hides_panel_flag() -> void:
	GameState.finish_run()
	assert_true(GameState.has_last_run_stats)
	GameState.clear_last_run_stats()
	assert_false(GameState.has_last_run_stats,
		"clear_last_run_stats снимает show-once флаг")

# ---- Title screen shows panel -------------------------------------------

func test_title_screen_shows_panel_after_finish_run() -> void:
	GameState.current_floor_number = 3
	GameState.player_level = 2
	GameState.run_gold = 15
	GameState.run_enemies_killed = 8
	GameState.finish_run()
	var screen = TitleScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var panel: PanelContainer = screen.get_node("VBox/RunStatsPanel")
	assert_true(panel.visible,
		"панель итогов должна быть видна после смерти игрока")
	# Тексты содержат числа snapshot'а. Проверяем что цифры прошли (без
	# сравнения через tr(), т.к. .translation могут отличаться в тестах).
	var floor_lbl: Label = screen.get_node("VBox/RunStatsPanel/RunStatsBox/RunStatsFloor")
	var lvl_lbl: Label = screen.get_node("VBox/RunStatsPanel/RunStatsBox/RunStatsLevel")
	var kills_lbl: Label = screen.get_node("VBox/RunStatsPanel/RunStatsBox/RunStatsKills")
	var gold_lbl: Label = screen.get_node("VBox/RunStatsPanel/RunStatsBox/RunStatsGold")
	assert_true(floor_lbl.text.contains("3"),
		"floor label должен показать snapshot floor=3, actual='%s'" % floor_lbl.text)
	assert_true(lvl_lbl.text.contains("2"),
		"level label должен показать snapshot level=2, actual='%s'" % lvl_lbl.text)
	assert_true(kills_lbl.text.contains("8"),
		"kills label должен показать 8, actual='%s'" % kills_lbl.text)
	assert_true(gold_lbl.text.contains("15"),
		"gold label должен показать 15, actual='%s'" % gold_lbl.text)

func test_title_screen_hides_panel_without_stats() -> void:
	# Свежий запуск, run ещё не был — окно скрыто.
	var screen = TitleScene.instantiate()
	add_child_autofree(screen)
	await get_tree().process_frame
	var panel: PanelContainer = screen.get_node("VBox/RunStatsPanel")
	assert_false(panel.visible,
		"без has_last_run_stats панель скрыта")
