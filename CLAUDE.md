# Roguelike — правила проекта

Модульные инструкции. Здесь только главные инварианты и указатели. Детали — в `.claude/rules/`, `.claude/skills/`, `.claude/agents/`.

## ⚠️ ГЛАВНОЕ ПРАВИЛО (не нарушать никогда)

**Каждое сообщение пользователя = отдельная фича = отдельный коммит и push.**

6 обязательных шагов перед считать фичу сданной:

1. **Docs** — обновить `docs/gamedesign/*.md` если задета game-design сущность.
2. **Tests** — написать/обновить тесты покрывающие изменение.
3. **Run tests** — прогнать всю GUT-сюиту. Красный тест = не коммитить.
4. **Self-review** — прогнать `godot-code-reviewer` через Task tool.
5. **Commit** — отдельный, не смешанный с другими фичами.
6. **Push** — `git push`. Без push фича не сдана.

Полный цикл: skill `/feature-close`.

**Исключение из «одна фича = один коммит»** — только явные слова пользователя: «доработай текущую», «в тот же коммит», «amend». Иначе — новая фича.

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
| `00-workflow.md` | Всегда — 6 шагов feature workflow'а, правило push'а |
| `10-tests.md` | Пишешь/меняешь `.gd` / `.tscn` / `.tres` — что и как покрывать в GUT |
| `20-gamedesign-docs.md` | Задета геймплейная сущность — какой doc-файл обновлять |
| `30-godot-artifacts.md` | Работа с `.tres` / `.import` / `.uid` / `.translation` / `.gitignore` |
| `40-i18n-and-exports.md` | Добавляешь `@export display_name` или новый i18n-ключ |
| `50-animations-gifs.md` | Меняешь `_draw` / tween-формулу процедурной анимации |
| `90-anti-patterns.md` | Быстрый список запретов — сверяйся перед commit'ом |

## Skills (`.claude/skills/`)

Запускаемые процедуры — используй по назначению:

| Skill | Когда |
|-------|-------|
| `/run-tests` | Прогнать GUT-сюиту и получить red/green summary |
| `/feature-close` | Полный pre-commit pipeline (docs → tests → review → commit → push) |
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

## Push разрешён по умолчанию

`git push` — часть штатного workflow'а, не запрашиваю подтверждение. Разрешение в `.claude/settings.local.json`.

Останавливаюсь и уточняю только:
1. `git push --force` в `main` — деструктивно.
2. Push отклонён remote'ом — разбираться, не force «на автомате».
