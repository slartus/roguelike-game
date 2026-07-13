class_name BossArenaProfile
extends Resource

# Профиль арены босса — размер комнаты, зона и параметры под будущий
# art overhaul. На этом этапе используется только `size`, остальное —
# метаданные под следующие PR (материалы пола, радиус чистой зоны).

@export var id: StringName = &""
@export var size: Vector2i = Vector2i(600, 400)
@export var zone: StringName = &""
@export var material_profile_id: StringName = &""
@export var clear_center_radius: float = 0.0
