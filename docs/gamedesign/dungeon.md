# Башня и этажи

Игра — забег по **башне**. Игрок телепортируется на верхний этаж и пробивается вниз. Каждый этаж — процедурно сгенерированное **жилое пространство**: комнаты разных размеров (кладовочки, гостиные, залы), соединённые дверьми в общих стенах. Не каждая пара соседних комнат имеет проход — часть смежных комнат просто соприкасается стенами, что даёт residential feel.

Терминология:
- **Этаж** (`floor`) = один сегмент забега (`GameState.current_floor_number`).
- **Комната** (`room`) = один прямоугольник в footprint'е, размер 80–280 px по стороне.
- **Дверной проём** (`doorway`, тип `corridor` в структуре) = проход шириной 40 px в общей стене между соседями. Для нижних зон (caves) тем же типом обозначаются tunnel'ы.
- **Выход** (`Door`) = `Area2D`, ведущий на следующий этаж.
- **Зона** (`zone`) = вертикальный участок мира башни (`TowerZone.ZONE_*`).
- **Архетип этажа** (`floor_archetype`) = конкретный тип генерации (`residential_spine`, `technical_grid`, `ruined_bsp`, `basement_bsp`, `caves_natural`, `boss_arena`, `fallback_room`).
- **Room graph** (`layout.room_graph`) = ненаправленный граф смежности комнат по проходам. Строится генератором явно (spine/technical/caves) или через `RoomGraph.build_from_doorways` (BSP). Используется для выбора entrance/exit, critical path и encounter budget.
- **Critical path** (`layout.critical_path_indices`) = комнаты на shortest entrance→exit пути в графе.

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

Пещерный стиль намеренно уходит в поздние этажи — верхние должны ощущаться архитектурно (жильё, служебные помещения), а не как пещеры. С PR 3 верхние зоны генерируются собственными генераторами (`ResidentialSpineGenerator`, `TechnicalGridGenerator`), нижние `lower_tower`/`basement` используют BSP-код с v2-параметрами, а `caves` уходит в новый `NaturalCaveGenerator`.

Boss floors (`floor % 5 == 0`) сохраняют старую логику: `floor_archetype = "boss_arena"`, `zone` тоже заполняется (тот же расчёт по этажу) — для будущего thematic-декора boss-арен.

### Целевые размеры footprint (PR 3)

Envelope в пикселях по зонам — `DungeonFootprint.footprint_tiles_for_zone(zone, floor_number)` линейно интерполирует min→max по прогрессии этажа внутри зоны:

| Zone | Min | Max |
|---|---|---|
| `tower_top` | 600×400 | 680×460 |
| `residential` | 680×440 | 760×520 |
| `technical` | 720×480 | 840×560 |
| `lower_tower` | 760×520 | 920×640 |
| `basement` | 820×560 | 960×680 |
| `caves` | 840×600 | 1000×720 |

Первый этаж (tower_top floor 1) заметно шире viewport (640 px) — с PR 3 больше нет «этаж влезает в один экран».

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

## Residential Spine floors (v2)

Для зон `tower_top` (floor 1-2) и `residential` (floor 3-6) генератор выбирает архетип `residential_spine`. Реализация в `scenes/dungeon/residential_spine_generator.gd::ResidentialSpineGenerator.generate(layout, rng, floor_number, footprint_tiles)`.

С PR 3 topology расширена: помимо основного коридора добавлены (по возможности) wing-комнаты в перпендикулярном под-коридоре и room-to-room shortcut. Граф явно моделируется как ladder-топология (top-row chain + bottom-row chain + cross-links через main corridor), что даёт множество loop'ов и минимум одну branch на большинстве seeds.

Схема:
```
                wing corridor
                     │
             ┌───────┼───────┐
             │ w0    │ w1    │
             └───┬───┴───┬───┘
                 │       │           ↑ wing rooms (branch)
+------+---------+-------+------+---------+
| room1| room2   | host  | room4| room5   |
|--D-----D---------D-------D-------D------|
|                                          |
|            main corridor                 |
|                                          |
|--D-----D---------D-------D-------D------|
| room6| room7   | room8 | room9 |room10   |
+------+-----+---+-------+------+---------+
             ↑ shortcut между room7↔room8 создаёт loop.
```

