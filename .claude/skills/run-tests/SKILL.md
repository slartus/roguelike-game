---
name: run-tests
description: Прогнать GUT-сюиту (все тесты из test/unit/) через headless Godot и вернуть red/green summary. Использовать после любой правки .gd/.tscn/.tres перед git commit, а также по явному запросу пользователя "прогони тесты".
---

# Skill: run-tests

## Команда

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit
```

Запускай через Bash из корня проекта. `-gexit` обязателен — иначе Godot не закроется после прогона и Bash зависнет.

## Как читать вывод

GUT в конце печатает summary в формате:

```
Totals
------
Scripts:      NN
Tests:        NNN
Passing:      NNN
Failing:      0
Errors:       0
```

Красный тест = `Failing > 0` или `Errors > 0`. Fatal ошибки Godot (parse errors, missing dependencies) — до GUT-summary.

## Правило

- **Красный тест = не коммитить.** Fix → повторный прогон до `Failing: 0` и `Errors: 0`.
- Если тесты падают не из-за твоих правок (сторонний баг GUT / инфра) — явно обозначь это в commit message и в отчёте пользователю, не маскируй.
- Если новая логика не покрыта существующим тестом — добавь тест **в том же коммите**, не откладывай.

## Что вернуть пользователю

Короткое summary:
- Passing/Failing/Errors числа.
- Если падают — список конкретных тестов (имя файла + метод).
- Если всё зелёное — одна строка «All tests passed (NN тестов)».

Не вставляй полный лог Godot в ответ — он длинный и шумный.

## Fast path

Если правишь один тестовый файл и хочешь прогнать только его — добавь `-gtest=res://test/unit/test_<name>.gd`:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_<name>.gd -gexit
```

Но **перед commit'ом** обязательно прогон полной сюиты, а не одного файла.
