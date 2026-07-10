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

## Конкретные оружия

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

## Стрельба игрока

- Cooldown берётся из `equipped_weapon.fire_interval`.
- За один shot спавнится `bullets_per_shot` пуль.
- При `bullets_per_shot > 1` разброс равномерный от `-spread/2` до `+spread/2`.
- При `bullets_per_shot == 1` и `spread_angle_deg > 0` — случайное отклонение в диапазоне `±spread/2`.
- Все пули стартуют из `global_position` игрока в направлении курсора мыши.

Смена оружия — через `WeaponPickup` (см. `pickups.md`); стартовое оружие после смерти сбрасывается в `DEFAULT_WEAPON`.