Ключевые параметры (TILE = 20 px):
- `CORRIDOR_WIDTH_TILES = 3` (60 px) — комфортная ширина.
- `ROOM_MIN/MAX_WIDTH_TILES = 4..8`, `ROOM_MIN/MAX_DEPTH_TILES = 4..6`.
- `WING_MIN/MAX_WIDTH_TILES = 4..6`, `WING_DEPTH_TILES = 4`, `WING_CORRIDOR_WIDTH_TILES = 2`.
- `DOORWAY_WIDTH_TILES = 2` (40 px).

Алгоритм:
1. Main corridor в вертикальной середине.
2. Верхний ряд: cursor слева, шаг = случайная ширина комнаты + 1 tile стены. Между низом комнат и верхом коридора — 1 tile под doorway.
3. Каждая комната получает 40×20 px doorway.
4. Нижний ряд симметрично.
5. **Wing** (если помещается — top band должен вместить wing rooms над host):
   - host выбирается как средняя top-комната;
   - wing corridor (тонкий, 40 px) уходит вверх от host;
   - две wing-комнаты (left и right от wing corridor) с собственными doorway'ями.
6. **Shortcut** (если найдётся пара смежных side rooms в одном ряду) — вертикальный 20×40 px doorway между двумя соседними комнатами; в графе появляется прямое ребро мимо основной цепочки.
7. `player_start`/`exit_position` — временные (концы коридора), финальные выставляются `EntranceExitSelector` по BFS-фарвест паре в графе (см. секцию «Entrance/exit selection»).

Room graph модель:
- Top-chain: `top_row[i]` ↔ `top_row[i+1]`.
- Bottom-chain: `bottom_row[i]` ↔ `bottom_row[i+1]`.
- Ladder cross-links: `top_row[i]` ↔ ближайший по X `bottom_row[j]` через main corridor.
- Host ↔ wing rooms, wing left ↔ wing right через wing corridor.
- Explicit shortcut → прямое ребро.

Chest и enemy_spawns — по общему pipeline (см. «Encounter budget» и «Rewards»).

Boss floors (`floor % 5 == 0`) в residential zone всё ещё получают `boss_arena`, а не spine — boss логика имеет приоритет.

## Technical Grid floors (v2)

Для зоны `technical` (floor 7-10) генератор выбирает архетип `technical_grid`. Реализация — `scenes/dungeon/technical_grid_generator.gd`. С PR 3 это настоящий двух-рельсовый служебный этаж.

Схема:
```
+--------------------------------------------------+
| maint0 | maint1 | maint2 | maint3 | maint4       |  ← верхняя maint-band
+--D--------D-------D--------D--------D------------+
════════════════════════════════════════════════════   ← top rail
+-----------+-----------+-----------+
| machine 0 | machine 1 | machine 2 |                ← middle band (крупные)
+-----------+-----------+-----------+
════════════════════════════════════════════════════   ← bottom rail
+--D--------D-------D--------D--------D------------+
| maint5 | maint6 | maint7 | maint8 | maint9       |  ← нижняя maint-band
+--------------------------------------------------+
```

Cross-connectors (не показаны) — 2-3 вертикальных corridor rects, соединяют top rail с bottom rail напрямую в промежутках между machine rooms. Дают дополнительные loops.

Ключевые параметры:
- `RAIL_WIDTH_TILES = 2` (40 px) — узкий служебный.
- `MAINT_MIN/MAX_WIDTH_TILES = 4..6`, `MAINT_MIN/MAX_DEPTH_TILES = 4..5`.
- `MACHINE_MIN/MAX_WIDTH_TILES = 8..12`, `MACHINE_MIN_DEPTH_TILES = 5`.
- Cross-connectors — до 3 штук, ширина `RAIL_WIDTH_TILES * TILE`.

Алгоритм:
1. Вертикальный layout: `TILE + maint_depth + TILE + rail + middle_band + rail + TILE + maint_depth + TILE`.
2. Два main corridor rect (top rail, bottom rail) на всю ширину.
3. Middle band — machine rooms с doorway'ями к ОБОИМ rails.
4. Top maint band — рядом с top rail, doorway'и вниз.
5. Bottom maint band — рядом с bottom rail, doorway'и вверх.
6. Cross-connectors выбираются рандомно из «свободных промежутков» между machine rooms.
7. Fallback single-rail при слишком узком footprint — просто один rail + maint по обе стороны (тот же паттерн, что residential).

Room graph модель:
- Top-chain, middle-chain, bottom-chain (все по X).
- Middle machine → ближайший по X top / bottom room.
- Ladder-графом → много loops + degree-3+ вершин.

Boss floor 10 остаётся `boss_arena` независимо от zone — boss логика имеет приоритет.

