extends Node

const SAVE_PATH: String = "user://save.cfg"

const DEFAULT_MAX_HEALTH: int = 5
const DEFAULT_WEAPON: WeaponResource = preload("res://resources/weapons/short_sword.tres")
const HEALTH_PER_LEVEL: int = 1

signal xp_changed(current: int, max_for_level: int)
signal leveled_up(new_level: int, new_max_health: int)
signal gold_changed(total: int)
# Число зелий здоровья в инвентаре игрока (слот 1). Меняется при
# подборе HealthPickup и при активации через клавишу "1".
signal health_potions_changed(count: int)
# Прогрессия карт (M2-M5). upgrade_choice_requested эмитится при
# достижении нечётного уровня >= 3 — HUD показывает панель выбора.
# upgrades_changed эмитится после применения карты — UI / HUD могут
# обновиться (индикатор, счётчик стеков и т.п.).
signal upgrade_choice_requested(level: int)
signal upgrades_changed()

var current_floor_number: int = 1
var player_max_health: int = DEFAULT_MAX_HEALTH
var player_health: int = DEFAULT_MAX_HEALTH
var equipped_weapon: WeaponResource = DEFAULT_WEAPON
var player_level: int = 1
var player_xp: int = 0

# Master seed забега. Один raw int определяет весь layout всех этажей.
# Floor использует tower_seed для формулы seed(floor) = tower_seed * PRIME + floor.
# Reset_run генерирует новый случайный tower_seed.
var tower_seed: int = 0

var total_gold: int = 0

# Инвентарь: пока один слот — зелья здоровья. Не сохраняется в save.cfg
# (потерянные с прошлого забега бутыльки не должны переноситься на новый).
var health_potions: int = 0

# Статистика текущего забега (run). Инкрементируется во время игры,
# капчурится в last_run_* при reset_run, чтобы title screen мог показать
# summary сессии после смерти игрока.
var run_gold: int = 0
var run_enemies_killed: int = 0

# Стат-снимок предыдущего run — заполняется в reset_run и живёт до
# начала следующего забега. Title screen читает эти поля и показывает
# окно «результаты забега», если has_last_run_stats == true.
var last_run_floor: int = 0
var last_run_level: int = 0
var last_run_gold: int = 0
var last_run_enemies_killed: int = 0
var has_last_run_stats: bool = false

# --- Run-scoped upgrade cards (M2) ---
# Стеки выбранных карт: {upgrade_id: int}. Обнуляется в reset_run() —
# карты не переносятся между забегами (это run progression, не meta).
var player_upgrade_stacks: Dictionary = {}
# Очередь уровней, для которых игрок должен выбрать карту. Заполняется
# в _level_up на нечётных уровнях >= 3. UI обрабатывает по одному.
var pending_upgrade_levels: Array = []
# Счётчик генераций оффера — компонент seed'а для deterministic offer
# generator (M4). Инкрементируется каждый раз при показе панели выбора.
var upgrade_offer_counter: int = 0
# Second Wind — раз в этаж переживает летальный урон. Сбрасывается в
# next_floor() и reset_run().
var second_wind_used_this_floor: bool = false

func _ready() -> void:
	tower_seed = _pick_random_tower_seed()
	_load()

func _pick_random_tower_seed() -> int:
	# Uniform в [0, 2^31 - 1]. Достаточно широкий диапазон для практики,
	# и легко копируется/вводится игроком.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(0, 2147483647)

func next_floor() -> void:
	current_floor_number += 1
	# Second Wind charge — раз в этаж, значит сбрасываем на новом.
	second_wind_used_this_floor = false
	# reload_current_scene из physics callback (Door.body_entered)
	# запрещён Godot и вызывает hard-freeze — оборачиваем в deferred.
	get_tree().call_deferred("reload_current_scene")

func reset_run() -> void:
	current_floor_number = 1
	player_max_health = DEFAULT_MAX_HEALTH
	player_health = DEFAULT_MAX_HEALTH
	equipped_weapon = DEFAULT_WEAPON
	player_level = 1
	player_xp = 0
	tower_seed = _pick_random_tower_seed()
	health_potions = 0
	run_gold = 0
	run_enemies_killed = 0
	# Прогрессия карт — run-scoped, сбрасываем полностью.
	player_upgrade_stacks = {}
	pending_upgrade_levels = []
	upgrade_offer_counter = 0
	second_wind_used_this_floor = false
	health_potions_changed.emit(health_potions)
	upgrades_changed.emit()

