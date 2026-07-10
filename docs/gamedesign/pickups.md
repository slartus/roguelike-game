# Пикапы и сундуки

Все пикапы — `Area2D` со сигналом `body_entered`. Игнорят всех кроме группы `player`.

**Порядок рендера.** Пикапы (сундук, сердечко, оружие) остаются на default `z_index = 0` — одном уровне с полом и порталом, чтобы не пропадать под окружением. Персонажи (игрок, враги, босс) идут выше — `z_index = 1`, поэтому всегда рисуются поверх любого пикапа, а не за ним.

## HealthPickup — зелье лечения (`health_pickup.tscn`)

Круглый бутылёк-сфера в Diablo-стиле: `Sprite2D` c текстурой `assets/sprites/pickups/health_potion.png` (16×16 pixel-art). Стеклянная колба-шар с коротким коричневым корком на макушке, красная жидкость с ярким бликом в верхнем-левом квадранте, тёмный ободок обводит всю сферу. Круглая коллизия r=5.

Раньше визуал был сложной Polygon2D-фигурой (корпус + блик + пробка тремя отдельными нодами) с прямоугольным силуэтом бутылька. Пользователь: «перерисовать зелье — более круглый бутылёк, диабло-стайл». Заменено на единый `Sprite2D` с новой текстурой; поскольку HUD-иконка использует тот же силуэт (`assets/sprites/ui/potion_icon.png`, 12×12), пикап и слот инвентаря визуально согласованы.

Обе текстуры генерирует `tools/gen_ui_icons.py` — ground pickup и HUD icon делят одну палитру `POTION_PALETTE`.

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

`Sprite2D` с текстурой из `weapon.icon_texture` (16×16), окрашенный через `modulate = weapon.icon_modulate`. Коллизия 14×14. Хранит ссылку на `WeaponResource`.

Поле `icon_modulate: Color = Color.WHITE` в `WeaponResource` управляет цветом мирового пикапа независимо от `bullet_color` (тот теперь только про снаряд). Legacy Dagger/Pistol/Shotgun имеют собственные `icon_texture` и default `icon_modulate = WHITE` — их полноцветные спрайты рендерятся без искажения. Новые classical weapons (Sword/Spear/Bow/Crossbow/Staff/Wand) пока используют `dagger.png` как placeholder-иконку, отличаясь друг от друга через `icon_modulate` (стальной для меча, серо-стальной для копья, коричневый для лука, тёмно-серый для арбалета, сине-голубой для посоха, пурпурный для жезла) — до появления настоящих спрайтов.

**Поведение:** при контакте с игроком вызывает `player.equip(weapon)` и удаляется. Игрок сохраняет новое оружие в `GameState.equipped_weapon` — оно живёт до конца забега.

**Источник:** сундуки (см. ниже). Отдельно не спавнится.

Скрипт: `scenes/pickups/weapon_pickup.gd`.

## Chest (`chest.tscn`)

`Sprite2D` 20×16 с двумя состояниями через `@export closed_texture` / `@export open_texture`:
- Закрытый — `assets/sprites/pickups/chest_closed.png`
- Открытый — `assets/sprites/pickups/chest_open.png` (виден отвалившаяся крышка и золото внутри)

**Поведение:** при первом контакте с игроком texture меняется на `open_texture`, `monitoring` выключается (повторно не сработает), спавнит `WeaponPickup` со случайным оружием из пула. Пикап появляется чуть ниже сундука (`+Vector2(0, 14)`) чтобы игрок не подобрал его тут же.

**Пул (v2, fantasy-стиль):** `chest.gd::WEAPON_POOL` — 6 классических оружий, по 2 на style:
- Warrior: `short_sword.tres`, `spear.tres`;
- Archer: `short_bow.tres`, `crossbow.tres`;
- Mage: `apprentice_staff.tres`, `wand.tres`.

Legacy `Dagger`, `Pistol`, `Shotgun` **выведены** из активного пула — ресурсы остаются в проекте как исторические, но выпасть в забеге не могут.

**Выбор:** `_choose_weapon()` фильтрует пул, исключая текущее оружие игрока (сравнение по `weapon.id`) — так сундук всегда даёт что-то новое. Если по фильтру ничего не осталось (пул из одного элемента или `GameState.equipped_weapon == null`), fallback — равновероятный выбор из всего пула.

**Спавн:** позиции сундуков задаёт `DungeonGenerator` — по одному сундуку на каждом этаже, кратном 3 (см. `CHEST_FLOOR_INTERVAL` в генераторе). В boss-этажах не спавнится (у генератора `chest_positions` пуст).

Скрипт: `scenes/pickups/chest.gd`.

## Door / Portal (`scenes/rooms/door.tscn`)

Магический портал на следующий этаж. `Area2D` 20×24 с `Sprite2D` из `assets/sprites/pickups/portal.png` (24×32, фиолетовое свечение в каменной раме с зелёной руной).

**Поведение:**
- Изначально `visible = false`, `monitoring = false`.
- Метод `open()` включает visibility и monitoring — вызывается из `Main._open_door()` когда все враги мертвы.
- Сигнал `player_entered` эмитится при входе игрока → `Main._on_door_entered` → `GameState.next_floor()`.

Скрипт: `scenes/rooms/door.gd`.
