# Враги

Все враги добавляются в группу `enemy` в `_ready`. При смерти начисляют XP и gold через `GameState.award_xp()` / `award_gold()`.

## Обычные враги

### Melee (`enemy.tscn`)

Красный квадрат 14×14, `CharacterBody2D`.

| Параметр | Значение |
|----------|----------|
| max_health | 3 |
| speed | 40 |
| contact_damage | 1 |
| contact_cooldown | 0.6 s |
| pickup_drop_chance | 30% |
| xp_reward | 5 |
| gold_reward | 1 |

**Поведение:** Идёт к игроку (`get_nodes_in_group("player")`), при `move_and_collide` попадании в игрока наносит `contact_damage` и уходит в cooldown. Cooldown применяется только к контактному урону, не к движению.

Дроп: `HealthPickup` через `pickup_scene`, инжектится `Main` при спавне.

Скрипт: `scenes/enemies/enemy.gd`.

### Ranged (`ranged_enemy.tscn`)

Синий квадрат 14×14, `CharacterBody2D`.

| Параметр | Значение |
|----------|----------|
| max_health | 2 |
| speed | 0 (стоит на месте) |
| fire_interval | 1.5 s |
| pickup_drop_chance | 30% |
| xp_reward | 7 |
| gold_reward | 2 |

**Поведение:** не двигается. Раз в `fire_interval` создаёт `enemy_bullet.tscn`, направленный в текущую позицию игрока. Стартовый таймер рандомно сдвинут (`randf() * fire_interval`) — чтобы залпы не были синхронными.

Скрипт: `scenes/enemies/ranged_enemy.gd`.

### Charger (`charger.tscn`)

Оранжевый треугольник вершиной вверх, `CharacterBody2D`.

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
1. `WAITING` — стоит `wait_duration` секунд (светло-оранжевый `modulate`).
2. По истечении таймера фиксирует направление к текущей позиции игрока и переходит в `CHARGING` (насыщенный оранжевый).
3. `CHARGING` — двигается `charge_speed` в фиксированном направлении `charge_duration` секунд. Уклонение возможно — направление не корректируется.
4. По истечении `charge_duration` возвращается в `WAITING`.

Контактный урон в `CHARGING`; `WAITING` = безопасно приближаться.

Скрипт: `scenes/enemies/charger.gd`.

## Босс

### Boss (`boss.tscn`)

Фиолетовый ромб 36×36, `CharacterBody2D`.

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
- Контактный урон 2 (сильнее рядовых), cooldown 0.8s.
- Каждые `volley_interval` выпускает `volley_count` штук `enemy_bullet.tscn` **по кругу** — направления через равные `TAU / volley_count` радиан (45° между пулями).

Пикапов не дропает — награда идёт через XP/gold. Появляется каждые 5 комнат.

Скрипт: `scenes/enemies/boss.gd`.

## Пули врагов

`enemy_bullet.tscn` (`Area2D`), оранжевый круг r=3.

| Параметр | Значение |
|----------|----------|
| speed | 110 |
| lifetime | 3.0 s |
| damage | 1 |

**Поведение:** движется `direction * speed`; при `body_entered` наносит `damage`, если body в группе `player`; уничтожается в любом случае (кроме тел в группе `enemy` — их игнорирует). Self-destroy через `lifetime`.

Используется Ranged-врагом и Boss'ом.

Скрипт: `scenes/bullets/enemy_bullet.gd`.
