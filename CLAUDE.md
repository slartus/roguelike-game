# Roguelike — правила проекта

Модульные инструкции. Здесь только главные инварианты и указатели. Детали — в `.claude/rules/`, `.claude/skills/`, `.claude/agents/`.

## ⚠️ ГЛАВНОЕ ПРАВИЛО (не нарушать никогда)

**Одна фича = отдельная ветка + отдельная worktree-папка + отдельный PR в `main`.** В `main` напрямую не коммитим, в основном клоне репозитория не работаем.

Что считать «одной фичей» — определяется по смыслу задачи, а не по количеству сообщений. Несколько сообщений подряд могут доводить одну и ту же фичу до готовности — тогда работаем в уже созданной ветке/папке, новую не заводим. Новая ветка/папка нужна, когда пользователь явно переключает контекст («новая задача», «отдельно сделай X», «начнём другую фичу») либо когда я вижу, что задача не связана с текущей — тогда уточняю у пользователя, продолжать в текущей ветке или заводить новую.

8 обязательных шагов перед считать фичу сданной:

1. **Branch + worktree** — новая ветка `<type>/<slug>` от актуального `origin/main` в отдельной папке `../roguelike-<slug>` через `git worktree add`. Никакой работы в основном клоне.
2. **Docs** — обновить `docs/gamedesign/*.md` если задета game-design сущность.
3. **Tests** — написать/обновить тесты покрывающие изменение.
4. **Run tests** — прогнать всю GUT-сюиту. Красный тест = не коммитить.
5. **Self-review** — прогнать `godot-code-reviewer` через Task tool.
6. **Commit + push ветки** — отдельный коммит, `git push -u origin <branch>` первый раз.
7. **PR в main** — `gh pr create --base main`. Без PR фича не сдана.
8. **Cleanup после merge** — после merge PR обязательно `git worktree remove ../roguelike-<slug>` + `git branch -d <type>/<slug>`. Мёртвые папки копятся и путают следующие сессии.

Полный цикл: skill `/feature-close`.

**Никогда не делаем `git checkout <существующая_ветка>` в общем каталоге.** Каждая параллельная Claude-сессия должна жить в своей worktree-папке — иначе `HEAD` «прыгает» под другими сессиями и файлы разбегаются. Детали и bootstrap-команда — в `.claude/rules/00-workflow.md`.

## Быстрый прогон тестов

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit
```

Или через skill `/run-tests`.

## Правила (`.claude/rules/`)

Читай релевантные при каждой правке:

| Файл | Когда читать |
|------|-------------|
| `00-workflow.md` | Всегда — 8 шагов feature workflow'а, worktree-изоляция, правило push'а, cleanup после merge |
| `10-tests.md` | Пишешь/меняешь `.gd` / `.tscn` / `.tres` — что и как покрывать в GUT |
| `20-gamedesign-docs.md` | Задета геймплейная сущность — какой doc-файл обновлять |
| `30-godot-artifacts.md` | Работа с `.tres` / `.import` / `.uid` / `.translation` / `.gitignore` |
| `40-i18n-and-exports.md` | Добавляешь `@export display_name` или новый i18n-ключ |
| `50-animations-gifs.md` | Меняешь `_draw` / tween-формулу процедурной анимации |
| `60-player-weapon-showcase.md` | Меняешь спрайт игрока / оружия, hand-offset / rest-angle, добавляешь новое оружие |
| `90-anti-patterns.md` | Быстрый список запретов — сверяйся перед commit'ом |

## Skills (`.claude/skills/`)

Запускаемые процедуры — используй по назначению:

| Skill | Когда |
|-------|-------|
| `/run-tests` | Прогнать GUT-сюиту и получить red/green summary |
| `/feature-close` | Полный pipeline фичи: branch+worktree → docs → tests → run tests → self-review → commit → push → PR → cleanup после merge |
| `/regen-gifs` | Регенерировать gif-и после правки процедурной анимации |
| `/check-godot-artifacts` | Проверить `.translation` / `.import` / `.uid` не заблокированы `.gitignore` |

## Agents (`.claude/agents/`)

Проектные субагенты, запускаются через Task tool. Знают специфику Godot и этого репозитория:

| Agent | Когда | Модель |
|-------|-------|--------|
| `godot-code-reviewer` | После **каждого** блока изменений перед commit'ом. Минимум 1 проход. `BLOCKER/CRITICAL` → фикс → новый проход | opus |
| `gut-test-writer` | Фича не покрыта тестом, нужно написать новый | sonnet |
| `gamedesign-doc-updater` | Задета геймплейная сущность, docs расходятся с кодом | sonnet |

## Executing (маппинг файлов → агенты)

| Scope | Агент |
|-------|-------|
| `**/*.gd`, `**/*.tscn`, `**/*.tres` | `godot-code-reviewer` (self-review) |
| `test/unit/**/*.gd` | `gut-test-writer` (написание тестов) |
| `docs/gamedesign/**` | `gamedesign-doc-updater` (синхронизация docs с кодом) |

## Push и PR — часть штатного workflow'а

`git push` на фиче-ветку и `gh pr create --base main` не требуют подтверждения. Разрешения — в `.claude/settings.local.json`.

Останавливаюсь и уточняю только:
1. `git push --force` / `--force-with-lease` в `main` — деструктивно, нельзя.
2. `git push` в `main` напрямую (минуя PR) — нарушает главное правило, нельзя.
3. Push отклонён remote'ом (protected / конфликт на фиче-ветке) — разбираться, не force «на автомате».
4. `gh pr merge` — по умолчанию **не мержу PR сам**, это делает пользователь. Мержу только по явной просьбе.
