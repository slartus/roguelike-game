# Враги

Все враги добавляются в группу `enemy` в `_ready`. При смерти начисляют XP и gold через `GameState.award_xp()` / `award_gold()`. Общий бэкстори — классический fantasy RPG-бестиарий: слизни, гоблиноиды, орки, нежить, пауки.

**Порядок рендера.** Корневой `CharacterBody2D` каждого врага (включая боса) имеет `z_index = 1`. Пикапы, пол и портал остаются на default `z_index = 0`, поэтому враг всегда рисуется поверх сундука/сердечка/оружейного пикапа, а не за ним. Тот же контракт у игрока (см. `pickups.md`).

## Spawn-таблица (`MonsterSpawnTable`)

Обычные монстры (не boss) собираются в data-driven таблицу `scenes/enemies/monster_spawn_table.gd`. Каждая запись — Dictionary с полями:

| Поле | Смысл |
|------|-------|
| `id` | уникальный slug (для тестов/логов) |
| `scene` | PackedScene, что спавнить |
| `min_floor` / `max_floor` | floor gating (закрытый интервал) |
| `weight` | вес для weighted random |
| `threat` | стоимость в room-aware budget (см. подфича 5) |
| `tags` | «что это»: beast, undead, ranged, ... |
| `room_tags` | какие темы комнаты приветствуют этого врага |
| `level_offset_min` / `level_offset_max` | смещение monster_level от floor |
| `elite_chance` | базовый шанс champion (0..1) |

### Текущая таблица

| id | scene | floor range | weight | threat | tags |
|---|---|---|---:|---:|---|
| `small_slime` | `small_slime.tscn` | 1–8 | 24 | 1 | beast, swarm, melee |
| `goblin` | `goblin.tscn` | 1–12 | 18 | 2 | goblinoid, melee, fast |
| `skeleton` | `skeleton.tscn` | 2–∞ | 14 | 2 | undead, melee, variant |
| `adult_slime` | `enemy.tscn` | 3–12 | 8 | 4 | beast, swarm_generator, melee |
| `orc` | `orc.tscn` | 3–∞ | 7 | 4 | goblinoid, brute, melee |
| `spider` | `charger.tscn` | 3–14 | 8 | 4 | beast, charger, control |
| `zombie` | `zombie.tscn` | 4–∞ | 10 | 4 | undead, tank, poison, control |
| `skeleton_archer` | `ranged_enemy.tscn` | 4–∞ | 8 | 3 | undead, ranged, kiter |
| `lich` | `lich.tscn` | 7–∞ | 3 | 7 | undead, caster, summoner, ranged |

**Eligibility rules** (`get_eligible_defs(floor, room_tags)`):
1. Первый фильтр — floor gating: `min_floor ≤ floor ≤ max_floor`.
2. Если `room_tags` не пустой — оставляем def'ы, у которых пересечение `def.room_tags ∩ room_tags` не пусто. Если после этого список пуст — fallback на floor-only список.
3. Никогда не возвращает boss.

**Weighted choice** (`choose_weighted(defs, rng)`) детерминирован при одинаковом `rng.seed` — критично для reproducible dungeon layouts.

**Monster level** (`roll_monster_level(floor, def, room_danger, rng)`) = `floor + room_danger + randi_range(level_offset_min, level_offset_max)`, минимум 1.

**Elite rank** (`roll_elite_rank(...)`) политика:
- rank 2 (elite) — только с floor 10+ и с шансом `chance × 0.25`.
- rank 1 (champion) — обычный roll от `chance = elite_chance + room_danger × 0.03 + max(0, floor - 6) × 0.005`.

**Подключение к Main.** `Main._spawn_enemies()` использует `MonsterSpawnTable` для каждого обычного этажа. RNG инжектится детерминированно от `tower_seed × 100003 + floor × 9176 + 1337` — один и тот же (tower_seed, floor) даёт один и тот же набор монстров. Boss floor обрабатывается отдельно и через таблицу не проходит. Подробности в `dungeon.md`.

## Balance-таблицы (D&D 5e-inspired)

**Базовые** значения `max_health` / `contact_damage` / `xp_reward` / `gold_reward` в таблицах ниже — это level-1 stats. Каждый монстр при спавне в `_ready` применяет линейный scaling по **effective monster level** через `Balance.scaled_*` (см. `progression.md`).

**Effective monster level.** У каждого обычного enemy family (`enemy.gd` — Slime/Goblin/Orc/Skeleton/Zombie, `ranged_enemy.gd` — Archer/Lich, `charger.gd` — Spider) есть `@export var monster_level: int = 0` и `@export var elite_rank: int = 0`. Boss из этой системы исключён — он остаётся на floor-scaling. Общая формула вынесена в `MonsterLevelUtil.effective_level()` и работает так:

- `monster_level <= 0` → fallback на `GameState.current_floor_number` (старый режим, ничего специально не настраивая).
- `monster_level > 0` → используется заданный уровень независимо от текущего этажа.
- `elite_rank = 1` → +1 к effective level (champion).
- `elite_rank = 2` → +2 к effective level (elite).
- Минимум — 1.

Настраивается через `configure_spawn(level, elite)` **до** `add_child()` — иначе `_ready` уже применит scaling к дефолтному нулю. Spawn-система задаёт уровень явно (см. `MonsterSpawnTable`), поэтому один и тот же монстр может встречаться на floor 3 как level 2 (легче) и на floor 8 как level 9 elite champion. Визуальные elite-эффекты пока не реализованы — только offset статов.

Источник цифр — D&D 5e Monster Manual (SRD), нормализованные к roguelike-масштабу (~1/5 оригинальных HP). Например Goblin D&D CR 1/4 имеет 7 HP → у нас 4 (base). Orc CR 1/2 имеет 15 HP → у нас 8.

## Общая механика восприятия (AI)

У каждого врага есть `perception_radius` — дистанция, на которой он «видит» игрока. Пока игрок вне радиуса, поведение — дефолтное (см. ниже per-type). Как только игрок ближе `perception_radius` — враг переходит в активную фазу. У melee-семейства и boss есть **гистерезис**: возвращение в WANDER происходит на дистанции `perception_radius * 1.6`, чтобы не флапало у границы.

