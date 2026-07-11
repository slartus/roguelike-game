# UI (HUD + Combat Log)

Всё UI живёт в одной сцене `scenes/ui/hud.tscn` (`CanvasLayer`), инстансится один раз в `Main`.

## Полоса жизни (визуальный HP-bar) + уровень

HP не показывается текстом — только визуальной полосой в самом верхнем-левом углу (`HealthBar` — `Control`, offset_left=8, offset_top=8). Внутри неё:

- `Background` (`ColorRect`) — тёмный фон (`Color(0.12, 0.12, 0.15, 0.85)`), anchor 15, растягивается на всю область HealthBar.
- `Fill` (`ColorRect`) — красный fill (`Color(0.85, 0.2, 0.2, 1)`) с padding 1 px внутри Background.
- `LevelLabel` (`Label`) — текст уровня («LVL 1» / «Ур. 1» через ключ `UI_LEVEL`), anchor 15, `font_size = 10`, белый текст + чёрная тень + outline (для читаемости на любом цвете fill'а). Обновляется через `hud.set_level`.

**Полоса растёт вместе с `max_health`.** `HEALTH_BAR_PX_PER_HP = 12` — ширина одного «hp-делителя». В `hud.set_health(current, maximum)`:
- `HealthBar.size.x = maximum * PX_PER_HP + 2 * padding` (background увеличивается вместе с level up).
- `Fill.size.x = current * PX_PER_HP` (заполнение = сколько ещё осталось).

`clampi` защищает от `current > max` и `max <= 0`. Player сигнал `Player.health_changed` пробрасывает `(current, max_health)` в `hud.set_health`, поэтому level up (расширяющий `max_health`) визуально расширяет саму полосу, а не только пропорцию заполнения. `LevelLabel` рендерится поверх Fill (anchor 15), так что при росте полосы он остаётся по центру.

## Правый-нижний угол — золото и этаж

Вертикальный контейнер `BottomRightStats` (`VBoxContainer`, anchor 3, offset (−104, −44) до (−4, −4), `alignment = 2` — контент прижат к низу). Внутри — две строки `HBoxContainer` со стандартом «иконка слева, число справа», `separation = 4`:

| Строка | Иконка (Control, 14×14) | Скрипт | Label |
|--------|-------------------------|--------|-------|
| `GoldRow` | `CoinIcon` — золотая монета через `_draw` (rim, outer, inner, highlight-круги) | `scenes/ui/coin_icon.gd` | `GoldLabel` — только число, `font_size = 12` |
| `FloorRow` | `TowerIcon` — башня с зубцами и окном через `_draw` | `scenes/ui/tower_icon.gd` | `FloorLabel` — только число, `font_size = 12` |

Иконки рисуются процедурно через `_draw` (см. `.claude/rules/50-animations-gifs.md` — процедурные визуалы), чтобы не заводить PNG-ассеты ради 14×14 пиктограмм. Тон монеты совпадает с золотой палитрой пикапов, тон башни — тёплый камень.

Обновляются через `hud.set_gold(total)` и `hud.set_floor(number)`; поскольку контекст даёт иконка, текст лейбла — просто `"%d"`, без префиксов `Gold:` / `Floor` (ключи `UI_GOLD` / `UI_FLOOR` из CSV в основном HUD не используются; они остались как исторические, но HUD их не читает).

`Main._ready` подключает `GameState.gold_changed → hud.set_gold` и однократно вызывает `hud.set_floor(current_floor_number)` + `hud.set_level(player_level)`. `GameState.leveled_up` через `_on_leveled_up` обновляет уровень на полосе HP.

**XP не показывается в основном HUD** — он виден только в pause панели (см. ниже). Соответствующего `hud.set_xp` больше нет, и `main.gd` не подписан на `xp_changed`.

## Title screen (`scenes/ui/title_screen.tscn`)

Точка входа в игру — `project.godot::run/main_scene` = `title_screen.tscn` (не `main.tscn` напрямую). Центрированный `VBoxContainer` с:
- заголовок «Roguelike» (`font_size = 28`);
- **RunStatsPanel** — окно «Итоги забега» (см. ниже), видно только когда `GameState.has_last_run_stats == true`;
- кнопка «Играть» — `_on_play_pressed` вызывает `GameState.clear_last_run_stats()` (гасит окно итогов), затем `GameState.reset_run()` и `change_scene_to_file("res://scenes/main.tscn")`;
- кнопка «Дебаг» (i18n-ключ `UI_TITLE_DEBUG`) — открывает хаб дебаг-инструментов `scenes/ui/debug_menu.tscn`;
- кнопка «Выход» — `_on_exit_pressed` вызывает `get_tree().quit()` (единственный «мирный» способ выйти из десктоп-сборки; ESC на title screen на quit не забинден — только явная кнопка).

### Итоги забега (`RunStatsPanel`)

После смерти игрок попадает на title screen с окном сводки: достигнутый этаж, уровень, убито врагов, собрано золота за забег. Пайплайн:

1. Во время run — `GameState.award_gold` копит `run_gold`, `GameState.award_enemy_kill` (вызывается из `enemy.gd`, `boss.gd`, `charger.gd`, `ranged_enemy.gd` при `queue_free`) копит `run_enemies_killed`.
2. `player.gd::_die` вызывает `GameState.finish_run()` — снимает snapshot (`last_run_floor`, `last_run_level`, `last_run_gold`, `last_run_enemies_killed`), поднимает `has_last_run_stats = true`, затем чистит run state через `reset_run()`.
3. `title_screen.gd::_refresh_run_stats_panel` показывает панель если флаг взведён, заполняет лейблы через `tr("UI_RUN_STATS_*")`.
4. Клик «Играть» → `clear_last_run_stats()` гасит флаг; следующий заход на title screen без реальной смерти окна не покажет.

Экран также появляется **после смерти игрока**: `player.gd::_die` делает `GameState.finish_run()` + `call_deferred("change_scene_to_file", "res://scenes/ui/title_screen.tscn")`. `finish_run` фиксирует итоги забега и сам зовёт `reset_run` (HP/XP/gold/tower_seed/potions).

## Debug menu (`scenes/ui/debug_menu.tscn`)

Хаб дебаг-инструментов. Открывается по кнопке «Дебаг» на title screen. Скрипт в `_ready` восстанавливает `Window.CONTENT_SCALE_MODE_VIEWPORT` — на случай если пользователь вернулся сюда из `dungeon_preview_screen`, который его отключает. ESC отсюда возвращает на title (тот же обработчик, что и кнопка «Назад»).

Три кнопки в центральном `VBoxContainer`, все текст-ключи из `strings.csv`:

- `GenerateButton` (`UI_DEBUG_GENERATE`) — открывает `scenes/debug/dungeon_preview_screen.tscn` (список превьюх этажей + seed picker + Play).
- `CharacterButton` (`UI_DEBUG_CHARACTER`) — открывает `scenes/debug/weapon_test_screen.tscn` (песочница персонажа со всеми оружиями).
- `BackButton` (`UI_DEBUG_BACK`) — возвращает на title screen.

## Weapon test screen (`scenes/debug/weapon_test_screen.tscn`)

Дебаг-песочница персонажа с оружием. Открывается из debug menu кнопкой «Персонаж». Комната совпадает с viewport'ом `480×270`; стены толщиной 12 px по периметру — 4 `StaticBody2D` с `RectangleShape2D`, ограничивающие камеру и движение игрока (пол — `ColorRect` `#1A1424`, стены — `ColorRect` `#38304C`).

В `_ready`:

1. `GameState.reset_run()` — нейтрализуем ongoing run (level/xp/gold/tower_seed сбрасываются); песочница не должна затрагивать прогресс живого забега.
2. `GameState.equipped_weapon = null` — снимаем стартовый меч, чтобы игрок реально подобрал оружие из ряда, а не бил дефолтным.
3. Строим комнату, спавним игрока в `PLAYER_SPAWN_POSITION` (`Vector2(240, 190)`), настраиваем `Camera2D.limit_*` по границам комнаты.
4. Раскладываем весь `WEAPON_ROSTER` (все 9 `.tres` из `resources/weapons/`) в ряд вдоль верхней стены на `y = 48`: `x = wall_thickness + slot_width * (i + 0.5)`, где `slot_width = inner_width / roster_size`. Порядок соответствует порядку в коде — читается слева направо.

HUD — один `Label` `UI_DEBUG_WEAPON_HINT` вверху с подсказкой управления. ESC (`ui_cancel`) возвращает на `debug_menu.tscn`.

Тест `test/unit/test_weapon_test_screen.gd::test_all_weapons_in_resources_dir_are_included_in_roster` защищает от рассинхрона: если в `resources/weapons/` добавили новый `.tres`, но `WEAPON_ROSTER` не обновили — тест красный.

## Level visualizer (`scenes/dungeon/level_visualizer.tscn`)

Просмотровщик генератора подземелий без игрока и врагов. Инстанцирует `floor.tscn` в `FloorRoot`, `Camera2D` подгоняет `zoom` так, чтобы весь этаж помещался в viewport (с margin ×1.15). В HUD — лейбл текущего `tower_seed` и подсказка «Space — новый seed | ESC — назад».

- `ui_accept` (Enter/Space, встроенное action Godot) — `GameState.tower_seed = randi()` + перегенерирует этаж, показывая новый layout.
- `ui_cancel` (ESC) — возвращает на title screen.

`GameState.current_floor_number` фиксируется на 1 при каждой перегенерации — визуализатор показывает только «обычные» этажи, boss-layout не превьюит.

## Пауза (ESC)

Клавиша `ESC` (input action `pause`) в `hud.gd::_unhandled_input` вызывает `_toggle_pause`: переключает `get_tree().paused` и `visible` панели `PausePanel` (полноэкранный `ColorRect` с alpha 0.6 и центрированным `VBoxContainer` `PauseBox` с заголовком «ПАУЗА» + пятью строками статистики текущего забега).

**Статистика текущего забега на паузе** (`_refresh_pause_stats`): при включении паузы labels обновляются через `tr(...)`, показывая:
- `UI_RUN_STATS_FLOOR` — `GameState.current_floor_number`;
- `UI_RUN_STATS_LEVEL` — `player_level`;
- `UI_XP` — `player_xp / xp_to_next_level(player_level)` (XP убран из основного HUD и виден только тут);
- `UI_RUN_STATS_KILLS` — `run_enemies_killed`;
- `UI_RUN_STATS_GOLD` — `run_gold`;
- `LOG_TOWER_SEED` — `tower_seed` (используется тот же ключ, что и в первом логе на floor 1 — семантически «seed этой башни», игрок может скопировать/поделиться).

Ключи `UI_RUN_STATS_*` shared с окном «Итоги забега» на title screen — одна семантика. Разница: пауза показывает **текущий прогресс** (`run_*` + `current_*`), title screen — **snapshot прошлого забега** (`last_run_*`).

HUD помечен `process_mode = ALWAYS` в `.tscn` — иначе после первого ESC весь дерево на паузе, HUD тоже, второй ESC не может её снять. Все остальные ноды (Main, Player, враги, пикапы) остаются на дефолте `INHERIT` → замирают при `get_tree().paused = true`.

## Нижний левый угол — Инвентарь

Панель `InventoryPanel` (`Control`, без фонового тона) с одной квадратной ячейкой `PotionSlot` (`Panel` 20×20 с прозрачным `StyleBoxFlat`, `border_color = Color(0.55, 0.55, 0.6)`, `border_width = 1` по всем сторонам). Внутри ячейки:
- `PotionIcon` (`TextureRect`, `res://assets/sprites/ui/potion_icon.png` 12×12) — в центре, `expand_mode = 1`, `stretch_mode = 5`;
- `PotionCount` (`Label`, `font_size = 10`) — в правом-нижнем углу ячейки, формат `«×N»`.

`hud.gd::set_potion_count` показывает или прячет **обе** дочерние ноды в зависимости от количества:
- `count == 0` → `PotionIcon.visible = false`, `PotionCount.visible = false`. Пользователь видит только рамку слота — «пустой квадратик без количества».
- `count > 0` → обе видны, счётчик пишет `«×3»`.

Пользователь просил «убрать затенение» — в старой версии `InventoryPanel` был `PanelContainer` с дефолтным полупрозрачным фоном; теперь `Control` без фона и sub-slot использует только 1-px рамку.

Активация — клавиша `1` (input action `inventory_slot_1`) в `player.gd::_unhandled_input`. Если игрок с полным HP или инвентарь пуст — no-op, зелье не тратится (см. `docs/gamedesign/pickups.md`).

Пока в инвентаре один слот — зелья лечения. Расширяется: новые квадратные слоты можно добавить как sibling'и `PotionSlot` (сдвинуть по `offset_left`) с их собственными иконками и подпиской на соответствующие сигналы `GameState`.

## Правый нижний угол — Combat Log (над BottomRightStats)

Панель `CombatLog` (`VBoxContainer`) справа-снизу с anchor preset `bottom-right`, `alignment = END` (новые записи прижаты к низу).

Размер: 206×130 px в viewport (offset_left=−210, offset_top=−180, offset_right=−4, offset_bottom=−50), с margin 4 px от краёв — «bottom-margin» 50 px оставляет место под `BottomRightStats` (золото + этаж), поэтому лог и статы не наезжают друг на друга.

Каждая запись — динамически создаваемый `Label` с:
- `font_size = 10` (мелкий, не мешает игре),
- цветовым `font_color` из `EventLog.*_TINT` (жёлтый убийства, зелёный heal, голубой оружие, оранжевый сундук, светло-жёлтый комната, красный босс, розовый level up),
- `horizontal_alignment = RIGHT` — прижаты к правому краю,
- `autowrap_mode = WORD_SMART`.

Жизненный цикл записи:
1. `EventLog.entry_added(text, tint)` → HUD создаёт `Label`, добавляет в `CombatLog`.
2. Если записей > `LOG_MAX_ENTRIES` (6) → удаляется самая старая (верхняя).
3. Через `LOG_ENTRY_LIFETIME` (5 с) запускается `tween` fade `modulate:a → 0` за `LOG_FADE_DURATION` (0.4 с) → `queue_free`.

Порядок: `alignment = END` в VBox прижимает всех детей к низу. Новые записи `add_child` → появляются в самом низу, старые уплывают вверх пока не будут удалены.

## EventLog (autoload)

`autoloads/event_log.gd` — event-bus для combat log. Сущности вызывают типизированные методы:

| Метод | Ключ шаблона | Кто вызывает |
|-------|--------------|--------------|
| `log_kill(key, xp, gold)` | `LOG_KILL_WITH_GOLD` / `LOG_KILL_XP_ONLY` / `LOG_KILL_PLAIN` | Enemy / Charger / Ranged / Boss в `take_damage` при смерти |
| `log_heal(amount)` | `LOG_HEAL` | HealthPickup при контакте |
| `log_weapon_pickup(key)` | `LOG_WEAPON_PICKUP` | WeaponPickup при контакте |
| `log_chest_open()` | `LOG_CHEST_OPEN` | Chest при первом контакте |
| `log_room(n)` | `LOG_ROOM` | Main._ready для обычных комнат |
| `log_boss_room(n)` | `LOG_BOSS_ROOM` | Main._ready для boss-комнат |
| `log_level_up(lvl)` | `LOG_LEVEL_UP` | GameState._level_up |

Все методы:
1. Резолвят имя через `tr(key)` (для kill/weapon — переводят display_key врага/оружия).
2. Форматируют шаблон через `tr("TEMPLATE") % args`.
3. Эмитят `entry_added(final_text, tint)`.

## Локаль по умолчанию

`EventLog._ready` вызывает `TranslationServer.set_locale("ru")` — сейчас проект стартует в русском. Fallback locale в `project.godot` — `en`.

## Что НЕ показывается в HUD

- Позиция игрока (визуально видно на экране).
- Ссылка на текущее оружие (можно добавить в HUD как отдельный лейбл — пока нет).
- Прогресс до boss-комнаты (пока не показываем).

Планы: показать текущее оружие рядом с `BottomRightStats`, добавить mini-progress "X комнат до босса".
