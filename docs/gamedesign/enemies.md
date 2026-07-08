# Враги

Все враги добавляются в группу `enemy` в `_ready`. При смерти начисляют XP и gold через `GameState.award_xp()` / `award_gold()`. Общий бэкстори — классический fantasy RPG-бестиарий: слизни, гоблиноиды, орки, нежить, пауки.

## Balance-таблицы (D&D 5e-inspired)

**Базовые** значения `max_health` / `contact_damage` / `xp_reward` / `gold_reward` в таблицах ниже — это floor-1 stats. Каждый монстр при спавне в `_ready` применяет линейный scaling по `GameState.current_floor_number` через `Balance.scaled_*` (см. `progression.md`).

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
- **Ranged** (Skeleton Archer, Lich) — **kiting**: держатся на `preferred_range` дистанции. Идут к игроку если он далеко (dist > preferred_range), отходят если слишком близко (dist < min_range), стоят и стреляют в промежутке. Не стреляют вне perception. move_and_slide гарантирует, что не залипают у стен.
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

## Melee (`enemy.gd`)

Все ближники используют один скрипт `enemy.gd`. Разные типы — это разные `.tscn` с разными `@export` параметрами и спрайтами. Поведение общее: идти к игроку, наносить контактный урон с cooldown.

### Slime (`enemy.tscn`)

Классический зелёный слизень. Спрайт `assets/sprites/enemies/slime.png` (16×16), коллизия r=7.

| Параметр | Значение |
|----------|----------|
| max_health | 3 |
| speed | 35 |
| contact_damage | 1 |
| contact_cooldown | 0.6 s |
| pickup_drop_chance | 30% |
| xp_reward | 5 |
| gold_reward | 1 |

Роль: слабый вводный враг. Появляется чаще всего.

### Goblin (`goblin.tscn`)

Маленький быстрый зелёный гуманоид с дубиной. Спрайт `goblin.png` (16×16), коллизия r=6.

| Параметр | Значение |
|----------|----------|
| max_health | 4 |
| speed | 55 |
| contact_damage | 1 |
| pickup_drop_chance | 30% |
| xp_reward | 6 |
| gold_reward | 2 |

Роль: быстрый преследователь. Опасен в группах.

### Orc (`orc.tscn`)

Крупный серо-зелёный орк с топором. Спрайт `orc.png` (16×16), коллизия r=8.

| Параметр | Значение |
|----------|----------|
| max_health | 8 |
| speed | 28 |
| contact_damage | 2 |
| pickup_drop_chance | 45% |
| xp_reward | 14 |
| gold_reward | 4 |

Роль: танк. Долго живёт, наносит двойной урон при контакте.

### Skeleton (`skeleton.tscn`)

Скелет-воин с мечом и красными огнями в глазницах. Спрайт `skeleton.png` (16×16), коллизия r=7.

| Параметр | Значение |
|----------|----------|
| max_health | 3 |
| speed | 50 |
| contact_damage | 1 |
| pickup_drop_chance | 30% |
| xp_reward | 7 |
| gold_reward | 2 |

Роль: средний быстрый ближник, немного крепче гоблина.

### Zombie (`zombie.tscn`)

Разлагающийся гуманоид, медленно тащится к игроку. Спрайт `zombie.png` (16×16), коллизия r=7.

| Параметр | Значение |
|----------|----------|
| max_health | 6 |
| speed | 22 |
| contact_damage | 2 |
| pickup_drop_chance | 40% |
| xp_reward | 11 |
| gold_reward | 3 |

Роль: медленный, но живучий и больно бьёт. Требует движения при контакте.

## Charger (`charger.gd`)

### Spider (`charger.tscn`)

Восьминогое чёрное существо с красными глазами. Спрайт `spider.png` (16×16), коллизия r=6.

| Параметр | Значение |
|----------|----------|
| max_health | 1 |
| charge_speed | 220 |
| wait_duration | 1.2 s |
| charge_duration | 0.9 s |
| contact_damage | 1 |
| contact_cooldown | 0.4 s |
| pickup_drop_chance | 35% |
| xp_reward | 8 |
| gold_reward | 1 |

**Поведение:** state machine.
1. `WAITING` — стоит `wait_duration` секунд (светлее оттенок через `modulate`).
2. Фиксирует направление к текущей позиции игрока и переходит в `CHARGING`.
3. `CHARGING` — двигается `charge_speed` в фиксированном направлении `charge_duration` секунд.
4. Возвращается в `WAITING`.

Контактный урон только в `CHARGING`.

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
| pickup_drop_chance | 30% |
| xp_reward | 7 |
| gold_reward | 2 |

Роль: базовый стрелок. Часто встречается.

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
| pickup_drop_chance | 35% |
| xp_reward | 12 |
| gold_reward | 4 |

Роль: продвинутый маг. Крепче лучника и стреляет чаще. Держится ближе (preferred_range 130 vs 160 у лучника).

## Босс

### Necromancer (`boss.tscn`)

Крупная фигура в тёмной робе с капюшоном, посох с зелёным кристаллом. Спрайт `necromancer.png` (32×32), коллизия r=14.

| Параметр | Значение |
|----------|----------|
| max_health | 30 |
| speed | 25 |
| contact_damage | 2 |
| contact_cooldown | 0.8 s |
| volley_interval | 2.0 s |
| volley_count | 8 |
| xp_reward | 40 |
| gold_reward | 20 |

**Поведение:**
- Медленно идёт к игроку через `move_and_collide`.
- Контактный урон 2, cooldown 0.8s.
- Каждые `volley_interval` выпускает `volley_count` штук `enemy_bullet.tscn` **по кругу** — направления через равные `TAU / volley_count` радиан (45° между пулями).

Не дропает пикапы — награда идёт через XP/gold. Появляется каждые 5 этажей (boss-этаж).

## Пул спавна

`Main.ENEMY_SCENES` содержит все 8 обычных типов (без босса). Спавн случайный, равновероятный (`pick_random()`). Босс появляется в отдельной ветке `Main._is_boss_floor()`.

На каждом этаже количество spawn-точек определяется `DungeonGenerator` (см. `docs/gamedesign/dungeon.md`): 2–3 точки в каждой средней комнате и 1–2 в финальной. Общее число врагов на этаж растёт вместе с количеством комнат (больше этажей = больше комнат = больше врагов).

## Пули врагов

`enemy_bullet.tscn` (`Area2D`), placeholder-квадрат 6×6 (визуал ещё Polygon2D, pixel-art follow-up).

| Параметр | Значение |
|----------|----------|
| speed | 110 |
| lifetime | 3.0 s |
| damage | 1 |

**Поведение:** движется `direction * speed`; при `body_entered` наносит `damage`, если body в группе `player`; уничтожается в любом случае (кроме тел в группе `enemy` — их игнорирует). Self-destroy через `lifetime`.

Используется Skeleton Archer, Lich и Necromancer.

Скрипт: `scenes/bullets/enemy_bullet.gd`.

## Спрайты

Все PNG в `assets/sprites/enemies/` генерируются детерминированно скриптом `tools/gen_enemy_sprites.py` (Pillow, палитра + матрица символов). Правки: меняй палитру / матрицу в скрипте, запускай `python3 tools/gen_enemy_sprites.py`, коммить и PNG, и изменения скрипта. Не редактируй PNG вручную — потеряется при следующей регенерации.
