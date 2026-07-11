# Башня и этажи

Игра — забег по **башне**. Игрок телепортируется на верхний этаж и пробивается вниз. Каждый этаж — процедурно сгенерированное **жилое пространство**: комнаты разных размеров (кладовочки, гостиные, залы), соединённые дверьми в общих стенах. Не каждая пара соседних комнат имеет проход — часть смежных комнат просто соприкасается стенами, что даёт residential feel.

Терминология:
- **Этаж** (`floor`) = один сегмент забега (`GameState.current_floor_number`).
- **Комната** (`room`) = один прямоугольник в footprint'е, размер 80–200 px по стороне.
- **Дверной проём** (`doorway`, тип `corridor` в структуре) = проход шириной 40 px в общей стене между соседями.
- **Выход** (`Door`) = `Area2D`, ведущий на следующий этаж.
- **Зона** (`zone`) = вертикальный участок мира башни (`TowerZone.ZONE_*`).
- **Архетип этажа** (`floor_archetype`) = конкретный тип генерации (`legacy_bsp`, `boss_arena`, позже `residential_spine`, `technical_grid`).

## Вертикальные зоны мира башни

Игрок стартует наверху и спускается вниз. Мир разделён на 6 зон, определяемых чисто по номеру этажа:

| Этажи | Zone | Что должно ощущаться |
|---|---|---|
| 1–2 | `tower_top` | Верхние помещения башни, чердачные комнаты, кабинеты |
| 3–6 | `residential` | Жилые этажи — спальни, гостиные, кухни, кабинеты |
| 7–10 | `technical` | Служебные этажи — машинные, щитовые, вентиляция |
| 11–14 | `lower_tower` | Нижняя разрушенная башня, склады, руины |
| 15–18 | `basement` | Подвалы, фундамент, каменные камеры |
| 19+ | `caves` | Естественные пещеры под башней |

Логика в `scenes/dungeon/tower_zone.gd::TowerZone.get_tower_zone(floor_number)`. Каждая `DungeonLayout` при генерации получает `layout.zone` и `layout.floor_archetype`.

Пещерный стиль намеренно уходит в поздние этажи — верхние должны ощущаться архитектурно (жильё, служебные помещения), а не как пещеры. Legacy BSP генератор в M1 всё ещё обрабатывает все non-boss этажи (`floor_archetype = "legacy_bsp"`), но zone metadata уже помечена — это позволит следующим milestone'ам постепенно переключать верхние зоны на archetype'ы `residential_spine` / `technical_grid`.

Boss floors (`floor % 5 == 0`) сохраняют старую логику: `floor_archetype = "boss_arena"`, `zone` тоже заполняется (тот же расчёт по этажу) — для будущего thematic-декора boss-арен.

## Роли комнат (`room_infos`)

Каждая комната получает `room_info: Dictionary` с полями:

| Поле | Смысл |
|---|---|
| `room_index` | индекс в `layout.rooms` |
| `role` | назначение комнаты (`entrance`, `bedroom`, `machine_room`, ...) |
| `zone` | зона мира (совпадает с `layout.zone`) |
| `tags` | свойства: `[zone, size_tag, ...]` (`small`/`medium`/`large`, а также `treasure`/`entrance`/`exit`) |
| `danger` | int, используется room-aware spawn budget'ом |

Логика в `scenes/dungeon/room_roles.gd::RoomRoles.assign_roles(layout, rng)`. Правила v1:

1. **start room → `entrance`** — комната, содержащая `player_start`.
2. **exit room → `exit_core`** — комната с `exit_position`.
3. **chest room → `treasure_room`** — комнаты, содержащие точки из `chest_positions`.
4. **остальные** — случайная роль из `ZONE_ROLE_POOL[zone]` (детерминировано по seed).
5. **boss floor** — все комнаты (обычно одна арена) получают `boss_arena`.

Пулы ролей по зонам:

| Zone | Возможные роли |
|---|---|
| `tower_top` | study, storage, ruined_room, small_room |
| `residential` | bedroom, living_room, kitchen, study, storage, small_room |
| `technical` | machine_room, boiler_room, switch_room, storage, corridor |
| `lower_tower` | warehouse, storage, ruined_room, small_room |
| `basement` | basement_cell, storage, ruined_room |
| `caves` | cave_chamber, ruined_room |

Размер комнаты определяется через `size_tag_for_area(area)`:
- `< 6400 px²` → `small`,
- `> 12000 px²` → `large`,
- иначе — `medium`.

**Danger v1** (`compute_danger(role, zone)`):
- treasure_room → +1;
- dangerous zone (lower_tower/basement/caves) → +1;
- dangerous role (machine_room/boiler_room/ruined_room/cave_chamber) → +1.

