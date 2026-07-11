# Analytics — machine-readable telemetry для баланса

Этот документ описывает архитектуру и правила подсистемы `Analytics`
autoload. Читай его перед тем как:

- добавлять новое событие;
- инструментировать gameplay-код;
- использовать данные для решений по балансу;
- писать local-reports pipeline (PR 3).

## Зачем это

Балансные решения — оружия, карт улучшений, монстров, темпераментов,
экономики, размеров этажей — должны опираться на данные, а не на
«кажется». Analytics превращает сессии игроков в machine-readable
события, которые pipeline (PR 3) агрегирует в отчёты и сравнения версий.

Главный контур:

```
гипотеза
→ аналитические события
→ агрегированные метрики
→ сравнение версий
→ балансное изменение
→ повторная проверка
```

Analytics **не заменяет** playtest, deterministic simulation и unit-тесты
— она их дополняет.

## Что это НЕ

**Analytics ≠ EventLog.** EventLog хранит **локализованные строки** для
игрока (HUD combat log). Analytics хранит **типизированные события** для
offline-анализа. Смешивать нельзя:

- **не парсить** строки из EventLog;
- **не использовать** display text как event ID;
- **не строить** аналитику на UI-логах.

Если фича одновременно нужна и игроку (сообщение в HUD) и балансу
(событие в отчёт) — в HUD идёт `EventLog.log_*(...)`, в аналитику
идёт **отдельный** типизированный `Analytics.<method>(...)` вызов.

## Архитектура

```
autoloads/analytics.gd          — сам сервис (autoload)
analytics/analytics_sink.gd     — интерфейс sink'а
analytics/null_analytics_sink.gd — no-op sink (disabled mode / safe fallback)
analytics/jsonl_analytics_sink.gd — JSONL файл в user://analytics/
analytics/run_analytics_state.gd — runtime counters забега/этажа
analytics/analytics_ids.gd      — генерация UUID, installation_id persistence
```

Analytics service держит **один** sink и один `RunAnalyticsState`.
Gameplay-код общается только с сервисом через типизированные методы
(`start_run`, `finish_floor`, `record_enemy_killed`, …). С sink'ами
напрямую не работает никто, кроме сервиса.

## Event envelope

Каждое событие — Dictionary с фиксированной внешней структурой:

```json
{
  "schema_version": 1,
  "event_name": "floor_completed",
  "event_id": "uuid",
  "timestamp_ms": 0,

  "installation_id": "anonymous-random-id",
  "session_id": "uuid",
  "run_id": "uuid",

  "game_version": "0.0.0",
  "build_commit": "unknown",
  "balance_version": 1,

  "platform": "macos",
  "locale": "ru",

  "tower_seed": 12345,
  "floor": 6,

  "payload": {}
}
```

### Обязательные поля (envelope)

| Поле                 | Тип     | Описание                                              |
|----------------------|---------|-------------------------------------------------------|
| `schema_version`     | int     | `Analytics.ANALYTICS_SCHEMA_VERSION`                  |
| `event_name`         | string  | Стабильное английское имя события                     |
| `event_id`           | string  | UUID-подобный, уникальный                             |
| `timestamp_ms`       | float   | Wall-clock unix time × 1000                           |
| `installation_id`    | string  | Random ID, стабильный между запусками                 |
| `session_id`         | string  | Новый при каждом запуске игры                         |
| `game_version`       | string  | `application/config/version`                          |
| `build_commit`       | string  | Из `res://build_info.txt` или `"unknown"`             |
| `balance_version`    | int     | `Balance.BALANCE_VERSION`                             |
| `platform`           | string  | `"macos"`, `"windows"`, `"linux"`, `"android"`, `"ios"`, `"web"` |
| `locale`             | string  | `TranslationServer.get_locale()`                      |
| `payload`            | dict    | Event-specific data                                   |

### Run-scoped поля

Присутствуют только если run активен (`run_started` эмиттится → есть до `run_finished`):

| Поле         | Тип    | Описание                       |
|--------------|--------|--------------------------------|
| `run_id`     | string | UUID текущего run              |
| `tower_seed` | int    | `GameState.tower_seed`          |

### Floor-scoped поля

Присутствуют только если floor активен (`floor_started` → `floor_completed`):

| Поле    | Тип | Описание                       |
|---------|-----|--------------------------------|
| `floor` | int | `GameState.current_floor_number` |

## События PR 1

