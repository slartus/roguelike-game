# Прогрессия

Всё живёт в `GameState` (autoload, `autoloads/game_state.gd`).

## Уровни забега (run-scoped)

Сбрасываются при смерти игрока (`reset_run()`):

| Поле | Стартовое значение |
|------|--------------------|
| `current_floor_number` | 1 |
| `player_max_health` | 5 (`DEFAULT_MAX_HEALTH`) |
| `player_health` | 5 |
| `equipped_weapon` | Dagger (`DEFAULT_WEAPON`) |
| `player_level` | 1 |
| `player_xp` | 0 |

## XP и уровень

- 1 уровень = **20 XP** (`XP_PER_LEVEL`).
- При level-up: **+1 max_health** (`HEALTH_PER_LEVEL`) и **full heal**.
- Emit `leveled_up(new_level, new_max_health)`, слушают `Player` (обновить `max_health/health`) и `HUD` (обновить label).

Награда за врагов:

| Враг | XP | Gold |
|------|----|----- |
| Melee | 5 | 1 |
| Ranged | 7 | 2 |
| Charger | 8 | 1 |
| Boss | 40 | 20 |

## Мета-прогресс (persistent)

Живёт между забегами, сохраняется в `user://save.cfg`:

| Поле | Смысл |
|------|-------|
| `total_gold` | Накопленное золото за все забеги (при смерти НЕ сбрасывается) |

Пока `total_gold` — просто счётчик; тратить его негде (нет хаба / permanent upgrades). Заготовка под будущий hub.

## Save/Load

- Формат: `ConfigFile` (INI-подобный).
- Файл: `user://save.cfg` (на macOS: `~/Library/Application Support/Godot/app_userdata/Roguelike/save.cfg`).
- Секция `meta`, ключ `total_gold`.
- `_save()` вызывается при каждом `award_gold()`.
- `_load()` — один раз в `_ready` autoload'а.

## Игровой цикл

1. Старт: floor 1, HP 5/5, LVL 1, XP 0/20, Dagger. Этаж — процедурно сгенерированное подземелье из 4–9 комнат, соединённых коридорами (см. `dungeon.md`).
2. Убил всех врагов на этаже → появляется дверь в комнате-выходе → следующий этаж.
3. Каждые 3 этажа: сундук со случайным оружием (генератор ставит одну точку в средней комнате).
4. Каждые 5 этажей: специальный boss-этаж — одна большая арена с одним боссом; обычные враги и сундук пропускаются.
5. Смерть: `reset_run()`, floor 1, всё сбрасывается кроме `total_gold`.

## Сигналы `GameState`

| Сигнал | Аргументы | Кто слушает |
|--------|-----------|-------------|
| `xp_changed` | `current, max_for_level` | HUD |
| `leveled_up` | `new_level, new_max_health` | Player, Main → HUD |
| `gold_changed` | `total` | HUD |