## Natural caves (PR 3)

Для зоны `caves` (floor 19+) генератор выбирает архетип `caves_natural`. Реализация — `scenes/dungeon/natural_cave_generator.gd`.

Отличие от BSP: chambers с randomised size/position + MST tunnels — нет grid-feel'а, но всё ещё rect-based (полное irregular boundary остаётся будущим улучшением, требует переработки wall-rendering в `floor.gd`).

Алгоритм:
1. Footprint делится на 3×3 grid slots (~9 регионов).
2. Из slots случайно (без замены) выбираются 5-9 → в каждом ставится chamber рандомного размера (4-9 tiles по стороне) с jitter внутри slot'а.
3. MST по расстоянию между центрами chambers (Kruskal + Union-Find).
4. Extra edges: 2 самые короткие non-MST → loops.
5. Для каждой edge вырезается L-shape tunnel (horizontal + vertical, порядок рандомен). Ширина tunnel — 40 px.
6. `layout.room_graph` строится по факту рёбер (без walk через doorway detection).

Инварианты:
- Каждый chamber доступен через MST → граф всегда связен.
- Минимум одна alternate connection на большинстве средних+ этажей (см. baseline metrics).
- Fallback: если placement провалился (< 2 chambers), кладём одну большую центральную; retry pipeline подхватит.

## Нижняя башня, подвалы, пещеры и boss

Zone → archetype диспетчер в `DungeonGenerator._generate_once`:

| Zone | Floor | Archetype |
|---|---|---|
| `tower_top` | 1-2 | `residential_spine` |
| `residential` | 3-6 (кроме boss 5) | `residential_spine` |
| `technical` | 7-10 (кроме boss 10) | `technical_grid` |
| `lower_tower` | 11-14 | `ruined_bsp` |
| `basement` | 15-18 (кроме boss 15) | `basement_bsp` |
| `caves` | 19+ (кроме boss) | `caves_natural` |
| — | boss (`floor % 5 == 0`) | `boss_arena` |
| — | fallback после retry | `fallback_room` |

**Ruined / basement BSP** — тот же BSP-код с v2-параметрами: `MAX_ROOM_TILES` подняли до 14 (большие залы), `EXTRA_EDGE_RATIO` до 0.35, `SKIP_DOORWAY_RATIO` снизили до 0.30. Физически `_generate_tower_floor` не переписан, только параметры.

**Caves теперь идут через `NaturalCaveGenerator`** (см. выше) — уходят от BSP grid-feel'а.

Тематическое различие достигается через:
- **`ZONE_ROLE_POOL`** — разные роли комнат.
- **`ZONE_FALLBACK_PROFILES`** — разный декор коридоров.
- **cave-декор разрешён только в нижних зонах** — верхние (`tower_top`, `residential`, `technical`) фильтруются `_strip_cave_only`.

Пещерный стиль намеренно является поздней зоной мира башни, а не основным стилем всех этажей.

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

## Генератор — `DungeonGenerator` (pipeline)

`scenes/dungeon/dungeon_generator.gd` (`class_name DungeonGenerator`). Метод `generate(seed, floor_number, is_boss) → DungeonLayout` — с PR 3 обёрнут в retry-pipeline с fallback.

### Retry + fallback

```
for attempt in _FALLBACK_MAX_RETRIES (3):
    derived_seed = seed_value ^ (0x9E3779B1 * (attempt + 1)) if attempt > 0 else seed_value
    candidate = _generate_once(derived_seed, floor_number, is_boss)
    if _is_layout_valid(candidate):
        return candidate
return _generate_minimal_fallback(seed_value, floor_number, is_boss)
```

Валидность (`_is_layout_valid`):
- boss: rooms.size() > 0;
- иначе: rooms.size() >= 2, player_start != exit_position, graph connected.

Fallback (`_generate_minimal_fallback`) — одна большая rectangular room 12×8 tiles с start/exit по краям. Гарантированно валидная, никогда не крешит игру. Всегда должен быть на карте `EventLog` при появлении.

### Pipeline `_generate_once`