Например `treasure_room` в `caves` даёт danger = 2. Это пригодится room-aware spawn budget'у (см. `enemies.md::MonsterSpawnTable`).

## Декор по зонам и ролям

Каждая tile проходит через `DecorProfiles.decor_profile_for_room(role, zone)` (внутри room'а) или `decor_profile_for_zone(zone)` (в коридорах / промежутках). Профиль — Dictionary `{floor: [...], wall: [...]}` со списком разрешённых типов декора.

**Ключевой инвариант M3.** Верхние зоны (`tower_top`, `residential`, `technical`) фильтруются от cave-only декора (`mold`, `crack`, `blood`, `candle`, `bones`, `stone_rubble`) в `decor_profile_for_room`. Даже если role (например `ruined_room` в `tower_top`) технически бы предлагала эти типы, они удаляются в `_strip_cave_only`. Это предотвращает ситуацию когда жилой этаж внезапно покрывается мхом.

**Типовые профили ролей:**

| Role | Wall | Floor |
|---|---|---|
| `bedroom` | bed, wardrobe | rug, small_table |
| `living_room` | cabinet, bookshelf | rug, small_table, chair |
| `kitchen` | cabinet, shelf | small_table, chair |
| `study` | bookshelf, cabinet | small_table, chair |
| `machine_room` | pipe, cable_bundle | machine_block, valve |
| `boiler_room` | pipe, vent | boiler, valve |
| `switch_room` | cable_bundle, vent | switch_box |
| `basement_cell` | mold, candle | crack, stone_rubble |
| `ruined_room` | mold, candle | crack, broken_furniture, stone_rubble |
| `cave_chamber` | mold | crack, stone_rubble, bones, blood |
| `treasure_room` | candle, shelf | crate, rug |
| `entrance`/`exit_core`/`boss_arena` | — | — (пустые, чтобы не блокировать критические точки) |

**Zone fallback** для tile вне rooms (коридоры):

| Zone | Wall | Floor |
|---|---|---|
| `tower_top`, `residential` | — | — |
| `technical` | pipe | — |
| `lower_tower` | mold | crack |
| `basement` | mold, candle | crack, stone_rubble |
| `caves` | mold | crack, stone_rubble, blood |

**Реальные спрайты пока есть только для cave-декора** (`mold.png`, `candle.tscn`, `floor_crack.png`, `floor_blood.png`). Профили верхних зон существуют как контракт — `floor.gd` пока их не рисует (нет ассетов), но rooms с этими профилями не получают cave-декор из-за фильтрации. Спрайты residential/technical декора — задача под следующие milestone'ы или отдельные фичи.

## Residential Spine floors

Для зон `tower_top` (floor 1-2) и `residential` (floor 3-6) генератор выбирает архетип `residential_spine` — план здания с центральным коридором и комнатами по обе стороны. Реализация в `scenes/dungeon/residential_spine_generator.gd::ResidentialSpineGenerator.generate(layout, rng, floor_number, footprint_tiles)`.

Схема:
```
+---------------------------------------+
| room1 | room2 | room3 | room4 | room5 |
|--D------D-------D-------D-------D-----|
|                                       |
|            main corridor              |
|                                       |
|--D------D-------D-------D-------D-----|
| room6 | room7 | room8 | room9 |room10 |
+---------------------------------------+
```

Ключевые параметры (в тайлах, TILE = 20 px):
- `CORRIDOR_WIDTH_TILES = 3` (60 px) — комфортная ширина для игрока.
- `ROOM_MIN_WIDTH_TILES = 4`, `ROOM_MAX_WIDTH_TILES = 8` — 80..160 px по X.
- `ROOM_MIN/MAX_DEPTH_TILES = 4..6` — 80..120 px по Y.
- `DOORWAY_WIDTH_TILES = 2` (40 px) — совместимо с legacy контрактом.

Алгоритм:
1. Горизонтальный main corridor в вертикальной середине — `Rect2i` по всей ширине этажа.
2. Верхний ряд комнат: cursor слева, шаг = случайная ширина комнаты + 1 tile стена между. Между низом комнат и верхом коридора зарезервирован ещё 1 tile — стена, в которую пробивается doorway.
3. Каждая комната получает doorway — узкий corridor rect 40×20 px через эту 1-tile стену.
4. Симметрично снизу от коридора.
5. `player_start` = центр левого конца corridor, `exit_position` = центр правого.
6. Enemy spawns добавляются в каждую комнату (2-3 на комнату), кроме entrance / exit.
7. Chest — в случайной комнате на этажах кратных `CHEST_FLOOR_INTERVAL = 3`.

Room roles применяются как обычно: комната содержащая chest → `treasure_room`. Player_start и exit_position лежат в коридоре, а не в комнате — `RoomRoles._find_room_containing` через fallback находит ближайшую по центру, ей ставится `entrance` / `exit_core`.

Boss floors (`floor % 5 == 0`) в residential zone всё ещё получают `boss_arena`, а не spine — boss логика имеет приоритет.

## Technical Grid floors

Для зоны `technical` (floor 7-10) генератор выбирает архетип `technical_grid`. Реализация — `scenes/dungeon/technical_grid_generator.gd`. Внешне схема остаётся spine-подобной (main corridor + rooms сверху/снизу), но параметры отличают служебный этаж от жилого:

| Параметр | Residential Spine | Technical Grid |
|---|---|---|
| `CORRIDOR_WIDTH_TILES` | 3 (60 px, комфорт) | 2 (40 px, узкий служебный) |
| Room width | 4-8 tiles (жилая) | 3 tiles (closet) или 8-12 (машинная) |
| Room depth | 4-6 tiles | 5-7 tiles (глубже) |
| Mix | равномерные bedroom/study/kitchen | случайные small closet (35%) + большие машинные |

Small closets между большими машинными дают классический служебный feel: пара крупных генераторов + пара маленьких щитков. Room roles приходят из `ZONE_ROLE_POOL["technical"]` (`machine_room`, `boiler_room`, `switch_room`, `storage`, `corridor`).

Контракт стен и дверных проёмов — тот же, что у residential_spine: между низом верхних комнат и верхом служебного коридора (симметрично снизу) зарезервирован 1 tile стены, в который пробивается doorway 40×20 px. Без этой прослойки комнаты сливались бы с коридором в открытый альков.

Boss floor 10 остаётся `boss_arena` независимо от zone — boss логика имеет приоритет.

## Нижняя башня, подвалы и пещеры

Zone → archetype диспетчер в `DungeonGenerator.generate`:

| Zone | Floor | Archetype |
|---|---|---|
| `tower_top` | 1-2 | `residential_spine` |
| `residential` | 3-6 (кроме boss 5) | `residential_spine` |
| `technical` | 7-10 (кроме boss 10) | `technical_grid` |
| `lower_tower` | 11-14 | `ruined_bsp` |
| `basement` | 15-18 (кроме boss 15) | `basement_bsp` |
| `caves` | 19+ | `caves_bsp` |

**Ruined / basement / caves BSP** — это тот же самый BSP-код что и оригинальный legacy_bsp. Физически `_generate_tower_floor` не переписан: разница между тремя archetype-именами — только явный tag в metadata, который позволяет тестам, spawn tables и будущим генераторам отличать «руины нижней башни» от «подвал» и «пещеры» без изменения геометрии.

Тематическое различие достигается через:
- **`ZONE_ROLE_POOL`** — разные роли комнат (см. таблицу в разделе Room roles).
- **`ZONE_FALLBACK_PROFILES`** — разный декор коридоров.
- **cave-декор разрешён только в этих трёх зонах** — верхние (`tower_top`, `residential`, `technical`) фильтруются `_strip_cave_only` (см. секцию «Декор по зонам»).

**Пещерный стиль намеренно является поздней зоной мира башни, а не основным стилем всех этажей.** Игрок, спустившийся до floor 19+, должен ощущать что он уже не в здании — вот теперь это пещеры под фундаментом башни. Верхние этажи с floor 1 — жилые/технические уровни, где cave-визуал был бы неуместен.

Легаси `_generate_tower_floor` (BSP+MST+extra edges) остаётся неизменным — его алгоритм ниже. В M6 он **не удалён и не переписан**, только явно закреплён за нижними зонами.

## World abstraction (заготовка)

`scenes/dungeon/world_zones.gd::WorldZones` — минимальный abstraction слой под будущие миры (гора, дерево и т.п.). Публичный API:

```gdscript
const WORLD_TOWER := "tower"
static func get_zone_for_world(world_id: String, floor_number: int) -> String
```

Пока реализован только `WORLD_TOWER` — возвращает `TowerZone.get_tower_zone(floor_number)`. Unknown world молча fallback'ит на tower (не крешит генератор, но и не пытается угадать зоны неизвестного мира).

**Планируемое / не реализовано:**

- `mountain`: summit → monastery → mines → deep caves.
- `tree`: canopy → branches → trunk → roots → mycelium.

Реальные генераторы для этих миров, их зон, ролей и декора — отдельные фичи. Сейчас в проекте есть только tower, и `GameState`/`DungeonGenerator` опираются на `TowerZone` напрямую. Переключение на `WorldZones` — будущая задача, когда появится второй мир.

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

## Материалы окружения и профили зон

Начиная с PR 1 «Environment materials and zone identity» башня перестала выглядеть как один материал на весь забег. Каждая зона получает свой `EnvironmentVisualProfile`, а роль комнаты может ещё раз переопределить материал пола.

### `EnvironmentVisualProfile`

`scenes/dungeon/environment_visual_profile.gd` (`class_name EnvironmentVisualProfile`) — Resource с полями:

| Поле | Смысл |
|---|---|
| `id: StringName` | ID зоны (совпадает с `TowerZone.ZONE_*`) |
| `background_color: Color` | Заливка `FloorsRoot` под всеми rect'ами |
| `default_floor_material: StringName` | Материал пола комнаты, если нет override по роли |
| `corridor_floor_material: StringName` | Материал пола коридора/дверного проёма |
| `default_wall_material: StringName` | Материал стен всего этажа |
| `room_role_floor_overrides: Dictionary` | `role → material_id`, приоритетнее default |
| `room_role_wall_overrides: Dictionary` | Тоже для стен (в этом PR используется редко) |
| `ambient_tint: Color` | Заготовка под будущий color grading |
| `detail_density_multiplier: float` | Заготовка под density-декор PR 2 |

Регистр — `scenes/dungeon/environment_visual_profiles.gd` (`class_name EnvironmentVisualProfiles`). Публичный API:

```gdscript
static func for_zone(zone: StringName) -> EnvironmentVisualProfile
static func has_zone(zone: StringName) -> bool
static func all_zones() -> Array
static func resolve_floor_material(zone, role, is_corridor) -> StringName
static func resolve_wall_material(zone, role) -> StringName
```

Приоритеты `resolve_floor_material`:

1. `corridor_floor_material` — если `is_corridor == true`, независимо от роли.
2. `room_role_floor_overrides[role]` — если роль есть в override'ах.
3. `default_floor_material` — иначе.

Неизвестная зона резолвится через FALLBACK (`tower_top`) — генератор не крешит.

### Zone → материалы

| Zone | Default floor | Corridor floor | Default wall |
|---|---|---|---|
| `tower_top` | `wood_floor` | `corridor_stone` | `plaster_wall` |
| `residential` | `wood_floor` | `corridor_stone` | `wood_panel_wall` |
| `technical` | `reinforced_stone` | `stone_metal_grid` | `technical_stone_wall` |
| `lower_tower` | `damaged_tower_stone` | `damaged_tower_stone` | `tower_stone_wall` |
| `basement` | `wet_basement_stone` | `wet_basement_stone` | `basement_brick_wall` |
| `caves` | `cave_ground` | `cave_ground` | `natural_cave_wall` |

Ключевые инварианты:

- **`caves` не используют regular tower brick.** `natural_cave_wall` — органическая скала без кладки. Игрок, спустившийся в пещеры, визуально ощущает переход из здания в природу.
- **`basement` уходит в холодную сине-серую палитру.** `wet_basement_stone` + `basement_brick_wall` резко отличаются от жилых этажей.
- **`technical` сохраняет fantasy identity.** Медные полосы и рунические каналы — не современный индустриал; палитра сдвинута в латунь/медь.

### Room role overrides (residential + technical)

| Zone | Role | Floor override |
|---|---|---|
| `tower_top` | `study` | `dark_wood_floor` |
| `residential` | `bedroom`, `living_room`, `storage` | `wood_floor` |
| `residential` | `study` | `dark_wood_floor` |
| `residential` | `kitchen` | `light_stone_tile` |
| `technical` | `machine_room`, `storage` | `reinforced_stone` |
| `technical` | `boiler_room` | `heat_stained_stone` |
| `technical` | `switch_room` | `stone_metal_grid` |

Wall overrides: `residential/kitchen` → `plaster_wall` (кухня со светлыми стенами вместо панелей). Для остальных пока используется `default_wall_material` зоны — стены разделяют две комнаты, единой роли у стены нет.

### Каталог материалов

`scenes/dungeon/environment_material_catalog.gd` (`class_name EnvironmentMaterialCatalog`). Data-driven регистр `EnvironmentMaterial` по `StringName`-ID. Материалы задаются в коде (не как `.tres`), потому что их немного, список стабилен и служит контрактом для тестов.

Минимальный набор PR 1:

- **Floor:** `wood_floor`, `dark_wood_floor`, `corridor_stone`, `light_stone_tile`, `reinforced_stone`, `stone_metal_grid`, `heat_stained_stone`, `damaged_tower_stone`, `wet_basement_stone`, `cave_ground`.
- **Wall (face + cap):** `plaster_wall`, `wood_panel_wall`, `tower_stone_wall`, `technical_stone_wall`, `basement_brick_wall`, `natural_cave_wall`.
- **Doorway:** `doorway_threshold` — общий overlay поверх corridor'а, визуально маркирующий границу между room material и corridor material.

Все текстуры лежат в `assets/sprites/environment/*.png` и генерируются `tools/gen_environment_sprites.py`. Legacy `floor.png` / `wall.png` сохранены совместимо с существующими preload'ами тестов.

### Wall cap distinct from solid wall

Толстые (2+ tile) горизонтальные стены имеют верхний ряд без коллизии (`cap`) — сохраняется top-down эффект глубины (см. секцию Cap-tiles ниже). PR 1 сделал cap **визуально отличным** от solid wall: у каждого wall материала есть `wall_texture` (для solid) и `wall_cap_texture` (для cap). Cap текстура автоматически выводится из face — верхние 6 px осветлены на ~35%, чтобы кромка читалась как «козырёк».

Инвариант проверяется в `test_environment_material_resolution.gd::test_wall_and_cap_are_different_textures`: для каждого wall материала `wall_texture.resource_path != wall_cap_texture.resource_path`.

### Детерминизм материалов

Резолвинг материала — pure функция от `(zone, room_role, is_corridor)`, без RNG. `layout.zone` и `room_infos[i].role` уже детерминированы `DungeonGenerator` от `tower_seed`, поэтому:

- Тот же `tower_seed` + `current_floor_number` всегда даёт ту же раскладку материалов.
- Cosmetic-RNG (декор в `_place_decor`) отделён от gameplay RNG (генерация layout) — cosmetic получает `tower_seed * 31 + 7`, gameplay — `tower_seed * 100003 + floor_number`. Ни один cosmetic-путь не влияет на количество или расположение комнат.

Инвариант проверяется в `test_floor_material_rendering.gd::test_same_seed_produces_same_material_sequence` и `test_layout_room_count_matches_between_two_runs_with_same_seed`.

### Ограничение PR 1: мебель и физические props

PR 1 добавил только материалы пола и стен + wall cap distinction + doorway threshold. **Мебель, физические props, интерактивные объекты и новый layout этажей** — задачи PR 2 «Room props and atmospheric decoration» и PR 3 «Larger levels and layout topology». `detail_density_multiplier` на профиле — заготовка под density-логику PR 2, сейчас не читается.

## Тайлы окружения

- `assets/sprites/environment/floor.png` (20×20) — legacy floor.
- `assets/sprites/environment/wall.png` (20×20) — legacy wall.

Плюс полный набор материалов из PR 1 (см. предыдущий раздел).

UV — абсолютные координаты этажа. Стыки между комнатами / проёмами / стенами бесшовные.

### Cap-tiles (walkable верхушка толстых стен)

Когда `ROOM_INSET_MAX_TILES = 2` даёт стену толщиной 2+ tile между вертикально соседствующими комнатами (верхняя комната → толстая стена → нижняя комната), **верхний ряд** этой стены рендерится как `Polygon2D` без `StaticBody2D` — чистый визуал без коллизии. Игрок и враги могут визуально «зайти» под кромку такой стены сверху вниз на 1 tile, создавая эффект глубины top-down: перед персонажем есть кирпичная стена, но реально он стоит в проходимом пространстве.

Классификация делает `_wall_kind_at(col, row)`:
- **cap** — этот tile — wall, tile сверху — floor, tile снизу — тоже wall. Только визуал, без коллизии. AStarGrid помечает как проходимый.
- **solid** — обычная стена: либо снизу этажа/пусто, либо снизу тоже комната. Полный `StaticBody2D + CollisionShape2D + Polygon2D`. AStarGrid — solid.

Merge горизонтальных span'ов делается отдельно для `cap` и `solid` (два прохода по каждому row), потому что это разные Godot-объекты. UV `Polygon2D` продолжает бесшовную кирпичную кладку с соседями обоих видов.

**Пули тоже пролетают через cap** — нет `StaticBody2D` → нет `PhysicsBody2D` для `body_entered`. Это намеренно и консистентно с walkability: где проходит персонаж, туда летит пуля. Игроку это может показаться неожиданным (визуально стена, но выстрел не блокируется), поэтому важно чтобы cap отличались визуально — в текущей версии cap визуально идентичен solid, но по геометрии это узкий 1-tile «козырёк» перед основной стеной.

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

`main.gd::_ready`:
1. `_spawn_floor()` — инстансирует `Floor`.
2. `_place_player()` — телепортирует в `_floor.player_start`.
3. `_configure_camera_limits()` — камера клампится к `floor_size`.
4. `_door.player_entered → GameState.next_floor()`.
5. `_spawn_enemies()` — по `_floor.enemy_spawn_positions`.
6. `_spawn_chests()` — по `_floor.chest_positions`.

### Обычный enemy spawn (не boss)

DungeonGenerator даёт **позиции** (`enemy_spawn_positions`) — но не решает, кто именно будет стоять в каждой. Это делает `Main._spawn_enemies()`:

1. Заводит детерминированный `RandomNumberGenerator` с seed'ом `tower_seed × 100003 + current_floor_number × 9176 + 1337` — так один и тот же (tower_seed, floor) даёт один и тот же набор монстров при повторных прохождениях. Глобальный `randi/randf` не используется — он был бы несовместим с shared random state (`randomize()` в `_ready`).
2. Для каждой позиции spawn'а:
   - `MonsterSpawnTable.get_eligible_defs(floor, ["generic"])` — фильтр по floor gating.
   - `MonsterSpawnTable.choose_weighted(defs, rng)` — weighted-random выбор конкретного монстра.
   - `roll_monster_level(...)` / `roll_elite_rank(...)` — вычисление effective level и elite rank.
   - `enemy.configure_spawn(level, elite)` **до** `add_child` — иначе `_ready` уже прогонит scaling на дефолтном level=0.
   - Все остальные подключения (`pickup_scene`, `died_at`, `tree_exited`) как раньше.

### Boss floor

Boss floor (`current_floor_number % 5 == 0`) обрабатывается отдельно — MonsterSpawnTable в этот путь не заходит. Boss спавнится в центре первой комнаты, обычные монстры на boss-этаже не появляются.

## Пропы комнат — `RoomDecorationPlanner`

PR 2 добавил room-level планировщик пропов поверх `_place_decor` из PR 1. Legacy per-cell декали (mold/candle/crack/blood) остались — они по-прежнему украшают стены и полы нижних зон, но мебель, стеллажи, машины, кровати и cave-props теперь размещаются планировщиком **по одной комнате целиком**.

### Категории пропов

Каждый prop — `EnvironmentPropDefinition`, одна из шести категорий (`scenes/dungeon/environment_prop_definition.gd::ALL_CATEGORIES`):

| Категория | Блокирует движение | Пример |
|-----------|:---:|--------|
| `floor_decal` | нет | ковёр, кости, щебень, floor-решётка, корни |
| `wall_surface` | нет | картина, труба, вентиль, полка, цепи |
| `wall_adjacent_prop` | да | кровать, шкаф, стеллаж, стол, верстак, койка |
| `floor_prop` | да | малый столик, стул, ящик, бочка, гриб, кристалл |
| `large_prop` | да | котёл, рунический двигатель, алхимическая колба, сталагмит |
| `interactive` | резерв | зарезервировано для PR 4 (сундуки как props, ловушки) |

Все ID пропов (`EnvironmentPropCatalog.PROP_*`) — стабильный контракт: имя `.png` в `assets/sprites/props/<id>.png` совпадает с константой каталога. Тесты `test_environment_prop_definition.gd::test_all_prop_ids_are_unique` фиксируют уникальность.

### `EnvironmentPropDefinition` (data-driven)

Одно определение хранит:

| Поле | Что описывает |
|------|---------------|
| `id: StringName` | стабильный идентификатор |
| `category: StringName` | одна из ALL_CATEGORIES |
| `texture: Texture2D` | fallback-визуал (в PR 2 все пропы через texture, PackedScene — future) |
| `scene: PackedScene` | опциональная сцена (резерв под сложные пропы) |
| `footprint_cells: Vector2i` | занимаемое место в клетках TILE=20 px |
| `blocks_movement: bool` | попадает ли в AStar как solid |
| `blocks_projectiles: bool` | зарезервировано под PR 4 |
| `allowed_zones: Array[StringName]` | пустой = везде |
| `allowed_room_roles: Array[StringName]` | пустой = все роли |
| `allowed_wall_sides: Array[StringName]` | зарезервировано |
| `weight: int` | вес в weighted roll (детерминированный) |
| `min_room_size_cells: Vector2i` | комнаты меньше — prop не ставится |
| `clearance_cells: int` | зарезервировано |
| `can_rotate`, `mirror_allowed` | зарезервировано |

Каталог собирается в коде (`EnvironmentPropCatalog._build`), как и `EnvironmentVisualProfiles` — единый источник истины, без `.tres`, чтобы тесты видели опечатки на этапе компиляции.

### Pipeline планировщика

`RoomDecorationPlanner.plan_floor(layout, reservations, tower_seed, floor_number) -> FloorPlan` для каждой комнаты выполняет:

1. Собирает `local grid` (Dictionary Vector2i→int) — свободные и зарезервированные клетки в пределах room rect.
2. Резервирует **doorway anchors** — клетки внутри room, смежные с corridor'ом.
3. Резервирует **клиренс** одной клетки вглубь room от каждого doorway anchor'а.
4. Между всеми парами doorway anchors резервирует **L-путь** (Manhattan) — гарантированный маршрут.
5. Уважает **внешние reservations** — player start, exit, chest, enemy spawns (см. ниже).
6. Выбирает **signature prop** — характерный объект роли (`bed` для bedroom, `boiler` для boiler_room и т.п.).
7. Заполняет **wall-adjacent → large → floor** до достижения `blocking budget` из таблицы плотности.
8. Добавляет **wall surfaces** (картины, трубы) — non-blocking.
9. Добавляет **floor decals** (ковры, кости, корни, floor-решётка) — non-blocking.
10. Для каждого blocking placement делает **connectivity pre-check** — BFS от одного doorway anchor'а к остальным по free/reserved/decal клеткам. Если пропа ломает связность — placement отклоняется.

Результат — `FloorPlan.placements: Array[Placement]` и `blocked_cells: Dictionary`. Floor.gd инстанциирует placements как Sprite2D + optional StaticBody2D и передаёт blocked_cells в AStar.

### Reservations (что резервируется до planner'а)

`Floor._collect_reservations()` собирает клетки, где planner не должен ставить блокирующий prop:

| Anchor | Радиус в клетках |
|--------|:---:|
| `player_start` | 2 |
| `exit_position` | 2 |
| `chest_positions` | 1 |
| `enemy_spawns` | 1 |

Radius = размер квадратного клирнса вокруг anchor'а. Клетки corridor'ов planner не занимает по геометрии (они вне room rect). Doorway anchors резервируются самим planner'ом.

### Connectivity guarantee

Для комнаты с 2+ дверями planner обеспечивает: между **любой** парой doorway anchors существует путь по не-blocking клеткам (free / reserved / decal / wall-surface). Blocking placement, ломающий связность, откатывается на этапе _try_place_prop. Тест `test_prop_navigation_integration.gd::test_all_doors_of_room_remain_connected` проверяет инвариант через реальный layout.

### Signature prop правило

Каждая тематическая роль в достаточно большой комнате получает как минимум один характерный объект:

| Роль | Signature |
|------|-----------|
| bedroom | bed |
| study | desk / bookshelf |
| kitchen | workbench / cabinet / barrel |
| living_room | wardrobe / bookshelf |
| storage | crate / barrel |
| machine_room | rune_engine / alchemical_vat |
| boiler_room | boiler |
| basement_cell | cot / chains |
| cave_chamber | stalagmite / mushroom |

Исключения: комната слишком мала (< 4×4 клетки для big props), entrance/exit/boss_arena, placement нарушает связность.

### Плотность (blocking footprint budget)

`RoomDecorationPlanner.DENSITY_LIMIT_PER_ROLE` задаёт долю площади комнаты, которую можно занять блокирующими пропами:

| Категория ролей | Лимит |
|-----------------|:---:|
| entrance / exit / boss_arena | 5–8% |
| treasure_room / small_room | 12% |
| bedroom / living_room / study | 20% |
| kitchen | 18% |
| storage / warehouse | 28% |
| machine_room / boiler_room | 25% |
| switch_room | 18% |
| ruined_room / basement_cell | 15% |
| cave_chamber | 18% |

Fallback для незнакомых ролей — 15%. Planner копит `blocked_area_cells` и останавливается при превышении. Тест `test_prop_occupancy.gd::test_density_does_not_exceed_role_limit` фиксирует лимит с допуском ±5%.

### Композиции по ролям

Композиции определяются каталогом (`allowed_room_roles` в каждом `.gd`-определении):

- **Bedroom** → bed (wall-adjacent), wardrobe, small_table, chair, rug, wall_picture.
- **Living room** → wardrobe, bookshelf, cabinet, chair, small_table, rug, wall_picture.
- **Kitchen** → cabinet, workbench, barrel, sack, crate, shelf.
- **Study** → desk, bookshelf, chair, cabinet, rug, wall_picture.
- **Storage/Warehouse** → crate, barrel, sack, shelf, broken_crate, rope_coil.
- **Machine room** → rune_engine, alchemical_vat, pipe_straight, valve, floor_grate, workbench.
- **Boiler room** → boiler, alchemical_vat, pipe_straight, valve, floor_grate, barrel.
- **Basement cell** → cot, chains, bucket, bones, rubble, broken_crate.
- **Cave chamber** → stalagmite, mushroom, crystal, bones, rubble, roots.

Тесты `test_room_compositions.gd` фиксируют, что residential зоны никогда не получают cave/technical props, а cave-chamber никогда не получает residential пропы (кровать, шкаф, письменный стол).

### Детерминизм пропов

Seed каждой комнаты внутри planner'а:

```
absi(tower_seed * 2654435761
     + floor_number * 40503
     + room_index * 92821
     + role_hash * 314159
     + zone_hash * 27183) + 1
```

Это отдельный stream от gameplay RNG (`tower_seed * 100003 + floor_number` в DungeonGenerator) и от cosmetic decal RNG (`tower_seed * 31 + 7` в _place_decor). Тесты `test_room_decoration_planner.gd::test_deterministic_same_seed_same_plan` и `test_decor_rng_does_not_affect_gameplay_generator` проверяют оба свойства:

1. Тот же (tower_seed, floor, room, role, zone) → тот же placement plan.
2. Прогон planner'а не сдвигает generator RNG (rooms/enemy_spawns/exit не меняются между двумя `DungeonGenerator.generate()` с одним seed'ом).

