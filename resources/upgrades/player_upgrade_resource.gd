class_name PlayerUpgradeResource
extends Resource

# Дата-driven описание одной upgrade card. Все конкретные карты живут
# как .tres в resources/upgrades/{general,warrior,archer,mage}/. Библиотека
# (PlayerUpgradeLibrary) загружает их разом и валидирует.
#
# Применение эффектов делает game state через `effect_type` + `parameters` —
# сам resource никакой логики не содержит, только данные. Так карты
# остаются легко-тюнимыми без code changes.

@export var id: String = "unknown"
@export var display_name: String = "UPGRADE_UNKNOWN"
@export var description: String = "UPGRADE_UNKNOWN_DESC"

@export_enum("common", "uncommon", "rare") var rarity: String = "common"
@export var max_stacks: int = 1

# Свободные теги для будущего фильтра/группировки (`melee`, `defense`, ...).
@export var tags: Array[String] = []

# Empty → general upgrade. Иначе warrior/archer/mage — влияет только на
# соответствующий weapon.style. Off-style stacks остаются в run state, но
# бездействуют пока игрок не сменит weapon на подходящий.
# @export_enum не принимает пустое значение как валидный вариант, поэтому
# используем plain String и валидируем в PlayerUpgradeLibrary.VALID_STYLES.
@export var style: String = ""

# Ключ типа эффекта — game state смотрит его через match, чтобы применить
# правильный modifier. Список стабильных effect_type перечислен в
# docs/gamedesign/upgrades.md.
@export var effect_type: String = ""
# Параметры зависят от effect_type. Пример:
#   max_health_bonus → {"amount": 1}
#   speed_multiplier → {"multiplier": 1.08}
#   style_damage_bonus → {"style": "warrior", "amount": 1}
@export var parameters: Dictionary = {}

# Совместимость с типом атаки текущего оружия. Пусто → карта работает на
# любом attack_type. Иначе оффер-генератор фильтрует карту, если у
# equipped_weapon.attack_type нет матча в required. `excluded_attack_types`
# — обратный список: карта не предлагается для перечисленных типов.
# Пример: sweeping_blade расширяет arc_degrees и полезна только melee_arc
# оружию → required_attack_types = ["melee_arc"].
@export var required_attack_types: Array[String] = []
@export var excluded_attack_types: Array[String] = []

@export var icon_texture: Texture2D