1. **Router по zone** → делегирует одному из под-генераторов (Residential Spine / Technical Grid / BSP / NaturalCave) или `_generate_boss_floor`.
2. **`_compute_bounds` + `_normalize`** → floor_bounds на (0, 0).
3. **RoomGraph.** Non-boss: если под-генератор не выставил `layout.room_graph`, строится через `RoomGraph.build_from_doorways(rooms, corridors)` (используется BSP-путём).
4. **`_apply_graph_distance_entrance_exit`** — `EntranceExitSelector.choose(rooms, graph, zone)` выбирает пару по BFS-фарвест внутри eligible rooms (площадь ≥ 1600 px²). `player_start` и `exit_position` перезаписываются центрами выбранных комнат.
5. **Critical path** — `graph.shortest_path(entrance_room_index, exit_room_index)`.
6. **`_apply_reward_placement`** (до assign_roles!) — chests на `floor % 3 == 0`; кандидаты по приоритету dead-end → остальные; entrance/exit исключены; 1 chest на floor < 12, 2 на deeper.
7. **`RoomRoles.assign_roles`** — назначает `entrance`, `exit_core`, `treasure_room` (по chest_positions), остальные — из `ZONE_ROLE_POOL[zone]`.
8. **`_annotate_optional_and_dead_end`** — добавляет tags `dead_end`, `optional_reward`, `critical_path` в `room_infos[i].tags` на основе графа.
9. **`_apply_encounter_budget`** (non-boss) — для каждой комнаты `FloorEncounterBudget.room_budget(...)` считает max spawn count, генератор берёт `rng.randi_range(1, budget)` реальных точек. Итог обрезается по `FloorEncounterBudget.floor_cap(zone, floor_number)`.

### Footprint scaling

`footprint_tiles_for_floor(floor_number)` (legacy public API для тестов) → `DungeonFootprint.footprint_tiles_for_zone(zone, floor_number)`. Envelope растёт по зонам:

| Zone | Min tiles | Max tiles |
|---|---|---|
| `tower_top` | 30×20 | 34×23 |
| `residential` | 34×22 | 38×26 |
| `technical` | 36×24 | 42×28 |
| `lower_tower` | 38×26 | 46×32 |
| `basement` | 41×28 | 48×34 |
| `caves` | 42×30 | 50×36 |

Прогрессия внутри зоны линейно интерполирует min → max по `(floor - zone_start) / (zone_end - zone_start)`.

### Entrance / exit selection

`EntranceExitSelector.choose(rooms, graph, zone)` — новая логика с PR 3.

1. Отбирает eligible rooms (площадь ≥ 1600 px² — не альковы).
2. Ищет пару максимальной BFS-дистанции (2× BFS approximation диаметра).
3. Fallback: если пара свернулась в одну комнату, берёт любую другую из eligible.

Zone-specific hint `_ZONE_MIN_HOPS` (3–5) документирует ожидаемый минимальный critical path; фактическое значение подтверждает статистика (тесты `test_dungeon_layout_metrics`).

### Encounter budget

`FloorEncounterBudget.room_budget(room, room_info, floor_number, is_critical_path, distance_from_entrance)` возвращает max spawn count для одной комнаты:

- 0 для entrance / exit_core / boss_arena / tiny (< 3200 px²).
- Base = `area / 3600 slots`, clamped 1..3.
- + danger (macho +1..+2).
- - 1 для optional_reward / dead_end.
- - 1 для treasure_room.
- + 1 за каждые 3 хопа от entrance.
- clamped ≤ 3 на critical path.
- clamped ≤ 5 глобально.

`floor_cap(zone, floor)` — верхний хард-лимит суммарного количества врагов на этаже (18–26 в зависимости от zone + `floor / 3`). Пересечение суммарно drops наиболее глубокие спавны.

### Rewards

- Chests на этажах `floor % 3 == 0`.
- Кандидаты: сначала dead-end rooms (degree ≤ 1 в графе, не entrance/exit), затем остальные (не entrance/exit).
- Количество: 1 на `floor < 12`, 2 на deeper.
- Chest room затем помечается `treasure_room` role через RoomRoles.

### Boss-этаж

`floor_number % 5 == 0` → одна большая арена `BOSS_ROOM_SIZE = 600×400`. Пропускает всю ветвь room_graph / encounter budget / rewards — boss спавнится напрямую в `main.gd::_spawn_boss`.

### BSP алгоритм (для lower_tower / basement)

2. **BSP split.** Recursive splitting региона:
   - Направление split'а — по длинной стороне (с 20% шансом flip'а для variety).
   - Split point выбирается в диапазоне 30–70% длины через `rng.randf_range(SPLIT_MIN_RATIO, SPLIT_MAX_RATIO)`.
   - На линии разреза резервируется **1 tile для стены** (даёт точное `a.end.x + WALL_THICKNESS == b.position.x` соседство).
   - Стоп: `depth >= MAX_BSP_DEPTH`, обе половины `< MIN_REGION_TILES`, или (после depth 3) `rng.randf() < 0.15` — сохраняет большие залы.