| Поле | По умолчанию (melee) | Смысл |
|------|----------------------|-------|
| `perception_radius` | 130 | Дистанция обнаружения игрока |
| `wander_speed_ratio` | 0.5 | Множитель скорости во время wander |
| `wander_change_interval` | 2.5 s | Период смены направления wander |
| `memory` | 0.65 | Вероятность **не забыть** игрока за один тик проверки (0 = сразу забудет, 1 = никогда не забудет) |
| `memory_check_interval` | 1.0 s | Интервал между «бросками кубика» на забывание |

### Как работает memory

Пока игрок в `perception_radius` — враг обновляет `_last_seen_position` и сбрасывает таймер памяти. Как только игрок выходит за `perception_radius * 1.6` (гистерезис):

1. Враг идёт к `_last_seen_position`.
2. Каждые `memory_check_interval` секунд вызывается `randf() > memory` — если true, враг **забывает** и переходит в WANDER.
3. Если враг дошёл до `_last_seen_position` (< 8 px) и никого нет — тоже уходит в WANDER (искать нечего).

Значения по типам:

| Монстр | `memory` | Интуиция |
|--------|----------|----------|
| Slime | 0.35 | Слизь — тупая, забывает быстро |
| Goblin | 0.55 | Средне |
| Skeleton | 0.75 | Нежить упорна |
| Orc | 0.85 | Тупой, но злобный — долго помнит цель |
| Zombie | 0.95 | Классический «walking dead» — почти никогда не сдаётся |
| Boss / Ranged / Charger | не применяется | Boss всегда видит, Ranged просто перестают стрелять, Charger возвращается в WATCH |

Дефолтное поведение по типам:
- **Melee** — WANDER: случайное направление, смена каждые `wander_change_interval`; при столкновении со стеной — разворот с малым случайным отклонением. Урон только в CHASE-фазе через `move_and_collide`.
- **Charger** — WATCH: неподвижно, ждёт игрока. Как только видит — переходит в WAITING → CHARGING.
- **Ranged** (Skeleton Archer, Lich) — **kiting**: держатся на `preferred_range` дистанции. Идут к игроку если он далеко (dist > preferred_range), отходят если слишком близко (dist < min_range), стоят и стреляют в промежутке. **Пока игрок вне perception** — бродят как melee (`_wander`: случайное направление × `wander_speed_ratio = 0.4`, смена по `wander_change_interval = 2.5 s` или при упоре в стену); `_fire_timer` при этом не тикает, стрельба только при активной цели. Раньше стояли столбом на месте спавна — «выключенный NPC», особенно на больших этажах. Если stuck-детектор ловит упор в стену во время kiting — уходят в escape (см. секцию ниже).
- **Boss** — `perception_radius = 3000` (эффективно всегда видит), CHASE постоянно + volleys.

Получение урона всегда сразу переводит melee в CHASE (враг «просыпается» даже если игрок был вне радиуса).

## Pathfinding (только melee)

Melee-враги используют **Godot AStarGrid2D** для обхода стен: при CHASE идут не по прямой к цели, а по A*-пути через wall-grid этажа.

Как это работает:
1. `Floor._build_astar_grid()` строит один `AStarGrid2D` на весь этаж — клетки 20×20 совпадают с wall-tiling'ом. Solid-flag выставлен на клетках, где стена (`_is_wall_at(tile_center) == true`). Grid добавляется в группу `"floor"`.
2. Enemy при `_ready` находит Floor через `get_tree().get_first_node_in_group("floor")` и хранит ссылку.
3. В `_chase_toward(target_pos, delta)`:
   - Раз в `PATH_RECALC_INTERVAL = 0.25 s` (или сразу если path пуст, или target сдвинулся > `PATH_TARGET_STALE_DISTANCE = 24 px`) пересчитывается A*-путь через `astar_grid.get_point_path(start_cell, end_cell)`.
   - Путь — массив `PackedVector2Array` в пиксельных координатах центров клеток.
   - Враг идёт к первому waypoint; когда до него < `WAYPOINT_REACHED_DISTANCE = 6 px`, waypoint удаляется, идём к следующему.
4. Fallback: если path пуст (target вне bounds, в solid-клетке или недостижим) — прямая линия через `_chase_direct`.
5. Charger / Ranged / Boss используют прежнюю прямую логику — им pathfinding не нужен (Charger движется по фикс-direction за короткий charge; Ranged стоит; Boss в открытой boss-арене без препятствий).

**Стоимость**: ~50 pathfind/sec (25 melee-enemies × 4 recalc/sec). AStarGrid2D — C++ core, на grid'е ≤ 40×28 клеток запрос < 1 ms.

## Stuck detection (melee + ranged)

`move_and_slide` не всегда вытаскивает врага из угла: если A* вернул пустой путь (например, `start_cell` попал на solid-клетку из-за того, что позиция врага скруглилась в стену) или ranged-враг пошёл по прямой в стену — velocity после `move_and_slide` обнуляется, и без вмешательства враг «прилипает» к стене намертво.

Обе группы делают одинаковую защиту:
1. Каждый кадр после `move_and_slide` считаем `velocity.length()`. Если она < `speed * STUCK_VELOCITY_RATIO` (0.15) при попытке двигаться — копим `_stuck_timer`.
2. Как только `_stuck_timer >= STUCK_TIMEOUT` (0.25 s melee / 0.3 s ranged), включаем **escape**: `_escape_direction` = перпендикуляр к направлению на цель, `_escape_timer = ESCAPE_DURATION` (0.4 s). Сторона выбирается случайно при первой попытке.
3. Пока `_escape_timer > 0`, velocity задаётся escape-направлением независимо от pathfinding / kiting-логики — враг обходит угол вбок.
4. Если движение восстановилось, `_stuck_timer` и запомненная `_last_escape_side` сбрасываются.
5. Если враг застрял снова **сразу после** предыдущего escape — берём **противоположную** сторону, чтобы не циклиться в тот же угол.
6. У melee при активации escape дополнительно сбрасывается `_path`: старые A*-waypoint'ы могли указывать на ту же самую стену.
7. При переходе melee-врага в `WANDER` (потеря памяти / достижение last_seen) весь stuck-state сбрасывается — WANDER сам вертит направление при столкновениях, stale `_escape_direction` через 10 s не должно «выстрелить».

