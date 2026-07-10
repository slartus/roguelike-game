# Тесты (GUT)

Проект использует GUT (Godot Unit Test) 9.6+ из `addons/gut/`.

## Основной принцип

**Покрывай тестами всё что технически можно покрыть.** Если у сущности есть детерминированное поведение с проверяемым результатом (числа, состояния, факт вызова метода, изменение поля, сигнал) — она **обязана** иметь тест. Не выбирай «а стоит ли», покрывай.

## Что покрывать

| Слой | Что проверять |
|------|---------------|
| **GameState / Balance** | XP, level, gold, `reset_run`, `finish_run`, save/load, все формулы прогрессии |
| **Player** | `take_damage`, `heal`, `equip`, level-up max_health, cooldown, spread/multishot, инвентарь потионов |
| **Enemies** | `take_damage`, drop pickup (детерминизировать `randf` через seed), award xp/gold/kill, state machine, volley/summon |
| **Bullets** | `apply_weapon` копирует статы, попадание вызывает `take_damage`, self-destroy по `lifetime` |
| **Pickups / Chest** | `HealthPickup` → `heal`, `WeaponPickup` → `equip`, Chest на первый контакт спавнит и уходит в `_opened=true` |
| **WeaponResource (.tres)** | Загружаются с ожидаемыми полями (защита от опечаток в `.tres`) |
| **Main / level controller** | `target_count(room_number)`, `_is_boss_floor()`, шанс сундука |
| **Rooms (.tscn)** | Наличие `SpawnPoints`, `PlayerStart`, `Door` в каждой комнате |
| **HUD / UI** | Реакция на сигналы `xp_changed`, `gold_changed`, `health_potions_changed`, pause контракт |

## Исключения (можно не тестировать)

- Чисто визуальные детали: конкретные координаты `Polygon2D`, цвета, `modulate`-flash.
- Random-эффекты которые нельзя детерминизировать. Если можно детерминизировать через seed — покрывай.

## Стиль тестов

- Файл: `test/unit/test_<feature>.gd`, `extends GutTest`.
- Метод: `func test_<what>_<condition>()`, snake_case, английский.
- Assert-сообщение — не «должно работать», а «actual='%s'» или «why: X при Y».

## Обязательный snapshot/restore autoload state

Autoload'ы (`GameState`, `Balance`, `EventLog`) — **shared state между тестами**. Всегда `before_each` снимает snapshot, `after_each` восстанавливает.

Reference шаблон — `test/unit/test_game_state.gd`:

```gdscript
var _snapshot: Dictionary

func before_each() -> void:
    _snapshot = {
        "floor": GameState.current_floor_number,
        "hp": GameState.player_health,
        # ... все поля которые тест может тронуть
    }

func after_each() -> void:
    GameState.current_floor_number = _snapshot["floor"]
    GameState.player_health = _snapshot["hp"]
    # ...
```

Специальные случаи `after_each`:
- Тесты с паузой — `get_tree().paused = false` (иначе следующие тесты с `await get_tree().process_frame` зависнут).
- Тесты `_toggle_pause` — вернуть панель в скрытое.

## Integration тесты сцен

Через `add_child_autofree(scene.instantiate())` + `await get_tree().process_frame`. Reference — `test/unit/test_pause.gd`.

```gdscript
var hud = HudScene.instantiate()
add_child_autofree(hud)
await get_tree().process_frame  # даём _ready сработать
```

Не забывай про `await get_tree().process_frame` перед проверками — `_ready` дочерних узлов срабатывает не мгновенно.

## Сигналы врагов

`died_at` эмиттится **до** `queue_free()`. Если тест проверяет `died_at` — assert **до** конца кадра, иначе node уже freed. Reference — `enemy.gd::take_damage`.

## Что делать когда покрыть трудно

Не «отложить», а найти способ:
- Random → передать seed через `RandomNumberGenerator` и мокнуть.
- Physics contact → использовать fallback path (без Floor/AStarGrid у enemy идёт прямой `move_and_slide`).
- Autoload → snapshot/restore + прямое присваивание полей.
- Signal + await → `signal_watcher` из GUT.

## Прогон

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit
```

Или skill `/run-tests`.

Из редактора: `Project → Tools → GUT` → `Run All`.

**Красный тест = не коммитить.** Fix → повторный прогон до `All tests passed`. Новую фичу не покрыть существующими тестами — добавь тест в том же коммите, не откладывай.
