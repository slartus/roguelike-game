extends GutTest

# Контракт слота инвентаря «1: зелье лечения».
# - GameState.add_health_potion / consume_health_potion меняют счётчик
#   и эмитят health_potions_changed;
# - reset_run() обнуляет слот (не переносится между забегами);
# - HUD слот-лейбл обновляется через сигнал;
# - клавиша "1" в Player: если HP < max и есть зелье — heal(1),
#   иначе no-op без списания.

const HudScene = preload("res://scenes/ui/hud.tscn")
const PlayerScene = preload("res://scenes/player/player.tscn")

func before_each() -> void:
	GameState.health_potions = 0
	GameState.player_health = GameState.DEFAULT_MAX_HEALTH
	GameState.player_max_health = GameState.DEFAULT_MAX_HEALTH

func test_add_potion_increments_and_emits_signal() -> void:
	var received: Array = []
	GameState.health_potions_changed.connect(func(n): received.append(n))
	GameState.add_health_potion()
	GameState.add_health_potion()
	assert_eq(GameState.health_potions, 2)
	assert_eq(received, [1, 2],
		"signal должен приходить с новым значением на каждый add")

func test_consume_returns_false_and_no_emit_when_empty() -> void:
	var received: Array = []
	GameState.health_potions_changed.connect(func(n): received.append(n))
	var ok := GameState.consume_health_potion()
	assert_false(ok, "consume вернёт false когда инвентарь пуст")
	assert_eq(GameState.health_potions, 0)
	assert_eq(received.size(), 0, "signal не эмиттится на пустое списание")

func test_consume_returns_true_and_decrements_when_available() -> void:
	GameState.add_health_potion()
	GameState.add_health_potion()
	var ok := GameState.consume_health_potion()
	assert_true(ok)
	assert_eq(GameState.health_potions, 1)

func test_reset_run_clears_potions() -> void:
	GameState.add_health_potion()
	GameState.add_health_potion()
	GameState.reset_run()
	assert_eq(GameState.health_potions, 0,
		"после смерти зелья сгорают вместе с прогрессом")

func test_hud_slot_shows_icon_and_count_when_potions_present() -> void:
	var hud = HudScene.instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	var icon: TextureRect = hud.get_node("InventoryPanel/PotionSlot/PotionIcon")
	var count_label: Label = hud.get_node("InventoryPanel/PotionSlot/PotionCount")
	# Стартовое: 0 → пустой слот (только рамка, ни иконки, ни числа).
	assert_false(icon.visible,
		"при 0 зелий иконка бутылька должна быть скрыта")
	assert_false(count_label.visible,
		"при 0 зелий счётчик должен быть скрыт")
	GameState.add_health_potion()
	GameState.add_health_potion()
	GameState.add_health_potion()
	assert_true(icon.visible, "при непустом инвентаре иконка видна")
	assert_true(count_label.visible, "и счётчик видим")
	assert_eq(count_label.text, "×3",
		"счётчик формата '×N': text='%s'" % count_label.text)

func test_input_action_inventory_slot_1_is_defined() -> void:
	assert_true(InputMap.has_action("inventory_slot_1"),
		"должен быть action 'inventory_slot_1' в project.godot")
	var events := InputMap.action_get_events("inventory_slot_1")
	assert_gt(events.size(), 0, "у action должны быть привязки")

func test_player_hotkey_consumes_and_heals_when_hp_below_max() -> void:
	GameState.player_health = 2
	GameState.add_health_potion()
	var player = PlayerScene.instantiate()
	add_child_autofree(player)
	await get_tree().process_frame
	player._try_use_health_potion()
	assert_eq(GameState.health_potions, 0, "зелье списалось")
	assert_eq(player.health, 3, "HP поднялось на 1")

func test_player_hotkey_no_op_when_hp_full() -> void:
	GameState.player_health = GameState.DEFAULT_MAX_HEALTH
	GameState.add_health_potion()
	var player = PlayerScene.instantiate()
	add_child_autofree(player)
	await get_tree().process_frame
	player._try_use_health_potion()
	assert_eq(GameState.health_potions, 1,
		"зелье не тратится, если HP уже максимальное")
	assert_eq(player.health, GameState.DEFAULT_MAX_HEALTH)

func test_player_hotkey_no_op_when_empty_inventory() -> void:
	GameState.player_health = 2
	var player = PlayerScene.instantiate()
	add_child_autofree(player)
	await get_tree().process_frame
	player._try_use_health_potion()
	assert_eq(GameState.health_potions, 0)
	assert_eq(player.health, 2,
		"пустой слот — HP не меняется, лечения не происходит")