Для ranged-врагов stuck-детектор триггерится **только** когда враг сам хотел двигаться (`intended_dir != 0` — kiting-фаза close-in / retreat). На ideal-range ranged штатно стоит на месте, ложных срабатываний быть не должно.

## Melee (`enemy.gd`)

Все ближники используют один скрипт `enemy.gd`. Разные типы — это разные `.tscn` с разными `@export` параметрами и спрайтами. Поведение общее: идти к игроку, наносить контактный урон с cooldown.

### Slime family: Small и Adult

Семейство слаймов разделено на две формы — они пользуются одним скриптом `slime.gd`, но разными `.tscn` с флагами `can_bud` / `can_split_on_death` и ссылками `bud_scene` / `death_split_scene`.

- **`enemy.tscn`** — исторический путь взрослого Slime; переименовывать сцену пока не стали, чтобы не тащить массовый diff в `main.gd`, `test/**`, а также в save-совместимых ссылках. В docs он обозначается как **Adult Slime**.
- **`small_slime.tscn`** — новая базовая форма.

### Small Slime (`small_slime.tscn`)

Мелкий ранний враг. Скейл 0.5, коллизия r=3.5.

| Параметр | Значение |
|----------|----------|
| `display_name` | `ENEMY_SMALL_SLIME` |
| max_health | 1 |
| speed | 36 |
| contact_damage | 1 |
| pickup_drop_chance | 4% |
| xp_reward | 2 |
| gold_reward | 1 |
| perception_radius | 95 |
| memory | 0.30 |
| `can_bud` | false |
| `can_split_on_death` | false |

Роль: базовый ранний filler (Floor 1+). Не почкуется, не распадается при смерти — цепь семьи слаймов конечна.

### Adult Slime (`enemy.tscn`)

Классический зелёный размножающийся слизень. Спрайт `assets/sprites/enemies/slime.png` (16×16), коллизия r=7.

| Параметр | Значение |
|----------|----------|
| max_health | 3 |
| speed | 35 |
| contact_damage | 1 |
| contact_cooldown | 0.6 s |
| pickup_drop_chance | 15% |
| xp_reward | 5 |
| gold_reward | 1 |
| memory | 0.35 |
| `can_bud` | true |
| `can_split_on_death` | true |
| `bud_scene` | `small_slime.tscn` |
| `death_split_scene` | `small_slime.tscn` |
| `death_split_count` | 2 |

Роль: размножающийся враг средних этажей (Floor 3+ через `MonsterSpawnTable`). Почкуется в Small Slime, при смерти распадается на 2 Small Slime.

**Движение — прыжки, не плавный ход.** Слайм — единственный ближник, у которого есть свой скрипт-обёртка `slime.gd` над `enemy.gd`. Скрипт держит state machine `REST → JUMP → REST`:

| Фаза | Длительность | Что делает |
|------|--------------|------------|
| `REST` | 0.55 s | `speed = 0` → super._physics_process не двигает. Visual возвращается к базовому scale. |
| `JUMP` | 0.35 s | `speed = base_speed × 2.4` → короткий рывок к цели. Visual одновременно раздувается по Y на +35% и сжимается по X на −15% через `sin(t*π)` — squash-and-stretch. |

Фазы никогда не останавливаются — крутятся по таймеру независимо от того, видит ли слайм цель. В `_ready` `_phase_timer` инициализируется от `randf() * REST_DURATION`, чтобы группа слаймов не прыгала синхронно.

![Slime hop squash & stretch](media/slime_hop.gif)

Контактный урон работает только в момент, когда `move_and_slide` реально столкнул слайма с игроком — то есть во время JUMP. В REST velocity=0, коллизии нет, damage не наносится.

**Почкование при агре (только Adult).** Только Adult Slime (`can_bud = true`) почкуется. При первом переходе `WANDER→CHASE` запускается таймер `BUD_DELAY` = 4.0 s. По истечении рядом появляется **Small Slime** (из `bud_scene = small_slime.tscn`), а не ещё один Adult — цепь семьи конечная. Каждый Adult почкуется максимум один раз (`_has_budded`), даже если после первой попытки он потерял цель и снова агрится. Small Slime имеет `can_bud = false` и вообще не заходит в bud-логику.

| Параметр почкования | Значение |
|---------------------|----------|
| `BUD_DELAY` | 4.0 s |
| `BUD_OFFSET_MIN` | 12 px (~0.6 тайла) |
| `BUD_OFFSET_MAX` | 22 px (~1.1 тайла) |
| `BUD_SPAWN_ATTEMPTS` | 8 |

Позиция: до 8 попыток случайного вектора в кольце `[BUD_OFFSET_MIN, BUD_OFFSET_MAX]` вокруг слайма-матери. Каждая проверяется через `Floor.astar_grid.is_point_solid` — почка не спавнится в стену. Если все 8 попыток промахнулись (слайм окружён стенами), почка не появляется и `_has_budded` остаётся `false`. При этом слайм-мать ещё может попробовать почкануться при **следующем** агра-цикле (WANDER→CHASE), потому что флаг всё ещё `false` — фичей это допускается, редкий edge case и без бесконечного ретрая внутри одного текущего кадра. Без Floor (тесты, автономный запуск) валидация пропускается — offset выбирается один раз без проверки клетки.

**Разделение при смерти (только Adult).** Только Adult Slime (`can_split_on_death = true`) распадается при смерти. Спавнится `death_split_count = 2` Small Slime (из `death_split_scene = small_slime.tscn`). Осколки летят в противоположные стороны от точки смерти на `DEATH_SPLIT_OFFSET = 4` px по случайной оси — не спавнятся поверх друг друга.

