# Analytics Reports — локальный pipeline и balance workflow

Инструкция для инженера/балансиста, который анализирует данные
из `Analytics` autoload'а. Реализация — `tools/analytics/`,
её README покрывает CLI-команды и формат таблиц.

Этот документ описывает **что делать с числами** — процесс, границы
интерпретации и типичный workflow балансировки.

## 1. Быстрый чек-лист «есть данные — построил отчёт»

```bash
# 1. Соберём CSV-датасет + issues + data_quality.
python3 -m tools.analytics.build_dataset \
  --input ~/Library/Application\ Support/Godot/app_userdata/roguelike-game/analytics \
  --output analytics_output

# 2. Отдельно проверим наличие ошибок валидации (exit code 1 при errors).
python3 -m tools.analytics.validate_events \
  --input ~/Library/Application\ Support/Godot/app_userdata/roguelike-game/analytics \
  --output analytics_output/issues.json

# 3. HTML-отчёт.
python3 -m tools.analytics.generate_report \
  --input ~/Library/Application\ Support/Godot/app_userdata/roguelike-game/analytics \
  --output analytics_output/report.html
open analytics_output/report.html
```

## 2. Content balance hash

Значимые balance-ресурсы (`resources/weapons/*.tres`,
`resources/upgrades/*.tres`, любые `resources/enemies/**/*.tres`,
`autoloads/balance.gd`) хешируются в один SHA256:

```bash
python3 -m tools.analytics.hash_content
```

- Одинаковый hash → набор balance-ресурсов совпадает; данные разных
  версий сравнимы.
- Разный hash → баланс менялся; смешивать периоды в отчёте нельзя без
  явного фильтра (или без осознания риска).

Hash игнорирует текстуры, docs, translation, timestamp'ы файлов —
меняются только те правки, что реально влияют на числа.

## 3. Interpretation caveats (жёсткие правила)

Отчёт печатает эти пункты явно, но повторим их и здесь:

1. **Correlation is not causation.** Если игроки, взявшие «Swift Edge»,
   проходят дальше — это может быть selection bias опытных игроков, а не
   эффективность карты.
2. **Rare weapons/upgrades нельзя оценивать raw floor reached.** Если
   карта появляется только на high-floor offer'ах — её pick-rate искажён
   контекстом.
3. **Position offer влияет на выбор.** Player picks position 0 чаще —
   всегда сначала сверяйся с `upgrades → positions` таблицей.
4. **Strong players создают selection bias.** Хорошие игроки берут
   определённые карты, доходят дальше по всем метрикам — не по вине
   карты.
5. **Маленький N (<30) — только тенденции.** N < 10 — вообще
   anecdotal, не строим выводов. Отчёт помечает это явно.
6. **Не смешивай balance_version.** Всегда фильтруй по
   `balance_version` или сравнивай `compare_versions.py`.
7. **Content-balance-hash mismatch = разные ресурсы.** Если добавились
   новые враги/оружия — старые прогоны не сравнимы с новыми.

## 4. Balance workflow

Строгий процесс при изменении баланса:

1. **Сформулируй гипотезу.** Пример: «Aggressive Spider наносит
   слишком много unavoidable damage».
2. **Зафиксируй baseline balance_version.** Не меняй код баланса, пока
   не собран baseline sample.
3. **Собери минимум выборки.** Ориентир: 30–50 runs baseline, столько
   же candidate — иначе N слишком мал для выводов.
4. **Проверь data quality.** Errors в валидации ⇒ не двигайся дальше,
   пока не поймёшь причину.
5. **Проверь связанные метрики.** Для Spider'а: charge attempts, hit
   rate, damage_per_spawn, deaths, room role, floor, weapon.
6. **Внеси ОДНО ограниченное изменение.** Не меняй два параметра
   одновременно — нельзя отличить их эффекты.
7. **Повысь `Balance.BALANCE_VERSION`** в `autoloads/balance.gd`.
   Иначе новые данные попадут в baseline bucket и всё испортят.
8. **По возможности сохраняй одинаковые seeds** между baseline и
   candidate прогонами — уменьшает variance.
9. **Сравни candidate с baseline** через
   `python3 -m tools.analytics.compare_versions`.
10. **Проведи ручной playtest** — числа + вкус.
11. **Приними / отклони изменение.** Reject == roll back `.tres` и
    вернуть `BALANCE_VERSION`.
12. **Зафиксируй решение** в commit message / PR description /
    отдельной note. Что было, что изменилось, почему.

### Пример гипотезы

```text
Гипотеза:
Aggressive Spider наносит слишком много unavoidable damage.

Смотрим:
- charge attempts;
- charge hit rate;
- damage_per_spawn;
- deaths;
- room role;
- floor;
- player weapon;
- web slow before charge.

Изменение:
wait_duration +15%.

После изменения:
compare_versions с одинаковыми seeds → damage_per_spawn упал,
deaths не выросли → accept.
```

## 5. Data quality troubleshooting

| Issue code | Что означает | Что делать |
|------------|--------------|------------|
| `json_parse_error` | Строка JSONL повреждена (обычно последняя, если crash во время записи) | Игнорируй, importer пропускает. Если много — проверь `JsonlAnalyticsSink._is_broken` в клиенте |
| `duplicate_event_id` | UUID collision | Не должно случаться; если много — issue в `analytics_ids.gd` |
| `unknown_event` | Клиент эмиттит event, которого нет в `schemas.py` | Добавь EventSpec в `tools/analytics/schemas.py` (см. `docs/engineering/analytics.md` за именами) |
| `future_schema_version` | Клиент новее pipeline | Обнови `SUPPORTED_SCHEMA_VERSION` в `schemas.py` после проверки, что pipeline действительно поддерживает новую версию |
| `envelope_missing_field` | Клиент не пишет обязательное поле | Смотри `Analytics._build_envelope` в GDScript — там что-то сломалось |
| `payload_missing_field` | Event эмиттится с неполным payload | Тот же root cause |
| `payload_negative_value` | Отрицательное duration/damage | Проверь `_run_state` — возможно, race где finalize пришёл раньше start |
| `impossible_health` | `health_before > max_health` | Скорее всего баг в player.gd (например, HP restore после max HP downgrade) |
| `duplicate_run_started` / `duplicate_run_finished` | Двойной эмит | Analytics не защищается от повторных вызовов — проверь callsite |
| `floor_event_without_started` | Summary event без предшествующего `floor_started` | Обычно клиент начал floor из редактора без `start_run` — orphan данные, можно игнорировать |
| `non_monotonic_floor` | Пришёл floor N после N+1 | Debug-load; либо race |

## 6. Реалистичные ожидания

- Отчёт не отвечает на вопрос «какая карта самая сильная». Он даёт
  входные данные для гипотезы.
- Bootstrap CI и significance tests НЕ реализованы. Sample size warning
  — единственный сигнал о надёжности.
- Version comparison помогает понять, куда сдвинулась метрика, но не
  доказывает, что сдвиг вызван твоим изменением.

## См. также

- `docs/engineering/analytics.md` — envelope и события (PR 1/2).
- `tools/analytics/README.md` — CLI cheat sheet.
- `plans/game-analytics-balance-claude-plan.md` — исходный план фичи.
