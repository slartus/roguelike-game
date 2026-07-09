extends GutTest

# HealthPickup всегда подбирается в инвентарь (`GameState.health_potions`),
# независимо от текущего HP игрока. Активация — через клавишу «1»
# в player.gd::_try_use_health_potion (там проверка «HP < max»).

const HealthPickupScene = preload("res://scenes/pickups/health_pickup.tscn")

class FakePlayer:
	extends CharacterBody2D
	var health: int
	var max_health: int
	func _init(cur: int, maxi: int) -> void:
		health = cur
		max_health = maxi

func _make_player(cur: int, maxi: int) -> FakePlayer:
	var p := FakePlayer.new(cur, maxi)
	p.add_to_group("player")
	add_child_autofree(p)
	return p

func before_each() -> void:
	GameState.health_potions = 0

func test_pickup_adds_potion_to_inventory_when_hp_below_max() -> void:
	var pickup = HealthPickupScene.instantiate()
	add_child_autofree(pickup)
	var player = _make_player(2, 5)
	pickup._on_body_entered(player)
	assert_eq(GameState.health_potions, 1,
		"зелье должно попасть в инвентарь при подборе")
	assert_eq(player.health, 2,
		"HP не меняется мгновенно — зелье лежит в инвентаре")
	assert_true(pickup.is_queued_for_deletion(),
		"пикап должен быть удалён после подбора")

func test_pickup_adds_potion_even_when_hp_full() -> void:
	# Новое поведение (было: пропускать при full HP). Теперь зелье
	# идёт в инвентарь всегда — игрок сам решит когда активировать.
	var pickup = HealthPickupScene.instantiate()
	add_child_autofree(pickup)
	var player = _make_player(5, 5)
	pickup._on_body_entered(player)
	assert_eq(GameState.health_potions, 1,
		"зелье идёт в инвентарь даже при полном HP")
	assert_true(pickup.is_queued_for_deletion(),
		"пикап всё равно удаляется — он подобран, но лежит в инвентаре")

func test_pickup_ignores_non_player_bodies() -> void:
	var pickup = HealthPickupScene.instantiate()
	add_child_autofree(pickup)
	var not_player := CharacterBody2D.new()
	add_child_autofree(not_player)
	pickup._on_body_entered(not_player)
	assert_eq(GameState.health_potions, 0)
	assert_false(pickup.is_queued_for_deletion())
