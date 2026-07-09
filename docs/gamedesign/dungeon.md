# Башня и этажи

Игра — забег по **башне**. Игрок телепортируется на верхний этаж и пробивается вниз. Каждый этаж — процедурно сгенерированное **жилое пространство**: комнаты разных размеров (кладовочки, гостиные, залы), соединённые дверьми в общих стенах. Не каждая пара соседних комнат имеет проход — часть смежных комнат просто соприкасается стенами, что даёт residential feel.

Терминология:
- **Этаж** (`floor`) = один сегмент забега (`GameState.current_floor_number`).
- **Комната** (`room`) = один прямоугольник в footprint'е, размер 80–200 px по стороне.
- **Дверной проём** (`doorway`, тип `corridor` в структуре) = проход шириной 40 px в общей стене между соседями.
- **Выход** (`Door`) = `Area2D`, ведущий на следующий этаж.

## Генератор — `DungeonGenerator` (BSP + MST + extra edges)

`scenes/dungeon/dungeon_generator.gd` (`class_name DungeonGenerator`). Метод `generate(seed, floor_number, is_boss) → DungeonLayout`.

Классический BSP dungeon algorithm (Rogue / NetHack / RogueSharp) с MST-связностью и небольшой долей случайных дополнительных дверей для циклов.

### Алгоритм tower-этажа

1. **Footprint.** `footprint_tiles_for_floor(floor_number) → Vector2i` (в tile-координатах, тайл = 20 px).

   | Этажи | Footprint (tiles) | Footprint (px) |
   |-------|-------------------|----------------|
   | 1–3 | 20×14 | 400×280 |
   | 4–6 | 23×16 | 460×320 |
   | 7–9 | 26×18 | 520×360 |
   | 10+ | 29×20 → cap 40×28 | 580×400 → 800×560 |

2. **BSP split.** Recursive splitting региона:
   - Направление split'а — по длинной стороне (с 20% шансом flip'а для variety).
   - Split point выбирается в диапазоне 30–70% длины через `rng.randf_range(SPLIT_MIN_RATIO, SPLIT_MAX_RATIO)`.
   - На линии разреза резервируется **1 tile для стены** (даёт точное `a.end.x + WALL_THICKNESS == b.position.x` соседство).
   - Стоп: `depth >= MAX_BSP_DEPTH`, обе половины `< MIN_REGION_TILES`, или (после depth 3) `rng.randf() < 0.15` — сохраняет большие залы.

3. **Комнаты в leaves.** В каждом leaf-регионе комната сжимается на `0..2` тайла с каждой стороны, дополнительно клампится до `MAX_ROOM_TILES = 10` (200 px). Минимум — `MIN_ROOM_TILES = 4` (80 px, кладовочка).

4. **Adjacency graph.** Для каждой пары комнат вычисляется `_shared_wall`. Стена засчитывается как «пригодная для двери» только если overlap ≥ `MIN_SHARED_WALL = 80` (иначе комнаты просто соприкасаются углами / малой частью стены — прохода нет).

5. **MST (Kruskal + Union-Find).** Edge weight = отрицательная длина shared-wall (широкие стены приоритетнее для основных проходов). Tiebreak — `(min(a, b), max(a, b))` для детерминизма при одинаковом seed. Гарантирует связность всех комнат.

6. **Extra edges.** `ceili(remaining_edges * 0.25)` дополнительных ребер из non-MST adjacencies выбираются случайно (Fisher-Yates prefix с `rng`). Создают циклы → игрок может обойти комнату двумя маршрутами.

7. **Прунинг лишних дверей.** До `SKIP_DOORWAY_RATIO = 0.35` доли уже выбранных дверей пытаются удалиться. Каждый кандидат — если после удаления BFS-от-нуля покрывает все комнаты (граф остался связным) → удаляем. Так остаётся часть смежных пар с общей стеной, но **без прохода** — residential feel.

8. **Doorway carving.** Для каждого оставшегося ребра пробивается 40-px проход в общей стене со случайной позицией `[wall_lo + DOORWAY_MARGIN, wall_hi - DOORWAY_MARGIN - DOORWAY_WIDTH]`.

8. **Player start / exit.** `player_start` = центр комнаты, минимизирующей `position.x + position.y` (верхний-левый угол). `exit_position` = центр комнаты, максимизирующей `end.x + end.y` (нижний-правый).

9. **Enemy spawns.** 2–3 точки в каждой комнате, кроме start и exit. Число слотов ограничивается площадью комнаты (маленькие комнаты — 1–2 врага).

10. **Chest.** Логика без изменений: `floor % 3 == 0` → одна точка в случайной middle-комнате.

11. **Нормализация.** `floor_bounds.position = (0, 0)`, все координаты неотрицательны.

### Boss-этаж

`floor_number % 5 == 0` → одна большая арена `BOSS_ROOM_SIZE = 600×400`. Без изменений.

### Константы