func finish_run() -> void:
	# Смерть игрока: снимаем snapshot текущего run и потом обнуляем.
	# has_last_run_stats нужен title screen'у, чтобы понять — показывать
	# ли окно итогов забега (иначе покажет нули после первого старта).
	last_run_floor = current_floor_number
	last_run_level = player_level
	last_run_gold = run_gold
	last_run_enemies_killed = run_enemies_killed
	has_last_run_stats = true
	reset_run()

func clear_last_run_stats() -> void:
	# Title screen вызывает это, когда игрок кликнул «Играть» — окно summary
	# больше не нужно, следующий finish_run заполнит его заново.
	has_last_run_stats = false

func award_enemy_kill() -> void:
	run_enemies_killed += 1
	Analytics.record_enemy_killed()

func add_health_potion() -> void:
	health_potions += 1
	health_potions_changed.emit(health_potions)

# Пытается списать одно зелье. Возвращает true, если зелье было в
# инвентаре и списание прошло. Проверку «здоровье уже полное»
# делает вызывающая сторона (Player), чтобы не тратить зелье впустую.
func consume_health_potion() -> bool:
	if health_potions <= 0:
		return false
	health_potions -= 1
	health_potions_changed.emit(health_potions)
	return true

func award_xp(amount: int) -> void:
	if amount <= 0:
		return
	player_xp += amount
	while player_xp >= Balance.xp_to_next_level(player_level):
		player_xp -= Balance.xp_to_next_level(player_level)
		_level_up()
	xp_changed.emit(player_xp, Balance.xp_to_next_level(player_level))

func _level_up() -> void:
	player_level += 1
	# Чётные уровни (2, 4, 6, ...) → HP-награда. Нечётные >= 3 → upgrade card.
	# Level 1→2 всегда даёт HP (первый level-up дружелюбен).
	if is_hp_reward_level(player_level):
		player_max_health += HEALTH_PER_LEVEL
	# Full heal сохраняется на любом level-up до v2 balance pass.
	player_health = player_max_health
	EventLog.log_level_up(player_level)
	leveled_up.emit(player_level, player_max_health)
	if is_upgrade_reward_level(player_level):
		# Ставим уровень в очередь. UI (M5) слушает upgrade_choice_requested
		# и обрабатывает pending уровни один за другим — множественный
		# level-up (одним XP-hit'ом) сложит несколько запросов подряд.
		pending_upgrade_levels.append(player_level)
		upgrade_choice_requested.emit(player_level)

func is_hp_reward_level(level: int) -> bool:
	return level % 2 == 0

func is_upgrade_reward_level(level: int) -> bool:
	return level >= 3 and level % 2 == 1

func award_gold(amount: int) -> void:
	if amount <= 0:
		return
	total_gold += amount
	run_gold += amount
	Analytics.record_gold_earned(amount)
	gold_changed.emit(total_gold)
	_save()

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "total_gold", total_gold)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Failed to save game state: %s" % err)

func _load() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	total_gold = cfg.get_value("meta", "total_gold", 0)

# --- Upgrade cards API (M2) ---

func get_upgrade_stack(upgrade_id: String) -> int:
	return int(player_upgrade_stacks.get(upgrade_id, 0))

# Применяет одну карту: увеличивает stack, эмитит upgrades_changed.
# Не проверяет max_stacks — offer generator (M4) уже отфильтровал maxed.
# Immediate-эффекты (max_health_bonus и т.п.) применяются здесь же —
# see M6. Modifier-эффекты берутся снимком в get_player_upgrade_modifiers.
func add_player_upgrade(upgrade: PlayerUpgradeResource) -> void:
	if upgrade == null:
		return
	var current := get_upgrade_stack(upgrade.id)
	player_upgrade_stacks[upgrade.id] = current + 1
	# Immediate effect: max_health_bonus увеличивает HP сразу. Полный набор
	# immediate-эффектов реализуется в M6, здесь только infra.
	if upgrade.effect_type == "max_health_bonus":
		var amount: int = int(upgrade.parameters.get("amount", 0))
		player_max_health += amount
		player_health = mini(player_health + amount, player_max_health)
	upgrades_changed.emit()

func has_pending_upgrade_choice() -> bool:
	return not pending_upgrade_levels.is_empty()

func pop_next_pending_upgrade_level() -> int:
	if pending_upgrade_levels.is_empty():
		return 0
	return pending_upgrade_levels.pop_front()

