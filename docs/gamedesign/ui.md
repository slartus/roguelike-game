# UI (HUD + Combat Log)

Всё UI живёт в одной сцене `scenes/ui/hud.tscn` (`CanvasLayer`), инстансится один раз в `Main`.

## Топ-левый угол — статы игрока

`Label`-ы в позициях слева-сверху, `theme_override_font_sizes/font_size = 12` (по умолчанию Godot ставит 16, но 12 читаемо и меньше перекрывает игровое поле):

| Label | Ключ tr() | Что показывает |
|-------|-----------|----------------|
| `HealthLabel` | `UI_HEALTH` | `HP: %d / %d` |
| `RoomLabel` | `UI_ROOM` | Номер комнаты |
| `LevelLabel` | `UI_LEVEL` | Текущий уровень |
| `XpLabel` | `UI_XP` | XP к следующему уровню |
| `GoldLabel` | `UI_GOLD` | Общее золото (mета) |

Обновляются через `hud.set_*` методы; `Main._ready` подключает сигналы `Player.health_changed`, `GameState.xp_changed`, `GameState.leveled_up`, `GameState.gold_changed`.

## Полоса жизни (визуальный HP-bar)

Рядом с `HealthLabel` в левом верхнем углу — визуальный health bar (`HealthBar` — `Control` 120×14 px, сразу справа от текста HP). Два вложенных `ColorRect`:

- `Background` — тёмный фон полосы (`Color(0.12, 0.12, 0.15, 0.85)`), заливает всю область HealthBar.
- `Fill` — красный fill (`Color(0.85, 0.2, 0.2, 1)`) с padding 1 px внутри Background. Максимальная ширина `HEALTH_BAR_FILL_MAX_WIDTH = 118 px`. Ширина обновляется в `hud.set_health(current, maximum)` как `HEALTH_BAR_FILL_MAX_WIDTH × clampf(current / max(maximum, 1), 0, 1)` — clamp защищает от `current > maximum` и деления на ноль.

Полоса живёт в первой строке HUD рядом с текстовым `HealthLabel`: цифры слева для точности, визуал справа для быстрого чтения на бегу. `HealthLabel` укорочен до 72 px ширины, чтобы освободить место под полосу.

## Title screen (`scenes/ui/title_screen.tscn`)

Точка входа в игру — `project.godot::run/main_scene` = `title_screen.tscn` (не `main.tscn` напрямую). Центрированный `VBoxContainer` с:
- заголовок «Roguelike» (`font_size = 28`);
- кнопка «Играть» — `_on_play_pressed` вызывает `GameState.reset_run()` и `change_scene_to_file("res://scenes/main.tscn")`;
- кнопка «Генерить уровни» — открывает `scenes/dungeon/level_visualizer.tscn`;
- кнопка «Выход» — `_on_exit_pressed` вызывает `get_tree().quit()` (единственный «мирный» способ выйти из десктоп-сборки; ESC на title screen на quit не забинден — только явная кнопка).

Экран также появляется **после смерти игрока**: `player.gd::_die` теперь делает `call_deferred("change_scene_to_file", "res://scenes/ui/title_screen.tscn")` вместо старого `reload_current_scene`. `reset_run` в `_die` уже был раньше — он обнуляет HP/XP/gold/tower_seed/potions.

## Level visualizer (`scenes/dungeon/level_visualizer.tscn`)

Просмотровщик генератора подземелий без игрока и врагов. Инстанцирует `floor.tscn` в `FloorRoot`, `Camera2D` подгоняет `zoom` так, чтобы весь этаж помещался в viewport (с margin ×1.15). В HUD — лейбл текущего `tower_seed` и подсказка «Space — новый seed | ESC — назад».

- `ui_accept` (Enter/Space, встроенное action Godot) — `GameState.tower_seed = randi()` + перегенерирует этаж, показывая новый layout.
- `ui_cancel` (ESC) — возвращает на title screen.

`GameState.current_floor_number` фиксируется на 1 при каждой перегенерации — визуализатор показывает только «обычные» этажи, boss-layout не превьюит.

## Пауза (ESC)

Клавиша `ESC` (input action `pause`) в `hud.gd::_unhandled_input` вызывает `_toggle_pause`: переключает `get_tree().paused` и `visible` панели `PausePanel` (полноэкранный `ColorRect` с alpha 0.6 и центрированной `Label` «ПАУЗА», `font_size = 24`).

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

## Правый нижний угол — Combat Log

Панель `CombatLog` (`VBoxContainer`) справа-снизу с anchor preset `bottom-right`, `alignment = END` (новые записи прижаты к низу).

Размер: 210×140 px в viewport, с margin 4 px от краёв.

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

Планы: показать текущее оружие рядом с `LVL`, добавить mini-progress "X комнат до босса".