| Параметр | Значение |
|----------|----------|
| `death_split_count` | 2 |
| `DEATH_SPLIT_OFFSET` | 4 px |
| max_health осколка | scaled(1, floor) из `small_slime.tscn` |
| xp_reward осколка | scaled(2, floor) из `small_slime.tscn` |
| gold_reward осколка | scaled(1, floor) из `small_slime.tscn` |
| pickup_scene осколка | `null` (обнуляется runtime — иначе фарм зелий) |

Реализация — override `take_damage` в `slime.gd`: после `super.take_damage(amount)` (её синхронная часть уже уменьшила health и запустила визуальный flash) проверяем `was_alive and health <= 0 and not _is_sterile and can_split_on_death` и в этот момент спавним осколков через `death_split_scene.instantiate()`. Мать всё ещё в дереве до окончания её собственного 0.08 s `await` — `get_parent()` и `global_position` валидны.

Раньше осколки runtime-скейлились из копии матери (half HP/xp/gold, scale 0.5, `_is_sterile = true`). Теперь Small Slime — самостоятельная сцена со своими base stat (max_health=1, xp=2, gold=1, scale=0.5), а стерильность фиксируется в `.tscn` (`can_bud=false`, `can_split_on_death=false`). Runtime у осколков остаётся только обнуление `pickup_scene`.

**Экономика цепочки.** Adult (xp=5) + 2 × Small (xp=2) = **9 XP** за всю семью, против одиночного Adult 5 XP. Прибавка за большее число ударов и рисков, но не удваивается вдвое — не даёт фарм. Gold: 1 + 2×1 = **3 gold** — тоже линейный рост, не эксплойт.

### Goblin (`goblin.tscn`)

Маленький быстрый зелёный гуманоид с дубиной. Спрайт `goblin.png` (16×16), коллизия r=6.

| Параметр | Значение |
|----------|----------|
| max_health | 4 |
| speed | 55 |
| contact_damage | 2 |
| pickup_drop_chance | 15% |
| xp_reward | 6 |
| gold_reward | 2 |

Роль: быстрый преследователь. Опасен в группах.

### Orc (`orc.tscn`)

Крупный серо-зелёный орк с топором. Спрайт `orc.png` (16×16), коллизия r=8.

| Параметр | Значение |
|----------|----------|
| max_health | 8 |
| speed | 28 |
| contact_damage | 3 |
| pickup_drop_chance | 22% |
| xp_reward | 14 |
| gold_reward | 4 |

Роль: танк. Долго живёт, наносит тройной урон при контакте.

### Skeleton (`skeleton.tscn`)

Скелет-воин с мечом и красными огнями в глазницах. Спрайт `skeleton.png` (16×16), коллизия r=7.

| Параметр | Значение |
|----------|----------|
| max_health | 3 |
| speed | 50 |
| contact_damage | 2 |
| pickup_drop_chance | 15% |
| xp_reward | 7 |
| gold_reward | 2 |

Роль: средний быстрый ближник, немного крепче гоблина.

**Арсенал (skeleton_arsenal.gd → MELEE_VARIANTS).** При спавне скелет случайно берёт один вариант оружия из таблицы (weighted-random) — он определяет display-key для UI/log, добавку к contact_damage и tint спрайта:

| Вариант | Δ contact_damage | Вес | attack_radius | Спрайт оружия |
|---------|-------------------|-----|---------------|---------------|
| `ENEMY_SKELETON_UNARMED` | +0 | 0.30 | 0 (только touch) | — (Weapon-нода скрыта) |
| `ENEMY_SKELETON_DAGGER_WOOD` | +1 | 0.22 | 0 (только touch) | `dagger_wood.png` (3×6, тёплое дерево) |
| `ENEMY_SKELETON_DAGGER_IRON` | +2 | 0.18 | 0 (только touch) | `dagger_iron.png` (3×6, стальное лезвие) |
| `ENEMY_SKELETON_SWORD_WOOD` | +2 | 0.16 | 22 px | `sword_wood.png` (3×10, длинный деревянный клинок) |
| `ENEMY_SKELETON_SWORD_IRON` | +3 | 0.14 | 26 px | `sword_iron.png` (3×10, стальной клинок) |

**Визуальное отличие вариантов.** До: разница между unarmed / dagger / sword выражалась только subtle `Color`-модуляцией всего скелета — практически неразличимо в тёмном подземелье. Теперь у каждого вооружённого варианта есть отдельный дочерний Sprite2D `Weapon` в `skeleton.tscn` (`position = Vector2(5, 3)`, изначально `visible = false`). В `skeleton.gd::_apply_weapon_sprite` при спавне текстура подставляется из `variant["weapon_sprite"]` и нода включается; для unarmed — остаётся скрытой. Модуляция самого скелета сброшена в `Color(1, 1, 1)` — цвет несёт оружие, а не тело. Спрайты оружия рисуются `tools/gen_skeleton_weapon_sprites.py`.

Δ применяется **до** `Balance.scaled_damage`, поэтому floor-scaling умножается уже на bumped-up значение.

**Радиус урона (`attack_radius`).** Экспортируемое поле в `enemy.gd`. `0` = урон только по физическому касанию `CharacterBody2D` через `get_slide_collision` (кулаки, кинжал). `>0` = extended reach: в `_handle_player_contact` после touch-ветки ещё проверяется `global_position.distance_to(target) <= attack_radius` — так меч бьёт на замахе даже до прижимания. `contact_cooldown` (0.6 s) применяется одинаково к touch- и reach-удару.

Reach-удар дополнительно проверяет **LoS** через `LineOfSight.is_clear` — raycast от врага к игроку, `exclude = [get_rid()]`. Если между ними стена (`StaticBody2D` из `floor.gd`), reach не наносит урон, даже если игрок в `attack_radius`. Touch-ветка через `get_slide_collision` уже гарантирует физический контакт, LoS-check ей не нужен.

