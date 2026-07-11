# Docs: showcase «игрок с оружием»

Как выглядит игрок с каждым оружием — задокументировано картинками в
`docs/gamedesign/weapons.md`, раздел «Внешний вид игрока с каждым
оружием». Файлы лежат в `docs/gamedesign/media/player_with_<id>.png` —
по одному на каждое `resources/weapons/<id>.tres`.

Генератор — `tools/gen_player_weapon_showcase.py` (Python + Pillow).
Композит повторяет ту же математику, что делает движок в
`scenes/player/player.gd::_apply_weapon_visual` +
`_apply_facing_visuals` — pivot вращения на нижнем крае иконки, offset
руки `(HAND_X_OFFSET, HAND_Y_OFFSET) = (5, 3)`, rest-угол
`MELEE_REST_ANGLE = 0.35` rad для `melee_arc` / `melee_thrust`, `0` для
`projectile` / `spell_projectile` / `spell_area`. Facing right.

## Когда обязательно перегенерировать

Любое изменение из списка — перегенерировать в том же коммите:

1. **Изменился спрайт игрока** — `assets/sprites/player/player.png` или
   генератор `tools/gen_player_sprite.py`.
2. **Изменился спрайт хотя бы одного оружия** — `assets/sprites/weapons/<id>.png`
   или один из генераторов (`tools/gen_weapon_sprites.py`,
   `tools/gen_item_sprites.py`).
3. **Добавлено новое оружие** — новый `.tres` в `resources/weapons/`. К
   моменту commit'а `player_with_<new_id>.png` **и** строка в таблице
   `weapons.md` обязаны существовать.
4. **Удалено оружие** — удалить `player_with_<removed_id>.png` и строку
   в таблице.
5. **Изменились `HAND_X_OFFSET` / `HAND_Y_OFFSET` / `MELEE_REST_ANGLE`**
   в `scenes/player/player.gd` — синхронизировать одноимённые константы
   в шапке `tools/gen_player_weapon_showcase.py`, затем перегенерировать.
6. **Изменился `MELEE_ATTACK_TYPES`** — появился новый `attack_type`,
   у которого своя rest-поза. Обновить `rest_angle_for` в генераторе.
   Legacy `.tres` без явного `attack_type` считается `projectile` — это
   совпадает с default'ом `weapon_resource.gd`, но если добавляешь
   **новое** legacy melee оружие, задай `attack_type = "melee_arc"` или
   `"melee_thrust"` явно, иначе картинка покажет вертикальный клинок.
7. **Изменилась поза или сборка оружия в руке** — любая правка
   `_apply_weapon_visual` / `_apply_facing_visuals`, влияющая на то,
   что видит игрок. Синхронизировать генератор.

## Команда

```bash
python3 tools/gen_player_weapon_showcase.py
```

Скрипт пересобирает **все** `player_with_<id>.png` за один прогон. Git
покажет `M` только для тех файлов, чей контент реально изменился.

После прогона визуально открой обновлённые картинки — совпадает ли с
ожиданиями (`open docs/gamedesign/media/player_with_<id>.png`).

## Что должен ловить reviewer

- Меняется `player.png` / любой `weapons/<id>.png` — но нет
  `M docs/gamedesign/media/player_with_*.png` в diff'е.
- Добавляется новый `<id>.tres` — но нет нового
  `player_with_<id>.png` и нет строки в таблице `weapons.md`.
- Изменились константы `HAND_*_OFFSET` / `MELEE_REST_ANGLE` в
  `player.gd`, но не тронут генератор `gen_player_weapon_showcase.py`.
- Появился новый `attack_type`, но `rest_angle_for` в генераторе о нём
  не знает — использует fallback (не-melee), картинка врёт про rest-позу.
- Docs и картинка расходятся: файл `player_with_<id>.png` есть, но в
  таблице `weapons.md` его нет (или наоборот).