| Константа | Значение | Смысл |
|-----------|----------|-------|
| `TILE` | 20 | Размер тайла (совпадает с `TILE_SIZE` в `floor.gd`) |
| `MIN_ROOM_TILES` / `MAX_ROOM_TILES` | 4 / 10 | Размер комнаты 80–200 px по стороне |
| `MIN_REGION_TILES` | 6 | Минимальный регион для дальнейшего сплита |
| `MAX_BSP_DEPTH` | 6 | Ограничение глубины дерева |
| `SPLIT_MIN_RATIO` / `SPLIT_MAX_RATIO` | 0.30 / 0.70 | Диапазон точки сплита |
| `ROOM_INSET_MAX_TILES` | 2 | Random shrink комнаты внутри leaf |
| `EARLY_STOP_CHANCE` | 0.15 | Шанс не сплитить после depth 3 (большие залы) |
| `WALL_THICKNESS` | 20 | Толщина общей стены (1 tile) |
| `DOORWAY_WIDTH` | 40 | Ширина прохода (2 tiles) |
| `DOORWAY_MARGIN` | 20 | Отступ прохода от углов комнаты |
| `MIN_SHARED_WALL` | 80 | Мин. overlap двух комнат чтобы считать их «adjacent для двери» |
| `EXTRA_EDGE_RATIO` | 0.25 | +25% случайных дверей сверх MST |
| `SKIP_DOORWAY_RATIO` | 0.35 | Доля дверей, которые пробуем удалить (только если reachability сохраняется) |
| `FLOOR_PADDING` | 60 | Отступ от края bounds |
| `ENEMY_SPAWN_MARGIN` | 22 | Отступ спавна от стены комнаты |
| `CHEST_FLOOR_INTERVAL` | 3 | Каждый N-й этаж — сундук |
| `BOSS_ROOM_SIZE` | 600×400 | Арена босса |

## Данные — `DungeonLayout`

`scenes/dungeon/dungeon_layout.gd` (`class_name DungeonLayout`). Чистая структура данных, контракт не меняется:

| Поле | Тип | Смысл |
|------|-----|-------|
| `rooms` | `Array[Rect2i]` | Комнаты (BSP DFS-порядок) |
| `corridors` | `Array[Rect2i]` | Дверные проёмы в общих стенах |
| `player_start` | `Vector2i` | Центр верхней левой комнаты |
| `exit_position` | `Vector2i` | Центр нижней правой |
| `enemy_spawns` | `Array[Vector2i]` | Позиции врагов |
| `chest_positions` | `Array[Vector2i]` | Позиции сундуков |
| `floor_bounds` | `Rect2i` | Границы этажа, `position = (0, 0)` |
| `is_boss_floor` | `bool` | Флаг boss-этажа |

## Рендер — `scenes/dungeon/floor.tscn` + `floor.gd`

Без изменений — генератор поменял алгоритм, но контракт с `Floor` тот же. `Floor`:
1. Вызывает `DungeonGenerator.generate(...)`.
2. Рисует фон, пол и стены с textures + `texture_repeat` (см. «Тайлы окружения» ниже).
3. Инстансирует `door.tscn` на `exit_position`.
4. Публикует `player_start`, `enemy_spawn_positions`, `chest_positions`, `door`, `floor_size`, `layout`.

Портал (открытая дверь) визуально живой: `door.gd` в `open()` включает эмиссию `CPUParticles2D` с фиолетовой пылью и запускает `_process`, который через синус-пульсацию `sin(_shimmer_time)` мерцает `modulate` sprite'а между тёплым фиолетовым (`brightness ≈ 0.75`) и белым пиком (`brightness ≈ 1.15`) с частотой ~2 пульсации/сек. При `_set_closed()` эмиссия и `_process` выключаются, чтобы закрытые двери не тратили ресурсы.

## Тайлы окружения

- `assets/sprites/environment/floor.png` (20×20) — каменные плитки со швами.
- `assets/sprites/environment/wall.png` (20×20) — тёмная кирпичная кладка (running bond).

UV — абсолютные координаты этажа. Стыки между комнатами / проёмами / стенами бесшовные.

## Декор — `floor.gd::_place_decor`

Поверх пола и стен раскладываются мелкие декали как `Sprite2D` без коллизии, в отдельном узле `DecorRoot` (рендерится поверх `WallsRoot`). Все спрайты процедурные, генерируются `tools/gen_decor_sprites.py`.

| Спрайт | Размер | Куда ставится | Шанс на подходящий тайл |
|--------|--------|---------------|-------------------------|
| `mold.png` — лишайник/мох | 18×14 | стена, обращённая «лицом» в комнату (тайл-пол снизу) | 14% |
| `candle.png` — настенный канделябр | 12×18 | там же | 5% |
| `floor_crack.png` — трещина | 14×10 | любой floor-тайл | 3% |
| `floor_blood.png` — засохшее кровяное пятно | 14×10 | любой floor-тайл | 1.5% |

