# Оружие

Data-driven через кастомный `Resource` — `WeaponResource` (class_name зарегистрирован глобально).

Начиная с v2 модель разделяется на **стили** и **типы атаки** — это фундамент для warrior / archer / mage игровых стилей. Старые Dagger / Pistol / Shotgun остаются как legacy (`style = "legacy"`) и продолжают работать через fallback-helper'ы.

## `WeaponResource` v2 (`resources/weapon_resource.gd`)

### Identity

| Поле | Тип | Смысл |
|------|-----|-------|
| `id` | `String` | Уникальный slug (например `short_sword`, `wand`) |
| `style` | `enum` | `warrior` / `archer` / `mage` / `legacy` |
| `attack_type` | `enum` | `melee_arc` / `melee_thrust` / `projectile` / `spell_projectile` / `spell_area` |
| `tier` | `int` | Уровень оружия (пока всё tier=1) |
| `tags` | `Array[String]` | Свободные теги для будущих upgrade cards и фильтров |
| `display_name` | `String` | i18n ключ (UPPER_SNAKE_CASE) |
| `icon_texture` | `Texture2D` | 16×16 иконка на `WeaponPickup` |

### Общие attack stats

| Поле | Тип | Смысл |
|------|-----|-------|
| `damage` | `int` | Урон одного попадания |
| `attack_interval` | `float` | Cooldown между атаками (сек). 0 → fallback на legacy `fire_interval` |
| `attack_range` | `float` | Информативная дистанция удара (для docs/HUD). Не `range` — то встроенная функция GDScript |

### Projectile stats (для `projectile`, `spell_projectile`, `spell_area`)

| Поле | Тип | Смысл |
|------|-----|-------|
| `projectile_scene` | `PackedScene` | Кастомная сцена снаряда. null → default `bullet.tscn` |
| `projectile_speed` | `float` | Скорость. 0 → fallback на `bullet_speed` |
| `projectile_lifetime` | `float` | Живучесть. 0 → fallback на `bullet_lifetime` |
| `projectile_color` | `Color` | Цвет визуала снаряда |
| `projectiles_per_attack` | `int` | Сколько снарядов. 0 → fallback на `bullets_per_shot` |
| `spread_angle_deg` | `float` | Полный угол разброса |
| `pierce` | `int` | Через сколько врагов пробивает (0 — не пробивает) |

### Melee stats (для `melee_arc`, `melee_thrust`)

| Поле | Тип | Смысл |
|------|-----|-------|
| `arc_degrees` | `float` | Ширина дуги для arc-атак |
| `hitbox_width` | `float` | Ширина hitbox'а перед игроком |
| `hitbox_length` | `float` | Длина hitbox'а перед игроком |
| `windup_time` | `float` | Задержка перед активной фазой |
| `active_time` | `float` | Как долго hitbox бьёт |
| `recovery_time` | `float` | Cooldown после активной фазы |
| `knockback` | `float` | Отбрасывание врагов |

### Magic v1 (заготовка, не расходуется)

| Поле | Тип | Смысл |
|------|-----|-------|
| `mana_cost` | `int` | В v1 всегда 0 (ману ещё не завели) |
| `status_effect` | `String` | Планируемый эффект (`burn`, `frost`, ...) |
| `area_radius` | `float` | Для `spell_area` |

### Legacy поля (для Dagger/Pistol/Shotgun)

`fire_interval`, `bullet_speed`, `bullet_lifetime`, `bullet_color`, `bullets_per_shot` — оставлены, чтобы старые `.tres` продолжали работать. Новые ресурсы задают эти же значения через `attack_interval` / `projectile_*`. Helper'ы `get_attack_interval()`, `get_projectile_speed()`, `get_projectile_lifetime()`, `get_projectiles_per_attack()`, `get_projectile_color()` возвращают новое поле, если задано, иначе fallback на legacy. WeaponController v2 (следующий milestone) читает всё через них — так и legacy, и новые оружия проходят один путь.

## Warrior — melee_arc / melee_thrust

Ближний бой реализован через `MeleeHitbox` (`scenes/player/melee_hitbox.tscn`) — `Area2D`, форма которого зависит от `attack_type`:

