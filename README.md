# Roguelike

2D top-down pixel-art roguelike-RPG. Godot 4 + GDScript.

## Требования

- **Godot 4.4+** (Standard build, не .NET) — https://godotengine.org/download
- macOS / Windows / Linux для разработки.

## Как открыть

1. Установить Godot 4: `brew install --cask godot` (macOS) или скачать с сайта.
2. Запустить Godot → Import → выбрать `project.godot` в этой папке.
3. Editor откроется. Слева в FileSystem — структура проекта.

## Структура

```
assets/          Art, звук, шрифты
  sprites/
  audio/
  fonts/
scenes/          .tscn — Godot-сцены
  player/
  enemies/
  rooms/
  ui/
scripts/         Отдельно лежащие .gd (обычно скрипты живут в сценах)
autoloads/       Синглтоны (GameState, SaveSystem)
addons/          Плагины редактора
```

## Настройки проекта (уже выставлены)

- Pixel-perfect рендер: `Nearest` filter, snap 2D transforms/vertices to pixel.
- Base viewport 480×270, окно 1280×720 (масштаб ×4 без блюра).
- Renderer: `gl_compatibility` — работает на всех платформах включая старые мобильные.
- Input actions: `move_up/down/left/right` (WASD + стрелки), `attack` (ЛКМ).

## Целевые платформы

Windows / macOS / Linux / Android / iOS. Web не поддерживается.

## Сборка Windows-билда

Из корня проекта:

```bash
./tools/build_windows.sh
```

Результат — единственный файл `dist/Roguelike.exe` (~106 MB, x86_64 PE32+ GUI). В preset включён `binary_format/embed_pck=true`, поэтому pack встроен в exe, отдельный `.pck` не нужен. Отдаёшь один файл — и он запускается.

Требования:
- Godot 4.7 в `/Applications/Godot.app` (переопределяется через `GODOT_BIN=...`).
- Установленные Windows export templates для Godot 4.7 (Editor → Manage Export Templates → Download).
- Секция `[preset.1]` в `export_presets.cfg` с именем `"Windows Desktop"`. Файл в `.gitignore`; при первом клоне добавьте preset через Project → Export → Add → Windows Desktop.

## План

См. `/Users/artemslinkin/.claude/plans/eventual-purring-dragon.md`.