# Snapshot всех активных модификаторов, вычисленных из player_upgrade_stacks.
# WeaponStats-layer (M7) читает эти поля перед каждой атакой. Мы намеренно
# перевычисляем на каждом вызове — стеков мало, дешевле чем держать
# derived dict в sync с сигналами.
func get_player_upgrade_modifiers() -> Dictionary:
	var mods := {
		"speed_multiplier": 1.0,
		"potion_heal_bonus": 0,
		"slow_resistance_bonus": 0.0,
		"poison_duration_multiplier": 1.0,
		"warrior_damage_bonus": 0,
		"warrior_range_multiplier": 1.0,
		"warrior_arc_multiplier": 1.0,
		"warrior_knockback_bonus": 0.0,
		"archer_damage_bonus": 0,
		"archer_attack_interval_multiplier": 1.0,
		"archer_spread_multiplier": 1.0,
		"archer_pierce_bonus": 0,
		"archer_projectile_speed_multiplier": 1.0,
		"mage_damage_bonus": 0,
		"mage_attack_interval_multiplier": 1.0,
		"mage_projectile_lifetime_multiplier": 1.0,
		"mage_area_radius_multiplier": 1.0,
	}
	for upgrade_id in player_upgrade_stacks:
		var stacks: int = int(player_upgrade_stacks[upgrade_id])
		if stacks <= 0:
			continue
		var upgrade := PlayerUpgradeLibrary.get_upgrade_by_id(upgrade_id)
		if upgrade == null:
			continue
		_apply_upgrade_to_mods(upgrade, stacks, mods)
	return mods

func _apply_upgrade_to_mods(upgrade: PlayerUpgradeResource, stacks: int, mods: Dictionary) -> void:
	var params: Dictionary = upgrade.parameters
	match upgrade.effect_type:
		"speed_multiplier":
			# Мультипликативно, стекается как m^stacks.
			var mult: float = float(params.get("multiplier", 1.0))
			mods.speed_multiplier *= pow(mult, stacks)
		"potion_heal_bonus":
			mods.potion_heal_bonus += int(params.get("amount", 0)) * stacks
		"slow_resistance":
			mods.slow_resistance_bonus += float(params.get("amount", 0.0)) * stacks
		"poison_resistance":
			var dur_mult: float = float(params.get("duration_multiplier", 1.0))
			mods.poison_duration_multiplier *= pow(dur_mult, stacks)
		"style_damage_bonus":
			var style: String = params.get("style", "")
			var amount: int = int(params.get("amount", 0)) * stacks
			match style:
				"warrior": mods.warrior_damage_bonus += amount
				"archer":  mods.archer_damage_bonus += amount
				"mage":    mods.mage_damage_bonus += amount
		"melee_range_multiplier":
			mods.warrior_range_multiplier *= pow(float(params.get("multiplier", 1.0)), stacks)
		"melee_arc_multiplier":
			mods.warrior_arc_multiplier *= pow(float(params.get("multiplier", 1.0)), stacks)
		"knockback_bonus":
			mods.warrior_knockback_bonus += float(params.get("amount", 0.0)) * stacks
		"style_attack_interval_multiplier":
			var style_ai: String = params.get("style", "")
			var mult_ai: float = pow(float(params.get("multiplier", 1.0)), stacks)
			match style_ai:
				"archer": mods.archer_attack_interval_multiplier *= mult_ai
				"mage":   mods.mage_attack_interval_multiplier *= mult_ai
		"pierce_bonus":
			mods.archer_pierce_bonus += int(params.get("amount", 0)) * stacks
		"spread_multiplier":
			var style_sp: String = params.get("style", "")
			if style_sp == "archer":
				mods.archer_spread_multiplier *= pow(float(params.get("multiplier", 1.0)), stacks)
		"projectile_speed_multiplier":
			var style_sp2: String = params.get("style", "")
			if style_sp2 == "archer":
				mods.archer_projectile_speed_multiplier *= pow(float(params.get("multiplier", 1.0)), stacks)
		"projectile_lifetime_multiplier":
			var style_pl: String = params.get("style", "")
			if style_pl == "mage":
				mods.mage_projectile_lifetime_multiplier *= pow(float(params.get("multiplier", 1.0)), stacks)
		"area_radius_multiplier":
			var style_ar: String = params.get("style", "")
			if style_ar == "mage":
				mods.mage_area_radius_multiplier *= pow(float(params.get("multiplier", 1.0)), stacks)
		# max_health_bonus и second_wind не имеют snapshot-эффекта (immediate
		# / conditional). Их обработка живёт в add_player_upgrade и
		# take_damage соответственно.
		_:
			pass
