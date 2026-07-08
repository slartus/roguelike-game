# Пикапы и сундуки

Все пикапы — `Area2D` со сигналом `body_entered`. Игнорят всех кроме группы `player`.

## HealthPickup (`health_pickup.tscn`)

Красное сердечко-полигон, круглая коллизия r=5.

| Параметр | Значение |
|----------|----------|
| heal_amount | 1 |

**Поведение:** при контакте с игроком, у которого `health < max_health`, вызывает `player.heal(heal_amount)` и удаляется. Если игрок с полным HP — пикап **не расходуется** и остаётся лежать, пока игрок не потеряет хотя бы 1 HP.

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
