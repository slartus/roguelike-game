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
# Категория зарезервирована для gameplay-interactive объектов будущих
# PR (сундуки как props, ловушки). Planner в этом PR такой категории
# не размещает — правило M2.
const CATEGORY_INTERACTIVE: StringName = &"interactive"

const ALL_CATEGORIES: Array[StringName] = [
	CATEGORY_FLOOR_DECAL,
	CATEGORY_WALL_SURFACE,
	CATEGORY_WALL_ADJACENT_PROP,
	CATEGORY_FLOOR_PROP,
	CATEGORY_LARGE_PROP,
	CATEGORY_INTERACTIVE,
]

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
# ЗАРЕЗЕРВИРОВАНО ПОД PR4. В M2 не читается — StaticBody2D в
# Floor._instantiate_placement всегда использует один и тот же layer,
# поэтому blocks_projectiles эффективно равен blocks_movement.
# Отдельный слой для projectile-blocker'ов появится вместе с
# destructible props (PR4), тогда поле начнёт работать самостоятельно.
@export var blocks_projectiles: bool = false
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
