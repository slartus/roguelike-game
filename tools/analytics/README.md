# tools/analytics — local analysis pipeline

Локальный CLI-pipeline, который превращает `user://analytics/*.jsonl`
из PR 1/2 в датасет, отчёт и балансовое сравнение. Никакого remote
backend, никаких сторонних зависимостей — Python 3.10+ standard library.

## Требования

- Python 3.10+.
- Никаких сторонних пакетов. Всё на stdlib (`json`, `csv`, `argparse`,
  `pathlib`, `hashlib`, `html`, `statistics`, `unittest`).

## Где лежат JSONL

Godot клиент пишет события через `JsonlAnalyticsSink` (см.
`docs/engineering/analytics.md`) в:

| Платформа | Путь |
|-----------|------|
| macOS     | `~/Library/Application Support/Godot/app_userdata/<project>/analytics/` |
| Linux     | `~/.local/share/godot/app_userdata/<project>/analytics/` |
| Windows   | `%APPDATA%/Godot/app_userdata/<project>/analytics/` |

Один файл на сессию, имя — `session_<uuid>.jsonl`.

## Команды

Все команды запускать из корня репо. Модули вызываются как
`python3 -m tools.analytics.<command>`.

### 1. Импорт JSONL

```bash
python3 -m tools.analytics.import_jsonl \
  --input /path/to/analytics \
  --output analytics_output/events.jsonl \
  --issues-output analytics_output/import_issues.json
```

Стойкий к повреждённой последней строке, дублям (по `event_id`), unknown
event_name (пропускаются с warning), future `schema_version` (отбрасываются).

### 2. Валидация

```bash
python3 -m tools.analytics.validate_events \
  --input /path/to/analytics \
  --output analytics_output/issues.json
```

Уровни: `error` / `warning` / `info`. Exit code = 1 если есть errors.

Проверяет: envelope required fields, event-specific payload,
типы/enum'ы, monotonic floor progression внутри run, дубли
`run_started`/`run_finished`, `floor_completed` без `floor_started`,
невозможный `health_before > max_health`, отрицательные numeric поля.

### 3. Датасет (CSV)

```bash
python3 -m tools.analytics.build_dataset \
  --input /path/to/analytics \
  --output analytics_output
```

Пишет 9 CSV + `data_quality.json`:

| Файл | Одна строка на |
|------|----------------|
| `sessions.csv` | session |
| `runs.csv` | run |
| `floors.csv` | (run, floor) |
| `weapons.csv` | (run, floor, weapon_id) |
| `upgrade_offers.csv` | offered card |
| `upgrade_selections.csv` | выбранная карта |
| `enemies.csv` | (run, floor, enemy_id, temperament, elite_rank) |
| `economy.csv` | (run, floor) — суммы gold/potions/heal |
| `rooms.csv` | first-entered room |

### 4. HTML-отчёт

```bash
python3 -m tools.analytics.generate_report \
  --input /path/to/analytics \
  --output analytics_output/report.html
```

Один автономный HTML: Overview, Weapons, Upgrades, Enemies, Dungeon,
Economy, Data quality. С каждым разделом идут sample sizes.

### 5. Сравнение balance-version'ов

```bash
python3 -m tools.analytics.compare_versions \
  --input /path/to/analytics \
  --baseline-balance-version 4 \
  --candidate-balance-version 5 \
  --output analytics_output/comparison.html \
  --json-output analytics_output/comparison.json
```

Показывает absolute + percent delta по completion rate, median floor,
median duration, weapon hit_rate + damage_per_equipped_minute, enemy
damage_per_spawn + kill_rate. Sample size warnings рядом с каждой
метрикой.

Statistical significance **не** рассчитывается — план явно запрещает
объявлять её без корректной реализации.

### 6. Content balance hash

```bash
python3 -m tools.analytics.hash_content --project-root .
```

Печатает SHA256 значимых balance-ресурсов (weapons/upgrades/enemies
`.tres` + `autoloads/balance.gd`). Считает hash строго по указанным
include-globs; всё остальное (textures, docs, translations, `.import`
кэш, timestamps) вне scope. Содержимое нормализуется CRLF → LF, чтобы
Windows и Unix checkout одной и той же ревизии давали одинаковый hash.

## Метрики

### Weapons
- `damage_per_equipped_minute`, `damage_per_combat_minute`
- `hit_rate` = attacks_with_hit / attacks
- `projectile_hit_rate` = projectiles_hit / projectiles_fired
- `kills_per_minute`
- `damage_taken_while_equipped`

### Upgrades
- `pick_rate` = selected / offered
- `pick_rate` по position (обнаруживает position bias)
- median `choice_time_seconds`

### Enemies
- `damage_per_spawn`
- `kill_rate` = killed / spawned
- `avg_time_to_kill_seconds` = time_alive_seconds / killed

### Dungeon (per floor number)
- `avg_duration_seconds`
- `rooms_visited_ratio` = rooms_visited / room_count
- `avg_walkable_area_cells`, `avg_critical_path_length`

### Economy
- `gold_split`: enemies / chests / props / bosses
- `potion_use_rate` = potions_used / potions_received
- `overheal_ratio` = overheal / healing_received

Все метрики используют safe-division (0 при пустом знаменателе).

## Privacy

Pipeline не читает и не пишет PII (usernames, IP, пути пользователя,
координаты в мире). Единственные идентификаторы — random UUID
`installation_id` / `session_id` / `run_id` / `event_id`, сгенерированные
на устройстве.

## Sample-size caveats

- N < 10 — anecdotal, не выводить решений о балансе.
- N < 30 — только тенденции.
- N < 100 — moderate.
- N ≥ 100 — sample ok.

Report печатает note на каждой секции. Guardrails против ложных выводов
описаны в `docs/engineering/analytics-reports.md` (раздел «Interpretation
caveats»).

## Тесты

```bash
python3 -m unittest discover -s tools/analytics/tests -p "test_*.py"
```

Не требуют реальных JSONL — используют synthetic fixture из
`tools/analytics/tests/fixtures/build_fixtures.py`.

## Что НЕ коммитить

- реальные пользовательские `*.jsonl`;
- `analytics_output/` (в `.gitignore`);
- сборки отчётов из личной сессии.

## См. также

- `docs/engineering/analytics.md` — PR 1/2 контракт (envelope + events);
- `docs/engineering/analytics-reports.md` — workflow балансировки и
  интерпретация метрик.
