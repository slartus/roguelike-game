# Upgrade cards

Прогрессия игрока внутри забега не сводится к «+1 HP каждый уровень». На нечётных level-up игрок получает выбор из 3 карточек, которые улучшают билд под текущий стиль оружия (warrior / archer / mage) или добавляют общие бонусы (HP, скорость, сопротивление).

Общие принципы v1:

- **Run-scoped.** Стеки карт живут только один забег, `reset_run()` их обнуляет. Никакой meta-progress в этой фиче.
- **Style emerges from cards + weapon**, а не жёсткий class-lock. Игрок с мечом, собирающий Warrior-карты, чувствует себя воином; со сменой оружия на лук те же Warrior-карты остаются в run state, но становятся неактивными.
- **Weapon resources immutable.** Модификаторы применяются на runtime поверх base weapon stats через WeaponStats-слой (появится в M7), а не мутируют `.tres`.
- **Никаких permanent карт**, hub'а, class-selection screen'а, skill tree, mana, armor, criticals в этой фиче. Это отдельные направления backlog'а.

## Data model (M1)

Каждая карта — `PlayerUpgradeResource` (`resources/upgrades/player_upgrade_resource.gd`):

| Поле | Тип | Смысл |
|---|---|---|
| `id` | `String` | Уникальный slug (`thick_skin`, `heavy_strike`) |
| `display_name` | `String` | i18n ключ (`UPGRADE_*`) |
| `description` | `String` | i18n ключ (`UPGRADE_*_DESC`) |
| `rarity` | `enum` | `common` / `uncommon` / `rare` |
| `max_stacks` | `int` | Максимум стеков (1..N) |
| `tags` | `Array[String]` | Свободные теги для фильтра |
| `style` | `String` | `""` (general) / `warrior` / `archer` / `mage` |
| `effect_type` | `String` | Ключ типа эффекта (список ниже) |
| `parameters` | `Dictionary` | Параметры эффекта, зависят от `effect_type` |
| `icon_texture` | `Texture2D` | Иконка на карточке |

**Известные `effect_type`** (список расширяется в M6/M7 при добавлении конкретных карт):

General:
- `max_health_bonus` — `{"amount": int}` — увеличивает max HP.
- `speed_multiplier` — `{"multiplier": float}` — множитель скорости игрока.
- `potion_heal_bonus` — `{"amount": int}` — зелья лечат на N больше.
- `slow_resistance` — `{"amount": float}` — уменьшает силу slow-эффектов.
- `poison_resistance` — `{"duration_multiplier": float}` — сокращает длительность яда.
- `second_wind` — `{"heal": int}` — раз в этаж переживает летальный урон.

Style (Warrior/Archer/Mage):
- `style_damage_bonus` — `{"style": String, "amount": int}` — +damage к оружию совпадающего style.
- `melee_range_multiplier` — `{"multiplier": float}` — melee reach.
- `melee_arc_multiplier` — `{"multiplier": float}` — ширина arc-hitbox'а.
- `knockback_bonus` — `{"amount": float}` — отбрасывание.
- `style_attack_interval_multiplier` — `{"style": String, "multiplier": float}` — cooldown между атаками.
- `pierce_bonus` — `{"amount": int}` — +pierce к projectile.
- `spread_multiplier` — `{"style": String, "multiplier": float}` — уменьшение спреда.
- `projectile_speed_multiplier` — `{"style": String, "multiplier": float}` — скорость снаряда.
- `projectile_lifetime_multiplier` — `{"style": String, "multiplier": float}` — дальность полёта.
- `area_radius_multiplier` — `{"style": String, "multiplier": float}` — радиус area-эффектов.

Все эти keys фиксированы в `PlayerUpgradeLibrary.KNOWN_EFFECT_TYPES`. Валидатор (`validate_all()`) flag'ит карты с unknown `effect_type` — так опечатки не проходят до runtime.

## Library

`PlayerUpgradeLibrary` (`resources/upgrades/player_upgrade_library.gd`, RefCounted):