- **`melee_arc`** — круговой сектор с углом `arc_degrees`, радиусом `hitbox_length`. Технически это `CircleShape2D(radius = hitbox_length)`, стоящий в позиции игрока, плюс angular-filter в `_try_hit`: тело попадает под удар только если его локальный угол (в системе координат, повёрнутой на `direction.angle()`) находится в `±arc_degrees/2`. `hitbox_width` игнорируется — форма секторная.
- **`melee_thrust`** — прямоугольник `RectangleShape2D(size = hitbox_length × hitbox_width)`, сдвинутый на `hitbox_length/2` вперёд от игрока. Никакого angular-фильтра, вся ловушка в самой форме.

**Общее поведение:**
- WeaponController при `attack_type ∈ {melee_arc, melee_thrust}` инстансирует `melee_hitbox_scene` и вызывает `hitbox.configure(source, direction, damage, length, width, active_time, knockback, attack_type, arc_degrees)` **до** `add_child` — конструирует `CollisionShape2D` под нужную форму и позиционирует / поворачивает Area2D.
- На первом `_physics_process` сканирует `get_overlapping_bodies()` (враги, стоявшие внутри hitbox'а на момент spawn'а, не выдадут `body_entered`).
- В течение `active_time` слушает `body_entered` для новых overlap'ов.
- Каждого enemy бьёт максимум один раз за swing (`_hit_targets` как set).
- После `active_time` — `monitoring = false`, hitbox больше не наносит урон, но остаётся в дереве и продолжает рендериться.
- По истечении `_visual_life = max(active_time, MIN_VISUAL_LIFE = 0.16)` — `queue_free`.

**Sword и Spear** — один hitbox scene, разные формы и размеры из `WeaponResource`:
- Short Sword: `attack_type=melee_arc`, `arc_degrees=80`, `hitbox_length=34` (радиус). Широкий замах перед игроком.
- Spear: `attack_type=melee_thrust`, `hitbox_length=58`, `hitbox_width=18`. Длинный узкий укол с дистанции.

### Анимация hitbox'а (процедурный `_draw`)

Каждый MeleeHitbox сам рисует «след» удара — не сплошную заливку области урона (она перекрывала бы врага), а лёгкие световые штрихи, читаемые как ветер от клинка:

- **`melee_arc`** — два дугообразных «ветерка» вокруг направления атаки: внутренний на радиусе `hitbox_length × ARC_INNER_RADIUS_RATIO` (~0.55) и внешний на `× ARC_OUTER_RADIUS_RATIO` (~0.92). Каждый ветерок покрывает `arc_degrees × ARC_STREAK_COVERAGE` (~85% сектора) — на концах остаются короткие «хвосты», а не резкий обрыв. Внешний штрих светлее и длиннее, читается как кромка замаха; внутренний глухой, поддерживает силу удара.
- **`melee_thrust`** — два горизонтальных штриха выше и ниже древка копья (`± hitbox_width × THRUST_STREAK_OFFSET_RATIO`, длина `× THRUST_STREAK_LENGTH_RATIO`), плюс треугольный «наконечник» у переднего края. Читается как свист копья при уколе.

Альфа-канал даёт burst-фазу: fade-in первые 15% `_visual_life`, hold 35%, fade-out оставшееся. Хитбокс перестаёт наносить урон после `active_time` (`monitoring = false`), но продолжает рендериться до `_visual_life = max(active_time, MIN_VISUAL_LIFE = 0.16)` — так игрок видит короткое затухание уже после того, как удар прошёл.

![Взмах меча — две дугообразные волны следа клинка](media/melee_arc_swing.gif)

![Укол копья — две линии свиста + наконечник](media/melee_thrust_swing.gif)

### Style upgrade: warrior_arc_multiplier

Sweeping Blade (`melee_arc_multiplier`, × 1.15 за стек) умножает `arc_degrees` — то есть **расширяет сектор удара**. `hitbox_width` не трогается (для arc-типа он не используется). Для `melee_thrust` этот модификатор игнорируется — у копья нет сектора. Общий cap — `MAX_ARC_DEGREES = 179°`: полный круг «съел бы» направление атаки, что визуально и геймплейно неоднозначно.

### Short Sword (`short_sword.tres`)

`style = warrior`, `attack_type = melee_arc`, `damage = 2`, `attack_interval = 0.38`, `attack_range = 36`, `knockback = 40`.
i18n: `WEAPON_SHORT_SWORD`.

### Spear (`spear.tres`)