| Событие              | Когда эмиттится                                          |
|----------------------|----------------------------------------------------------|
| `session_started`    | Первое обращение к `Analytics.start_session()`           |
| `session_finished`   | `Analytics.end_session(reason)`                          |
| `run_started`        | `Analytics.start_run(context)`                           |
| `run_finished`       | `Analytics.finish_run(summary)`                          |
| `floor_started`      | `Analytics.start_floor(context)`                         |
| `floor_completed`    | `Analytics.finish_floor(summary)`                        |

Полный catalog с payload schema расширится в PR 2 (weapon/upgrade/enemy).

### `session_started`

```json
{ "debug_build": true }
```

### `session_finished`

```json
{ "reason": "normal_exit" }
```

Допустимые reasons: `normal_exit`, `quit_to_menu`, `restart`, `unknown`.

### `run_started`

```json
{
  "starting_weapon_id": "short_sword",
  "starting_max_health": 5,
  "starting_level": 1
}
```

### `floor_started`

```json
{
  "layout_archetype": "residential_spine",
  "zone": "residential"
}
```

В PR 1 archetype/zone ещё не всегда известны — до полной реализации
posylaem `"unknown"`, не выдумываем.

### `floor_completed`

```json
{
  "duration_seconds": 120.0,
  "kills": 12,
  "gold_earned": 20,
  "damage_taken": 4
}
```

### `run_finished`

```json
{
  "reason": "player_death",
  "duration_seconds": 900.0,
  "floor_reached": 7,
  "player_level": 6,
  "gold_earned": 110,
  "enemies_killed": 64,
  "damage_taken": 25
}
```

Допустимые reasons: `player_death`, `victory`, `quit_to_menu`, `restart`,
`application_closed`, `unknown`.

## IDs

| ID              | Стабильность                            | Хранение                       |
|-----------------|-----------------------------------------|--------------------------------|
| `installation_id` | между запусками игры                  | `user://analytics/installation_id.txt` |
| `session_id`      | одна сессия игры                      | RAM                            |
| `run_id`          | один забег                            | RAM                            |
| `event_id`        | одно событие                          | RAM                            |

Все ID генерируются через `AnalyticsIds.new_uuid()` — 128-битный random
через `RandomNumberGenerator` (отдельный от глобального `randi()` стрима,
см. «Детерминизм»). Формат: 8-4-4-4-12 hex-символов.

## Приватность

**Собираем:** random installation ID, session ID, run ID, game version,
commit, balance version, platform family, locale, gameplay-параметры
(seed, floor, weapon ID, kill count и т.п.).

**Не собираем:** имя пользователя, email, IP, домашнюю директорию,
системный username, точную геолокацию, произвольный пользовательский
ввод, содержимое файлов, device fingerprint.

Analytics отключается через `Analytics.set_enabled(false)`. При выключении
sink переключается на `NullAnalyticsSink` — файлы не создаются, события
отбрасываются.

В PR 1 analytics включена **только в debug builds** (`OS.is_debug_build()`).
Prod-переключение и settings-UI — вне scope PR 1 (см. PR 2/3 планы).

## Локальное хранение

- Директория: `user://analytics/`
- Файл сессии: `session_<session_id>.jsonl`
- Формат: UTF-8 JSONL, одна строка — одно JSON-событие
- Запись: append-only

Godot user:// — это platform-specific writable path (см.
[Godot docs](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)).
Не путать с рабочей директорией проекта.

## Batch / flush policy

Sink держит внутренний буфер до `BUFFER_EVENT_LIMIT = 32` событий, затем
автоматически сбрасывает на диск. Дополнительно service вызывает `flush()`
на важных lifecycle-точках:

- `finish_floor` → flush
- `finish_run` → flush
- `end_session` → flush

Application close: Analytics хукает `NOTIFICATION_WM_CLOSE_REQUEST` через
`_notification` handler. При закрытии окна ОС (крестик, cmd+Q, alt+F4):

1. Если run активен → `finish_run({reason: RUN_END_APPLICATION_CLOSED})`.
2. Если session активна → `end_session(SESSION_END_APPLICATION_CLOSED)`.
3. `flush()` → JSONL sink дописывает буфер на диск.
4. `get_tree().quit()`.

Пользователь ничего не замечает — все шаги синхронны и быстры.

**Analytics owns `WM_CLOSE_REQUEST`.** Если в проекте появится ещё один
компонент, желающий перехватить close (например, custom quit-confirm
dialog), его handler должен вызвать `Analytics._handle_application_close()`
перед своей логикой.

