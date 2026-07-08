# Roguelike — правила проекта

## Game Design Docs — обязательное правило

При **любом** изменении геймплейных сущностей (комнаты, враги, оружие, пикапы, боссы, прогрессия, экономика, статы, поведение AI, броня, любые новые механики) **обязательно** обновляй соответствующий файл в `docs/gamedesign/` в **том же коммите**.

Правило действует одинаково на:
- добавление новой сущности,
- изменение параметров существующей (HP, damage, speed, cooldown, drop chance, XP/gold reward и т. д.),
- изменение поведения (AI, state machine, взаимодействия с игроком/пулями/pickup'ами),
- удаление сущности,
- изменение экономики / формул прогрессии.

## Соответствие файлов

| Что менял | Обновить |
|-----------|----------|
| `scenes/rooms/**`, `main.gd` (spawn/room logic) | `docs/gamedesign/rooms.md` |
| `scenes/enemies/**`, `scenes/bullets/enemy_bullet.*` | `docs/gamedesign/enemies.md` |
| `resources/weapons/**`, `resources/weapon_resource.gd`, `scenes/bullets/bullet.*`, `scenes/player/player.gd` (shoot logic) | `docs/gamedesign/weapons.md` |
| `scenes/pickups/**` | `docs/gamedesign/pickups.md` |
| `autoloads/game_state.gd`, любая логика XP/level/gold/save | `docs/gamedesign/progression.md` |
| Появилась броня (`ArmorResource`, `equipped_armor`, `ArmorPickup` и т. п.) | `docs/gamedesign/armor.md` |

## Чеклист перед commit'ом

Перед `git commit` пробеги мысленно:

1. Затронул `.gd`/`.tscn`/`.tres` в списке выше?
2. Открыл соответствующий `docs/gamedesign/*.md`?
3. Числа в таблицах совпадают с реальными `@export` / const в коде?
4. Если изменил поведение — переписал раздел «Поведение» под текущую логику?
5. Если добавил новую сущность — добавил её в таблицу-обзор и в `docs/gamedesign/README.md` если появился новый файл?

Если ответ «нет» хоть на один — доработай docs перед commit'ом.

## Стиль docs

- Русский язык.
- Таблицы для числовых параметров, а не перечисления в тексте.
- В конце каждой сущности — путь к скрипту и/или сцене.
- Только фактическое состояние. Планы и «будущее» — отдельным разделом «Планируемое» с явной пометкой «не реализовано», как в `armor.md`.
- Не переписывать код в docs — описываем **что** делает сущность, а не **как** реализовано.

## Что НЕ является game design doc

- Инструкции по сборке проекта, запуску Godot, экспорту → `README.md` в корне.
- Архитектурные решения, разбиение кода, паттерны → `docs/architecture/` (если появится).
- Задачи / roadmap → issue-трекер, а не `docs/gamedesign/`.
