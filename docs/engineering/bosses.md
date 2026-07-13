# Boss framework

Инженерное описание boss-инфраструктуры. Game-design параметры конкретных боссов лежат в `docs/gamedesign/enemies.md`.

## Обзор

Boss framework — data-driven механика выбора и спавна боссов по floor'у. До PR 1 boss floor обрабатывался через hardcoded `preload("res://scenes/enemies/boss.tscn")` в `main.gd`; после PR 1 всё идёт через `BossRegistry`, а конкретные lifecycle-механики вынесены в общий `BossBase`.

Слои:

- `BossDefinition` — Resource (`scenes/enemies/boss_definition.gd`). Data-описание: id, i18n-ключ, сцена, floor, зона, arena/reward профили, флаг `fallback_allowed`.
- `BossArenaProfile` — Resource (`scenes/enemies/boss_arena_profile.gd`). Размер и метаданные арены. На PR 1 используется только `size`; остальные поля зарезервированы под PR 2–5.
- `BossSpawnContext` — RefCounted (`scenes/enemies/boss_spawn_context.gd`). Typed context, который `Main` передаёт боссу перед `add_child()`.
- `BossBase` — CharacterBody2D (`scenes/enemies/boss_base.gd`). Общий lifecycle: health, floor scaling, take_damage → death, reward hook, phase helper, attack telemetry сигналы.
- `BossRegistry` — RefCounted static (`scenes/enemies/boss_registry.gd`). Единственный источник истины «floor → BossDefinition».

## Spawn pipeline

```
Main._spawn_enemies()
  → _is_boss_floor()   # BossRegistry.definition_for_floor(floor) != null
  → _spawn_boss()
       definition = BossRegistry.definition_for_floor(floor)
       boss      = definition.scene.instantiate()
       context   = BossSpawnContext { floor_number, zone, tower_seed, arena_rect, player }
       boss.apply_spawn_context(context)          # до add_child(), чтобы _ready() видел контекст
       add_child(boss)
```

`floor.gd::_ready()` в свою очередь резолвит `arena_profile` через `BossRegistry.arena_profile_for_floor(floor)` и передаёт `arena_profile.size` в `DungeonGenerator.generate(...)`. Non-boss floor'ы игнорируют параметр.

## Attack IDs

Стабильные идентификаторы атак Некроманта (для аналитики, тестов и будущих UI-тултипов):

- `aimed_projectile` — прицельный magic_bolt.
- `radial_volley` — «звёздочка» dark_orb.
- `summon_minions` — призыв 3 melee + 2 archer.
- `contact` — контактный урон.

Каждый другой босс определит свой набор ID.

## Arena profile

`legacy_arena_profile.tres`:

| Поле                  | Значение         |
|-----------------------|------------------|
| id                    | `legacy_600x400` |
| size                  | 600×400 px       |
| zone                  | `""` (шеринговый) |
| material_profile_id   | `boss_arena`     |
| clear_center_radius   | 0.0              |

`clear_center_radius` пока не используется — оставлен под будущие боссы, у которых центр арены должен быть свободен под особую механику (Rune Golem, Crystal Wyrm).

## Registry mapping (PR 1)

| Floor | Definition   | Notes                                      |
|------:|--------------|--------------------------------------------|
| 5     | necromancer  | Explicit (первый босс).                    |
| 10    | necromancer  | Fallback (fallback_allowed=true).          |
| 15    | necromancer  | Fallback.                                  |
| 20    | necromancer  | Fallback.                                  |

Правила резолвинга (`BossRegistry.definition_for_floor(floor)`):

1. **Явное совпадение** — если в `all_definitions()` есть definition с `floor_number == floor`, возвращается она. Приоритет над fallback.
2. **Fallback slot** — если floor присутствует в `FALLBACK_BOSS_FLOORS` (сейчас `[10, 15, 20]`) и есть хотя бы одна definition с `fallback_allowed = true`, возвращается она.
3. **Иначе** — `null` (non-boss floor).

Логика без magic constant вроде `% 5 == 0` — если завтра появится босс на floor 7, его definition просто получит `floor_number = 7` и попадёт в шаг 1; никакие guard'ы менять не нужно. Slot'ы fallback'а явно перечислены — reviewer видит, где заглушка Некроманта, и что заменяется в PR 2–5 (Castellan → floor 5, Necromancer → floor 15, Rune Golem → floor 10, Crystal Wyrm → floor 20).

## Как добавить нового босса

1. Создать сцену `scenes/enemies/<slug>.tscn` со скриптом, наследующим `BossBase`. Обязательные ноды: `Visual: Sprite2D`, `CollisionShape2D`.
2. Задать i18n-ключ через `display_name` (например `ENEMY_CASTELLAN`) и добавить перевод в `resources/translations/strings.csv` во всех колонках.
3. Создать `resources/bosses/<slug>_definition.tres` с типом `BossDefinition`:
   - `id` — стабильный StringName (`&"castellan"`).
   - `display_name_key` — совпадает с `display_name` босса.
   - `scene` — ссылка на `.tscn`.
   - `floor_number` — на каком этаже спавнить.
   - `zone` — зональный slug из `TowerZone` (`residential` / `technical` / `basement` / `caves`).
   - `arena_profile_id` — id арены (либо переиспользуй `legacy_600x400`, либо создай `<slug>_arena.tres`).
   - `reward_profile_id` — id профиля наград (пока не используется, но заполняй под PR 6).
   - `fallback_allowed = false` — новые боссы всегда явные, не fallback.
4. Обновить `BossRegistry.definition_for_floor()`: добавить mapping для нового floor'а и убрать старый fallback (или оставить если он ещё нужен).
5. Обновить `BossRegistry.all_definitions()`: добавить preload новой definition в возвращаемый массив.
6. Написать GUT-тесты:
   - `test_boss_registry.gd` — floor mapping корректный, id уникален.
   - `test_<slug>.gd` — специфичные механики.
7. Обновить `docs/gamedesign/enemies.md` — добавить раздел с параметрами и поведением.

## Инварианты

- `BossBase` не знает про Necromancer projectiles, summon, arsenal — эта логика живёт в конкретном скрипте.
- `BossRegistry` не использует random. Одинаковый floor всегда даёт одинаковую definition.
- `Main` не знает конкретных boss scene paths. Единственный способ узнать сцену — через `BossRegistry.scene_for_floor(floor)`.
- `died_at` эмиттится **до** `queue_free()` — иначе слушатели увидят freed node (см. `.claude/rules/90-anti-patterns.md`).
- `phase_changed` не эмиттится при `set_phase(same)` — идемпотентно.

## Тесты

- `test/unit/test_boss_registry.gd` — mapping/uniqueness/fallback.
- `test/unit/test_boss_definition.gd` — валидность `necromancer_definition.tres`.
- `test/unit/test_boss_base.gd` — phase, spawn context, signals, inheritance.
- `test/unit/test_boss_volley.gd` / `test_boss_aimed_shot.gd` / `test_boss_summon.gd` — специфика Некроманта, сохранены без изменений после миграции.