- `get_all_upgrades()` — все загруженные resources.
- `get_upgrade_by_id(id)` — конкретная карта или null.
- `validate_all()` — Array[String] ошибок (empty = OK). Проверяет: непустой id, уникальность id, префикс `UPGRADE_` у display_name/description, `max_stacks >= 1`, valid `rarity` / `style` / `effect_type`.
- `get_eligible_upgrades(current_stacks)` — карты, у которых игрок ещё не набрал max_stacks. Offer generator (M4) фильтрует через это перед weighted choice.

В M1 `UPGRADE_PATHS = []` — конкретные карты приходят в M6 (general) и M7 (style).

## Run state, генерация оффера, UI

- **M2** — Run state в GameState:
  - `player_upgrade_stacks: Dictionary` — `{upgrade_id: int}`.
  - `pending_upgrade_levels: Array` — очередь уровней, для которых игрок должен выбрать карту (M5 UI обрабатывает по одному).
  - `upgrade_offer_counter: int` — компонент seed'а для deterministic offer generator (M4).
  - `second_wind_used_this_floor: bool` — сбрасывается в `next_floor()` и `reset_run()`.
  - API: `get_upgrade_stack(id)`, `add_player_upgrade(upgrade)`, `has_pending_upgrade_choice()`, `pop_next_pending_upgrade_level()`, `get_player_upgrade_modifiers()`.
  - Сигналы: `upgrade_choice_requested(level)` (эмитится в M3 на нечётных уровнях), `upgrades_changed()` (эмитится после `add_player_upgrade`).
  - `add_player_upgrade` инкрементирует stack и применяет **immediate effects**: `max_health_bonus` увеличивает `player_max_health` + heal на amount. Остальные эффекты — snapshot через `get_player_upgrade_modifiers`, не immediate.
  - `reset_run()` очищает все 4 поля upgrade state.

`get_player_upgrade_modifiers()` возвращает Dictionary с 17 полями (speed_multiplier, potion_heal_bonus, slow_resistance_bonus, poison_duration_multiplier + 4 style-специфичных набора для warrior/archer/mage). Пересчитывается на каждом вызове — стеков мало, дешевле чем держать derived dict в sync с сигналами. Base upgrade resources при этом не мутируются (проверено `test_modifier_snapshot_does_not_mutate_resource`).
- **M3** — hybrid level rhythm: чётные уровни → HP, нечётные (3+) → upgrade choice queue.
- **M4** — Deterministic offer generator (`UpgradeOfferGenerator.generate_offer(context, current_stacks)`):
  - Seed = `tower_seed × 100003 + player_level × 9176 + upgrade_offer_counter × 31337 + 1337`. Одинаковый (tower_seed, level, counter) → одинаковый offer.
  - **Slot 1** отдаётся current-style (если есть eligible), иначе general.
  - **Slot 2** отдаётся general (если ещё не занят).
  - **Slot 3+** — любой из оставшихся eligible.
  - Weighted-random по rarity: common=100, uncommon=35, rare=10.
  - Дубликатов в offer'e нет; maxed cards исключены заранее через `PlayerUpgradeLibrary.get_eligible_upgrades`.
  - Graceful degrade: если eligible < 3, offer будет короче, не крешит.
- **M5** — Modal choice panel (`scenes/ui/upgrade_choice_panel.tscn`):
  - `CanvasLayer` с `layer=5`, `process_mode = ALWAYS` (обрабатывает input во время pause).
  - Автоподписывается на `GameState.upgrade_choice_requested` в `_ready`, отписывается в `_exit_tree`.
  - При событии: pop next pending level → `UpgradeOfferGenerator.generate_offer` → инкремент `upgrade_offer_counter` → рендер 3 кнопок-карточек.
  - Клик по карточке или клавиши 1/2/3 выбирают карту → `add_player_upgrade` → `EventLog.log_upgrade_selected` → если ещё pending — сразу следующий offer, иначе снятие pause.
  - Если `offer.is_empty()` (все карты maxed) — тихо пропускается, чтобы игрок не застыл в pause'е.
  - Подключена в `main.tscn` как sibling HUD.
  - i18n: `UI_CHOOSE_UPGRADE`, `LOG_UPGRADE_SELECTED`.
- **M6/M7** — конкретные карты и их эффекты.