**Анимация удара скелета.** На каждый успешный удар `enemy.gd` эмиттит сигнал `attack_played(target_position)`. `skeleton.gd` подписывается и в `_play_lunge_animation` запускает параллельный `Tween`:
- корпус (`Visual`) рывком смещается на **10 px** в сторону цели за **80 ms**, возвращается за **140 ms**;
- одновременно `Weapon` рубит по дуге: `rotation` от 0 до **PI·0.55** (~99°) за 80 ms и обратно за 140 ms. Пивот вращения — hilt рукояти (Node2D.position совпадает с верхом клинка через `offset = (0, tex_height/2)`), поэтому свинг читается как замах, а не как оружие, летящее вокруг своего центра.

Первая версия lunge (4 px, 60/100 ms, без свинга оружия) выглядела как «скелет тыкается в игрока» — практически незаметно. Раскачали дистанцию до 10 px и подключили вращение видимого клинка, чтобы удар читался.

При повторном ударе предыдущий tween убивается через `.kill()`, чтобы визуал не «застрял» посередине. У безоружных скелетов вращение оружия не играется (проверяется `weapon.visible`). У других мили-врагов (Zombie, Slime, Goblin, Orc) сигнал игнорируется — они наносят урон без лунга.

Список расширяется добавлением новых записей в `MELEE_VARIANTS` — рассчитано на будущие «улучшалки» (магические клинки, заражённое оружие и т.п.). Новые варианты с extended reach просто ставят `attack_radius > 0`.

### Zombie (`zombie.tscn`)

Разлагающийся гуманоид, медленно тащится к игроку. Спрайт `zombie.png` (16×16), коллизия r=7.

| Параметр | Значение |
|----------|----------|
| max_health | 6 |
| speed | 22 |
| contact_damage | 3 |
| pickup_drop_chance | 20% |
| xp_reward | 11 |
| gold_reward | 3 |

Роль: медленный, но живучий и больно бьёт. Требует движения при контакте.

**Ядовитое облако (`zombie.gd` + `poison_cloud.gd/tscn`).** Раз в `POISON_CLOUD_COOLDOWN = 6.0 s` зомби роняет у своей позиции облако зловония. Первый спавн — через полный кулдаун после появления зомби (не сразу, иначе зомби у ног игрока бросал бы облако без окна на реакцию).

| Параметр | Значение |
|----------|----------|
| `POISON_CLOUD_COOLDOWN` (zombie) | 6.0 s |
| `LIFETIME` (cloud) | 4.0 s |
| `RADIUS` (cloud) | 16 px (~0.8 тайла) |
| `POISON_DURATION` (cloud → player) | 3.0 s |
| `POISON_TICK_INTERVAL` (player) | 1.0 s |
| `POISON_DAMAGE_PER_TICK` (player) | 1 hp |
| `POISON_SLOW_FACTOR` (player) | 0.7 |

Облако — Area2D с процедурным рендером (`_draw` без спрайта). Внутри — плотный тёмно-зелёный «сгусток» в центре плюс `PUFF_COUNT = 6` клубков на орбите радиусом `PUFF_ORBIT_RADIUS`. Клубки медленно вращаются вокруг центра со скоростью `CLOUD_ROTATION_SPEED = 0.55 rad/s`, а их радиус пульсирует по `sin(t * PUFF_PULSE_FREQUENCY + phase)` — соседние клубки дышат в противофазе, облако визуально клубится, а не мигает одним куском. Общая прозрачность делает fade-in первых 10% и fade-out оставшихся 90%. По истечении `LIFETIME` облако `queue_free`. Начальный overlap (игрок стоит в точке спавна) обрабатывается через `call_deferred("_check_initial_overlap") → get_overlapping_bodies()`, потому что `body_entered` не срабатывает ретроактивно.

![Poison cloud](media/poison_cloud.gif)

**Статус «отравлен» на игроке** (в `player.gd`):
- `apply_poison(duration)` ставит `_poison_timer = duration`. Если игрок не был отравлен, дополнительно взводит `_poison_tick_timer = POISON_TICK_INTERVAL` — первый урон случится через 1 s, а не мгновенно.
- Refresh (повторный `apply_poison` до истечения) обновляет длительность, **но НЕ трогает** `_poison_tick_timer`. Иначе игрок мог бы избегать урона, ре-заражаясь непосредственно перед каждым тиком.
- `_tick_poison(delta)` в `_physics_process` декрементит оба таймера. По истечении tick-таймера снимается `POISON_DAMAGE_PER_TICK` через `take_damage(1)` и tick-таймер снова 1.0 s.
- Пока `_poison_timer > 0`, `current_speed()` домножает базовую скорость на `POISON_SLOW_FACTOR = 0.7` — тело сковано, движение тяжелее. Slow стакается **мультипликативно** с паутинным (`SLOW_FACTOR = 0.3`): игрок, стоящий в LANDED-паутине и одновременно отравленный, движется `speed × 0.3 × 0.7 = speed × 0.21`. Порядок множителей неважен, обе ветки в `current_speed()` независимы.
- По истечении `_poison_timer` статус пропадает, tick'и и slow прекращаются.

_Follow-up:_ `POISON_DAMAGE_PER_TICK` фиксированный (1 hp) и не масштабируется по floor через `Balance.scaled_damage`. На глубоких этажах контактный урон зомби растёт, а яд остаётся 1/сек — со временем яд перестанет быть значимой угрозой. Когда балансу это станет мешать, добавить `Balance.scaled_damage(POISON_DAMAGE_PER_TICK, floor_num)` при применении статуса, либо scaling на самом облаке.

## Charger (`charger.gd`)

### Spider (`charger.tscn`)

Восьминогое чёрное существо с красными глазами. Спрайт `spider.png` (16×16), коллизия r=6.

| Параметр | Значение |
|----------|----------|
| max_health | 1 |
| charge_speed | 220 |
| wander_speed | 25 |
| wander_change_interval | 2.5 s |
| wait_duration | 1.2 s |
| charge_duration | 0.9 s |
| contact_damage | 2 |
| contact_cooldown | 0.4 s |
| pickup_drop_chance | 18% |
| xp_reward | 8 |
| gold_reward | 1 |

