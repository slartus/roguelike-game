class_name WeaponResource
extends Resource

@export var display_name: String = "WEAPON_UNKNOWN"
@export var damage: int = 1
@export var fire_interval: float = 0.25
@export var bullet_speed: float = 220.0
@export var bullet_lifetime: float = 1.5
@export var bullet_color: Color = Color(1.0, 0.9, 0.3, 1.0)
@export var bullets_per_shot: int = 1
@export var spread_angle_deg: float = 0.0
@export var icon_texture: Texture2D  # Иконка на WeaponPickup (16×16)