### AStar интеграция

`Floor._build_astar_grid` сначала помечает solid стены (по геометрии), затем добавляет все `floor_plan.blocked_cells` через `astar_grid.set_point_solid(cell, true)`. Ключевые инварианты:

- Blocking prop (footprint 2×1 или 2×2) полностью блокирует свои клетки — AI не идёт сквозь мебель.
- Floor decal (ковёр, кости, корни) — passable, `blocks_movement=false`, клетки НЕ попадают в blocked_cells.
- Wall surface (картина, труба) — passable, размещается в клетках у стены как маркер, но не в blocked_cells.
- Summoned creature (lich/boss) вычисляет fallback позицию по AStar, значит не появится внутри пропа.

Проверяется в `test_prop_navigation_integration.gd::test_astar_marks_blocking_prop_cells_as_solid` и `test_astar_leaves_decal_cells_walkable`.

### Z-order

Внутри Floor сцены порядок Node2D-детей (передний план внизу списка):

1. `FloorsRoot` — background + floor tiles + doorway thresholds.
2. `WallsRoot` — стены и cap-tiles.
3. `DecorRoot` — legacy стенные decals (mold, candle, crack, blood).
4. `PropsRoot` — все пропы planner'а (декали + мебель + стены).
5. `MarkersRoot` — дверь-переход.

