# Game Design Docs

При **любом** изменении геймплейных сущностей — обновить соответствующий файл в `docs/gamedesign/` **в том же коммите**.

## Что считается «геймплейной сущностью»

- Комнаты, генерация подземелья.
- Враги, их AI, статы, поведение.
- Оружие, пули, механика стрельбы.
- Пикапы, сундуки, инвентарь.
- Боссы и их спецатаки.
- Прогрессия (XP, level, gold), формулы `Balance`.
- Броня, статус-эффекты, любые новые механики.

Правило действует одинаково на: добавление сущности, изменение параметров (HP, damage, speed, cooldown, drop chance, XP/gold reward), изменение поведения (AI, state machine, взаимодействия), удаление, изменение экономики.

## Соответствие файлов

| Что менял | Обновить |
|-----------|----------|
| `scenes/dungeon/**`, `scenes/main.gd` (spawn/floor logic) | `docs/gamedesign/dungeon.md` |
| `scenes/enemies/**`, `scenes/bullets/enemy_bullet.*` | `docs/gamedesign/enemies.md` |
| `resources/weapons/**`, `resources/weapon_resource.gd`, `scenes/bullets/bullet.*`, `scenes/player/player.gd` (shoot logic) | `docs/gamedesign/weapons.md` |
| `scenes/pickups/**` | `docs/gamedesign/pickups.md` |
| `autoloads/game_state.gd`, `autoloads/balance.gd`, любая логика XP/level/gold/save | `docs/gamedesign/progression.md` |
| Броня (`ArmorResource`, `equipped_armor`, `ArmorPickup`) | `docs/gamedesign/armor.md` |
| HUD, pause, title screen, i18n-строки | `docs/gamedesign/ui.md` / `docs/gamedesign/i18n.md` |
| `assets/sprites/player/player.png`, `assets/sprites/weapons/*.png`, `scenes/player/player.gd` (hand offset / rest angle), новое `resources/weapons/<id>.tres` | `docs/gamedesign/media/player_with_*.png` — см. `60-player-weapon-showcase.md` |

## Чеклист перед commit'ом

1. Затронул `.gd` / `.tscn` / `.tres` в таблице выше?
2. Открыл соответствующий `docs/gamedesign/*.md`?
3. Числа в таблицах doc'а совпадают с реальными `@export` / `const` в коде?
4. Если изменил поведение — переписал раздел «Поведение» под текущую логику?
5. Если добавил новую сущность — добавил её в таблицу-обзор и в `docs/gamedesign/README.md`?

Ответ «нет» хоть на один — доработать docs перед commit'ом.

## Стиль

- Русский язык.
- **Таблицы** для числовых параметров, а не перечисления в тексте.
- В конце описания сущности — путь к скрипту и/или сцене.
- Только фактическое состояние. Планы «на будущее» — отдельный раздел «Планируемое» с явной пометкой «не реализовано» (см. `armor.md`).
- Не переписывай код в docs — описывай **что** делает сущность, не **как** реализовано.

## Что НЕ является game design doc

- Инструкции по сборке / запуску / экспорту → `README.md` в корне.
- Архитектурные решения, паттерны, разбиение кода → `docs/architecture/` (если появится).
- Задачи / roadmap → issue-трекер, не `docs/gamedesign/`.