**Mobile lifecycle (TODO):** `NOTIFICATION_WM_CLOSE_REQUEST` покрывает
desktop close. Для Android/iOS ОС может убить процесс без close-запроса
после `NOTIFICATION_APPLICATION_PAUSED` (свёртывание в фон). Проект
сейчас не таргетит mobile, но при первом mobile-таргете нужно добавить
flush на `NOTIFICATION_APPLICATION_PAUSED`.

## Версионирование

**`Analytics.ANALYTICS_SCHEMA_VERSION`** — версия envelope-структуры.
Инкрементируется при breaking change формата (новое обязательное поле,
переименование, изменение типа). Не инкрементируется при добавлении
event_name'а или optional payload field'а.

**`Balance.BALANCE_VERSION`** — версия баланса (числовые константы,
формулы, `.tres` веса). Инкрементируется при любом изменении баланса.
Позволяет local-reports pipeline (PR 3) сравнивать runs с одинаковым
балансом.

**`build_commit`** — hash коммита. Берётся из `res://build_info.txt`,
который пишет CI-шаг перед сборкой. Отсутствие файла даёт `"unknown"`
(допустимо для dev-запусков, аналитика не падает).

## Как добавить новое событие

1. Определить смысл события: одно action → один event, или частое
   действие → floor summary с counter'ами.

2. Добавить типизированный wrapper в `autoloads/analytics.gd`:

   ```gdscript
   func weapon_equipped(context: Dictionary) -> void:
       _emit_event(&"weapon_equipped", {
           "weapon_id": String(context.get("weapon_id", "unknown")),
           "previous_weapon_id": String(context.get("previous_weapon_id", "")),
           "source": String(context.get("source", "other")),
       })
   ```

3. **НЕ** экспонировать `_emit_event(name, dict)` наружу — gameplay-код
   должен вызывать только типизированные wrappers.

4. Вызвать wrapper из точки инструментирования — обычно рядом со
   стороной, эмиттящей `EventLog`-сообщение (или прямо в GameState).

5. Обновить этот файл: добавить event в таблицу и описать payload.

6. Добавить unit-test: событие эмиттится, payload корректен, invariants
   держатся.

## Детерминизм

Analytics **не должна** трогать глобальный `randi()` стрим Godot. Это
критично, потому что dungeon generation, spawn table, upgrade offer
generator используют глобальный `randi()` (посеянный через `randomize()`
в `main.gd::_ready`). Если аналитика сдвинет стрим, runs с одинаковым
seed'ом станут воспроизводиться по-разному в зависимости от того,
включена аналитика или нет.

Поэтому:

- `AnalyticsIds.new_uuid()` создаёт **свой** `RandomNumberGenerator`;
- никаких `randi()` / `randf()` из аналитического кода;
- проверяется тестом `test_analytics_does_not_shift_global_rng` и
  `test_new_uuid_does_not_consume_global_rng`.

## Отказоустойчивость

Правило: аналитика **никогда** не должна останавливать gameplay.

При IO-ошибке (не открылся файл, не создалась директория,
FileAccess вернул null):

1. Sink помечает себя `is_broken() == true`.
2. Sink пишет `push_warning(...)`.
3. При следующем `_emit_event` service читает `is_broken()` и
   переключается на `NullAnalyticsSink`.
4. Gameplay продолжает работать. Никаких popup'ов, никаких crashes.

## Time source

- **`Time.get_ticks_msec()`** — monotonic clock, используется для
  duration'ов (`floor_duration_seconds`, `run_duration_seconds`).
  Не подвержен изменению системного времени в процессе игры.

- **`Time.get_unix_time_from_system()`** — wall-clock, используется
  только для `envelope.timestamp_ms`.

## Ограничения PR 1

Это первая версия. Целенаправленно НЕ включено:

- weapon/upgrade/enemy/temperament instrumentation (PR 2);
- damage attribution с source chain (PR 2);
- room-level exploration events (PR 2);
- economy/potion split (PR 2);
- floor layout metrics (PR 2);
- local reports pipeline / CSV / HTML (PR 3);
- content balance hash (PR 3);
- version comparison (PR 3);
- settings-UI toggle (PR 2 или M13);
- remote endpoint (не планируется в первой версии).

При добавлении новых событий следуй той же дисциплине: envelope
неизменен, payload event-specific, никакого сдвига RNG, никакого
crash'а от IO-ошибки.
