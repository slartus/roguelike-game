# Башня и этажи

Игра — забег по **башне**. Игрок телепортируется на верхний этаж и пробивается вниз, глубже. Каждый этаж — процедурно сгенерированный «слой» из нескольких комнат, расположенных в grid и соприкасающихся стенами через дверные проёмы.

**Лор:** «Мы телепортировались на самый верх башни с N уровнями. Каждый уровень — этаж башни сверху вниз. Башня расширяется к низу — чем глубже, тем шире планировка. Пока мы не добрались до подвалов, уровни не должны быть сильно растянуты — компактные grid'ы комнат, соединённых простыми проходами в общих стенах.»

Терминология:
- **Этаж** (`floor`) = один сегмент забега (`GameState.current_floor_number`).
- **Комната** (`room`) = один прямоугольник 140×100 в grid.
- **Дверной проём** (`doorway`, тип `corridor` в структуре) = проход шириной 40 px в общей стене между соседними комнатами.
- **Выход** (`Door`) = `Area2D`, ведущий на следующий этаж.

## Генератор — `DungeonGenerator`

`scenes/dungeon/dungeon_generator.gd` (`class_name DungeonGenerator`). Метод `generate(seed, floor_number, is_boss) → DungeonLayout`.

### Алгоритм tower-этажа

1. **Grid dimension.** `grid_dim_for_floor(floor_number) = clampi(2 + (floor - 1) / 3, 2, 5)`.

   | Этажи | Grid | Комнат |
   |-------|------|--------|
   | 1–3 | 2×2 | 4 |
   | 4–6 | 3×3 | 9 |
   | 7–9 | 4×4 | 16 |
   | 10+ | 5×5 | 25 (cap) |

2. **Размещение комнат.** Каждая комната — `ROOM_SIZE = 140×100`. Между соседними комнатами — общая стена `WALL_THICKNESS = 20`. Cell step = `(ROOM_SIZE + WALL_THICKNESS) = (160, 120)`.

3. **Дверные проёмы.** Для каждой пары соседей по grid (справа/снизу) в общей стене пробит `DOORWAY_WIDTH = 40` px проход. Позиция проёма — случайная, с отступом `DOORWAY_MARGIN = 20` от углов комнаты. Проёмы в структуре layout лежат в поле `corridors: Array[Rect2i]` (историческое имя; для tower это именно короткие doorway-прямоугольники в стене).

4. **Player start** — центр верхней левой комнаты `(0, 0)` (мы прыгнули с верха башни).

5. **Exit** — центр нижней правой комнаты `(grid_dim-1, grid_dim-1)` (глубже в башню).

6. **Enemy spawns** — 2–3 точки в каждой комнате, **кроме** стартовой и exit.

7. **Chest** — на этажах, кратных 3 (`CHEST_FLOOR_INTERVAL = 3`), одна точка в случайной средней комнате.

8. **Нормализация** — `floor_bounds.position = (0, 0)`, все координаты неотрицательны.

### Boss-этаж

`floor_number % 5 == 0` → один большой 600×400 зал. Никаких обычных врагов и сундуков. `Player.start` слева, `exit_position` справа.

### Константы

| Константа | Значение | Смысл |
|-----------|----------|-------|
| `ROOM_SIZE` | 140×100 | Фиксированный размер комнаты (7×5 tiles) |
| `WALL_THICKNESS` | 20 | Толщина общей стены между соседями (1 tile) |
| `DOORWAY_WIDTH` | 40 | Ширина проёма (2 tiles) |
| `DOORWAY_MARGIN` | 20 | Отступ проёма от угла комнаты |
| `FLOOR_PADDING` | 60 | Отступ bounds от края комнат |
| `ENEMY_SPAWN_MARGIN` | 22 | Отступ спавна от стены |
| `MIN_GRID` / `MAX_GRID` | 2 / 5 | Границы размера grid |
| `CHEST_FLOOR_INTERVAL` | 3 | Каждый N-й этаж — сундук |
| `BOSS_ROOM_SIZE` | 600×400 | Арена босса |

## Данные — `DungeonLayout`

