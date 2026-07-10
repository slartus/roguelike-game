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

Ближний бой реализован через `MeleeHitbox` (`scenes/player/melee_hitbox.tscn`) — `Area2D` с прямоугольным `RectangleShape2D`, живёт `active_time` секунд, бьёт каждого врага один раз за swing.

**Как работает:**
- WeaponController при `attack_type ∈ {melee_arc, melee_thrust}` инстансирует `melee_hitbox_scene`;
- вызывает `hitbox.configure(source, direction, damage, length, width, active_time, knockback)` **до** `add_child` — конструирует `CollisionShape2D` с `RectangleShape2D(size = length × width)` и позиционирует hitbox в `source.global_position + direction × length/2` с `rotation = direction.angle()`;
- на первом `_physics_process` сканирует `get_overlapping_bodies()` (враги, стоявшие внутри hitbox'а на момент spawn'а, не выдадут `body_entered`);
- в течение `active_time` слушает `body_entered` для новых overlap'ов;
- каждого enemy бьёт максимум один раз (`_hit_targets: Dictionary` как set);
- по истечении `active_time` — `queue_free`.

**Sword и Spear** — один hitbox scene, разные размеры из `WeaponResource`:
- Short Sword: `hitbox_length=34`, `hitbox_width=42` — короткий широкий (arc, замах).
- Spear: `hitbox_length=58`, `hitbox_width=18` — длинный узкий (thrust, укол с дистанции).

Идеальная дуга и визуальная анимация замаха — за пределами M3. Прямоугольный hitbox читается достаточно, чтобы отличить sword от spear.

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

**Projectile spawn:**
- количество = `weapon.get_projectiles_per_attack()` (v2 поле или fallback на `bullets_per_shot`);
- при count > 1 — равномерный spread от `-spread/2` до `+spread/2`;
- при count == 1 и spread > 0 — случайное отклонение `±spread/2`;
- каждая пуля вызывает `apply_weapon(weapon)` — тот сам подхватывает `damage` / `get_projectile_speed()` / `get_projectile_lifetime()` / `get_projectile_color()`.

Смена оружия — через `WeaponPickup` (см. `pickups.md`); стартовое оружие после смерти сбрасывается в `DEFAULT_WEAPON`.