**Приоритет.** Для одного тайла выбирается ровно один декор: сначала пробуем «редкий» (candle / blood), при неудаче — «частый» (mold / crack). Это удерживает канделябры и кровь как акценты, а плесень и трещины — как фоновый эффект.

**Почему не кости.** Ранняя версия использовала маленький череп на полу, но пользователь заметил, что он визуально путается с активными предметами (пикапами, мобами). Заменён на кровяное пятно с брызгами — тёмно-бордовое, несимметричное, без узнаваемых форм, однозначно читается как декор.

**Детерминизм.** Отдельный `RandomNumberGenerator` с seed `_pick_seed() * 31 + 7` — тот же tower_seed + номер этажа даёт то же расположение декора при повторном забеге.

**Что не считается «стеной, обращённой в комнату».** Тайл внутри толщины стены (сверху и снизу — стена) или на нижней границе `floor_bounds`. Так канделябр никогда не «висит» на внутренней грани стены, где игрок его физически не увидит.

**Мерцание канделябра.** Кандеябр — не просто `Sprite2D`, а сцена `scenes/dungeon/candle.tscn`: корневой Sprite2D свечи + дочерний Sprite2D-ореол с радиальным `GradientTexture2D` (56×56) и `CanvasItemMaterial` в режиме `BLEND_MODE_ADD` (`show_behind_parent = true`, чтобы свет ложился за спрайтом на стену). Скрипт `candle.gd` в `_process` считает мерцание как `slow_sin + fast_jitter*0.35` (медленная синусоида + быстрый мелкий джиттер → неровное «живое» пламя): `modulate` свечи пульсирует по яркости ±15% от тёплого `Color(1.0, 0.95, 0.85)`, ореол синхронно меняет `scale` ±18% и `alpha` ±0.13 вокруг базовых `1.0` и `0.30`. `alpha` самой свечи всегда `1.0` — спрайт не должен становиться полупрозрачным на пиках. В `_ready` каждый канделябр получает случайную фазу `randf() * TAU`, чтобы соседние канделябры не мерцали в унисон. Радиус ореола (~1.5 тайла) и базовая alpha 0.30 подобраны так, чтобы свечение было заметно, но не забивало соседние тайлы пола и не мешало читать врагов и пикапы.

**Настоящих 2D-огней (`PointLight2D` + `CanvasModulate`) нет намеренно.** Реальное освещение потребовало бы затемнить весь уровень через `CanvasModulate`, что изменило бы тональность всей игры — это отдельная архитектурная задача, а не декор. Additive-ореол даёт визуальный эффект «света» вокруг канделябра без переделки рендер-конвейера и без цены на fill-rate от десятков `PointLight2D`.

## Использование в Main

Без изменений. `main.gd::_ready`:
1. `_spawn_floor()` — инстансирует `Floor`.
2. `_place_player()` — телепортирует в `_floor.player_start`.
3. `_configure_camera_limits()` — камера клампится к `floor_size`.
4. `_door.player_entered → GameState.next_floor()`.
5. `_spawn_enemies()` — по `_floor.enemy_spawn_positions`.
6. `_spawn_chests()` — по `_floor.chest_positions`.

## Тесты

`test/unit/test_dungeon_generator.gd`:

**Общие инварианты** (сохранены при переходе с grid → BSP):
- Boss floor: 1 room, 0 corridors, 0 enemies, 0 chests.
- Player start в top-left комнате, exit в bottom-right.
- Все enemy spawns внутри какой-то комнаты, ни один в start/exit.
- Chest только на этажах кратных 3.
- Same seed → identical layout.
- Different seeds → different layouts.
- Нормализация: `floor_bounds.position = (0, 0)`, координаты неотрицательны.
- `floor_bounds` enclose'ит все rooms и corridors.
- Более глубокие этажи имеют больше комнат.

**BSP-specific**:
- `test_footprint_scales_with_floor` — footprint растёт с этажом, кап 40×28.
- `test_rooms_vary_in_size` — `max_area >= 2 * min_area` (разные размеры).
- `test_all_rooms_reachable_via_doorways` — BFS через doorways посещает все комнаты (MST guarantees).
- `test_start_reaches_exit_via_doorways` — start достигает exit.
- `test_has_cycles_on_floor_4_plus` — `corridors.size() > rooms.size() - 1` (25% extra edges создают циклы).
- `test_some_adjacent_rooms_have_no_doorway_on_floor_7` — часть смежных пар без doorway.

## Планы

- **Подвалы** — глубокие этажи (например 15+) должны стать «пещерными»: длинные извилистые коридоры, cellular automata caves, ветвления и тупики. Заготовка на будущее — переключение по `floor_number > BASEMENT_THRESHOLD` на другой алгоритм.
- **Специальные комнаты** — trap rooms, altar rooms, treasure rooms с уникальной планировкой внутри leaf'а.
- **Секретные проходы** — скрытые doorways, видимые только после активации триггера.
- **Комнаты необычной формы** (L, T) — пока все прямоугольные; можно комбинировать несколько соседних leaf'ов через shape merge.