**Поведение:** state machine.
1. `WATCH` — неспешно бродит `move_and_slide` со скоростью `wander_speed = 25 px/s` (сильно ниже `charge_speed = 220`), плавно, без прыжков как у слайма. Направление меняется по `wander_change_interval = 2.5 s` или при упоре в стену. Ждёт пока игрок войдёт в `perception_radius` **и** между ними не окажется стены. Переход в `WAITING` требует **LOS**: raycast от паука к игроку не должен упереться в `StaticBody2D` (стены `floor.gd` — единственные `StaticBody2D` в сцене). Стена между пауком и игроком блокирует и плевок паутиной, и рывок.
2. `WAITING` — стоит `wait_duration` секунд (светлее оттенок через `modulate`). **В момент входа в WAITING** паук плюёт паутиной (`spider_web.tscn`) в текущую позицию игрока — цель фиксируется на этом моменте, не хоминг.
3. Фиксирует направление к текущей позиции игрока и переходит в `CHARGING`.
4. `CHARGING` — двигается `charge_speed` в фиксированном направлении `charge_duration` секунд.
5. Возвращается в `WATCH`.

Контактный урон только в `CHARGING`.

**Паутина (`spider_web.gd/tscn`).** Area2D-снаряд с двумя фазами.

| Параметр | Значение |
|----------|----------|
| `FLIGHT_SPEED` | 140 px/s |
| `LANDING_THRESHOLD` | 3 px |
| `FLYING_RADIUS` | 3 px |
| `LANDED_RADIUS` | 14 px (~0.7 тайла) |
| `LANDED_LIFETIME` | 12.0 s |
| `SLOW_FACTOR` (player) | 0.3 |

- **FLYING** — летит к `target_position` со скоростью `FLIGHT_SPEED`. Коллизия маленькая (r=3); пролёт над игроком **не** триггерит slow — иначе сам факт стрельбы был бы двойным ударом. Визуал: маленький «липкий комок» — основной круг + сдвинутый светлый блик, чтобы глоб не выглядел плоским.

  ![Spider web glob in flight](media/spider_web_flying.gif)
- **LANDED** — приземлилась на `target_position`; коллизия раздувается до r=14, живёт `LANDED_LIFETIME = 12 s` и `queue_free`. Пока игрок стоит внутри — его скорость умножается на `SLOW_FACTOR` = 0.3. Финальный fade-out последние 25% жизни. Визуал — **рваная кобвеб-геометрия**, кешируемая один раз при приземлении в `_build_ragged_geometry` (чтобы форма не мигала каждый кадр): 8 радиальных нитей случайной длины `[0.55–1.0] × LANDED_RADIUS` со случайным угловым jitter, половина нитей имеет короткий оборванный «хвост» под углом; 3 концентрических кольца, каждое разорвано на 2 пропуска случайной ширины `[0.25–0.7 rad]` и стартового угла — рисуется несколькими `draw_polyline`-дугами. Паутина выглядит потрёпанной и не идеально симметричной.

  ![Spider web landed](media/spider_web_landed.gif)

**Slow-статус на игроке.** Реализован через счётчик источников (`_slow_source_count`), не bool. Каждая LANDED-паутина, содержащая игрока, +1 источник; выход из паутины / её исчезновение по таймеру — −1. Пока счётчик > 0, `current_speed()` возвращает `speed × SLOW_FACTOR`. Несколько наложенных паутин **не** стакаются мультипликативно — минимальная скорость всегда `speed × 0.3`. Перед `queue_free` паутина ручным обходом `get_overlapping_bodies()` снимает свои +1 у всех замедлённых — иначе счётчик залипнет, и игрок останется медленным.

**Изоляция коллизий.** `CircleShape2D` пересоздаётся уникальным на каждый инстанс в `_ready` и снова при переходе в LANDED — иначе `_shape.shape.radius = ...` мутировал бы шаренный sub_resource и все инстансы получили бы одинаковый радиус в неподходящий момент.

## Ranged (`ranged_enemy.gd`)

Стоят на месте и стреляют `enemy_bullet` в текущую позицию игрока.

### Skeleton Archer (`ranged_enemy.tscn`)

Скелет с луком, стрелы на спине. Спрайт `skeleton_archer.png` (16×16), коллизия r=7.

| Параметр | Значение |
|----------|----------|
| max_health | 2 |
| fire_interval | 1.5 s |
| speed | 30 |
| perception_radius | 200 |
| preferred_range | 160 |
| min_range | 100 |
| pickup_drop_chance | 15% |
| xp_reward | 7 |
| gold_reward | 2 |

Роль: базовый стрелок. Часто встречается.

**Арсенал стрел (skeleton_arsenal.gd → ARROW_VARIANTS).** При спавне лучник случайно выбирает tier стрел:

| Вариант | Δ bullet damage | Вес | Tint лучника | Спрайт стрелы |
|---------|------------------|-----|--------------|---------------|
| `ENEMY_SKELETON_ARCHER_WOOD` | +0 | 0.6 | тёплый охристый | `arrow_wood.png` (коричневое древко, красное оперение, стальной head) |
| `ENEMY_SKELETON_ARCHER_IRON` | +1 | 0.4 | холодный стальной | `arrow_iron.png` (стальное древко, серо-голубое оперение, закалённый head) |

Bonus прибавляется к `damage` каждой заспавненной стрелы. `skeleton_archer.gd::_configure_bullet` в момент выстрела подменяет `Visual.texture` снаряда на `sprite_path` из variant'а — тем самым сама стрела в полёте визуально отличается по материалу, не только tint стрелка. Расширяется добавлением записей в `ARROW_VARIANTS` с новым `sprite_path` (elven, poisoned и т.п.); генератор спрайтов — `tools/gen_enemy_bullet_sprites.py`.

### Lich (`lich.tscn`)

Скелет-маг в тёмном капюшоне с посохом и зелёным свечением. Спрайт `lich.png` (16×16), коллизия r=7.

