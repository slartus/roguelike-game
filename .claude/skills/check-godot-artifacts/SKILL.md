---
name: check-godot-artifacts
description: Проверяет что важные Godot-артефакты (.translation, .import, .uid) не заблокированы .gitignore и присутствуют в staged/tracked файлах. Использовать при подозрении что после clone игра запускается с сырыми i18n-ключами или broken preload'ами; после правки .gitignore; при добавлении нового .png/.tres.
---

# Skill: check-godot-artifacts

Проверка что критичные для запуска игры файлы **не** попадают под `.gitignore`.

## Что проверять

### 1. Translations

`.translation` файлы должны быть tracked:

```bash
git ls-files resources/translations/*.translation
```

Ожидание: список из всех `.translation`. Пустой ответ = проблема.

Проверка что не игнорятся:

```bash
git check-ignore -v resources/translations/*.translation
```

Ожидание: пустой ответ (значит не игнорится). Любой матч в `.gitignore` = красный флаг.

### 2. Import metadata

Для каждой `.png` рядом должен быть `.png.import`. Для каждой `.tres` — `.tres.import` (если Godot импортирует ресурс).

```bash
find assets -name "*.png" | while read f; do
  test -f "$f.import" || echo "MISSING: $f.import"
done
```

Ожидание: пусто. Любой `MISSING` — Godot либо не открывал редактор после добавления PNG, либо `.import` в `.gitignore`.

### 3. UID файлы

Для каждого `.gd` рядом должен быть `.gd.uid` (Godot 4.4+). Аналогично для `.tscn` / `.tres`.

```bash
find scenes autoloads resources -name "*.gd" | while read f; do
  test -f "$f.uid" || echo "MISSING: $f.uid"
done
```

Ожидание: пусто. Любой `MISSING` — Godot регенерирует `uid://` при первом открытии, ломая `preload("uid://…")` в других сценах.

### 4. Что должно быть в .gitignore

Проверка что кэш игнорится:

```bash
git check-ignore -v .godot/imported/dummy .godot/uid_cache.bin dist/dummy
```

Ожидание: все три матчатся. Если не игнорится — раздувает репо.

## Что делать при находках

- `MISSING: *.import` → открыть Godot editor, дать ему импортировать, закоммитить `.import` файлы.
- `MISSING: *.uid` → то же самое; или руками добавить `uid://<random>` через IDE.
- `.translation` игнорится → удалить строку из `.gitignore`, `git add resources/translations/*.translation`.
- `.godot/imported/**` tracked → `git rm -r --cached .godot/imported/` + добавить в `.gitignore`.

## Полный прогон

```bash
echo "=== translations ===" && \
git ls-files resources/translations/*.translation && \
echo "=== .import missing ===" && \
find assets resources -name "*.png" -o -name "*.tres" | while read f; do \
  test -f "$f.import" || echo "MISSING: $f.import"; \
done && \
echo "=== .uid missing ===" && \
find scenes autoloads resources -name "*.gd" -o -name "*.tres" -o -name "*.tscn" | while read f; do \
  test -f "$f.uid" || echo "MISSING: $f.uid"; \
done
```