3. **Комнаты в leaves.** В каждом leaf-регионе комната сжимается на `0..2` тайла с каждой стороны, дополнительно клампится до `MAX_ROOM_TILES = 14` (280 px, PR 3 v2 — большие залы). Минимум — `MIN_ROOM_TILES = 4` (80 px).

4. **Adjacency graph.** Для каждой пары комнат вычисляется `_shared_wall`. Стена засчитывается как «пригодная для двери» только если overlap ≥ `MIN_SHARED_WALL = 80`.

5. **MST (Kruskal + Union-Find).** Edge weight = отрицательная длина shared-wall. Tiebreak — `(min(a, b), max(a, b))` для детерминизма.

6. **Extra edges.** `ceili(remaining_edges * 0.35)` (v2, повышено с 0.25). Больше циклов на глубоких этажах.

7. **Прунинг лишних дверей.** До `SKIP_DOORWAY_RATIO = 0.30` (v2, снижено с 0.35) — меньше «глухих стен», больше проходов.

8. **Doorway carving.** Для каждого оставшегося ребра пробивается 40-px проход.

9. **Hint player_start / exit_position.** Legacy top-left / bottom-right — но эти значения перезаписываются `_apply_graph_distance_entrance_exit` в основном pipeline.

10. **Enemy spawns и chest** не выполняются в самом BSP-подгенераторе — post-processing (`_apply_encounter_budget`, `_apply_reward_placement`) владеет ими.

11. **Нормализация.** `floor_bounds.position = (0, 0)`, все координаты неотрицательны.

### Константы (BSP v2)

| Константа | Значение | Смысл |
|-----------|----------|-------|
| `TILE` | 20 | Размер тайла |
| `MIN_ROOM_TILES` / `MAX_ROOM_TILES` | 4 / **14** | Размер комнаты 80–280 px по стороне (PR 3: max ↑) |
| `MIN_REGION_TILES` | 6 | Минимальный регион для сплита |
| `MAX_BSP_DEPTH` | 6 | Ограничение глубины дерева |
| `SPLIT_MIN_RATIO` / `SPLIT_MAX_RATIO` | 0.30 / 0.70 | Диапазон точки сплита |
| `ROOM_INSET_MAX_TILES` | 2 | Random shrink комнаты внутри leaf |
| `EARLY_STOP_CHANCE` | 0.15 | Шанс не сплитить после depth 3 |
| `WALL_THICKNESS` | 20 | Толщина общей стены |
| `DOORWAY_WIDTH` | 40 | Ширина прохода |
| `DOORWAY_MARGIN` | 20 | Отступ прохода от углов комнаты |
| `MIN_SHARED_WALL` | 80 | Мин. overlap для двери |
| `EXTRA_EDGE_RATIO` | **0.35** | +35% случайных дверей сверх MST (PR 3: ↑) |
| `SKIP_DOORWAY_RATIO` | **0.30** | Доля дверей, которые пробуем удалить (PR 3: ↓) |
| `FLOOR_PADDING` | 60 | Отступ от края bounds |
| `ENEMY_SPAWN_MARGIN` | 22 | Отступ спавна от стены |
| `CHEST_FLOOR_INTERVAL` | 3 | Каждый N-й этаж — сундук |
| `BOSS_ROOM_SIZE` | 600×400 | Арена босса |
| `_FALLBACK_MAX_RETRIES` | 3 | Максимум retries для валидной геометрии |

## Данные — `DungeonLayout`

`scenes/dungeon/dungeon_layout.gd` (`class_name DungeonLayout`).

| Поле | Тип | Смысл |
|------|-----|-------|
| `rooms` | `Array[Rect2i]` | Комнаты (порядок = order of addition в генераторе) |
| `corridors` | `Array[Rect2i]` | Проходы, main rails, tunnels (per-generator семантика) |
| `player_start` | `Vector2i` | Центр entrance-комнаты (после EntranceExitSelector) |
| `exit_position` | `Vector2i` | Центр exit-комнаты |
| `enemy_spawns` | `Array[Vector2i]` | Позиции врагов после FloorEncounterBudget |
| `chest_positions` | `Array[Vector2i]` | Позиции сундуков после reward placement |
| `floor_bounds` | `Rect2i` | Границы этажа, `position = (0, 0)` |
| `is_boss_floor` | `bool` | Флаг boss-этажа |
| `zone` | `String` | TowerZone.ZONE_* |
| `floor_archetype` | `String` | Тип генерации (`residential_spine` / `technical_grid` / `ruined_bsp` / `basement_bsp` / `caves_natural` / `boss_arena` / `fallback_room`) |
| `room_infos` | `Array[Dictionary]` | По одному info на комнату (role/zone/tags/danger) |
| `room_graph` | `RoomGraph` | Граф смежности комнат по проходам (PR 3) |
| `entrance_room_index` | `int` | Индекс entrance-комнаты в `rooms` (PR 3) |
| `exit_room_index` | `int` | Индекс exit-комнаты (PR 3) |
| `critical_path_indices` | `Array[int]` | Комнаты на shortest entrance→exit пути (PR 3) |

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