`style = warrior`, `attack_type = melee_thrust`, `damage = 2`, `attack_interval = 0.48`, `attack_range = 56`, `knockback = 30`.
i18n: `WEAPON_SPEAR`.

## Archer — projectile

Классические ranged-оружия используют текущий `bullet.tscn` через `WeaponController._attack_projectile`. Отличаются от legacy Dagger/Pistol только identity (`style = archer`) и v2-полями (`projectile_speed / lifetime / color / pierce`).

**Pierce.** Новое поле `pierce: int` в `WeaponResource`. Bullet `apply_weapon` копирует его в `_pierce_remaining`. При попадании во врага:
1. если враг уже был в `_hit_bodies` (Area2D может слать `body_entered` повторно) — пропускаем;
2. иначе наносим `damage`, отмечаем в `_hit_bodies`;
3. если `_pierce_remaining > 0` — decrement, пуля летит дальше;
4. иначе — `queue_free`.

Legacy (Dagger/Pistol/Shotgun) не задают `pierce` → default 0 → old behaviour без изменений.

### Short Bow (`short_bow.tres`)

`style = archer`, `attack_type = projectile`, `damage = 1`, `attack_interval = 0.32`, `projectile_speed = 260`, `projectile_lifetime = 1.2`, `spread_angle_deg = 2`, `pierce = 0`. Быстрый и надёжный ranged.
i18n: `WEAPON_SHORT_BOW`.

### Crossbow (`crossbow.tres`)

`style = archer`, `attack_type = projectile`, `damage = 3`, `attack_interval = 0.75`, `projectile_speed = 300`, `projectile_lifetime = 1.4`, `spread_angle_deg = 0`, `pierce = 1`. Медленнее, но сильнее и пробивает одного врага насквозь.
i18n: `WEAPON_CROSSBOW`.

## Mage — spell_projectile

Магические оружия v1 — без маны и без сложных заклинаний. Отличаются от archer только identity (`style = mage`, `attack_type = spell_projectile`) и визуально (свои `projectile_color`). WeaponController обрабатывает `spell_projectile` тем же путём, что и `projectile` — общий `_attack_projectile()`.

**mana_cost = 0** в v1 — поле-заготовка. Реальная система маны, spellbook и elemental статусы — backlog.

### Apprentice Staff (`apprentice_staff.tres`)

`style = mage`, `attack_type = spell_projectile`, `damage = 3`, `attack_interval = 0.62`, `projectile_speed = 210`, `projectile_lifetime = 1.2`, `spread_angle_deg = 0`. Сине-голубой снаряд, медленный тяжёлый cast.
i18n: `WEAPON_APPRENTICE_STAFF`.

### Wand (`wand.tres`)

`style = mage`, `attack_type = spell_projectile`, `damage = 1`, `attack_interval = 0.24`, `projectile_speed = 230`, `projectile_lifetime = 1.0`, `spread_angle_deg = 4`. Пурпурный, лёгкий частый cast.
i18n: `WEAPON_WAND`.

## Legacy оружия (Dagger/Pistol/Shotgun)

Все `.tres` лежат в `resources/weapons/`. Пул сундука в `chest.gd::WEAPON_POOL`.

### Dagger — стартовое

Быстрое ближнее оружие, low damage, короткая дальность. Стартует у игрока (`GameState.DEFAULT_WEAPON`).

| damage | fire_interval | bullet_speed | bullet_lifetime | bullets | spread |
|--------|---------------|--------------|-----------------|---------|--------|
| 1 | 0.16 | 280 | 0.35 | 1 | 0° |

Цвет: холодный светло-голубой `Color(0.9, 0.95, 1.0)`.

Файл: `resources/weapons/dagger.tres`.

### Pistol — сбалансированный

Средний ритм, урон 1, лёгкий разброс. За счёт большего `bullet_lifetime` и `bullet_speed` пуля летит дальше и быстрее, чем у dagger — эффективна на дистанции, где dagger уже растворяется.

| damage | fire_interval | bullet_speed | bullet_lifetime | bullets | spread |
|--------|---------------|--------------|-----------------|---------|--------|
| 1 | 0.32 | 240 | 1.4 | 1 | 4° |

Цвет: жёлтый `Color(1.0, 0.85, 0.25)`.

Файл: `resources/weapons/pistol.tres`.

### Shotgun — конус

5 пуль веером 32°, короткая дистанция (lifetime 0.55). Один залп — 5 попаданий по 1 урону.