Игрок и враги живут выше на уровне Main. Внутри `PropsRoot` порядок добавления соответствует порядку `FloorPlan.placements`.

### Placeholder art

Спрайты — процедурные PNG размером `footprint * TILE`, генерируются `tools/gen_prop_sprites.py` (31 prop). Каждый prop имеет отличительный силуэт (bed = длинный с подушкой, boiler = медный круг с трубой и пламенем, mushroom = ножка + шляпка с пятнами), чтобы placeholder сразу читался. При регенерации спрайта — обновляй именно генератор, не .png в редакторе.

### Ограничение PR 2

- Пропы не интерактивны — категория `interactive` зарезервирована под PR 4 (destructibles, containers, traps).
- Wall-surface рендерится как обычный Sprite2D в клетке у стены, не как child StaticBody стены — визуально «прилипает» к стене, но геометрически лежит на floor cell.
- `PackedScene` для пропов пока не используется — все пропы через `texture`. Сцены — под PR 4 (интерактивные пропы).
- Размер этажа не увеличен — layout topology остаётся BSP из PR 1. Уровни глобально не растут (задача PR 3).

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

**Пропы и planner** (PR 2):
- `test_environment_prop_definition.gd` — уникальность prop ID, валидные категории/textures, filter по зоне/роли, fits_in_room.
- `test_room_decoration_planner.gd` — signature prop для bedroom/study/machine_room/boiler_room/cave_chamber, детерминизм по seed, отсутствие сдвига gameplay RNG, blocking props уважают reservations, props внутри room rect, wall_adjacent касается стены, маленькая комната остаётся sparse.
- `test_prop_occupancy.gd` — doorway anchors не заняты, chest/enemy_spawn/entrance clear zones уважаются, blocking props не пересекаются, density не превышает role limit, decals не блокируют движение.
- `test_prop_navigation_integration.gd` — Floor.gd интегрирует plan → AStar solid, decal cells остаются walkable, все двери одной комнаты связаны после placement (через реальный BSP layout).
- `test_room_compositions.gd` — residential зоны никогда без cave props, tower_top без technical, caves без residential, композиции детерминированы между запусками.

## Планы

- **Подвалы** — глубокие этажи (например 15+) должны стать «пещерными»: длинные извилистые коридоры, cellular automata caves, ветвления и тупики. Заготовка на будущее — переключение по `floor_number > BASEMENT_THRESHOLD` на другой алгоритм.
- **Специальные комнаты** — trap rooms, altar rooms, treasure rooms с уникальной планировкой внутри leaf'а.
- **Секретные проходы** — скрытые doorways, видимые только после активации триггера.
- **Комнаты необычной формы** (L, T) — пока все прямоугольные; можно комбинировать несколько соседних leaf'ов через shape merge.