Толстые (2+ tile) горизонтальные стены имеют верхний ряд с отдельной текстурой (`cap`) — это визуальное отличие «кромки» от основного массива стены. Коллизия у cap такая же, как у solid: игрок и мобы не проходят сквозь неё (детали — в секции «Cap-tiles (визуальная кромка толстых стен)» ниже). У каждого wall материала есть `wall_texture` (для solid) и `wall_cap_texture` (для cap). Cap текстура автоматически выводится из face — верхние 6 px осветлены на ~35%, чтобы кромка читалась как «козырёк».

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

### Cap-tiles (визуальная кромка толстых стен)

Когда `ROOM_INSET_MAX_TILES = 2` даёт стену толщиной 2+ tile между вертикально соседствующими комнатами (верхняя комната → толстая стена → нижняя комната), **верхний ряд** этой стены рендерится отдельной текстурой-«козырьком» (`cap`). Коллизия у cap такая же, как у solid — игрок и мобы не могут зайти в нижнюю стену снизу вверх. Cap отличается только текстурой (кромка со светлой полосой сверху), чтобы визуально читался «край» толстой стены, а не бесконечный однородный массив.

Классификация делает `_wall_kind_at(col, row)`:
- **cap** — этот tile — wall, tile сверху — floor, tile снизу — тоже wall. `StaticBody2D + CollisionShape2D + Polygon2D` с cap-текстурой. AStarGrid — solid.
- **solid** — обычная стена: либо снизу этажа/пусто, либо снизу тоже комната. `StaticBody2D + CollisionShape2D + Polygon2D` с face-текстурой. AStarGrid — solid.

Merge горизонтальных span'ов делается отдельно для `cap` и `solid` (два прохода по каждому row), потому что у span'а одна текстура. UV `Polygon2D` продолжает бесшовную кирпичную кладку с соседями обоих видов.

**Пули блокируются cap** — есть `StaticBody2D`, `body_entered` срабатывает как на обычной стене. Игрок и мобы физически не могут оказаться внутри клетки cap, поэтому «сюрпризов» вроде «стреляю в стену, а пуля пролетает» не бывает.

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
- Все enemy spawns внутри какой-то комнаты.
- Chest только на этажах кратных 3.
- Same seed → identical layout.
- Different seeds → different layouts.
- Нормализация: `floor_bounds.position = (0, 0)`, координаты неотрицательны.
- `floor_bounds` enclose'ит все rooms и corridors.
- Более глубокие этажи имеют больше комнат.

**BSP-specific**:
- `test_footprint_scales_with_floor` — footprint растёт с этажом.
- `test_rooms_vary_in_size` — `max_area >= 2 * min_area`.
- `test_all_rooms_reachable_via_doorways` — BFS через doorways посещает все комнаты.
- `test_start_reaches_exit_via_doorways` — start достигает exit.
- `test_has_cycles_on_floor_4_plus` — extra edges создают циклы.
- `test_some_adjacent_rooms_have_no_doorway_on_floor_7` — часть смежных пар без doorway.

**PR 3 — новые тестовые файлы:**
- `test_room_graph.gd` — базовые графовые примитивы (BFS, dead ends, branches, cycles, shortest path, build_from_doorways).
- `test_dungeon_footprint.gd` — envelope монотонно растёт по зонам, footprint растёт внутри зоны, первый этаж заметно шире viewport, unknown zone fallback.
- `test_floor_encounter_budget.gd` — entrance/exit → 0 budget, tiny room → 0, dangerous role boosts, optional_reward уменьшает, floor_cap растёт с zone и floor.
- `test_natural_cave_generator.gd` — archetype `caves_natural`, chambers ≥ 3, graph connected, tunnels ≥ 1, loops на большинстве seeds, вариация размеров, детерминизм.
- `test_dungeon_layout_metrics.gd` — статистические инварианты (connected, entrance→exit reachable, first residential > viewport, deeper floor > walkable, residential имеет branches, technical имеет loops, chest room получает treasure role, детерминизм).

