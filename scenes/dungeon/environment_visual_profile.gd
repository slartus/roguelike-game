class_name EnvironmentVisualProfile
extends Resource

# Профиль визуальной идентичности одной зоны мира башни. Хранит
# ссылки на материалы (по ID) для пола и стен + опциональные
# override'ы на конкретные роли комнат.
#
# Профиль не хранит текстур сам — конкретные material ID
# резолвятся через `EnvironmentMaterialCatalog`. Это позволяет:
# - шарить одну текстуру между разными профилями через общий ID;
# - тестам проверять только имена материалов без загрузки Texture2D;
# - в будущем добавлять runtime-override'ы (моды, DLC-зоны) без
#   переписывания рендер-кода.
#
# Инвариант: `default_floor_material`, `corridor_floor_material` и
# `default_wall_material` обязаны существовать в каталоге. Override'ы
# опциональны — отсутствующий ключ роли просто использует default.

@export var id: StringName
@export var background_color: Color = Color(0.03, 0.02, 0.05, 1.0)
@export var default_floor_material: StringName
@export var corridor_floor_material: StringName
@export var default_wall_material: StringName
@export var room_role_floor_overrides: Dictionary
@export var room_role_wall_overrides: Dictionary
@export var ambient_tint: Color = Color.WHITE
@export var detail_density_multiplier: float = 1.0
