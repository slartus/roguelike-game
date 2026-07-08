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

## XP-кривая (Pokémon Medium Fast)

Формула: `total_xp(L) = L^3` (canonical Medium Fast growth group из Pokémon Gen III+, ссылка: bulbapedia.bulbagarden.net/wiki/Experience).

XP до следующего уровня: `xp_to_next(L) = (L+1)³ − L³ = 3L² + 3L + 1`.

| Уровень | XP до след. | Cumulative |
|---------|-------------|------------|
| 1 → 2 | 7 | 7 |
| 2 → 3 | 19 | 26 |
| 3 → 4 | 37 | 63 |
| 4 → 5 | 61 | 124 |
| 5 → 6 | 91 | 215 |
| 10 → 11 | 331 | 1000 |

Формулы живут в `autoloads/balance.gd`: `Balance.total_xp_for_level(L)`, `Balance.xp_to_next_level(L)`. `GameState.award_xp` использует `Balance.xp_to_next_level(player_level)` вместо старой константы.

При level-up: **+1 max_health** и **full heal** (`HEALTH_PER_LEVEL = 1`).

## Награды и scaling монстров

Базовые награды и характеристики монстров зафиксированы в их `.tscn` файлах (см. `enemies.md`). Каждый монстр при спавне `_ready` применяет линейное scaling по номеру этажа:

| Стат | Формула | Прирост / этаж |
|------|---------|----------------|
| max_health | `base * (1 + 0.12 * (floor - 1))` | +12% |
| contact_damage | `base * (1 + 0.10 * (floor - 1))` | +10% |
| xp_reward | `base * (1 + 0.15 * (floor - 1))` | +15% |
| gold_reward | `base * (1 + 0.20 * (floor - 1))` | +20% |

Формулы — `Balance.scaled_hp / scaled_damage / scaled_xp_reward / scaled_gold_reward`. Каждый результат `maxi(1, roundi(...))` — минимум 1, никаких 0.

Источник кривой — WoW Classic mob-level table (~10-15% рост stats на уровень). Линейный вариант предсказуемее экспоненты и легче тюнится.

Base statы монстров — D&D 5e Monster Manual (SRD), нормализованные примерно к 1/5 от исходных HP (в roguelike игрок хрупок). См. `enemies.md`.

## Мета-прогресс (persistent)

Живёт между забегами, сохраняется в `user://save.cfg`:

| Поле | Смысл |
|------|-------|
| `total_gold` | Накопленное золото за все забеги (при смерти НЕ сбрасывается) |

Пока `total_gold` — просто счётчик; тратить его негде (нет хаба / permanent upgrades). Заготовка под будущий hub.

## Tower seed

Один `GameState.tower_seed: int` в диапазоне `[0, 2^31-1]` определяет весь layout всех этажей забега. `Floor._pick_seed()` = `tower_seed * 100003 + current_floor_number` — детерминированное отображение.

Свойства:
- Один и тот же `tower_seed` = идентичная башня (все этажи, все комнаты, все спавны в тех же позициях).
- `reset_run()` при смерти генерирует новый случайный `tower_seed` — следующий забег будет другой башней.
- При запуске игры `_ready` тоже генерирует случайный seed.
- Seed логируется в Combat Log при заходе на floor 1 (`EventLog.log_tower_seed(...)` → `LOG_TOWER_SEED` template) — игрок видит его, может скопировать/поделиться/повторить забег.

Формат ключа: `LOG_TOWER_SEED,"Tower seed: %d","Seed башни: %d"` (`resources/translations/strings.csv`).

Пока нет UI для ручного ввода seed — задел под start menu / debug console.

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
