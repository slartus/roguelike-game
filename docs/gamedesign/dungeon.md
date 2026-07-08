# Подземелье и этажи

Один «уровень» игры теперь — **этаж подземелья**, состоящий из нескольких комнат, соединённых коридорами. Камера следит за игроком, этаж намного больше viewport'а 480×270.

Терминология:
- **Этаж** (`floor`) = один сегмент забега, соответствует `GameState.current_floor_number`.
- **Комната** (`room`) = один прямоугольник внутри этажа.
- **Коридор** (`corridor`) = узкий прямоугольник, соединяющий две соседние комнаты.
- **Выход** (`Door`) = `Area2D`, ведущий на следующий этаж.

## Генерация — `DungeonGenerator`

`scenes/dungeon/dungeon_generator.gd` (`RefCounted`, `class_name DungeonGenerator`). Метод `generate(seed, floor_number, is_boss) → DungeonLayout`.

### Алгоритм обычного этажа

1. Число комнат: `clampi(MIN_ROOMS + floor_number / 2, MIN_ROOMS, MAX_ROOMS)` — от 4 до 9.
2. Комнаты выстраиваются в цепочку: каждая следующая правее (60% шанс) или ниже (40%) предыдущей с зазором 80–140 px.
3. Каждая комната случайного размера в диапазоне 140–210 × 100–150 px.
4. Между парой соседних комнат — L-образный коридор шириной 24 px (горизонтальный сегмент + вертикальный).
5. `player_start` = центр первой комнаты.
6. `exit_position` = центр последней комнаты.
7. Enemy spawn'ы: 2–3 точки в каждой средней комнате + 1–2 в последней (перед выходом).
8. Сундук: если `floor_number % 3 == 0` и есть middle rooms — одна точка в случайной средней комнате.
9. Layout нормализуется — `floor_bounds.position = (0, 0)`.

### Boss-этаж

`is_boss = true` (для `floor_number % 5 == 0`):
- Одна большая комната 600×400.
- `player_start` слева, `exit_position` справа.
- Никаких обычных врагов, `enemy_spawns` и `chest_positions` пустые (Main спавнит босса в центре).

### Константы

| Константа | Значение | Смысл |
|-----------|----------|-------|
| `ROOM_MIN_SIZE` | 140×100 | Мин. размер комнаты |
| `ROOM_MAX_SIZE` | 210×150 | Макс. размер |
| `ROOM_GAP_MIN`/`MAX` | 80/140 | Зазор между соседними комнатами |
| `CORRIDOR_WIDTH` | 24 | Ширина коридора |
| `FLOOR_PADDING` | 60 | Отступ от бордюра до края bounds |
| `ENEMY_SPAWN_MARGIN` | 22 | Отступ спавна от стены комнаты |
| `MIN_ROOMS`/`MAX_ROOMS` | 4/9 | Границы количества комнат |
| `CHEST_FLOOR_INTERVAL` | 3 | Каждый N-й этаж — сундук |
| `BOSS_ROOM_SIZE` | 600×400 | Арена босса |

## Данные — `DungeonLayout`

`scenes/dungeon/dungeon_layout.gd` (`RefCounted`, `class_name DungeonLayout`). Чистая структура данных, без рендера:

| Поле | Тип | Смысл |
|------|-----|-------|
| `rooms` | `Array[Rect2i]` | Прямоугольники комнат в координатах этажа |
| `corridors` | `Array[Rect2i]` | Прямоугольники коридоров |
| `player_start` | `Vector2i` | Точка старта игрока |
| `exit_position` | `Vector2i` | Точка двери на следующий этаж |
| `enemy_spawns` | `Array[Vector2i]` | Точки для инстансирования врагов |
| `chest_positions` | `Array[Vector2i]` | Точки для сундуков |
| `floor_bounds` | `Rect2i` | Границы этажа, `position = (0, 0)` после нормализации |
| `is_boss_floor` | `bool` | Флаг boss-этажа |

## Рендер — `scenes/dungeon/floor.tscn` + `floor.gd`

`Floor` — Node2D-сцена, которая при `_ready()`:

1. Вызывает `DungeonGenerator.generate(seed, floor_number, is_boss)`. Seed — комбинация номера этажа и `Time.get_unix_time_from_system()`, чтобы каждый заход давал новый layout.
2. Рисует **фон** этажа: `Polygon2D` с `BACKGROUND_COLOR` на весь `floor_bounds`.
3. Рисует **пол** комнат и коридоров: отдельный `Polygon2D` с `FLOOR_COLOR` на каждый `Rect2i` из layout.
4. Строит **стены**: grid 20×20 pixel tile'ов над `floor_bounds`. Для каждой tile-cell проверяем — входит ли центр tile в какую-либо `room` или `corridor`. Если нет — это стена. Смежные wall-tiles в одной строке объединяются в один `StaticBody2D` (per-row merge) с `RectangleShape2D` — сокращает число тел с ~1000+ до ~200–400.
5. Инстансирует `door.tscn` (`Area2D`) на `exit_position`.
6. Публикует поля для потребителей:
   - `player_start: Vector2`
   - `enemy_spawn_positions: Array[Vector2]`
   - `chest_positions: Array[Vector2]`
   - `door: Area2D`
   - `floor_size: Vector2`
   - `layout: DungeonLayout` (для доступа к rooms из Main — используется при спавне босса)

## Использование в Main

`scenes/main.gd::_ready`:

1. `_spawn_floor()` — инстансирует `Floor`, добавляет как первого child (чтобы фон был позади).
2. `_place_player()` — телепортирует игрока в `_floor.player_start`.
3. `_configure_camera_limits()` — устанавливает лимиты у `Player.Camera2D` по `floor_size`, чтобы камера не «выезжала» за пределы этажа.
4. Подключает `_floor.door.player_entered → _on_door_entered → GameState.next_floor()`.
5. `_spawn_enemies()` — по `_floor.enemy_spawn_positions` спавнит случайных врагов из `ENEMY_SCENES`. Для boss-этажа — один босс в центре комнаты через `_spawn_boss()`.
6. `_spawn_chests()` — по `_floor.chest_positions` инстансирует `Chest`.

## Дверь (`door.tscn`)

Не изменилась структурно с прошлой архитектуры: `Area2D` со скриптом `door.gd`, сигнал `player_entered`, методы `open()` / `_set_closed()`. Только теперь она живёт внутри `Floor`, а не внутри статической комнаты.

## Тесты

`test/unit/test_dungeon_generator.gd` (13 тестов):

- Number of rooms scales with floor (min/max clamping).
- Boss floor invariants: single room, no corridors, no enemies, no chests.
- `player_start` внутри первой комнаты, `exit_position` внутри последней.
- Все `enemy_spawns` внутри какой-то комнаты, ни один не в стартовой.
- Chest только на кратных 3 этажах.
- Детерминизм: одинаковый seed → идентичный layout.
- Разные seed → разные layout.
- Нормализация: `floor_bounds.position = (0, 0)`, все координаты неотрицательны.
- `floor_bounds` enclose'ит все rooms и corridors.

## Пределы и планы

- Все стены — прямоугольники в grid 20×20; не используется TileMap. При переходе на TileMap с terrain autotile можно перерисовать без изменения алгоритма.
- Merge стен только по строкам, не по столбцам — можно оптимизировать при необходимости.
- Комнаты — просто прямоугольники без декора (стулья, свечи, ящики). Задел на будущее.
- Дверь появляется в стене последней комнаты; можно сделать визуальный акцент (тайлы «лестница вниз»).
- Room graph — цепочка, без ответвлений. Можно добавить side-branches для реиграбельности.
