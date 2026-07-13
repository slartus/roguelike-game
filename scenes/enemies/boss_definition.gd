class_name BossDefinition
extends Resource

# Data-driven описание босса: какая сцена, на каком этаже, в какой зоне,
# какой профиль арены и наград. `display_name_key` — i18n-ключ, не raw
# строка (см. .claude/rules/40-i18n-and-exports.md).

@export var id: StringName = &""
@export var display_name_key: StringName = &"ENEMY_UNKNOWN"
@export var scene: PackedScene

@export var floor_number: int = 0
@export var zone: StringName = &""
@export var arena_profile_id: StringName = &""
@export var reward_profile_id: StringName = &""

# Разрешено ли использовать эту definition как fallback для этажей,
# на которых явно не назначен свой босс. Первый PR всей роадмапы:
# Некромант помечается fallback_allowed = true, чтобы floor 10/15/20
# продолжали работать до внедрения соответствующих боссов в PR 3–5.
@export var fallback_allowed: bool = false
