# Враги

Все враги добавляются в группу `enemy` в `_ready`. При смерти начисляют XP и gold через `GameState.award_xp()` / `award_gold()`. Общий бэкстори — классический fantasy RPG-бестиарий: слизни, гоблиноиды, орки, нежить, пауки.

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
| pickup_drop_chance | 35% |
| xp_reward | 12 |
| gold_reward | 4 |

Роль: продвинутый маг. Крепче лучника и стреляет чаще.

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
