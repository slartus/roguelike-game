class_name EnvironmentPropDefinition
extends Resource

# Data-driven определение одного пропа окружения. Один экземпляр
# описывает "что за объект", "как его размещать", "что он блокирует".
# Инстансы создаёт EnvironmentPropCatalog по коду (не через .tres) —
# так же, как EnvironmentVisualProfiles описывает материалы: единый
# статический регистр без файлов .tres, компилятор ловит опечатки в
# идентификаторах констант.
#
# Планировщик RoomDecorationPlanner работает исключительно на этих
# полях (id/category/footprint/…) и не знает про конкретную графику.
# Floor.gd инстанцирует placement plan → берёт texture из definition
# и рисует спрайт; блокирующие props получают StaticBody2D.

# --- Категории пропов (стабильные строки контракта). Совпадают с
# документацией dungeon.md, тестами и совместимы с фильтром planner'а.
const CATEGORY_FLOOR_DECAL: StringName = &"floor_decal"
const CATEGORY_WALL_SURFACE: StringName = &"wall_surface"
const CATEGORY_WALL_ADJACENT_PROP: StringName = &"wall_adjacent_prop"
const CATEGORY_FLOOR_PROP: StringName = &"floor_prop"
const CATEGORY_LARGE_PROP: StringName = &"large_prop"
# Gameplay-interactive пропы: destructibles, hazards, lore-objects.
# В PR4 планировщик размещает их отдельным gameplay-pass поверх
# декоративного слоя. Категория выступает category-фильтром для
# _CATALOG.filter; конкретное поведение выбирается interaction_type.
const CATEGORY_INTERACTIVE: StringName = &"interactive"

const ALL_CATEGORIES: Array[StringName] = [
	CATEGORY_FLOOR_DECAL,
	CATEGORY_WALL_SURFACE,
	CATEGORY_WALL_ADJACENT_PROP,
	CATEGORY_FLOOR_PROP,
	CATEGORY_LARGE_PROP,
	CATEGORY_INTERACTIVE,
]

# --- Interaction type: определяет, какая gameplay-логика подхватывает
# prop в floor.gd::_instantiate_placement. NONE — чисто декоративный
# (default для всех PR2-props). Другие значения → floor.gd подставляет
# одну из PackedScene из GAMEPLAY_PROP_SCENES.
const INTERACTION_NONE: StringName = &"none"
const INTERACTION_DESTRUCTIBLE: StringName = &"destructible"
const INTERACTION_HAZARD_EXPLOSIVE: StringName = &"hazard_explosive"
const INTERACTION_LORE: StringName = &"lore"

const ALL_INTERACTION_TYPES: Array[StringName] = [
	INTERACTION_NONE,
	INTERACTION_DESTRUCTIBLE,
	INTERACTION_HAZARD_EXPLOSIVE,
	INTERACTION_LORE,
]

# --- Damage factions: кто может уронить destructible / взорвать hazard.
# Используется DamageableEnvironmentProp.take_damage(faction) для
# фильтрации. Explosive barrel не взрывается от урона другого барреля
# в chain reaction (guard по FACTION_ENVIRONMENT-only defs).
const FACTION_PLAYER: StringName = &"player"
const FACTION_ENEMY: StringName = &"enemy"
const FACTION_ENVIRONMENT: StringName = &"environment"

# --- Стороны стены для wall-adjacent / wall-surface пропов.
const WALL_SIDE_TOP: StringName = &"top"
const WALL_SIDE_RIGHT: StringName = &"right"
const WALL_SIDE_BOTTOM: StringName = &"bottom"
const WALL_SIDE_LEFT: StringName = &"left"

const ALL_WALL_SIDES: Array[StringName] = [
	WALL_SIDE_TOP,
	WALL_SIDE_RIGHT,
	WALL_SIDE_BOTTOM,
	WALL_SIDE_LEFT,
]

@export var id: StringName
@export var category: StringName
# Опционально: если задан, planner инстанциирует его вместо простого
# Sprite2D. В M2 все props используют texture-based fallback — сцены
# оставляем для будущего art pass (M4+).
@export var scene: PackedScene
# Texture-based fallback: floor.gd рисует один Sprite2D по этой
# текстуре в позиции prop'а. Используется когда scene не задан.
@export var texture: Texture2D
# Занимаемое место в клетках TILE_SIZE (20 px). Vector2i.ONE = один
# tile. Для floor_decal footprint игнорируется на occupancy — decals
# не блокируют клетки, но footprint всё ещё используется для проверки
# что prop влезает в room rect.
@export var footprint_cells: Vector2i = Vector2i.ONE
# Блокирует ли prop передвижение — прибавляется к AStar solid grid и
# получает StaticBody2D с CollisionShape2D. Дефолтный collision layer
# (physics layer 1) — тот же, что у стен, поэтому в M2 blocks_movement
# всегда автоматически подразумевает blocks_projectiles.
@export var blocks_movement: bool = false
# Флаг projectile-blocking. В PR4 MVP используется только для
# документации/будущих тестов — все gameplay-props физически сидят
# на общем physics layer'е, поэтому bullet останавливается независимо
# от этого поля. Отдельный projectile-layer + bullet mask — follow-up
# на PR5 (tactical cover).
@export var blocks_projectiles: bool = false

