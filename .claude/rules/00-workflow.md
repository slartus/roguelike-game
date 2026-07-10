# Workflow фичи

Одно сообщение пользователя = одна фича = отдельная ветка = отдельный PR в `main`.

## 7 обязательных шагов перед считать фичу сданной

1. **Branch** — создать новую ветку от `main` под фичу. Не коммитить в `main` напрямую (см. раздел «Ветка и PR» ниже).
2. **Docs** — обновить `docs/gamedesign/*.md` если задета game-design сущность (см. `20-gamedesign-docs.md`).
3. **Tests** — написать/обновить тесты покрывающие изменённое поведение (см. `10-tests.md`).
4. **Run tests** — прогнать всю GUT-сюиту через CLI. Красный тест = не коммитить.
5. **Self-review** — прогнать `godot-code-reviewer` через Task tool (см. `.claude/agents/godot-code-reviewer.md`). `BLOCKER/CRITICAL` → фикс → новый проход → тесты снова.
6. **Commit + push ветки** — отдельный коммит на фичу, не смешанный с другими. Push ветку в `origin` (`git push -u origin <branch>` первый раз).
7. **PR в main** — открыть PR через `gh pr create --base main`. Без PR фича не сдана.

Быстрый запуск всего цикла: skill `/feature-close`.

## Правило одного сообщения

Каждый пользовательский запрос — **новая фича**, даже если тематически похожа на предыдущую. Отдельная ветка, отдельный коммит, отдельный PR.

**Исключение — только явные слова пользователя:** «это правка к текущей», «доработай текущую», «в тот же коммит», «в текущую фичу», «amend». Иначе — новая фича.

Если во время выполнения одной фичи пришло новое сообщение — не бросай текущую, добавь в очередь через `TaskCreate`, доведи текущую до PR, потом бери новую (со свежей веткой от актуального `main`).

Если один запрос физически требует несколько зависящих коммитов (миграция → refactor → cleanup) — каждый под-коммит проходит все 7 шагов и уезжает своим PR (stacked PR: base предыдущего PR, а не `main`, если они действительно цепляются).

## Ветка и PR

### Имя ветки

Формат: `<type>/<slug>`, где `type ∈ {feat, fix, refactor, docs, chore, test}`, `slug` — kebab-case, короткое английское описание фичи.

Примеры: `feat/melee-arc-swing`, `fix/hud-gold-key`, `refactor/weapon-controller-cooldown`, `docs/upgrades-overview`.

Ветку создаём **от актуального `main`**:

```bash
git fetch origin
git checkout main
git pull --ff-only
git checkout -b feat/<slug>
```

### Push ветки

Первый push — с `-u`, чтобы upstream был на одноимённую remote-ветку, а не на `main`:

```bash
git push -u origin feat/<slug>
```

Последующие пушы в эту же ветку — просто `git push`.

**Никогда не пушить в `main` напрямую.** Если случайно оказался на `main` с коммитом — переносим коммит на новую ветку (`git branch feat/<slug> && git reset --hard origin/main && git checkout feat/<slug>`), потом стандартный push веткой.

### PR через gh

```bash
gh pr create --base main --head feat/<slug> \
  --title "<type>(<scope>): <краткое описание>" \
  --body "$(cat <<'EOF'
## Что

<1–3 предложения по существу>

## Зачем

<опционально: мотивация / контекст>

## Как проверять

- [ ] `/run-tests` — GUT-сюита зелёная
- [ ] визуальный smoke-test если задета механика игрока
EOF
)"
```

После `gh pr create` — вернуть URL PR'а пользователю.

### Что делать если PR не проходит CI / ревью

- CI красный — фиксить в той же ветке, коммитить, `git push`. PR обновится автоматически.
- Reviewer запросил правки — те же правки в ту же ветку. Не открывай новый PR.
- Ветка разошлась с `main` (конфликт merge) — `git fetch origin && git rebase origin/main`, решить конфликты, `git push --force-with-lease` (только на свою фиче-ветку, никогда на `main`).

### Merge

По умолчанию **не мержим PR из-под агента** — это делает пользователь через GitHub UI после ревью. Исключение: пользователь явно попросил «смерджи» / «замерджи PR». Тогда — `gh pr merge <number> --squash --delete-branch` (или `--merge` если пользователь предпочитает).

После merge — вернуться на `main`, `git pull --ff-only`, удалить локальную ветку (`git branch -d feat/<slug>`).

## Освобождения

Только `docs/*.md` / `CLAUDE.md` / `.claude/**` изменены и `.gd`/`.tscn`/`.tres` не тронуты → шаги 3 и 4 (tests, run tests) можно пропустить. Шаги 1, 2, 5, 6, 7 остаются — даже docs-only фичи едут через ветку и PR.

## Команда прогона тестов

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit
```

Или через skill `/run-tests`.

Если тесты падают не из-за твоих правок (инфра, сторонний баг GUT) — явно пишешь это в PR description, не маскируешь.

## Push и safety

`git push` на фиче-ветку — часть штатного workflow'а, разрешён по умолчанию (`.claude/settings.local.json`).

Останавливаюсь и уточняю только:
1. `git push --force` / `--force-with-lease` в `main` — деструктивно, нельзя.
2. `git push` в `main` напрямую (минуя PR) — нарушает главное правило, нельзя.
3. Push отклонён remote'ом (protected / конфликт на фиче-ветке) — разбираться, не делать force «на автомате».

Проверяю ответ push'а — `To ... <branch> -> <branch>` или `Everything up-to-date`. Пока не увидел успех — PR не открывается.

Проверяю ответ `gh pr create` — должна быть URL вида `https://github.com/<owner>/<repo>/pull/<n>`. Пока не увидел — фича не сдана.
