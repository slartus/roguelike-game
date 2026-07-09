# Пикапы и сундуки

Все пикапы — `Area2D` со сигналом `body_entered`. Игнорят всех кроме группы `player`.

**Порядок рендера.** Пикапы (сундук, сердечко, оружие) остаются на default `z_index = 0` — одном уровне с полом и порталом, чтобы не пропадать под окружением. Персонажи (игрок, враги, босс) идут выше — `z_index = 1`, поэтому всегда рисуются поверх любого пикапа, а не за ним.

## HealthPickup — зелье лечения (`health_pickup.tscn`)

Маленький красный бутылёк из трёх Polygon2D: корпус (`Body`, тёмно-красная жидкость с горлышком и плечами), блик (`Highlight`, светло-розовая полоска на левой стороне) и коричневая пробка (`Cork`). Круглая коллизия r=5.

**Поведение (изменено).** Раньше пикап мгновенно лечил и не подбирался при полном HP. Теперь при контакте с игроком **всегда** прибавляет `+1` к `GameState.health_potions` (инвентарь, слот 1) и удаляется. Логика «лечит только при HP < max» переехала в активацию — см. клавишу `1` ниже.

**Активация.** Клавиша `1` (input action `inventory_slot_1`) — `player.gd::_try_use_health_potion`:
- если `health >= max_health` → no-op, зелье не тратится;
- если инвентарь пуст → no-op;
- иначе → `GameState.consume_health_potion()` + `heal(1)` + `EventLog.log_heal(1)`.

**Сброс.** `GameState.reset_run()` (смерть игрока) обнуляет `health_potions` — зелья не переносятся между забегами. `save.cfg` их **не** сохраняет.

**Источники:** случайный дроп с обычных врагов при смерти:

| Враг | Шанс |
|------|------|
| Slime / Goblin / Skeleton | 15% |
| Zombie | 20% |
| Orc | 22% |
| Skeleton Archer | 15% |
| Lich | 18% |
| Charger (Spider) | 18% |
| Boss | 0% |

Скрипт: `scenes/pickups/health_pickup.gd`.

## WeaponPickup (`weapon_pickup.tscn`)

`Sprite2D` с текстурой из `weapon.icon_texture` (16×16), окрашенный через `modulate = weapon.bullet_color`. Коллизия 14×14. Хранит ссылку на `WeaponResource`.

**Поведение:** при контакте с игроком вызывает `player.equip(weapon)` и удаляется. Игрок сохраняет новое оружие в `GameState.equipped_weapon` — оно живёт до конца забега.

**Источник:** сундуки (см. ниже). Отдельно не спавнится.

Скрипт: `scenes/pickups/weapon_pickup.gd`.

## Chest (`chest.tscn`)

`Sprite2D` 20×16 с двумя состояниями через `@export closed_texture` / `@export open_texture`:
- Закрытый — `assets/sprites/pickups/chest_closed.png`
- Открытый — `assets/sprites/pickups/chest_open.png` (виден отвалившаяся крышка и золото внутри)

**Поведение:** при первом контакте с игроком texture меняется на `open_texture`, `monitoring` выключается (повторно не сработает), спавнит `WeaponPickup` со случайным оружием из пула. Пикап появляется чуть ниже сундука (`+Vector2(0, 14)`) чтобы игрок не подобрал его тут же.

**Пул:** `chest.gd::WEAPON_POOL` — `[Dagger, Pistol, Shotgun]`. Выбор равновероятный (может выпасть текущее оружие игрока).

**Спавн:** позиции сундуков задаёт `DungeonGenerator` — по одному сундуку на каждом этаже, кратном 3 (см. `CHEST_FLOOR_INTERVAL` в генераторе). В boss-этажах не спавнится (у генератора `chest_positions` пуст).

Скрипт: `scenes/pickups/chest.gd`.

## Door / Portal (`scenes/rooms/door.tscn`)

Магический портал на следующий этаж. `Area2D` 20×24 с `Sprite2D` из `assets/sprites/pickups/portal.png` (24×32, фиолетовое свечение в каменной раме с зелёной руной).

**Поведение:**
- Изначально `visible = false`, `monitoring = false`.
- Метод `open()` включает visibility и monitoring — вызывается из `Main._open_door()` когда все враги мертвы.
- Сигнал `player_entered` эмитится при входе игрока → `Main._on_door_entered` → `GameState.next_floor()`.

Скрипт: `scenes/rooms/door.gd`.