| Параметр | Значение |
|----------|----------|
| max_health | 3 |
| fire_interval | 1.0 s |
| speed | 25 |
| perception_radius | 200 |
| preferred_range | 130 |
| min_range | 80 |
| pickup_drop_chance | 18% |
| xp_reward | 12 |
| gold_reward | 4 |

Роль: продвинутый маг. Крепче лучника и стреляет чаще. Держится ближе (preferred_range 130 vs 160 у лучника).

**Умный обстрел с упреждением (`lich.gd::_shoot`).** В отличие от базового `ranged_enemy._shoot` (стреляет в текущую позицию игрока), лич считает точку упреждения по вектору движения игрока:

- `time_to_hit = distance / BULLET_SPEED_FOR_LEAD` (`BULLET_SPEED_FOR_LEAD = 110` — соответствует `enemy_bullet.gd::speed` по умолчанию);
- `predicted = target.position + target.velocity * time_to_hit`;
- `direction = (predicted - lich.position).normalized()`.

Одна итерация (без recompute predicted после смены distance) — намеренная простота: игрок редко резко разворачивается за флайт 0.3–1.0 s, а идеально-точное упреждение делало бы боя невыносимым. `target.velocity` берётся напрямую из CharacterBody2D (Player). Расчёт вынесен в `_compute_lead_direction(target_pos, target_velocity)` — pure-функция, тестируется отдельно от side-effects `_shoot`.

**Призыв скелета (`lich.gd`).** Помимо стрельбы magic-bolt лич поддерживает одного скелета-миньона.

| Параметр | Значение |
|----------|----------|
| SUMMON_COOLDOWN | 5.0 s |
| SUMMON_CAST_DURATION | 0.8 s |
| SUMMON_OFFSET_MIN | 14 px (~0.7 тайла) |
| SUMMON_OFFSET_MAX | 28 px (~1.4 тайла) |
| SUMMON_TOWARD_PLAYER_ARC | ~100° (TAU × 0.28) |

**Жизненный цикл призыва (`_physics_process` → каст-стейт-машина):**
1. `_summon_cooldown_timer` тикает вниз. **Стартует нулевым** — первый же physics-тик после спавна лича запускает каст. Игрок сразу видит, что лич — призыватель, и получает окно `SUMMON_CAST_DURATION`, чтобы среагировать (добить, отойти, ударить), пока лич колдует. Раньше стартовало полным (5 s), и лич долго воспринимался как обычный ranged.
2. При его истечении `_maybe_start_summon` включает каст: `_summon_cast_timer = SUMMON_CAST_DURATION`.
3. Пока `_summon_cast_timer > 0` — лич **не стреляет и не двигается**: `_physics_process` полностью пропускает `super._physics_process` (там живёт kite-логика и `_shoot`). `velocity = Vector2.ZERO`, `move_and_slide()` для physics-стабильности.
4. `_tick_cast` в каждом кадре уменьшает таймер и через `_apply_cast_visual` мешает `Visual.modulate` с `CAST_TINT_COLOR = (0.7, 1.6, 0.85)` — лич пульсирует ярко-зелёным, «набирает мощь» через синусоидальную пульсацию поверх линейного прогресса.
5. Когда таймер ≤ 0, `_finish_cast` возвращает базовый modulate и вызывает `_summon_skeleton`.

Каст даёт игроку 0.8 s окно среагировать: атаковать лича прямо во время колдовства (тот не отстреливается), выйти из перцепции, использовать зелье. Без каст-фазы скелет «телепортировался» бы возле игрока без предупреждения.

![Cast pulse (лич/босс)](media/cast_pulse.gif)

**Правила:**
- Один активный миньон одновременно; `_summoned_minion` держит `Node`-ссылку, `is_instance_valid` ловит `queue_free`.
- Первый каст стартует сразу при спавне (`_summon_cooldown_timer` = 0.0). Скелет появляется через `SUMMON_CAST_DURATION = 0.8 s`. Игрок мгновенно понимает роль лича, а окно каста даёт время среагировать до появления миньона.
- Когда миньон убит и ссылка невалидна — таймер снова тикает от 0 до 5 s, потом каст, потом новый призыв.
- Позиция: **сначала до 8 попыток в узком секторе (~100°) в сторону игрока** — миньон оказывается «между личом и игроком», играя роль живого щита. Если все 8 попыток попали в стену, **fallback: 12 попыток в полном 360°-кольце вокруг лича**. Отбрасываются те кандидаты, чья клетка `AStarGrid2D.is_point_solid` (стена) или `not is_in_boundsv` (за пределами этажа). Радиус спавна: `randf_range(14, 28)` — «рядом», не «где-то там» (раньше было 24-40 px). Если все 20 попыток провалились — тик пропускается, `_summon_cooldown_timer` остаётся ≤ 0, следующий physics-тик снова стартует каст. Без валидации был баг: скелет иногда спавнился внутри стены и застревал в геометрии, оставаясь неубиваемым.

**Никаких наград с призванных.** `xp_reward = 0`, `gold_reward = 0`, `pickup_scene = null` устанавливаются в `_summon_skeleton` перед `add_child`. Иначе игрок бы «фармил» лича стоя на дистанции — за 5 минут получал бы бесконечно XP и зелий. Скелет-миньон при этом настоящий (в группе `enemy`, со всей арсенальной случайной комплектацией), просто без экономики.

## Босс

### Necromancer (`boss.tscn`)

Крупная фигура в тёмной робе с капюшоном, посох с зелёным кристаллом. Спрайт `necromancer.png` (32×32), коллизия r=14.

| Параметр | Значение |
|----------|----------|
| max_health | 30 |
| speed | 25 |
| contact_damage | 3 |
| contact_cooldown | 0.8 s |
| volley_interval | 2.0 s |
| volley_count | 8 |
| aimed_fire_interval | 1.0 s |
| xp_reward | 40 |
| gold_reward | 20 |

