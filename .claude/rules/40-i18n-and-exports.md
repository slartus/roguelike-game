# i18n и @export defaults

## Правило

Если поле `@export` используется как i18n-ключ (например `display_name` у врагов, оружия) — **fallback default обязан быть валидным ключом из CSV в UPPER_SNAKE_CASE**, а не raw-строкой на русском/английском.

Причина: `tr("Boss")` при отсутствии перевода в CSV вернёт саму строку `"Boss"` — и в UI появится незапереведённая заглушка. `tr("ENEMY_BOSS")` при отсутствии перевода вернёт `"ENEMY_BOSS"` — сразу видно, что ключ не переведён, а не «Boss» замаскировался под настоящий текст.

## Правильно

```gdscript
# enemy.gd
@export var display_name: String = "ENEMY_UNKNOWN"

# weapon_resource.gd
@export var display_name: String = "WEAPON_UNKNOWN"
```

В каждой `.tscn` / `.tres` — переопределение под конкретную сущность:

```
# dagger.tres
display_name = "WEAPON_DAGGER"
```

## Неправильно

```gdscript
@export var display_name: String = "Босс"     # → tr() вернёт "Босс", i18n сломан
@export var display_name: String = "Monster"  # то же самое
@export var display_name: String = ""         # пустая строка — теряется guard, UI покажет пусто
```

## Чек reviewer'а

- Все `@export var display_name: String` имеют default вида `UPPER_SNAKE_CASE`.
- Каждая `.tscn`/`.tres` переопределяет `display_name` на конкретный ключ (`ENEMY_GOBLIN`, `WEAPON_PISTOL`).
- Новый ключ добавлен в `resources/translations/strings.csv` во всех колонках (ru, en).
- После правки `.csv` — регенерированы `.translation` файлы (Godot делает это при импорте, но при headless-запуске может отставать; см. `docs/gamedesign/i18n.md`).

## Другие поля с тем же паттерном

Любое `@export`-поле, чьё значение попадает в UI через `tr()` — подчиняется тому же правилу. Не только `display_name`, но и `description`, `tooltip`, `hint_key` и т.п.

Если поле — **не** i18n-ключ (например `texture_path: String = "res://..."` или числовое поле как строка) — правило не применяется.
