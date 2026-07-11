---
name: feature-close
description: Полный pipeline для одной фичи — branch+worktree → docs → tests → run tests → self-review → commit → push → PR → cleanup после merge. Использовать когда фича готова и пользователь хочет её закрыть, либо когда сам достиг состояния "готово, пора закрывать".
---

# Skill: feature-close

Полный цикл закрытия фичи по правилам `.claude/rules/00-workflow.md`.

## Preconditions

- Есть локальные изменения (`git status` не пустой) внутри worktree-папки фичи.
- Пользователь **не** сказал «доработай текущую» / «amend» / «в текущий PR» — иначе это правка к предыдущему коммиту в уже открытой ветке, а не новая фича.

## Порядок шагов

### 1. Branch + worktree

Проверить текущий каталог и ветку: `pwd && git branch --show-current`.

- Уже внутри worktree-папки фичи (`../roguelike-<slug>`) на фиче-ветке (`feat/*`, `fix/*`, ...) → пропускаем создание, работаем здесь.
- Оказался в основном клоне (`/Users/artemslinkin/projects/roguelike-game`) на `main` или чужой ветке → **не** делаем `git checkout` в этом каталоге (сломает параллельные сессии). Создаём отдельную папку через worktree:

```bash
MAIN_REPO=/Users/artemslinkin/projects/roguelike-game
git -C $MAIN_REPO fetch origin
git -C $MAIN_REPO worktree add ../roguelike-<slug> -b <type>/<slug> origin/main --no-track
cd ../roguelike-<slug>
git branch --unset-upstream
```

где `type ∈ {feat, fix, refactor, docs, chore, test}`, `slug` — короткое английское описание фичи в kebab-case (`melee-arc-swing`, `hud-gold-key`, `weapon-controller-cooldown`).

Если изменения фичи уже есть в working tree основного клона (не должно случаться при штатном flow, но возможно) — перед созданием worktree сделать `git stash push -u -m "wip: <slug>"` в основном клоне, потом в новой worktree-папке применить их обратно через `git stash apply --index stash@{0}`.

**Никогда не коммитим в `main` напрямую и не работаем в основном клоне.**

### 2. Docs

Проверить: тронуты ли `.gd`/`.tscn`/`.tres` из таблицы в `.claude/rules/20-gamedesign-docs.md`?

- Да → открыть соответствующий `docs/gamedesign/*.md`, обновить таблицы чисел / раздел «Поведение» под текущий код. Проверить, что `@export` / `const` совпадают с таблицами.
- Нет → пропустить.

Если процедурная анимация задета (`_draw` / tween / `AnimatedSprite2D`) — прогнать `/regen-gifs` перед commit'ом.

### 3. Tests

Проверить: покрыта ли новая/изменённая логика тестом?

- Нет → написать тест по правилам `.claude/rules/10-tests.md`. Snapshot autoload state, `add_child_autofree` для сцен, `await get_tree().process_frame` перед assert'ами.
- Уже покрыта → пропустить.

### 4. Run tests

Прогнать skill `/run-tests`. **Красный тест = стоп.** Фиксить → повторный прогон.

### 5. Self-review

Запустить агента `godot-code-reviewer` через Task tool.

Передать в prompt:
- цель блока изменений (что и зачем);
- список изменённых файлов из `git status --short`;
- краткий контекст правки (какая механика / сущность).

Обработка вердикта:
- `BLOCKER` / `CRITICAL` → фикс → **новый проход агента** → тесты снова.
- `MAJOR` / `MINOR` → оценить: в scope — фиксить; вне scope — зафиксировать в PR description как follow-up.
- `READY-TO-COMMIT` → переходим к 6.

Минимум **один** проход. Если агент нашёл что-то — обязателен второй проход после фикса.

### 6. Commit + push ветки

```bash
git add <specific files>  # не git add -A без нужды
git commit -m "$(cat <<'EOF'
<type>(<scope>): <краткое описание фичи>

<опциональный body с "почему">
EOF
)"
```

Типы: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`. Скоуп — модуль (`enemy`, `boss`, `hud`, `dungeon`, `progression`, `weapons`, `pickups`).

Один коммит на фичу. Не смешивать с другими правками.

Push ветки. Первый push — с `-u`, чтобы upstream был на одноимённую remote-ветку:

```bash
git push -u origin <branch>
```

Последующие пушы в эту же ветку — просто `git push`.

Проверить ответ — `To ... <branch> -> <branch>`. Push отклонён → **стоп**, разбираться.

### 7. PR в main

```bash
gh pr create --base main --head <branch> \
  --title "<type>(<scope>): <краткое описание>" \
  --body "$(cat <<'EOF'
## Что

<1–3 предложения по существу>

## Зачем

<опционально: мотивация / контекст>

## Как проверять

- [ ] `/run-tests` — GUT-сюита зелёная
- [ ] визуальный smoke-test если задета механика игрока

<если reviewer нашёл follow-up'ы — перечислить их здесь>
EOF
)"
```

Проверить ответ `gh pr create` — должна быть URL `https://github.com/<owner>/<repo>/pull/<n>`. Без URL — фича не сдана.

**Merge PR не делаю сам** — это делает пользователь через GitHub UI после ревью. Исключение: пользователь явно попросил «смерджи» / «замерджи PR». Тогда — `gh pr merge <number> --squash --delete-branch` (или `--merge`, если пользователь предпочитает merge-commit).

### 8. Cleanup после merge PR

**Обязательный шаг, не опциональный.** Как только PR смержен (через GitHub UI или `gh pr merge` по явной просьбе), удалить worktree-папку и локальную ветку:

```bash
cd $MAIN_REPO
git fetch --prune origin                    # подтягиваем удаление remote ветки
git worktree remove ../roguelike-<slug>
git branch -d <type>/<slug>
```

Проверить: `git worktree list` показывает только `$MAIN_REPO`, `git branch --list '<type>/<slug>'` пустой.

Если пользователь мержит PR молча (или сам смержил в UI до того, как я успел спросить) — при следующей активности проверить `gh pr list --state merged --limit 5`, найти свои смерженные PR'ы и почистить их worktree'ы. Оставленные worktree'ы копятся в `../roguelike-*` и путают следующие сессии.

## Отчёт пользователю

После создания PR — одна-две строки:
- Что сделано (одна строка).
- Ссылка на PR из вывода `gh pr create`.
- В какой worktree-папке идёт работа (`../roguelike-<slug>`) — чтобы пользователь понимал, где живёт ветка.
- Если были follow-up'ы от reviewer'а — перечислить их.

## Что делать если пользователь оставил вопрос по ходу

Сначала оценить: это продолжение текущей фичи (доработка, уточнение) или новая независимая задача?

- Продолжение → работаем в той же ветке / той же worktree-папке. Новую ветку/папку не заводим.
- Новая независимая задача → добавить в очередь через `TaskCreate`, довести текущую до PR, после merge (или как только пользователь дал зелёный свет на переключение) завести новую worktree-папку от свежего `origin/main`:

```bash
MAIN_REPO=/Users/artemslinkin/projects/roguelike-game
git -C $MAIN_REPO fetch origin
git -C $MAIN_REPO worktree add ../roguelike-<next-slug> -b <type>/<next-slug> origin/main --no-track
cd ../roguelike-<next-slug>
```

Если не уверен, продолжение это или новая — уточни у пользователя перед созданием новой ветки/папки.