**Поведение:**
- Медленно идёт к игроку через `move_and_collide`.
- Контактный урон 3, cooldown 0.8s.
- Каждые `volley_interval` выпускает `volley_count` штук `dark_orb_bullet.tscn` **по кругу** — направления через равные `TAU / volley_count` радиан (45° между пулями). Каждый второй залп сдвигается на `step / 2` (22.5° при `volley_count = 8`), чтобы звёздочка визуально вращалась между кадрами и игрок не мог заучить статичные коридоры безопасности.
- Параллельно, каждые `aimed_fire_interval = 1.0 s`, выпускает **прицельный `magic_bolt_bullet.tscn`** — как обычный лич. Направление считается с упреждением по вектору движения игрока: `predicted = target.pos + target.velocity * (distance / AIMED_BULLET_SPEED)`, `AIMED_BULLET_SPEED = 100` (совпадает с `magic_bolt::speed`). Формула идентична `lich.gd::_compute_lead_direction`, вынесена в pure-функцию для тестов. Aimed shot добавляет постоянное давление между залпами звёздочек — раньше игрок в промежутках между volley спокойно вложить урон.

**Призыв свиты — батч из 5 скелетов.** Аналог лича по механике, но с бустом:

| Параметр | Значение |
|----------|----------|
| SUMMON_COOLDOWN | 10.0 s |
| SUMMON_CAST_DURATION | 1.2 s |
| SUMMON_COUNT | 5 |
| SUMMON_OFFSET_MIN | 18 px |
| SUMMON_OFFSET_MAX | 40 px |
| SUMMON_TOWARD_PLAYER_ARC | ~108° (TAU × 0.30) |

- `_minions: Array` держит ссылки на всех живых миньонов; `_cleanup_minions` каждый тик прополняет мёртвых (`is_instance_valid`).
- **Первый каст стартует сразу.** `_summon_cooldown_timer` инициализирован нулём — босс со входа в комнату начинает колдовать свиту, а не тратит 10 s на «зарядку». Игрок мгновенно понимает роль призывателя; `SUMMON_CAST_DURATION = 1.2 s` даёт окно среагировать до появления первой пятёрки скелетов.
- **Топ-ап, не всегда 5.** Если 3 миньона выжили с прошлого каста — следующий каст призовёт 2, чтобы вернуть популяцию к SUMMON_COUNT. Не растёт бесконечно.
- Если инвентарь миньонов полон (`_minions.size() >= SUMMON_COUNT`) — каст не стартует, кулдаун ждёт снижения популяции.
- Каст (1.2 s) полностью тормозит босса: `_summon_cast_timer > 0` → пропускается движение (`velocity = 0`), контактный урон (не двигается — нет `move_and_collide`), и volley-таймер тоже пропускается (декремент только вне каста). Игрок получает окно «босс колдует, добивай минионов пока свежие не появились».
- Каст-визуал: `Visual.modulate` мешается с `Color(0.7, 1.6, 0.85)` через синусоидальную пульсацию поверх линейного прогресса — тот же паттерн что у лича, но более длинная фаза телеграфа. Gif `media/cast_pulse.gif` рендерит 0.8 s (длительность лича); у босса эта же пульсация растянута до 1.2 s.

  ![Cast pulse (та же формула, у босса растянута до 1.2 s)](media/cast_pulse.gif)
- Позиция каждого миньона: сначала до `SPAWN_ATTEMPTS_PER_MINION = 10` попыток в узком секторе к игроку (миньоны становятся щитом между Necromancer и целью), fallback: 10 попыток в полном 360° кольце. Отсев через `AStarGrid2D.is_point_solid` и `is_in_boundsv` — не спавнит в стены.
- Миньоны без наград: `xp_reward = 0`, `gold_reward = 0`, `pickup_scene = null` — как у лича. Иначе игрок фармил бы босса стоя на расстоянии.

Не дропает пикапы — награда идёт через XP/gold. Появляется каждые 5 этажей (boss-этаж).

## Пул спавна

`Main.ENEMY_SCENES` содержит все 8 обычных типов (без босса). Спавн случайный, равновероятный (`pick_random()`). Босс появляется в отдельной ветке `Main._is_boss_floor()`.

На каждом этаже количество spawn-точек определяется `DungeonGenerator` (см. `docs/gamedesign/dungeon.md`): 2–3 точки в каждой средней комнате и 1–2 в финальной. Общее число врагов на этаж растёт вместе с количеством комнат (больше этажей = больше комнат = больше врагов).

## Пули врагов

У каждого типа стрелка — своя визуализация:

| Тип стрелка | Bullet-сцена | Sprite | Размеры | Speed | Lifetime |
|-------------|--------------|--------|---------|-------|----------|
| Skeleton Archer | `arrow_bullet.tscn` | `arrow_wood.png` / `arrow_iron.png` (по варианту) | 10×5, RectShape 10×3 | 130 | 3.0 s |
| Lich | `magic_bolt_bullet.tscn` | `magic_bolt.png` | 10×10 зелёный сгусток, r=3.5 | 100 | 3.5 s |
| Necromancer (boss) | `dark_orb_bullet.tscn` | `dark_orb.png` | 10×10 фиолетовый шар, r=4 | 110 | 3.5 s |

Все три Area2D-сцены используют общий `scenes/bullets/enemy_bullet.gd`. Скрипт разворачивает весь root по `direction.angle()` в `_ready()` — стрела визуально смотрит в цель, коллизия узкой rectangle-стрелы тоже поворачивается (важно для попаданий).

**Поведение:** движется `direction * speed`; при `body_entered` наносит `damage` игроку и уничтожается. Self-destroy через `lifetime`.

Скрипт: `scenes/bullets/enemy_bullet.gd`.

Старый `enemy_bullet.tscn` (оранжевый шар) остаётся для обратной совместимости, но никто из активных сцен его больше не использует.

## Спрайты

Все PNG в `assets/sprites/enemies/` генерируются детерминированно скриптом `tools/gen_enemy_sprites.py` (Pillow, палитра + матрица символов). Правки: меняй палитру / матрицу в скрипте, запускай `python3 tools/gen_enemy_sprites.py`, коммить и PNG, и изменения скрипта. Не редактируй PNG вручную — потеряется при следующей регенерации.
