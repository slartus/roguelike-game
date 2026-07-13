class_name WeaponController
extends Node

# Единая точка атаки для Player. Player делегирует «атаковать оружием X в
# направлении Y» — контроллер решает как именно это сделать по
# weapon.attack_type. В M2 реализованы projectile / spell_projectile
# (используют текущий bullet.tscn), melee-ветки — заглушки под M3.
#
# Cooldown хранится и тикает здесь, не в Player — так одна и та же
# инфраструктура работает для любого оружия и для будущих модификаторов.

# Player выставляет default_projectile_scene в _ready — это существующий
# bullet.tscn. WeaponController использует его, когда weapon.projectile_scene
# не задан.
@export var default_projectile_scene: PackedScene
# Сцена ближнего hitbox'а — единственная и используется всеми melee-типами
# (sword arc и spear thrust отличаются только размером box'а).
@export var melee_hitbox_scene: PackedScene

var _owner_player: Node2D
var _cooldown: float = 0.0

func setup(owner_player: Node2D) -> void:
	_owner_player = owner_player

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)

func is_ready() -> bool:
	return _cooldown <= 0.0

# Возвращает true если атака действительно запущена (cooldown был готов и
# weapon не null). Player использует возврат, чтобы понимать «была ли
# атака» — сейчас не критично, но пригодится для триггера анимаций/звуков.
func try_attack(weapon: WeaponResource, target_global_position: Vector2) -> bool:
	if weapon == null or _owner_player == null:
		return false
	if _cooldown > 0.0:
		return false
	var direction := (target_global_position - _owner_player.global_position).normalized()
	if direction == Vector2.ZERO:
		return false
	var success := false
	match weapon.attack_type:
		"projectile", "spell_projectile":
			success = _attack_projectile(weapon, direction)
		"melee_arc", "melee_thrust":
			success = _attack_melee(weapon, direction)
		"spell_area":
			push_warning("spell_area not implemented yet")
		_:
			push_warning("unknown attack_type='%s'" % weapon.attack_type)
	if not success:
		# Cooldown не выставляем — иначе игрок «залипает» на пустой атаке
		# (например, оружие с забытым projectile_scene): visually ничего не
		# происходит, но cooldown идёт, и мы не понимаем почему.
		return false
	# Analytics: одна activation = один attacks-count (для melee — swing;
	# для projectile — попытка выстрела, независимо от числа projectiles).
	Analytics.record_player_attack(StringName(weapon.resource_path.get_file().get_basename()))
	# Cooldown берём из stats (учитывает archer/mage attack_interval_multiplier).
	var mods := GameState.get_player_upgrade_modifiers()
	var stats := WeaponStats.compute(weapon, mods)
	_cooldown = stats.attack_interval
	# Визуал взмаха у игрока — короткий выпад тела + свинг оружия для
	# melee. Метод опционален: контроллер работает и без него (тесты
	# инстансируют fake player без сцены).
	if _owner_player.has_method("play_attack_visual"):
		_owner_player.play_attack_visual(target_global_position, weapon)
	return true

func _attack_projectile(weapon: WeaponResource, direction: Vector2) -> bool:
	var scene: PackedScene = weapon.projectile_scene
	if scene == null:
		scene = default_projectile_scene
	if scene == null:
		# Возвращаем false — try_attack не поставит cooldown, игрок сможет
		# нажать снова (визуально ничего не произойдёт). Warning: тихо
		# не логируем в push_error, потому что GUT считает push_error за
		# fail; use push_warning вместо этого для видимости при отладке.
		push_warning("WeaponController: у оружия '%s' нет projectile_scene и default_projectile_scene пуст" % weapon.id)
		return false
	var mods := GameState.get_player_upgrade_modifiers()
	var stats := WeaponStats.compute(weapon, mods)
	var count := maxi(1, stats.projectiles_per_attack)
	var spread := deg_to_rad(stats.spread_angle_deg)
	# Spawn origin — не в центре игрока, а у наконечника оружия. Для оружия
	# без spawn distance (`= 0`) поведение идентично старому (центр игрока).
	# lateral перпендикулярный сдвиг: `direction.orthogonal()` направлен на
	# 90° влево от direction, положительный lateral сдвигает спавн влево.
	var spawn_origin := _owner_player.global_position \
		+ direction * weapon.projectile_spawn_distance \
		+ direction.orthogonal() * weapon.projectile_spawn_lateral_offset
	var scene_root := get_tree().current_scene
	for i in count:
		var offset := 0.0
		if count > 1:
			offset = lerp(-spread * 0.5, spread * 0.5, float(i) / float(count - 1))
		elif spread > 0.0:
			offset = randf_range(-spread * 0.5, spread * 0.5)
		var bullet := scene.instantiate()
		bullet.direction = direction.rotated(offset)
		# apply_weapon_stats — новый метод, читает из stats. Fallback на
		# apply_weapon если сцена ещё старого контракта.
		if bullet.has_method("apply_weapon_stats"):
			bullet.apply_weapon_stats(stats)
		else:
			bullet.apply_weapon(weapon)
		if scene_root != null:
			scene_root.add_child(bullet)
		else:
			# Fallback для тестов, когда current_scene == null: цепляем в
			# сам Player, чтобы bullet попал в дерево и мог что-то делать.
			_owner_player.add_child(bullet)
		# global_position ставим ПОСЛЕ add_child — иначе Godot пересчитает
		# его через parent transform: если у scene_root есть смещение, spawn
		# сместится на это смещение. Для main-сцены в (0,0) поведение не
		# меняется; для тестов с GUT runner в собственной позиции — теперь
		# spawn действительно попадает в spawn_origin.
		bullet.global_position = spawn_origin
		# Analytics: один record_projectile_fired на каждый реально созданный
		# projectile — spread shot из 3 pellets = 3 fired.
		Analytics.record_projectile_fired(stats.source_weapon_id)
	return true

func _attack_melee(weapon: WeaponResource, direction: Vector2) -> bool:
	if melee_hitbox_scene == null:
		push_warning("WeaponController: melee_hitbox_scene не задан — melee-оружие '%s' не работает" % weapon.id)
		return false
	var mods := GameState.get_player_upgrade_modifiers()
	var stats := WeaponStats.compute(weapon, mods)
	var hitbox := melee_hitbox_scene.instantiate()
	# configure ДО add_child: он создаёт CollisionShape2D и позиционирует
	# hitbox. _ready родного узла увидит уже готовое состояние.
	hitbox.configure(
		_owner_player,
		direction,
		stats.damage,
		stats.hitbox_length,
		stats.hitbox_width,
		stats.active_time,
		stats.knockback,
		stats.attack_type,
		stats.arc_degrees,
	)
	# Attribution: source_weapon_id для аналитики (передаём после configure
	# чтобы _ready() увидел его установленным).
	hitbox.source_weapon_id = stats.source_weapon_id
	var scene_root := get_tree().current_scene
	if scene_root != null:
		scene_root.add_child(hitbox)
	else:
		_owner_player.add_child(hitbox)
	return true