**Пропы и planner** (PR 2):
- `test_environment_prop_definition.gd` — уникальность prop ID, валидные категории/textures, filter по зоне/роли, fits_in_room.
- `test_room_decoration_planner.gd` — signature prop, детерминизм по seed, отсутствие сдвига gameplay RNG.
- `test_prop_occupancy.gd` — doorway anchors, clear zones, blocking overlap, density.
- `test_prop_navigation_integration.gd` — plan → AStar solid, connectivity после placement.
- `test_room_compositions.gd` — фильтрация по zone.

## Gameplay-props (PR 4)

Отдельный слой props, у которых есть *взаимодействие*: destructibles,
hazards и lore. Ставится **поверх** декоративного слоя PR 2 —
декоративные объекты сохраняют свою природу (обычный `crate` в углу
storage room по-прежнему не разрушается, это тот же texture asset).

Различие обеспечивается через два новых поля в
`EnvironmentPropDefinition` (см. `scenes/dungeon/environment_prop_definition.gd`):

- `interaction_type: StringName` — `none` / `destructible` / `hazard_explosive` / `lore`.
- `category: CATEGORY_INTERACTIVE` — планировщик собирает эти props
  отдельным `_place_gameplay_props` pass'ом.

Дополнительно у каждого gameplay-def'а:

- `destructible_max_health: int` — HP для destructibles.
- `damage_factions: Array[StringName]` — какие фракции могут ранить
  (обычно `[FACTION_PLAYER]`).
- `explosion_radius / explosion_damage / explosion_telegraph_time` —
  для `interaction_type == hazard_explosive`.
- `lore_prompt_key / lore_text_key` — i18n ключи для `lore`.
- `max_per_room / max_per_floor` — жёсткие бюджеты сверху density limit.

### Каталог gameplay-props (PR 4)

| id                    | interaction         | HP | max/room | max/floor | Комментарий                                     |
|-----------------------|---------------------|---:|---------:|----------:|-------------------------------------------------|
| `destructible_crate`  | destructible        | 2  | 3        | 8         | wooden crate, low damage, чаще пустой           |
| `destructible_barrel` | destructible        | 3  | 2        | 6         | storage barrel, low/medium HP                   |
| `urn`                 | destructible        | 1  | 3        | 10        | ceramic urn/pot, HP=1 — бьётся с одного попадания |
| `explosive_barrel`    | hazard_explosive    | 2  | 1        | 3         | telegraph 0.55 s, R = 42 px, damage 3           |
| `lore_bookshelf`      | lore                | —  | 1        | 2         | `LORE_BOOKSHELF` snippet, `[E] Read` prompt     |

Оригинальные `crate` / `barrel` / `bookshelf` из PR 2 **остаются
декоративными** — их размещает `_plan_room` в обычном decorative pass'е.
Gameplay-варианты имеют отдельный `id`, но переиспользуют текстуру.

### Разрушение и drop-таблица

`DamageableEnvironmentProp` (см. `scenes/dungeon/damageable_environment_prop.gd`)
принимает `take_damage(amount)` от melee hitbox и bullet'а, при `_health <= 0`:

