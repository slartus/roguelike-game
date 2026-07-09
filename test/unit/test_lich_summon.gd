extends GutTest

# Lich призывает одного скелета за раз.
# - первый призыв — через SUMMON_COOLDOWN после спавна;
# - пока миньон жив, новый не призывается;
# - как только миньон невалиден (queue_freed / удалён из дерева),
#   через SUMMON_COOLDOWN появляется следующий;
# - призванные скелеты не дают XP/gold и не роняют пикапы, иначе
#   лич превращается в фарм-точку.

const LichScene = preload("res://scenes/enemies/lich.tscn")

func _spawn_lich():
	var lich = LichScene.instantiate()
	add_child_autofree(lich)
	return lich

func test_no_immediate_summon_at_spawn() -> void:
	var lich = _spawn_lich()
	assert_null(lich._summoned_minion,
		"сразу после спавна лич ещё не призвал никого")
	assert_almost_eq(lich._summon_cooldown_timer, lich.SUMMON_COOLDOWN, 0.001,
		"кулдаун стартует полным")

func test_summon_after_cooldown_expires() -> void:
	var lich = _spawn_lich()
	lich._summon_cooldown_timer = 0.01
	lich._update_summon(0.05)
	assert_not_null(lich._summoned_minion,
		"по истечении кулдауна лич призывает скелета")
	assert_almost_eq(lich._summon_cooldown_timer, lich.SUMMON_COOLDOWN, 0.001,
		"кулдаун сбрасывается на новую константу после призыва")

func test_does_not_summon_while_minion_alive() -> void:
	var lich = _spawn_lich()
	# Форсируем «есть живой миньон» и обнуляем кулдаун — второй призыв
	# не должен случиться.
	var minion = Node2D.new()
	add_child_autofree(minion)
	lich._summoned_minion = minion
	lich._summon_cooldown_timer = 0.0
	lich._update_summon(0.05)
	# Ссылка не поменялась — второй скелет не заспавнен.
	assert_eq(lich._summoned_minion, minion,
		"при живом миньоне лич не призывает ещё одного")

func test_new_summon_after_minion_dies_plus_cooldown() -> void:
	var lich = _spawn_lich()
	var minion = Node2D.new()
	add_child_autofree(minion)
	lich._summoned_minion = minion
	minion.queue_free()
	await get_tree().process_frame  # даём queue_free сработать
	# Теперь _summoned_minion — freed reference; is_instance_valid = false.
	lich._summon_cooldown_timer = 0.0
	lich._update_summon(0.05)
	# Ссылка обновилась на новую живую ноду.
	assert_not_null(lich._summoned_minion)
	assert_ne(lich._summoned_minion, minion,
		"после смерти миньона призывается НОВЫЙ, не тот же самый")

func test_summoned_skeleton_has_no_rewards() -> void:
	var lich = _spawn_lich()
	lich._summon_cooldown_timer = 0.0
	lich._update_summon(0.05)
	var minion = lich._summoned_minion
	assert_eq(minion.xp_reward, 0,
		"призванные скелеты не должны давать XP")
	assert_eq(minion.gold_reward, 0,
		"призванные скелеты не должны давать gold")
	assert_null(minion.pickup_scene,
		"призванные скелеты не должны ронять пикапы")
	# Убираем миньон вручную, чтобы не оставить в дереве.
	minion.queue_free()
