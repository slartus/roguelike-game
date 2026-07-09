#!/usr/bin/env bash
# Собирает Windows x86_64 release-билд игры в dist/Roguelike.exe.
#
# Требования:
# - Godot 4.7 (macOS/Linux — headless mode).
# - Windows export templates 4.7.stable установлены в стандартную папку
#   (macOS: ~/Library/Application\ Support/Godot/export_templates/4.7.stable/).
#   Проверка: `ls "$HOME/Library/Application Support/Godot/export_templates/4.7.stable/windows_release_x86_64.exe"`.
# - Секция `[preset.1]` в export_presets.cfg с именем "Windows Desktop".
#   Файл в .gitignore — поэтому если preset'а нет (свежий clone), добавьте
#   его через Project → Export → Add → Windows Desktop либо руками
#   продублируйте блок из существующего репо.
#
# Артефакт:
# - dist/Roguelike.exe (~106 MB, PE32+ x86_64 GUI).
#
# В preset выставлено `binary_format/embed_pck=true`, поэтому pack встроен
# в сам exe. Отдельный .pck файл не создаётся, распространяется один exe.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"

if [ ! -x "$GODOT_BIN" ]; then
    echo "Godot не найден: $GODOT_BIN" >&2
    echo "Задайте GODOT_BIN или установите Godot 4.7 в /Applications." >&2
    exit 1
fi

mkdir -p "$PROJECT_ROOT/dist"

"$GODOT_BIN" --headless \
    --path "$PROJECT_ROOT" \
    --export-release "Windows Desktop" \
    dist/Roguelike.exe

echo
echo "Билд готов: $PROJECT_ROOT/dist/Roguelike.exe"
ls -lh "$PROJECT_ROOT/dist/Roguelike.exe" "$PROJECT_ROOT/dist/Roguelike.pck" 2>/dev/null || true