1. Один раз эмиттит `destroyed(prop_id, world_position)`.
2. Отключает collision через `set_deferred` (safe для body_entered
   callback'а).
3. `queue_free()` (наследники hazard могут отсрочить через
   `_keep_alive_after_destroy`).

`Floor.gd` слушает `destroyed`:

- Освобождает AStar cells → AI перестраивает путь на следующем recalc'е.
- Для non-hazard prop'ов — детерминированный roll через
  `EnvironmentDropTable` (`scenes/dungeon/environment_drop_table.gd`).

**Drop-таблица** (per-prop):

| Результат       | Chance | Value (в budget) |
|-----------------|-------:|-----------------:|
| Nothing         | 80 %   | 0                |
| Small gold      | 15 %   | 1                |
| Potion          | 4 %    | 3                |
| Rare gold stash | 1 %    | 5                |

Floor-wide cap — `FLOOR_TOTAL_VALUE_CAP = 12`. При исчерпании ролл
возвращает `RESULT_NONE`, даже если prop разбит.

Seed drop'а: `hash(tower_seed, floor_number, prop_id, placement_index)`.
Тот же placement на том же seed → тот же drop. Environment drop RNG
не пересекается с gameplay RNG (спавны монстров, chest).

### Explosive barrel

Наследуется от `DamageableEnvironmentProp`. При `_destroy()` не
free-ится сразу, а стартует telegraph:

- Красная тональность и pulse-scale через `_process`.
- По истечении `telegraph_time` — `_explode()`: обходит всех в
  группах `player` / `enemy` / `damageable_prop` в радиусе
  `explosion_radius`, зовёт `take_damage(explosion_damage)`.

**Chain-reaction guard**: соседним `explosive_barrel` уходит
`take_damage_from(FACTION_ENVIRONMENT, damage)`, а их
`damage_factions = [FACTION_PLAYER]` — фильтр отсекает environment
damage, бесконечных цепочек не будет. Обычные destructibles тоже
принимают только `FACTION_PLAYER`, поэтому взрыв не разрушает соседний
crate «за компанию».

### Lore interaction

`LoreInteractable` (`scenes/dungeon/lore_interactable.gd`) — StaticBody2D
с child DetectionArea (48×48 px). При overlap с player:

- Эмиттит `prompt_shown(prompt_key)` → `EventLog.log_lore_prompt`
  показывает подсказку `[E] Read`.
- По нажатию `interact` (E) — `read(text_key)` → snippet в combat log.
- Флаг `_already_read` — one-shot, повторное чтение не даёт эффекта.

### Placement rules

`_place_gameplay_props` в `room_decoration_planner.gd`:

- Работает поверх занятой decorative grid — не пересекает существующие
  props.
- Skip hazards в ролях `entrance / exit_core / boss_arena /
  treasure_room / corridor` (`_NO_HAZARD_ROLES`).
- Skip hazards в первой/последней комнате (`_is_boundary_room`) — где
  расположены `player_start / exit_position`.
- Skip hazards, если placement origin в 1 клетке от doorway
  (`_is_near_door`).
- Hard cap `_GAMEPLAY_PROPS_PER_ROOM_CAP = 4` gameplay props на комнату
  сверх per-prop `max_per_room`.
- Per-prop `max_per_floor` пересекает все rooms этажа через
  `floor_counts`-словарь.

### Тесты (PR 4)

- `test_damageable_environment_prop.gd` — take_damage, faction фильтр,
  idempotent destroy, destroyed signal один раз.
- `test_interactive_prop_budget.gd` — max_per_room / max_per_floor,
  hazards в запрещённых ролях, entrance/exit clear.
- `test_environment_prop_drops.gd` — determinism per seed, floor cap,
  распределение результатов.
- `test_environment_hazards.gd` — telegraph delay, radial damage, chain
  reaction guard.
- `test_environment_interactions.gd` — lore prompt on overlap, one-shot
  read, i18n keys существуют.

## Baseline metrics (PR 3, average over 5 seeds)

| Floor | Zone | Rooms | Hops (E→X) | Branches | Cycles | Walkable px² |
|---|---|---:|---:|---:|---:|---:|
| 1 | tower_top | 8.4 | 4.0 | 4.2 | 3.2 | 157,280 |
| 3 | residential | 9.4 | 4.4 | 5.2 | 3.8 | 180,160 |
| 7 | technical | 14.4 | 5.0 | 7.0 | 4.0 | 252,720 |
| 12 | lower_tower | 12.4 | 8.8 | 2.0 | 0.0 | 349,520 |
| 16 | basement | 12.4 | 7.6 | 2.6 | 0.0 | 385,520 |
| 21 | caves | 7.4 | 3.8 | 3.0 | 2.0 | 209,840 |

Замечания:
- Residential/technical → богатая ladder-топология (много branches и cycles).
- Lower/basement BSP → длинные hops (~8), но малое количество cycles на 5 seeds. Кандидат под дальнейшую настройку `EXTRA_EDGE_RATIO`.
- Caves → компактный, но связный, с loops на большинстве seeds.

## Планы

- **Irregular cave boundaries** — переход от rect chambers к настоящим blob'ам с polygonal wall rendering в `floor.gd`.
- **Cellular automata caves** как вариант B для caves-зоны — альтернативный алгоритм под тот же archetype.
- **Специальные комнаты** — trap rooms, altar rooms.
- **Секретные проходы** — скрытые doorways, видимые только после активации.
- **Комнаты необычной формы** (L, T) — комбинирование соседних leaf'ов через shape merge.
- **Camera hint** — не показывать exit marker до захода в exit room (fog-of-war сокращённый).