# --- Gameplay поля (PR4) -------------------------------------------------
# Тип интерактивности. NONE — декоративный, любой другой сдвигает
# floor.gd в специализированную сцену.
@export var interaction_type: StringName = INTERACTION_NONE
# Опциональный override сцены для gameplay props. Если null — floor.gd
# использует default сцену из GAMEPLAY_PROP_SCENES по interaction_type.
@export var interaction_scene: PackedScene
# Максимум экземпляров этого prop'а в одной комнате. 0 = без ограничения.
@export var max_per_room: int = 0
# Максимум экземпляров этого prop'а на весь этаж. 0 = без ограничения
# сверх floor-wide budget планировщика.
@export var max_per_floor: int = 0
# HP разрушаемого prop'а. 0 = не разрушаемый (или неприменимо).
@export var destructible_max_health: int = 0
# Какие фракции могут наносить урон этому prop'у. Пустой = любая
# фракция (в т.ч. environment, что открывает chain reaction).
@export var damage_factions: Array[StringName] = []
# Радиус взрыва в пикселях для hazard_explosive. 0 = default (см. explosive_barrel).
@export var explosion_radius: float = 0.0
# Урон от взрыва (int, применяется через take_damage у enemy/player).
@export var explosion_damage: int = 0
# Задержка telegraph перед взрывом, секунды. 0 = default.
@export var explosion_telegraph_time: float = 0.0
# Для lore-объекта: ключ i18n, чей текст показывается при интеракции.
@export var lore_text_key: String = ""
# Для lore-объекта: ключ i18n подсказки "Press E" (или generic).
@export var lore_prompt_key: String = ""
# Список zones (StringName-ключи TowerZone.ZONE_*), где prop разрешён.
# Пустой массив = разрешено везде.
@export var allowed_zones: Array[StringName] = []
# Список room roles (StringName поверх RoomRoles.ROLE_*), где prop
# разрешён. Пустой = разрешено везде (fallback для generic пропов).
@export var allowed_room_roles: Array[StringName] = []
# Wall-side constraint для wall_adjacent_prop / wall_surface: prop
# должен касаться одной из этих сторон комнаты. Пустой = любая
# сторона.
@export var allowed_wall_sides: Array[StringName] = []
# Deterministic weight в roll внутри compatible props. Больше =
# чаще выбирается.
@export var weight: int = 1
# Минимальный размер комнаты в tiles, где prop разрешён. Vector2i.ZERO
# = нет минимума (маленькие комнаты).
@export var min_room_size_cells: Vector2i = Vector2i.ZERO
# Дополнительный clearance вокруг prop'а (в клетках), чтобы игрок мог
# обойти. 0 = plot заполняется вплотную.
@export var clearance_cells: int = 0
# Разрешено ли поворачивать при placement. В M2 planner не поворачивает,
# зарезервировано под PR4.
@export var can_rotate: bool = false
# Разрешено ли зеркалить (для симметричных wall-adjacent) в M2 не
# используется.
@export var mirror_allowed: bool = false

# Стабильные категории → нужны planner'у.
func is_floor_decal() -> bool:
	return category == CATEGORY_FLOOR_DECAL

func is_wall_surface() -> bool:
	return category == CATEGORY_WALL_SURFACE

func is_wall_adjacent() -> bool:
	return category == CATEGORY_WALL_ADJACENT_PROP

func is_floor_prop() -> bool:
	return category == CATEGORY_FLOOR_PROP

func is_large_prop() -> bool:
	return category == CATEGORY_LARGE_PROP

# Разрешён ли prop для (zone, role)? Пустые списки — "везде".
func is_allowed_in(zone: StringName, role: StringName) -> bool:
	if not allowed_zones.is_empty() and not allowed_zones.has(zone):
		return false
	if not allowed_room_roles.is_empty() and not allowed_room_roles.has(role):
		return false
	return true

# Помещается ли prop в комнату размера room_size_cells (в клетках)?
func fits_in_room(room_size_cells: Vector2i) -> bool:
	if room_size_cells.x < footprint_cells.x or room_size_cells.y < footprint_cells.y:
		return false
	if room_size_cells.x < min_room_size_cells.x:
		return false
	if room_size_cells.y < min_room_size_cells.y:
		return false
	return true

# --- Gameplay predicates ---------------------------------------------------

func is_gameplay_prop() -> bool:
	return interaction_type != INTERACTION_NONE

func is_destructible() -> bool:
	return destructible_max_health > 0

func is_hazard() -> bool:
	return interaction_type == INTERACTION_HAZARD_EXPLOSIVE

func is_lore() -> bool:
	return interaction_type == INTERACTION_LORE

# Может ли данная фракция нанести урон этому prop'у? Если damage_factions
# пуст — да (любая). Если задан — фракция должна быть в списке.
func accepts_damage_from(faction: StringName) -> bool:
	if damage_factions.is_empty():
		return true
	return damage_factions.has(faction)
