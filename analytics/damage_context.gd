class_name DamageContext
extends RefCounted

# Structured context для damage-события. Заполняется на стороне attacker'а
# (player weapon, enemy, projectile, poison cloud) и передаётся в
# take_damage(amount, context). Analytics использует context для:
#  - weapon damage_dealt / kills;
#  - enemy damage_to_player / hits_to_player;
#  - death attribution (кто убил игрока);
#  - damage_history (последние 16 записей).
#
# Все поля опциональны — attacker заполняет то, что знает. Analytics
# use'ит defaults ("unknown", 0, StringName("")) для отсутствующих полей.

# --- Source (кто нанёс урон) ---
# "player_weapon", "enemy", "enemy_projectile", "enemy_ability", "boss",
# "environment", "unknown".
var source_type: StringName = &"unknown"
# Стабильный slug: weapon_id ("dagger"), enemy_id ("goblin"), boss ("boss"),
# "poison_cloud", и т.п. Не i18n-ключ — path-basename ресурса.
var source_id: StringName = &"unknown"
# Уникальный runtime ID экземпляра источника (для сопоставления кадров).
# Обычно str(instance_id) attacker'а. Optional.
var source_instance_id: String = ""
# Для enemy — monster_level (см. enemy.gd), для weapon — 0.
var source_level: int = 0
# Для enemy — elite_rank (0=common, 1=champion, 2=elite).
var elite_rank: int = 0
# Для enemy — temperament_id ("aggressive", "cautious", ...).
var temperament_id: StringName = &""
# Слог конкретной атаки: "melee_arc", "projectile", "poison_tick",
# "charge", "aimed_shot", "volley", "summon". Отличается от source_type
# тем, что описывает сам удар, а не тип источника.
var attack_id: StringName = &"unknown"

# --- Target (кто получил) ---
# "player", "enemy", "boss".
var target_type: StringName = &"unknown"
# player_id / enemy_id, часто дублирует source_id соседнего события.
var target_id: StringName = &"unknown"

# --- Damage ---
var amount: int = 0
# "physical", "magic", "poison", "true". Пока проект различает только
# physical и poison, но enum расширяемый.
var damage_type: StringName = &"physical"

# --- Location ---
# Опциональный room_id (заполняется PR 2.9 room detection). "" = unknown.
var room_id: StringName = &""

# --- Factory helpers ---

# Player weapon hit (melee/projectile) на enemy.
# weapon может быть null (без веса).
static func from_player_weapon(weapon: WeaponResource, target: Node) -> DamageContext:
	var ctx := DamageContext.new()
	ctx.source_type = &"player_weapon"
	ctx.target_type = &"enemy"
	if weapon != null:
		ctx.source_id = StringName(weapon.resource_path.get_file().get_basename())
		ctx.attack_id = StringName(weapon.attack_type)
	if target != null:
		ctx.source_instance_id = ""
		ctx.target_id = _resolve_target_id(target)
	return ctx

# Enemy contact/melee damage → player.
# attack_id: "contact", "reach", "charge".
# enemy — untyped: у callsite может оказаться freed reference (Godot не обнуляет
# ссылки при queue_free). Типизированный `Node` крашится type-check'ом при вызове;
# untyped + is_instance_valid деградирует до source_id="unknown".
static func from_enemy_attack(enemy, attack: StringName) -> DamageContext:
	var ctx := DamageContext.new()
	ctx.source_type = &"enemy"
	ctx.attack_id = attack
	ctx.target_type = &"player"
	ctx.target_id = &"player"
	if is_instance_valid(enemy):
		_populate_enemy_fields(ctx, enemy)
	return ctx

# Enemy projectile hit → player.
# source_enemy untyped — см. from_enemy_attack (freed reference защита).
static func from_enemy_projectile(source_enemy, attack: StringName) -> DamageContext:
	var ctx := DamageContext.new()
	ctx.source_type = &"enemy_projectile"
	ctx.attack_id = attack
	ctx.target_type = &"player"
	ctx.target_id = &"player"
	if is_instance_valid(source_enemy):
		_populate_enemy_fields(ctx, source_enemy)
	return ctx

# Ability hit (poison cloud tick, aoe) → player.
# source_enemy untyped — см. from_enemy_attack (freed reference защита).
static func from_enemy_ability(source_enemy, attack: StringName) -> DamageContext:
	var ctx := DamageContext.new()
	ctx.source_type = &"enemy_ability"
	ctx.attack_id = attack
	ctx.target_type = &"player"
	ctx.target_id = &"player"
	ctx.damage_type = &"poison" if attack == &"poison_tick" else &"physical"
	if is_instance_valid(source_enemy):
		_populate_enemy_fields(ctx, source_enemy)
	return ctx

# Unknown / legacy path — заполняется defaults, пусть pipeline
# отсортирует по source_type="unknown" для аудита.
static func unknown() -> DamageContext:
	return DamageContext.new()

static func _populate_enemy_fields(ctx: DamageContext, enemy: Node) -> void:
	# Читаем через get() с null-check вместо `in` — устойчиво к тестовым
	# фейкам с dynamic-set properties и к scene-inst без явного @export.
	if enemy.scene_file_path != "":
		ctx.source_id = StringName(enemy.scene_file_path.get_file().get_basename())
	else:
		var display_name = enemy.get("display_name")
		if display_name != null and str(display_name) != "":
			ctx.source_id = StringName(str(display_name).to_lower())
	var monster_level = enemy.get("monster_level")
	if monster_level != null:
		ctx.source_level = int(monster_level)
	var elite_rank = enemy.get("elite_rank")
	if elite_rank != null:
		ctx.elite_rank = int(elite_rank)
	var temperament_id = enemy.get("temperament_id")
	if temperament_id != null and str(temperament_id) != "":
		ctx.temperament_id = StringName(str(temperament_id))
	ctx.source_instance_id = str(enemy.get_instance_id())

static func _resolve_target_id(target: Node) -> StringName:
	if target.scene_file_path != "":
		return StringName(target.scene_file_path.get_file().get_basename())
	return StringName(target.name)

# Diagnostic Dictionary для payload'а. Используется Analytics при записи
# damage_history entry и death attribution.
func to_dictionary() -> Dictionary:
	return {
		"source_type": String(source_type),
		"source_id": String(source_id),
		"source_instance_id": source_instance_id,
		"source_level": source_level,
		"elite_rank": elite_rank,
		"temperament_id": String(temperament_id),
		"attack_id": String(attack_id),
		"target_type": String(target_type),
		"target_id": String(target_id),
		"amount": amount,
		"damage_type": String(damage_type),
		"room_id": String(room_id),
	}
