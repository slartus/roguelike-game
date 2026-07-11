# Антипаттерны — быстрый список

Не делай без очень явной причины.

## Workflow

- Работать в основном клоне репозитория (`/Users/artemslinkin/projects/roguelike-game`) вместо отдельной worktree-папки для фичи. `HEAD` общего каталога «прыгает» между параллельными Claude-сессиями, файлы и staging разбегаются. См. `00-workflow.md` → «Изоляция фичи».
- `git checkout <существующая_ветка>` / `git switch <branch>` в общем каталоге. Ломает HEAD параллельных сессий. Только `git worktree add ... -b <new_branch> origin/main`.
- Начинать фичу с `git checkout main; git pull; git checkout -b <branch>` — двойной switch в общем каталоге, ломает параллельные сессии. Правильно: `git worktree add ../roguelike-<slug> -b <type>/<slug> origin/main --no-track`.
- Заводить новую ветку/папку на **каждое** сообщение пользователя. Одна фича может продолжаться несколькими сообщениями — работаем в уже созданной ветке/папке. Новую заводим только когда пользователь явно переключает контекст или задача явно не связана с текущей.
- Смешивать в одном коммите правки разных фич (та, что просят сейчас, + WIP из working tree). Стажим только файлы текущей фичи по явному списку путей, а не `git add .`.
- Пропускать `git push` — фича не сдана до пуша.
- `git push --force` в `main` без явного согласия пользователя.
- Коммитить с красными тестами. Красный тест = стоп.
- Пропускать self-review агентом — минимум один проход обязателен.
- Не удалять worktree-папку и локальную ветку после merge PR (шаг 8 workflow). Мёртвые `../roguelike-*` папки копятся и путают следующие сессии. После merge — `git worktree remove ../roguelike-<slug>` + `git branch -d <type>/<slug>`.

## GDScript

- `@export var display_name: String = "Босс"` — raw-строка вместо i18n-ключа `"ENEMY_UNKNOWN"`. См. `40-i18n-and-exports.md`.
- Эмит `died_at` **после** `queue_free()` — слушатели увидят freed node. Всегда эмит **до** `queue_free`.
- `randf()` без seed'а в тестируемом коде без возможности инжектнуть `RandomNumberGenerator` — тест не сможет детерминизировать.
- Прямая мутация `GameState.player_health = X` из сцен вместо вызова `GameState.take_damage(...)` / `GameState.heal(...)` — обходит сигналы, HUD не обновится.
- `preload("res://...")` устаревшего пути после переименования — используй `uid://` через IDE.
- Игнорировать `Balance.scaled_hp / scaled_damage / scaled_xp_reward / scaled_gold_reward` в новом враге — статы не будут скейлиться по этажам.

## Godot / .tscn / .tres

- Не коммитить `.gd.uid` рядом с `.gd` — Godot перегенерирует id, `preload("uid://…")` в других сценах сломается.
- Коммитить `.godot/imported/**` — это кэш, регенерируется. Только раздувает репо.
- НЕ коммитить `resources/translations/*.translation` — без них при свежем clone `tr()` вернёт сырые ключи.
- `@export`-поле без дефолта того же типа что и `@export_range` / target — Godot покажет warning в редакторе.

## Тесты

- Пропускать `before_each` / `after_each` snapshot autoload'ов — соседние тесты унаследуют dirty state.
- `Thread.sleep` / фиксированные задержки — не детерминизирует, флаки.
- Забыть `await get_tree().process_frame` после `add_child_autofree(scene.instantiate())` — `_ready` дочерних узлов не успевает.
- Оставлять `get_tree().paused = true` после теста паузы — следующие тесты с `await` зависнут.
- Assert только «сцена открылась» без проверки бизнес-полей — псевдо-покрытие.

## Docs

- Изменить число (`@export damage = 5` → `= 7`) без обновления таблицы в `docs/gamedesign/*.md`.
- Изменить `_draw` / tween-формулу без обновления `tools/gen_animation_gifs.py` и перегенерации gif'а.
- Изменить `assets/sprites/player/player.png`, любой `assets/sprites/weapons/*.png` или константы hand-offset / rest-angle в `player.gd` без перегенерации `docs/gamedesign/media/player_with_*.png` через `tools/gen_player_weapon_showcase.py`. Добавить новое оружие без соответствующего `player_with_<id>.png` и строки в таблице `weapons.md`. См. `60-player-weapon-showcase.md`.
- Писать «планы» в основной раздел docs — только в отдельный «Планируемое» с явной пометкой.
- Переписывать код в docs — описывай **что**, не **как**.

## Комментарии

- Комментарий, описывающий *что* делает код (легко читается по коду). Комментарии оправданы только для *почему* — почему такой выбор, какой edge case, какой инцидент.
