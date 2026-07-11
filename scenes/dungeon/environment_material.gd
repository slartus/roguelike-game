class_name EnvironmentMaterial
extends Resource

# Один материал окружения — комплект текстур, применяемых floor.gd при
# рендере пола/стен. Одно ID (`StringName`) идентифицирует материал в
# каталоге; профиль зоны (см. `EnvironmentVisualProfile`) ссылается на
# материалы по этим ID.
#
# Не все материалы используют все поля. Материал типа «пол» может
# заполнить только floor_texture; материал «стена» — wall_texture +
# wall_cap_texture. floor.gd берёт то, что нужно для конкретного слоя.

@export var id: StringName
@export var floor_texture: Texture2D
@export var wall_texture: Texture2D
@export var wall_cap_texture: Texture2D
@export var doorway_texture: Texture2D
