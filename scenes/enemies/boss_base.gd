class_name BossBase
extends CharacterBody2D

# Общий базовый класс всех боссов. Владеет только lifecycle-механикой,
# которая одинакова для любого босса:
# - health/max_health, take_damage → death;
# - phase transition helper с dedupe;
# - stable attack telemetry signals;
# - player lookup;
# - reward hook на смерть;
# - spawn context (typed) вместо ad-hoc dictionary.
#
# Конкретные боссы (Necromancer, будущий Castellan, Golem, Wyrm)
# наследуются от `BossBase` и реализуют собственные attack/summon/phase
# логики. Base не знает про volley, aimed shot, summon quotas, projectile
# scenes — всё это остаётся в конкретных `.gd`.

# died_at сохранён под тем же именем, что и у обычных enemies — Main
# подписывается на него единообразно для _last_kill_position door-portal.
signal died_at(position: Vector2)
# Boss lifecycle сигналы — стабильный API для аналитики, тестов и UI.
signal phase_changed(phase: int)
signal attack_started(attack_id: StringName)
signal attack_resolved(attack_id: StringName, hit: bool)
signal boss_died(boss_id: StringName, position: Vector2)

@export var boss_id: StringName = &""
@export var display_name: String = "ENEMY_UNKNOWN"
@export var max_health: int = 30
@export var contact_damage: int = 3
@export var xp_reward: int = 40
@export var gold_reward: int = 20
@export var reward_profile_id: StringName = &""

var health: int
var current_phase: int = 1
var _visual_base_modulate: Color = Color.WHITE
# Spawn context выставляется через `apply_spawn_context()` до _ready(),
# если Main передаёт его. Может быть null — тогда floor scaling берётся
# из GameState.current_floor_number (legacy).
var _spawn_context: BossSpawnContext = null

func _ready() -> void:
	add_to_group("enemy")
	_apply_floor_scaling()
	health = max_health
	var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
	if visual != null:
		_visual_base_modulate = visual.modulate

# Вызывается Main'ом ДО add_child(), чтобы boss видел свои параметры
# уже в _ready(). Дефолтная реализация просто сохраняет ссылку —
# наследники могут override'ить и читать arena_rect, player, tower_seed.
func apply_spawn_context(context: BossSpawnContext) -> void:
	_spawn_context = context

# Возвращает номер этажа: из spawn context, если задан; иначе fallback
# на GameState (legacy). Наследники используют для scaling'а.
func effective_floor_number() -> int:
	if _spawn_context != null and _spawn_context.floor_number > 0:
		return _spawn_context.floor_number
	return GameState.current_floor_number

func _apply_floor_scaling() -> void:
	var floor_num := effective_floor_number()
	max_health = Balance.scaled_hp(max_health, floor_num)
	contact_damage = Balance.scaled_damage(contact_damage, floor_num)
	xp_reward = Balance.scaled_xp_reward(xp_reward, floor_num)
	gold_reward = Balance.scaled_gold_reward(gold_reward, floor_num)

func _find_player() -> Node2D:
	if _spawn_context != null and _spawn_context.player != null and is_instance_valid(_spawn_context.player):
		return _spawn_context.player
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

# Смена фазы. Идемпотентно: повторный set_phase(same) не эмиттит.
# phase нумеруется с 1; сам base не знает, сколько фаз у босса.
func set_phase(new_phase: int) -> void:
	if new_phase == current_phase:
		return
	current_phase = new_phase
	phase_changed.emit(new_phase)

func take_damage(amount: int, context: DamageContext = null) -> void:
	Analytics.record_damage_dealt(mini(health, amount), context)
	health -= amount
	modulate = Color(1, 0.5, 0.5)
	await get_tree().create_timer(0.08).timeout
	if is_inside_tree():
		modulate = Color.WHITE
	if health <= 0 and is_inside_tree():
		_handle_death(context)

func _handle_death(context: DamageContext) -> void:
	# Сигналы эмиттятся ДО queue_free() — иначе слушатели уже не увидят
	# node в дереве. См. `.claude/rules/90-anti-patterns.md`, правило про
	# died_at.
	died_at.emit(global_position)
	boss_died.emit(boss_id, global_position)
	EventLog.log_kill(display_name, xp_reward, gold_reward)
	GameState.award_xp(xp_reward)
	GameState.award_gold(gold_reward, &"boss")
	GameState.award_enemy_kill(context)
	queue_free()
