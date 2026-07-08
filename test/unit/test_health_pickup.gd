extends GutTest

# HealthPickup не должен тратиться, если игрок уже с полным HP.
# Иначе пикапы «сгорают» на подходе через комнату где HP не нужно.

const HealthPickupScene = preload("res://scenes/pickups/health_pickup.tscn")

class FakePlayer:
	extends CharacterBody2D
	var health: int
	var max_health: int
	var heal_calls: int = 0
	func _init(cur: int, maxi: int) -> void:
		health = cur
		max_health = maxi
	func heal(amount: int) -> void:
		heal_calls += 1
		health = min(max_health, health + amount)

func _make_player(cur: int, maxi: int) -> FakePlayer:
	var p := FakePlayer.new(cur, maxi)
	p.add_to_group("player")
	add_child_autofree(p)
	return p

func test_pickup_heals_when_hp_below_max() -> void:
	var pickup = HealthPickupScene.instantiate()
	add_child_autofree(pickup)
	var player = _make_player(2, 5)
	pickup._on_body_entered(player)
	assert_eq(player.heal_calls, 1, "heal должен вызваться при неполном HP")
	assert_eq(player.health, 3, "HP должен подняться на heal_amount")
	assert_true(pickup.is_queued_for_deletion(),
		"пикап должен быть удалён после использования")

func test_pickup_skipped_when_hp_full() -> void:
	var pickup = HealthPickupScene.instantiate()
	add_child_autofree(pickup)
	var player = _make_player(5, 5)
	pickup._on_body_entered(player)
	assert_eq(player.heal_calls, 0,
		"heal не должен вызываться если HP == max_health")
	assert_eq(player.health, 5, "HP не должен изменяться")
	assert_false(pickup.is_queued_for_deletion(),
		"пикап должен остаться лежать для использования позже")

func test_pickup_skipped_when_hp_above_max() -> void:
	# Edge case: если health > max_health (например баг level-up race) —
	# всё равно не тратим пикап.
	var pickup = HealthPickupScene.instantiate()
	add_child_autofree(pickup)
	var player = _make_player(7, 5)
	pickup._on_body_entered(player)
	assert_eq(player.heal_calls, 0)
	assert_false(pickup.is_queued_for_deletion())