`scenes/dungeon/dungeon_layout.gd` (`class_name DungeonLayout`). Чистая структура данных:

| Поле | Тип | Смысл |
|------|-----|-------|
| `rooms` | `Array[Rect2i]` | Прямоугольники комнат (row-major, top-left первая) |
| `corridors` | `Array[Rect2i]` | Дверные проёмы в общих стенах между соседями |
| `player_start` | `Vector2i` | Точка телепортации (центр верхней левой комнаты) |
| `exit_position` | `Vector2i` | Точка выхода (центр нижней правой) |
| `enemy_spawns` | `Array[Vector2i]` | Позиции для врагов |
| `chest_positions` | `Array[Vector2i]` | Позиции для сундуков |
| `floor_bounds` | `Rect2i` | Границы этажа, `position = (0, 0)` |
| `is_boss_floor` | `bool` | Флаг boss-этажа |

## Рендер — `scenes/dungeon/floor.tscn` + `floor.gd`

`Floor` — Node2D, при `_ready()`:

1. Вызывает `DungeonGenerator.generate(seed, floor_number, is_boss)`.
2. Рисует **фон** — Polygon2D с `BACKGROUND_COLOR`.
3. Рисует **пол** — Polygon2D с `FLOOR_TEXTURE` (`assets/sprites/environment/floor.png`), UV в абсолютных координатах → бесшовный тайлинг между комнатами и проёмами.
4. Строит **стены** — grid 20×20 tile'ов. Для каждой tile-cell, не входящей ни в комнату, ни в проём, создаётся StaticBody2D + RectangleShape2D. Смежные wall-tiles в одной строке объединяются (per-row merge). Визуал — Polygon2D с `WALL_TEXTURE`, UV в абсолютных координатах → кирпичный узор непрерывен.
5. Инстансирует `door.tscn` на `exit_position`.
6. Публикует `player_start`, `enemy_spawn_positions`, `chest_positions`, `door`, `floor_size`, `layout` для потребителей.

## Тайлы окружения

- `assets/sprites/environment/floor.png` (20×20) — каменные плитки со швами.
- `assets/sprites/environment/wall.png` (20×20) — тёмная кирпичная кладка (running bond).

UV — абсолютные координаты этажа. Стыки между комнатами / проёмами / стенами бесшовные.

Тайлы генерируются детерминированно из `tools/gen_environment_sprites.py`.

## Использование в Main

`scenes/main.gd::_ready`:

1. `_spawn_floor()` — инстансирует `Floor`, добавляет как первого child.
2. `_place_player()` — телепортирует в `_floor.player_start`.
3. `_configure_camera_limits()` — камера Player'а клампится к `floor_size`.
4. `_door.player_entered → GameState.next_floor()`.
5. `_spawn_enemies()` — по `_floor.enemy_spawn_positions`. Для boss-этажа — один босс в центре.
6. `_spawn_chests()` — по `_floor.chest_positions`.

## Тесты

`test/unit/test_dungeon_generator.gd` (13 тестов):
- Grid dimension scales every 3 floors, capped at MAX_GRID.
- Number of doorway connectors = `2 * N * (N-1)` для NxN grid.
- Boss floor: один room, никаких проходов/enemies/chests.
- Player start внутри top-left комнаты, exit внутри bottom-right.
- Enemy spawns внутри какой-то комнаты, ни один не в стартовой/exit.
- Chest только на этажах кратных 3.
- Детерминизм по seed, разные seed → разные позиции проёмов.
- Нормализация до `(0, 0)`, все координаты неотрицательны.
- `floor_bounds` enclose'ит все комнаты и проёмы.
- Более глубокие этажи имеют больше комнат.

## Планы

- **Подвалы** — глубокие этажи (например 15+) должны стать более «пещерными»: длинные коридоры между не-adjacent комнатами, ветвления, тупики. Заготовка на будущее — переключение по `floor_number > BASEMENT_THRESHOLD` на другую генерацию.
- **Специальные комнаты** — trap rooms, altar rooms, treasure rooms с уникальной планировкой внутри grid.
- **Секретные проходы** — скрытые проёмы, которые видны только после активации какого-то триггера.
