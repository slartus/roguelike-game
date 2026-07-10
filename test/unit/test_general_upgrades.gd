extends GutTest

# M6 general upgrade cards:
# Thick Skin — max HP;
# Light Boots — speed;
# Potion Mastery — potion heal;
# Sure Footing — slow resistance;
# Antidote Blood — poison duration multiplier;
# Second Wind — survive lethal damage once per floor.

const PlayerScene = preload("res://scenes/player/player.tscn")
const ThickSkin = preload("res://resources/upgrades/general/thick_skin.tres")
const LightBoots = preload("res://resources/upgrades/general/light_boots.tres")
const PotionMastery = preload("res://resources/upgrades/general/potion_mastery.tres")
const SureFooting = preload("res://resources/upgrades/general/sure_footing.tres")
const AntidoteBlood = preload("res://resources/upgrades/general/antidote_blood.tres")
const SecondWind = preload("res://resources/upgrades/general/second_wind.tres")

var _snapshot: Dictionary

func before_each() -> void:
	_snapshot = {
		"stacks": GameState.player_upgrade_stacks.duplicate(),
		"max_hp": GameState.player_max_health,
		"hp": GameState.player_health,
		"potions": GameState.health_potions,
		"second_wind": GameState.second_wind_used_this_floor,
	}
	GameState.player_upgrade_stacks = {}
	GameState.player_max_health = 5
	GameState.player_health = 5
	GameState.health_potions = 0
	GameState.second_wind_used_this_floor = false

func after_each() -> void:
	GameState.player_upgrade_stacks = _snapshot.stacks
	GameState.player_max_health = _snapshot.max_hp
	GameState.player_health = _snapshot.hp
	GameState.health_potions = _snapshot.potions
	GameState.second_wind_used_this_floor = _snapshot.second_wind

func _make_player() -> Node:
	var p: Node = PlayerScene.instantiate()
	add_child_autofree(p)
	return p

func test_all_general_upgrades_load() -> void:
	for u in [ThickSkin, LightBoots, PotionMastery, SureFooting, AntidoteBlood, SecondWind]:
		assert_not_null(u, "upgrade должен грузиться")
		assert_ne(u.id, "unknown")
		assert_true(u.style == "", "все general upgrades → style пустой")

func test_thick_skin_increases_max_hp_immediately() -> void:
	var before_max := GameState.player_max_health
	var before_hp := GameState.player_health
	GameState.player_health = 3
	GameState.add_player_upgrade(ThickSkin)
	assert_eq(GameState.player_max_health, before_max + 1)
	assert_eq(GameState.player_health, 4,
		"current HP тоже вырос на amount")

func test_light_boots_affects_current_speed() -> void:
	var player := _make_player()
	await get_tree().process_frame
	var speed_before: float = player.current_speed()
	GameState.add_player_upgrade(LightBoots)
	var speed_after: float = player.current_speed()
	assert_gt(speed_after, speed_before,
		"Light Boots увеличивает current_speed")

func test_potion_mastery_increases_potion_heal() -> void:
	var player := _make_player()
	await get_tree().process_frame
	GameState.health_potions = 1
	player.health = 3
	GameState.add_player_upgrade(PotionMastery)
	player._try_use_health_potion()
	# Base heal 1 + potion_mastery 1 = 2 HP.
	assert_eq(player.health, 5, "3 + (1+1) heal = 5")

func test_sure_footing_softens_slow_but_not_immune() -> void:
	var player := _make_player()
	await get_tree().process_frame
	player._slow_source_count = 1
	var speed_with_slow_no_upgrade: float = player.current_speed()
	GameState.add_player_upgrade(SureFooting)
	var speed_with_slow_with_upgrade: float = player.current_speed()
	assert_gt(speed_with_slow_with_upgrade, speed_with_slow_no_upgrade,
		"Sure Footing делает slow мягче")
	# Но не выше базовой (никаких slow-immunity).
	player._slow_source_count = 0
	var normal_speed: float = player.current_speed()
	assert_lte(speed_with_slow_with_upgrade, normal_speed,
		"Sure Footing НЕ должен превысить обычную скорость")

func test_antidote_blood_reduces_poison_duration() -> void:
	var player := _make_player()
	await get_tree().process_frame
	GameState.add_player_upgrade(AntidoteBlood)
	# duration_multiplier = 0.75; apply(3.0) → 2.25.
	player.apply_poison(3.0)
	assert_almost_eq(player._poison_timer, 2.25, 0.01,
		"3.0 × 0.75 = 2.25")

func test_second_wind_prevents_lethal_damage_once() -> void:
	var player := _make_player()
	await get_tree().process_frame
	GameState.add_player_upgrade(SecondWind)
	player.health = 3
	# take_damage 100 — должно бы убить, но Second Wind возвращает 2 HP.
	player.take_damage(100)
	# Not death: player жив, HP > 0.
	assert_true(is_instance_valid(player),
		"Second Wind spared player from death")
	assert_gt(player.health, 0)
	assert_true(GameState.second_wind_used_this_floor,
		"charge потрачен")
	await get_tree().create_timer(0.15).timeout

func test_second_wind_does_not_trigger_twice_same_floor() -> void:
	var player := _make_player()
	await get_tree().process_frame
	GameState.add_player_upgrade(SecondWind)
	player.health = 3
	player.take_damage(100)  # первый триггер
	assert_true(GameState.second_wind_used_this_floor)
	# Второй летальный удар — уже без Second Wind. Метод _try_trigger_second_wind
	# должен вернуть false. take_damage приведёт к _die (который вызывает
	# get_tree().call_deferred change_scene), но player сначала потеряет HP.
	# В этом тесте проверяем что _try_trigger_second_wind не срабатывает
	# через direct API.
	assert_false(player._try_trigger_second_wind(),
		"Second Wind не триггерится второй раз на этаже")
	await get_tree().create_timer(0.15).timeout

func test_second_wind_charge_resets_after_reset_run() -> void:
	GameState.second_wind_used_this_floor = true
	var seed_snapshot := GameState.tower_seed
	GameState.reset_run()
	assert_false(GameState.second_wind_used_this_floor,
		"reset_run восстанавливает charge")
	GameState.tower_seed = seed_snapshot