| damage | fire_interval | bullet_speed | bullet_lifetime | bullets | spread |
|--------|---------------|--------------|-----------------|---------|--------|
| 1 | 0.65 | 220 | 0.55 | 5 | 32° |

Цвет: оранжевый `Color(1.0, 0.55, 0.25)`.

Файл: `resources/weapons/shotgun.tres`.

## Пуля игрока (`bullet.tscn`)

`Area2D` с `Polygon2D` радиуса 2. Метод `apply_weapon(weapon)` копирует `damage / speed / lifetime / bullet_color` из ресурса.

**Поведение:** движется `direction * speed`; при `body_entered` игнорит группу `player`, наносит `damage` через `take_damage` если у ноды есть метод, и уничтожается. Self-destroy через `lifetime`.

Скрипт: `scenes/bullets/bullet.gd`.

## Атака игрока

Атака вынесена из `player.gd` в `WeaponController` (child-нода `Player/WeaponController`, скрипт `scenes/player/weapon_controller.gd`). Player только держит `equipped_weapon` и на каждый tick вызывает `_weapon_controller.try_attack(equipped_weapon, get_global_mouse_position())` — controller сам решает как атаковать по `weapon.attack_type`.

**WeaponController отвечает за:**
- cooldown (`_cooldown` тикает в `_process`, `is_ready()` возвращает готовность);
- projectile spawning для `projectile` / `spell_projectile`;
- будущие `melee_arc` / `melee_thrust` / `spell_area` реализации (в M2 они возвращают `false` и логируют warning);
- fallback на `default_projectile_scene` (= `bullet.tscn` из player.tscn) если `weapon.projectile_scene` не задан.

**`try_attack(weapon, target_global_position) → bool`** — возвращает `true` если атака действительно запущена (weapon не null, cooldown готов, direction не нулевой). Cooldown ставится ТОЛЬКО на успешной атаке — failed attempt не залипает на cooldown'е.

## Модель оружия в руке игрока

`player.tscn` содержит дочерний `Sprite2D` **Weapon** — sprite оружия в правой руке игрока (`position = (5, 3)`, offset вычисляется от icon_texture в `_apply_weapon_visual`, пивот на «рукояти» чтобы вращение читалось как замах).

- При `_ready` и `equip(weapon)` — `_apply_weapon_visual` подставляет `weapon.icon_texture` и `modulate = weapon.icon_modulate`.
- Без equipped weapon (или без icon_texture) — Weapon-нода скрыта.
- Legacy Dagger / Pistol / Shotgun имеют полноцветные icon_texture, `icon_modulate = WHITE` → рендерятся как есть.
- Новые 6 classical weapons используют `dagger.png` как placeholder-иконку и отличаются через `icon_modulate` (см. `pickups.md`).

## Анимация взмаха

WeaponController при успешной `try_attack` вызывает `player.play_attack_visual(target_pos, weapon)`. Реализация повторяет паттерн `skeleton.gd::_play_lunge_animation`:

- Корпус (Sprite2D `Visual`) делает выпад в сторону цели на `SWING_DISTANCE = 6` px за `SWING_OUT_DURATION = 60 ms`, возвращается обратно за `SWING_BACK_DURATION = 120 ms`.
- Только для melee (`melee_arc` / `melee_thrust`) параллельно с выпадом Weapon-нода поворачивается на `WEAPON_SWING_ANGLE = PI × 0.55` (~99°) и обратно — через пивот на рукояти это читается как рубящий удар.
- Для projectile / spell (лук, посох, жезл) свинг оружия не запускается — только выпад тела: было бы странно если лук «резал».
- Предыдущий tween убивается через `.kill()` перед стартом нового, чтобы визуал не застревал в промежуточной точке при частой стрельбе.

**Projectile spawn:**
- количество = `weapon.get_projectiles_per_attack()` (v2 поле или fallback на `bullets_per_shot`);
- при count > 1 — равномерный spread от `-spread/2` до `+spread/2`;
- при count == 1 и spread > 0 — случайное отклонение `±spread/2`;
- каждая пуля вызывает `apply_weapon(weapon)` — тот сам подхватывает `damage` / `get_projectile_speed()` / `get_projectile_lifetime()` / `get_projectile_color()`.

Смена оружия — через `WeaponPickup` (см. `pickups.md`); стартовое оружие после смерти сбрасывается в `DEFAULT_WEAPON`.
