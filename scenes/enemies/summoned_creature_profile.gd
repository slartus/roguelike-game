class_name SummonedCreatureProfile
extends RefCounted

# Профиль-контракт для существ, вызванных в бою (в первую очередь свита
# Некроманта). Задаётся хозяином summon'а ДО `add_child()` через
# `configure_summon(profile)` — иначе `_ready()` вражеского узла
# успевает применить Balance.scaled_* по boss floor и случайно
# выбрать iron-оружие из общего пула.

# ID хозяина (для аналитики/логов, не для gameplay-логики).
var summon_owner_id: StringName = &""
# Роль миньона — "melee" / "ranged". Босс использует, чтобы вести
# раздельные квоты и восполнять именно тот же role, что погиб.
var summon_role: StringName = &""

# Уровень для Balance.scaled_*. По умолчанию первый tier (1), не floor.
var monster_level: int = 1
var elite_rank: int = 0

# Rewards / farming guard: миньоны из бесконечного summon'а не должны
# давать XP/gold/drops. Boss.gd конструирует profile с false во всех
# трёх — но default оставляем true, чтобы не сломать возможные будущие
# summon'ы, которым farming уместен.
var grants_xp: bool = true
var grants_gold: bool = true
var grants_drops: bool = true

# Разрешённый пул темпераментов. Пусто = стандартный catalog roll по
# creature_type_id.
var allowed_temperaments: Array[StringName] = []
# Явный override (если непусто и известен — оно и используется).
var temperament_id: StringName = &""

# Отдельный arsenal pool (формат SkeletonArsenal). Пусто = стандартный
# пул скелета/лучника.
var arsenal_pool: Array = []
# Верхний cap damage'а после всех модификаторов. 0 = не клампить.
# Для melee применяется к contact_damage; для ranged — к arrow damage
# внутри `_configure_bullet`.
var max_damage: int = 0

# Задержка перед первым выстрелом (ranged). 0 = штатный стохастический
# старт (`randf() * fire_interval`).
var first_attack_delay: float = 0.0
# Override fire_interval. 0 = не менять.
var fire_interval_override: float = 0.0
