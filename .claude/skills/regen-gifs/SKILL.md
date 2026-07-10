---
name: regen-gifs
description: Регенерирует gif-документацию процедурных анимаций через tools/gen_animation_gifs.py. Использовать после правки _draw / tween / фазовых формул в poison_cloud.gd, spider_web.gd, slime.gd, lich.gd, boss.gd — либо при добавлении новой процедурной анимации.
---

# Skill: regen-gifs

## Команда

```bash
python3 tools/gen_animation_gifs.py
```

Скрипт перепишет только затронутые файлы в `docs/gamedesign/media/`. Идемпотентен — прогон без изменений даёт тот же output.

## Когда запускать

Обязательно после любого изменения процедурной анимации (см. `.claude/rules/50-animations-gifs.md`):
- `_draw`-код в `poison_cloud.gd` / `spider_web.gd` / любые новые процедурные `_draw`.
- Tween-формулы: `slime.gd::_apply_visual_bounce`, `lich.gd::_apply_cast_visual`, `boss.gd::_apply_cast_visual`.
- Константы, влияющие на визуал: цвета, фазы, частоты, радиусы.

## Обязательный порядок

1. **Сначала** обнови `render_<name>()` функцию в `tools/gen_animation_gifs.py`, чтобы она отражала новую логику `_draw`/tween.
2. Прогони скрипт.
3. Открой полученный gif визуально: `open docs/gamedesign/media/<name>.gif`. Убедись что совпадает с ожиданиями.
4. Закоммить `.gd`-правку + правку `gen_animation_gifs.py` + новый `<name>.gif` **в тот же коммит**.

## Добавление новой анимации

1. Написать `render_<name>()` в `tools/gen_animation_gifs.py`, вернуть `list[PIL.Image]`.
2. Добавить запись в массив `ANIMATIONS` внутри скрипта.
3. Прогнать skill (эта команда).
4. Встроить `![<caption>](media/<name>.gif)` в раздел `docs/gamedesign/*.md`, где описан эффект.

## Ловушки

- Скрипт **не** вызывает Godot — он реализует формулы на Python + Pillow. Если формула в `.gd` разошлась с Python — gif врёт. Ревьюер обязан ловить.
- Если Pillow не установлен: `pip3 install Pillow`.
- Random в анимациях — управляется через `random.seed(<name>)` внутри скрипта, чтобы gif был детерминированным между прогонами.

## Текущие gif-и

`docs/gamedesign/media/`:
- `cast_pulse.gif`
- `poison_cloud.gif`
- `slime_hop.gif`
- `spider_web_flying.gif`
- `spider_web_landed.gif`
