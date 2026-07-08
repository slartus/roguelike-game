# Оружие

Data-driven через кастомный `Resource` — `WeaponResource` (class_name зарегистрирован глобально).

## `WeaponResource` (`resources/weapon_resource.gd`)

| Поле | Тип | Смысл |
|------|-----|-------|
| `display_name` | `String` | Название для UI (пока не используется в HUD) |
| `damage` | `int` | Урон одной пули |
| `fire_interval` | `float` | Cooldown между выстрелами (сек) |
| `bullet_speed` | `float` | Скорость пули |
| `bullet_lifetime` | `float` | Сколько сек пуля живёт |
| `bullet_color` | `Color` | Цвет визуала пули + окраска WeaponPickup |
| `bullets_per_shot` | `int` | Сколько пуль стреляет за один shot |
| `spread_angle_deg` | `float` | Полный угол разброса в градусах (при `bullets_per_shot > 1` — равномерно; при 1 — случайно ±spread/2) |
| `icon_texture` | `Texture2D` | Спрайт 16×16 в `assets/sprites/weapons/`. Показывается на `WeaponPickup` на полу |

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
