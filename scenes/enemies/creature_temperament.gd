class_name CreatureTemperament
extends RefCounted

# Каталог темпераментов существ: единый источник истины по ID,
# по допустимым пулам с весами и по детерминированному выбору
# из пула. Поведенческие модификаторы применяются в конкретных
# AI-скриптах (enemy.gd / ranged_enemy.gd / charger.gd) — здесь
# только данные и рандом.

const AGGRESSIVE: StringName = &"aggressive"
const CAUTIOUS: StringName = &"cautious"
const PERSISTENT: StringName = &"persistent"
const RESTLESS: StringName = &"restless"
const WATCHFUL: StringName = &"watchful"

const ALL_IDS: Array[StringName] = [
	AGGRESSIVE,
	CAUTIOUS,
	PERSISTENT,
	RESTLESS,
	WATCHFUL,
]

# monster_id -> [{"id": StringName, "weight": int}, ...]
# Сумма весов в каждом пуле = 100.
const POOLS := {
	&"small_slime": [
		{"id": RESTLESS, "weight": 45},
		{"id": AGGRESSIVE, "weight": 35},
		{"id": WATCHFUL, "weight": 20},
	],
	&"adult_slime": [
		{"id": AGGRESSIVE, "weight": 40},
		{"id": PERSISTENT, "weight": 35},
		{"id": RESTLESS, "weight": 25},
	],
	&"goblin": [
		{"id": AGGRESSIVE, "weight": 30},
		{"id": CAUTIOUS, "weight": 30},
		{"id": RESTLESS, "weight": 25},
		{"id": WATCHFUL, "weight": 15},
	],
	&"orc": [
		{"id": PERSISTENT, "weight": 45},
		{"id": AGGRESSIVE, "weight": 35},
		{"id": WATCHFUL, "weight": 20},
	],
	&"skeleton": [
		{"id": PERSISTENT, "weight": 35},
		{"id": AGGRESSIVE, "weight": 30},
		{"id": WATCHFUL, "weight": 20},
		{"id": RESTLESS, "weight": 15},
	],
	&"zombie": [
		{"id": PERSISTENT, "weight": 55},
		{"id": WATCHFUL, "weight": 25},
		{"id": AGGRESSIVE, "weight": 20},
	],
	&"spider": [
		{"id": WATCHFUL, "weight": 40},
		{"id": AGGRESSIVE, "weight": 35},
		{"id": RESTLESS, "weight": 25},
	],
	&"skeleton_archer": [
		{"id": CAUTIOUS, "weight": 45},
		{"id": WATCHFUL, "weight": 30},
		{"id": AGGRESSIVE, "weight": 15},
		{"id": RESTLESS, "weight": 10},
	],
	&"lich": [
		{"id": CAUTIOUS, "weight": 45},
		{"id": WATCHFUL, "weight": 35},
		{"id": AGGRESSIVE, "weight": 20},
	],
}

static func is_known(temperament_id: StringName) -> bool:
	return ALL_IDS.has(temperament_id)

static func has_pool(creature_type_id: StringName) -> bool:
	return creature_type_id != &"" and POOLS.has(creature_type_id)

# Разрешает финальный temperament_id для creature с учётом override'а.
#
# Если явно задан валидный ID — оставляем.
# Если задан неизвестный ID — сбрасываем в &"" с предупреждением (чтобы
# «bogus» не применился как pass в match).
# Иначе — пытаемся выбрать из пула по типу существа с переданным сидом.
# Если пула нет — возвращаем &"" (боссы и legacy scenes без setup).
static func resolve_id(current_id: StringName, creature_type_id: StringName, seed_value: int) -> StringName:
	if current_id != &"":
		if is_known(current_id):
			return current_id
		push_warning("CreatureTemperament: unknown temperament_id '%s' — сбрасываем" % current_id)
	if not has_pool(creature_type_id):
		return &""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return roll_for(creature_type_id, rng)

# Fallback-сид для runtime-созданных существ (bud, split, summon, тест).
# Стабилен в пределах одного tower_seed × floor × type × округлённая
# позиция — повторный запуск даёт тот же самый сид для того же контекста.
# Через `hash(Array)` — арифметика без риска wrap-around'а при больших
# tower_seed (иначе умножения могли давать коллизии по int64-overflow).
static func compute_fallback_seed(creature_type_id: StringName, world_position: Vector2) -> int:
	var px := int(round(world_position.x))
	var py := int(round(world_position.y))
	return hash([
		int(GameState.tower_seed),
		int(GameState.current_floor_number),
		creature_type_id,
		px,
		py,
	])

# Выбирает темперамент из пула монстра weighted-random через переданный
# RNG. Не трогает глобальный randi/randf — важно для детерминизма
# spawn-точек (сид приходит из Main._spawn_enemies).
#
# Возвращает пустой StringName, если ID неизвестен или пул пуст.
static func roll_for(creature_type_id: StringName, rng: RandomNumberGenerator) -> StringName:
	if not has_pool(creature_type_id):
		return &""
	var pool: Array = POOLS[creature_type_id]
	var total := 0
	for entry in pool:
		total += int(entry["weight"])
	if total <= 0:
		return &""
	var pick := rng.randi_range(1, total)
	var acc := 0
	for entry in pool:
		acc += int(entry["weight"])
		if pick <= acc:
			return entry["id"]
	# Формально недостижимо: pick ≤ total = сумма всех acc-инкрементов.
	# Fallback — на случай числового noise в будущем при переходе на float.
	return pool[pool.size() - 1]["id"]
