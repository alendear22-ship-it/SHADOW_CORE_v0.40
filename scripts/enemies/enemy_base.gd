extends CharacterBody2D
class_name EnemyBase

const PIXELS_PER_METER: float = 48.0
const MELEE_MIN_RANGE_PX: float = 42.0
const WATER_PUDDLE_SCENE: String = "res://scenes/effects/water_puddle_zone.tscn"
const MELEE_WINDUP_SECONDS: float = 0.4
const MELEE_TRACKING_SECONDS: float = 0.2
const POINT_ABILITY_TELEGRAPH_SECONDS: float = 0.4
const AREA_ABILITY_TELEGRAPH_SECONDS: float = 0.7
const DRAW_EFFECT_SCRIPT: String = "res://scripts/effects/simple_draw_effect.gd"
const ENEMY_ATTACK_INTERVAL_MULTIPLIER: float = 1.30
const POST_ATTACK_LOCK_SECONDS: float = 0.45
const LEAD_CAST_DISTANCE_PX: float = 24.0 # 0.5 m
const SLIME_RANGE_MULTIPLIER: float = 1.21
const SLIME_RETREAT_DISTANCE_FACTOR: float = 0.90
const SLIME_ATTACK_MOVE_LOCK_SECONDS: float = 0.20
const SLIME_ATTACK_MOVE_SPEED_MULTIPLIER: float = 0.70
const SPIRIT_BACKSTAB_DISTANCE_PX: float = 44.0
const ORC_MIN_SEPARATION_PX: float = 24.0 # 0.5 m
const ORC_MAX_SEPARATION_PX: float = 192.0 # 4 m
const ORC_MAX_SEPARATION_DISTANCE_PX: float = 144.0 # 3 m


@export var enemy_id: String = "ENEMY_KR_ORC_FIGHTER"

@onready var health_component: HealthComponent = $HealthComponent as HealthComponent
@onready var status_effects: StatusEffectComponent = $StatusEffectComponent as StatusEffectComponent
@onready var visual: CanvasItem = get_node_or_null("Visual") as CanvasItem

var data: Dictionary = {}
var faction_id: String = ""
var creature_type_id: String = ""
var essence_amount: int = 1
var movement_speed_px: float = 160.0
var attack_range_px: float = 58.0
var attack_interval: float = 1.5
var attack_damage: float = 8.0
var ai_type: String = "chaser"

var _attack_timer: float = 0.0
var _player: Node2D = null
var _strafe_sign: float = 1.0
var _windup_timer: float = 0.0
var _windup_elapsed: float = 0.0
var _windup_total: float = 0.0
var _pending_attack_type: String = ""
var _pending_attack_range: float = 0.0
var _pending_attack_position: Vector2 = Vector2.ZERO
var _pending_attack_direction: Vector2 = Vector2.ZERO
var _base_visual_color: Color = Color.WHITE
var _runtime_difficulty_multiplier: float = 1.0
var _sprite_visual: SpriteSheetAnimator = null
var _visual_action_lock: float = 0.0
var _post_attack_lock_timer: float = 0.0
var _visual_enemy_id: String = ""
var weak_mob_abilities: Array = []
var _weak_mob_power_total: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	health_component.died.connect(_on_died)
	_strafe_sign = 1.0 if randf() > 0.5 else -1.0
	if visual != null:
		_base_visual_color = visual.modulate
	if data.is_empty():
		setup(DataRegistry.get_enemy(enemy_id))

func setup(enemy_data: Dictionary) -> void:
	if enemy_data.is_empty():
		enemy_data = DataRegistry.get_enemy(enemy_id)
	data = enemy_data.duplicate(true)
	var previous_enemy_id: String = enemy_id
	enemy_id = data.get("id", enemy_id)
	if previous_enemy_id != enemy_id and _sprite_visual != null and is_instance_valid(_sprite_visual):
		_sprite_visual.queue_free()
		_sprite_visual = null
		_visual_enemy_id = ""
	faction_id = data.get("faction_id", "")
	creature_type_id = data.get("creature_type_id", "")
	ai_type = data.get("ai_type", "chaser")
	var stats: Dictionary = data.get("base_stats", {})
	essence_amount = int(stats.get("essence_amount", 1))
	movement_speed_px = float(stats.get("movement_speed_m_per_sec", 3.2)) * PIXELS_PER_METER
	attack_range_px = max(MELEE_MIN_RANGE_PX, float(stats.get("attack_range_m", 1.2)) * PIXELS_PER_METER)
	if _is_slime_enemy():
		attack_range_px *= SLIME_RANGE_MULTIPLIER
	attack_interval = float(stats.get("attack_interval_seconds", 1.5)) * ENEMY_ATTACK_INTERVAL_MULTIPLIER
	_runtime_difficulty_multiplier = max(0.5, float(data.get("runtime_difficulty_multiplier", 1.0)))
	attack_damage = _damage_from_profile(str(stats.get("damage_profile", "низкий"))) * (0.85 + _runtime_difficulty_multiplier * 0.15)
	health_component.configure(float(stats.get("hp", 40.0)) * (0.80 + _runtime_difficulty_multiplier * 0.20))
	_apply_weak_abilities_from_system()
	_apply_visual_from_data()

func set_weak_abilities(payloads: Array) -> void:
	weak_mob_abilities = []
	_weak_mob_power_total = 0.0
	for payload_value in payloads:
		if not (payload_value is Dictionary):
			continue
		var payload_source: Dictionary = payload_value
		var payload: Dictionary = payload_source.duplicate(true)
		# Ordinary mobs receive only run-scoped weak_mob_version payloads from MobWeakAbilitySystem.
		# Full boss/player versions are explicitly rejected here.
		if bool(payload.get("is_full_boss_ability", false)) or bool(payload.get("uses_player_version", false)):
			continue
		if not bool(payload.get("is_weak_mob_version", false)):
			continue
		weak_mob_abilities.append(payload)
		_weak_mob_power_total += clampf(float(payload.get("power_scale", payload.get("power_multiplier", 0.0))), 0.0, 0.60)
	_apply_weak_mob_stat_tuning()
	set_meta("weak_boss_abilities", weak_mob_abilities)
	set_meta("weak_boss_ability_ids", get_weak_boss_ability_ids())

func get_weak_abilities() -> Array:
	return weak_mob_abilities.duplicate(true)

# Backward-compatible adapters for older debug tooling.
func apply_weak_boss_abilities(abilities: Array) -> void:
	set_weak_abilities(abilities)

func get_weak_boss_abilities() -> Array:
	return get_weak_abilities()

func get_weak_boss_ability_ids() -> Array[String]:
	var ids: Array[String] = []
	for ability_value in weak_mob_abilities:
		if ability_value is Dictionary:
			ids.append(str(ability_value.get("boss_ability_id", ability_value.get("id", ""))))
	return ids

func _apply_weak_abilities_from_system() -> void:
	weak_mob_abilities.clear()
	_weak_mob_power_total = 0.0
	if creature_type_id.is_empty():
		return
	var system: Node = get_node_or_null("/root/MobWeakAbilitySystem")
	if system == null:
		return
	if system.has_method("build_weak_ability_payloads"):
		var payloads: Variant = system.call("build_weak_ability_payloads", creature_type_id)
		if payloads is Array:
			set_weak_abilities(payloads)
			return
	if system.has_method("apply_weak_ability_to_enemy"):
		system.call("apply_weak_ability_to_enemy", self, creature_type_id)

func _apply_weak_mob_stat_tuning() -> void:
	if weak_mob_abilities.is_empty():
		return
	# Weak mob versions are intentionally small tuning variants, not full boss effects.
	# The full boss ability logic remains player/boss-only and is not copied into ordinary enemy attacks.
	var damage_bonus: float = clampf(_weak_mob_power_total * 0.06, 0.0, 0.10)
	var interval_reduction: float = clampf(_weak_mob_power_total * 0.02, 0.0, 0.08)
	var range_bonus: float = clampf(_weak_mob_power_total * 0.02, 0.0, 0.08)
	attack_damage *= 1.0 + damage_bonus
	attack_interval = max(0.35, attack_interval * (1.0 - interval_reduction))
	attack_range_px *= 1.0 + range_bonus

func _physics_process(delta: float) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)
	_post_attack_lock_timer = max(0.0, _post_attack_lock_timer - delta)
	_update_sprite_visual(delta)
	_player = _get_player()
	if _update_attack_windup(delta):
		move_and_slide()
		return
	if _player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var to_player: Vector2 = _player.global_position - global_position
	var distance: float = to_player.length()
	match ai_type:
		"ranged":
			_process_ranged(distance, to_player)
		"skirmisher":
			_process_skirmisher(distance, to_player)
		_:
			_process_chaser(distance, to_player)
	move_and_slide()

func _process_chaser(distance: float, to_player: Vector2) -> void:
	var melee_range: float = min(attack_range_px, 72.0)
	if _is_orc_enemy():
		var surround_velocity: Vector2 = _get_orc_surround_velocity(distance, to_player, melee_range)
		if distance <= melee_range:
			velocity = surround_velocity * 0.45
			_try_melee_attack(melee_range)
			return
		velocity = surround_velocity
		return
	if distance <= melee_range:
		velocity = Vector2.ZERO
		_try_melee_attack(melee_range)
		return
	velocity = to_player.normalized() * movement_speed_px * status_effects.get_speed_multiplier()

func _process_ranged(distance: float, to_player: Vector2) -> void:
	if _is_slime_enemy():
		_process_timid_slime(distance, to_player)
		return
	var preferred_min: float = attack_range_px * 0.55
	if distance > attack_range_px:
		velocity = to_player.normalized() * movement_speed_px * 0.85 * status_effects.get_speed_multiplier()
	elif distance < preferred_min:
		velocity = -to_player.normalized() * movement_speed_px * 0.70 * status_effects.get_speed_multiplier()
	else:
		var strafe: Vector2 = to_player.normalized().rotated(PI * 0.5 * _strafe_sign)
		velocity = strafe * movement_speed_px * 0.45 * status_effects.get_speed_multiplier()
		_try_ranged_attack()

func _process_timid_slime(distance: float, to_player: Vector2) -> void:
	var dir_to_player: Vector2 = to_player.normalized() if to_player.length_squared() > 0.001 else Vector2.RIGHT
	var speed_mult: float = status_effects.get_speed_multiplier()
	var retreat_distance: float = attack_range_px * SLIME_RETREAT_DISTANCE_FACTOR
	if distance < retreat_distance:
		velocity = -dir_to_player * movement_speed_px * 0.78 * speed_mult
		_try_ranged_attack()
		return
	if distance > attack_range_px:
		velocity = dir_to_player * movement_speed_px * 0.82 * speed_mult
		return
	var strafe: Vector2 = dir_to_player.rotated(PI * 0.5 * _strafe_sign)
	velocity = strafe * movement_speed_px * 0.38 * speed_mult
	_try_ranged_attack()

func _process_skirmisher(distance: float, to_player: Vector2) -> void:
	if _is_spirit_enemy():
		_process_smart_spirit(distance, to_player)
		return
	if distance > attack_range_px:
		var approach: Vector2 = to_player.normalized()
		var lateral: Vector2 = approach.rotated(PI * 0.5 * _strafe_sign) * 0.25
		velocity = (approach + lateral).normalized() * movement_speed_px * status_effects.get_speed_multiplier()
		return
	var dir: Vector2 = to_player.normalized()
	var strafe: Vector2 = dir.rotated(PI * 0.5 * _strafe_sign)
	velocity = (strafe * 0.75 + dir * 0.20).normalized() * movement_speed_px * status_effects.get_speed_multiplier()
	_try_skirmisher_attack(dir)

func _process_smart_spirit(distance: float, to_player: Vector2) -> void:
	var to_player_dir: Vector2 = to_player.normalized() if to_player.length_squared() > 0.001 else Vector2.RIGHT
	var player_forward: Vector2 = _get_player_move_direction()
	if player_forward.length_squared() <= 0.001:
		player_forward = to_player_dir
	var backstab_point: Vector2 = _player.global_position - player_forward.normalized() * SPIRIT_BACKSTAB_DISTANCE_PX
	var to_backstab: Vector2 = backstab_point - global_position
	var lateral: Vector2 = to_player_dir.rotated(PI * 0.5 * _strafe_sign) * 0.30
	var speed_mult: float = status_effects.get_speed_multiplier()
	if distance > attack_range_px * 0.72:
		velocity = (to_backstab.normalized() + lateral).normalized() * movement_speed_px * 0.95 * speed_mult
		return
	velocity = (to_backstab.normalized() * 0.70 + lateral).normalized() * movement_speed_px * 0.48 * speed_mult
	_try_skirmisher_attack((_player.global_position - global_position).normalized())

func _try_melee_attack(melee_range: float) -> void:
	if _attack_timer > 0.0 or _post_attack_lock_timer > 0.0 or _player == null or _is_winding_up():
		return
	if global_position.distance_to(_player.global_position) > melee_range:
		return
	_begin_attack_windup("melee", melee_range, _player.global_position, Vector2.ZERO)

func _try_ranged_attack() -> void:
	if _attack_timer > 0.0 or _post_attack_lock_timer > 0.0 or _player == null or _is_winding_up():
		return
	_begin_attack_windup("ranged", max(72.0, attack_range_px * 0.32), _predict_player_position(LEAD_CAST_DISTANCE_PX), Vector2.ZERO)

func _try_skirmisher_attack(direction: Vector2) -> void:
	if _attack_timer > 0.0 or _post_attack_lock_timer > 0.0 or _player == null or _is_winding_up():
		return
	_begin_attack_windup("skirmisher", 96.0, _predict_player_position(LEAD_CAST_DISTANCE_PX), direction.normalized())

func _begin_attack_windup(attack_type: String, attack_range: float, target_position: Vector2, direction: Vector2) -> void:
	_pending_attack_type = attack_type
	_pending_attack_range = attack_range
	_pending_attack_position = target_position
	_pending_attack_direction = direction
	_windup_total = _get_windup_duration(attack_type)
	_windup_timer = _windup_total
	_windup_elapsed = 0.0
	_attack_timer = attack_interval
	velocity = Vector2.ZERO
	_set_windup_visual(true)
	if attack_type == "melee" and _is_orc_enemy():
		_play_sprite_action("attack", MELEE_WINDUP_SECONDS + 0.05)
	_spawn_attack_windup_vfx(attack_type, target_position, attack_range, direction)

func _update_attack_windup(delta: float) -> bool:
	if _windup_timer <= 0.0:
		return false
	_windup_elapsed += delta
	_windup_timer -= delta
	if _pending_attack_type == "melee" and _windup_elapsed < MELEE_TRACKING_SECONDS and _player != null and is_instance_valid(_player):
		var to_player: Vector2 = _player.global_position - global_position
		if to_player.length() <= _pending_attack_range + 16.0 and to_player.length_squared() > 0.001:
			velocity = to_player.normalized() * movement_speed_px * 0.35 * status_effects.get_speed_multiplier()
		else:
			velocity = Vector2.ZERO
	elif _pending_attack_type == "ranged" and _is_slime_enemy() and _windup_elapsed < SLIME_ATTACK_MOVE_LOCK_SECONDS and _player != null and is_instance_valid(_player):
		var to_player_slime: Vector2 = _player.global_position - global_position
		var dist_slime: float = to_player_slime.length()
		var dir_slime: Vector2 = to_player_slime.normalized() if to_player_slime.length_squared() > 0.001 else Vector2.RIGHT
		if dist_slime < attack_range_px * SLIME_RETREAT_DISTANCE_FACTOR:
			velocity = -dir_slime * movement_speed_px * SLIME_ATTACK_MOVE_SPEED_MULTIPLIER * status_effects.get_speed_multiplier()
		else:
			velocity = dir_slime.rotated(PI * 0.5 * _strafe_sign) * movement_speed_px * 0.25 * status_effects.get_speed_multiplier()
	elif _pending_attack_type == "skirmisher" and _is_spirit_enemy() and _player != null and is_instance_valid(_player):
		var player_forward: Vector2 = _get_player_move_direction()
		if player_forward.length_squared() <= 0.001:
			player_forward = (_player.global_position - global_position).normalized()
		var back_point: Vector2 = _player.global_position - player_forward.normalized() * SPIRIT_BACKSTAB_DISTANCE_PX
		var to_back: Vector2 = back_point - global_position
		velocity = to_back.normalized() * movement_speed_px * 0.22 * status_effects.get_speed_multiplier() if to_back.length_squared() > 0.001 else Vector2.ZERO
	else:
		velocity = Vector2.ZERO
	if _windup_timer <= 0.0:
		_execute_pending_attack()
		_post_attack_lock_timer = POST_ATTACK_LOCK_SECONDS
		_clear_pending_attack()
	return true

func _get_windup_duration(attack_type: String) -> float:
	match attack_type:
		"ranged":
			return AREA_ABILITY_TELEGRAPH_SECONDS
		"skirmisher":
			return POINT_ABILITY_TELEGRAPH_SECONDS
		_:
			return MELEE_WINDUP_SECONDS

func _execute_pending_attack() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	match _pending_attack_type:
		"melee":
			_execute_melee_attack()
		"ranged":
			_execute_ranged_attack()
		"skirmisher":
			_execute_skirmisher_attack()
		_:
			pass

func _get_enemy_damage_source_type(default_source_type: String = DamagePayload.SOURCE_FRIENDLY_FIRE) -> String:
	if not weak_mob_abilities.is_empty():
		return DamagePayload.SOURCE_WEAK_MOB_ABILITY_DAMAGE
	return default_source_type

func _execute_melee_attack() -> void:
	_spawn_enemy_attack_impact(global_position, _pending_attack_range, "melee")
	if global_position.distance_to(_player.global_position) > _pending_attack_range + 8.0:
		return
	var payload: DamagePayload = CombatSystem.build_payload(attack_damage, "physical", enemy_id, faction_id, "", _get_enemy_damage_source_type(DamagePayload.SOURCE_FRIENDLY_FIRE))
	payload.can_trigger_secondary_effects = false
	payload.can_trigger_boss_abilities = false
	payload.can_trigger_reactions = false
	payload.can_apply_reaction_prerequisites = false
	payload.normalize_source_type()
	CombatSystem.apply_damage(_player, payload)

func _execute_ranged_attack() -> void:
	_spawn_water_puddle(_pending_attack_position)
	_spawn_enemy_attack_impact(_pending_attack_position, max(64.0, _pending_attack_range), "ranged")
	# The windup makes the ranged hit dodgeable: damage is only applied if the player is still in the telegraphed spot.
	if _player.global_position.distance_to(_pending_attack_position) > max(64.0, _pending_attack_range):
		return
	var payload: DamagePayload = CombatSystem.build_payload(max(4.0, attack_damage * 0.75), "magical", enemy_id, faction_id, "", _get_enemy_damage_source_type(DamagePayload.SOURCE_BOSS_AI_ABILITY_DAMAGE))
	payload.can_trigger_secondary_effects = false
	payload.can_trigger_boss_abilities = false
	payload.can_trigger_reactions = false
	payload.can_apply_reaction_prerequisites = false
	payload.normalize_source_type()
	CombatSystem.apply_damage(_player, payload)

func _execute_skirmisher_attack() -> void:
	var dir: Vector2 = _pending_attack_direction
	if dir.length_squared() <= 0.001:
		dir = (_player.global_position - global_position).normalized()
	_spawn_enemy_attack_impact(global_position, 86.0, "skirmisher")
	global_position += dir.normalized() * 86.0
	if global_position.distance_to(_player.global_position) <= _pending_attack_range:
		var payload: DamagePayload = CombatSystem.build_payload(attack_damage, "magical", enemy_id, faction_id, "", _get_enemy_damage_source_type(DamagePayload.SOURCE_FRIENDLY_FIRE))
		payload.can_trigger_secondary_effects = false
		payload.can_trigger_boss_abilities = false
		payload.can_trigger_reactions = false
		payload.can_apply_reaction_prerequisites = false
		payload.normalize_source_type()
		CombatSystem.apply_damage(_player, payload)
	_strafe_sign *= -1.0

func _clear_pending_attack() -> void:
	_windup_timer = 0.0
	_windup_elapsed = 0.0
	_windup_total = 0.0
	_pending_attack_type = ""
	_pending_attack_range = 0.0
	_pending_attack_position = Vector2.ZERO
	_pending_attack_direction = Vector2.ZERO
	_set_windup_visual(false)

func _is_winding_up() -> bool:
	return _windup_timer > 0.0

func _set_windup_visual(active: bool) -> void:
	var target_color: Color = Color(1.0, 0.55, 0.35, 1.0) if active else _base_visual_color
	if visual != null:
		visual.modulate = target_color
	if _sprite_visual != null and is_instance_valid(_sprite_visual):
		_sprite_visual.modulate = target_color

func _spawn_attack_windup_vfx(attack_type: String, target_position: Vector2, attack_range: float, direction: Vector2) -> void:
	var windup_duration: float = _get_windup_duration(attack_type)
	match attack_type:
		"ranged":
			_spawn_draw_effect("telegraph_circle", target_position, max(64.0, attack_range), Vector2.RIGHT, attack_range, Color(1.0, 0.35, 0.18, 0.82), windup_duration, TAU)
		"skirmisher":
			var dir: Vector2 = direction.normalized() if direction.length_squared() > 0.001 else Vector2.RIGHT
			_spawn_draw_effect("telegraph_line", global_position, 16.0, dir, 96.0, Color(1.0, 0.55, 0.18, 0.82), windup_duration, 0.0)
		_:
			_spawn_draw_effect("telegraph_circle", global_position, attack_range, Vector2.RIGHT, attack_range, Color(1.0, 0.42, 0.22, 0.72), windup_duration, TAU)

func _spawn_enemy_attack_impact(origin: Vector2, radius: float, attack_type: String) -> void:
	match attack_type:
		"ranged":
			_spawn_draw_effect("impact", origin, min(radius, 72.0), Vector2.RIGHT, radius, Color(0.45, 0.75, 1.0, 0.80), 0.24, TAU)
			_spawn_sequence_effect(_effect_id_for_enemy(), origin, 0.32, max(0.65, radius / 80.0), 0.0, Color(0.75, 0.90, 1.0, 0.94))
		"skirmisher":
			var dir: Vector2 = _pending_attack_direction.normalized() if _pending_attack_direction.length_squared() > 0.001 else Vector2.RIGHT
			_spawn_draw_effect("line", origin, 14.0, dir, 96.0, Color(1.0, 0.65, 0.22, 0.85), 0.22, 0.0)
			_spawn_sequence_effect(_effect_id_for_enemy(), origin + dir * 46.0, 0.26, 0.75, dir.angle(), Color(0.92, 0.74, 1.0, 0.96))
		_:
			_spawn_draw_effect("impact", origin, max(18.0, radius), Vector2.RIGHT, radius, Color(1.0, 0.50, 0.22, 0.82), 0.22, TAU)
			_spawn_sequence_effect("enemy_slash", origin, 0.22, 0.55, 0.0, Color(1.0, 0.78, 0.58, 0.94))

func _spawn_draw_effect(mode: String, origin: Vector2, radius: float, direction: Vector2, range_px: float, effect_color: Color, duration: float, angle_rad: float) -> void:
	var script: Script = load(DRAW_EFFECT_SCRIPT) as Script
	if script == null:
		return
	var effect: Node2D = script.new() as Node2D
	if effect == null:
		return
	var current: Node = get_tree().current_scene
	if current == null:
		return
	current.add_child(effect)
	effect.global_position = origin
	if effect.has_method("setup"):
		effect.call("setup", mode, radius, direction, range_px, effect_color, duration, angle_rad)

func _spawn_sequence_effect(effect_id: String, origin: Vector2, duration: float, scale_value: float, rotation_value: float = 0.0, tint: Color = Color.WHITE) -> void:
	var script: Script = load("res://scripts/visuals/sequence_sprite_effect.gd") as Script
	if script == null:
		return
	var effect: Node2D = script.new() as Node2D
	if effect == null:
		return
	var current: Node = get_tree().current_scene
	if current == null:
		effect.queue_free()
		return
	current.add_child(effect)
	effect.global_position = origin
	if effect.has_method("setup_from_paths"):
		var ok: bool = bool(effect.call("setup_from_paths", ShadowCoreAssetPaths.effect_sequence(effect_id), duration, scale_value, rotation_value, tint, Vector2.ZERO, 55))
		if not ok:
			effect.queue_free()

func _effect_id_for_enemy() -> String:
	match enemy_id:
		"ENEMY_PR_FIRE_SLIME":
			return "fire"
		"ENEMY_PR_POISON_SLIME":
			return "poison"
		"ENEMY_EF_AIR_SPIRIT":
			return "wind"
		"ENEMY_EF_LIGHTNING_SPIRIT":
			return "lightning"
		"ENEMY_EF_VOID_SPIRIT":
			return "void"
		_:
			return "water"

func _predict_player_position(lead_distance_px: float) -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return global_position
	var predicted: Vector2 = _player.global_position
	var move_dir: Vector2 = Vector2.ZERO
	if _player.has_method("get_current_move_direction"):
		move_dir = _player.call("get_current_move_direction")
	elif _player is CharacterBody2D:
		move_dir = (_player as CharacterBody2D).velocity.normalized() if (_player as CharacterBody2D).velocity.length_squared() > 1.0 else Vector2.ZERO
	if move_dir.length_squared() > 0.001:
		predicted += move_dir.normalized() * max(0.0, lead_distance_px)
	return predicted

func _spawn_water_puddle(position: Vector2) -> void:
	var scene: PackedScene = load(WATER_PUDDLE_SCENE) as PackedScene
	if scene == null:
		return
	var zone: Node2D = scene.instantiate() as Node2D
	if zone == null:
		return
	var current: Node = get_tree().current_scene
	if current == null:
		zone.queue_free()
		return
	current.add_child(zone)
	zone.global_position = position
	if zone.has_method("setup"):
		zone.call_deferred("setup", 25.0, 64.0, 2.25)

func apply_damage(payload: DamagePayload) -> void:
	health_component.damage(payload.amount, payload)

func apply_slow_status(status_id: String, slow_percent: float, duration: float) -> void:
	status_effects.apply_slow(status_id, slow_percent, duration)

func apply_periodic_status(status_id: String, total_damage: float, duration: float, payload: DamagePayload) -> void:
	status_effects.apply_periodic_damage(status_id, total_damage, duration, payload)

func _on_died(_payload: DamagePayload) -> void:
	EventBus.enemy_died.emit(enemy_id, faction_id, creature_type_id, essence_amount)
	EventBus.enemy_died_with_position.emit(enemy_id, faction_id, creature_type_id, essence_amount, global_position)
	queue_free()


func _setup_sprite_visual() -> void:
	if _sprite_visual != null and is_instance_valid(_sprite_visual) and _visual_enemy_id == enemy_id:
		return
	if _sprite_visual != null and is_instance_valid(_sprite_visual):
		_sprite_visual.queue_free()
		_sprite_visual = null
	_visual_enemy_id = enemy_id
	_sprite_visual = SpriteSheetAnimator.new()
	_sprite_visual.name = "SpriteVisual"
	_sprite_visual.position = Vector2(0, -8)
	_sprite_visual.scale = Vector2.ONE * 1.0
	add_child(_sprite_visual)
	move_child(_sprite_visual, 0)
	var paths: Dictionary = ShadowCoreAssetPaths.enemy_animation_paths(enemy_id)
	var loaded: bool = false
	loaded = _add_enemy_anim("idle", paths, 4.0, true) or loaded
	loaded = _add_enemy_anim("walk", paths, 4.4, true) or loaded
	loaded = _add_enemy_anim("run", paths, 4.2, true) or loaded
	loaded = _add_enemy_anim("attack", paths, 5.0, false) or loaded
	loaded = _add_enemy_anim("hurt", paths, 4.0, false) or loaded
	loaded = _add_enemy_anim("death", paths, 4.0, false) or loaded
	if loaded:
		if visual != null:
			visual.visible = false
		_sprite_visual.play_if_available("idle")
	else:
		_sprite_visual.queue_free()
		_sprite_visual = null

func _add_enemy_anim(anim_name: String, paths: Dictionary, fps: float, loop: bool) -> bool:
	if _sprite_visual == null or not is_instance_valid(_sprite_visual):
		return false
	var grid: Vector2i = ShadowCoreAssetPaths.enemy_animation_grid(enemy_id, anim_name)
	return _sprite_visual.add_sheet_animation(anim_name, str(paths.get(anim_name, "")), fps, loop, grid.x, grid.y, 0)

func _play_sprite_action(anim_name: String, lock_seconds: float = 0.22) -> void:
	if _sprite_visual == null or not is_instance_valid(_sprite_visual):
		return
	if _sprite_visual.play_if_available(anim_name):
		_visual_action_lock = max(_visual_action_lock, lock_seconds)

func _update_sprite_visual(delta: float) -> void:
	if _sprite_visual == null or not is_instance_valid(_sprite_visual):
		return
	if _player != null and is_instance_valid(_player):
		var dx: float = _player.global_position.x - global_position.x
		if dx < -2.0:
			_sprite_visual.flip_h = true
		elif dx > 2.0:
			_sprite_visual.flip_h = false
	_visual_action_lock = max(0.0, _visual_action_lock - delta)
	if _visual_action_lock > 0.0:
		return
	if velocity.length() > movement_speed_px * 0.72:
		_sprite_visual.play_if_available("run")
	elif velocity.length() > 5.0:
		_sprite_visual.play_if_available("walk")
	else:
		_sprite_visual.play_if_available("idle")

func _apply_visual_from_data() -> void:
	_setup_sprite_visual()
	if visual == null and _sprite_visual == null:
		return
	var faction_id_local: String = str(data.get("faction_id", ""))
	var tint: Color = _base_visual_color
	match faction_id_local:
		"FACTION_KRUSHERS":
			tint = Color(0.82, 0.20, 0.12, 1.0)
		"FACTION_NATURE":
			tint = Color(0.12, 0.72, 0.42, 1.0)
		"FACTION_ETHERS":
			tint = Color(0.70, 0.52, 1.0, 1.0)
		_:
			tint = _base_visual_color
	if visual != null:
		visual.modulate = tint
		_base_visual_color = visual.modulate
	elif _sprite_visual != null and is_instance_valid(_sprite_visual):
		_base_visual_color = tint
	if _sprite_visual != null and is_instance_valid(_sprite_visual):
		_sprite_visual.modulate = Color.WHITE if faction_id_local != "FACTION_ETHERS" else Color(0.86, 0.78, 1.0, 1.0)
	var hp_value: float = float(data.get("base_stats", {}).get("hp", 40.0))
	# Patch S: increase ordinary enemy models by about 20% while keeping collision/movement scale stable.
	var visual_scale: float = clamp((0.98 + hp_value / 120.0) * 1.20, 1.25, 1.95)
	if str(data.get("id", "")).contains("COMMANDER") or str(data.get("id", "")).contains("VOID"):
		visual_scale += 0.10
	scale = Vector2.ONE
	if _sprite_visual != null and is_instance_valid(_sprite_visual):
		_sprite_visual.scale = Vector2.ONE * visual_scale
	if visual != null:
		visual.scale = Vector2.ONE * visual_scale

func _is_slime_enemy() -> bool:
	return enemy_id.find("SLIME") != -1 or creature_type_id.find("SLIME") != -1

func _is_spirit_enemy() -> bool:
	return enemy_id.find("SPIRIT") != -1 or creature_type_id.find("SPIRIT") != -1

func _is_orc_enemy() -> bool:
	return enemy_id.find("ORC") != -1 or creature_type_id.find("ORC") != -1

func _get_player_move_direction() -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return Vector2.ZERO
	if _player.has_method("get_current_move_direction"):
		var d: Vector2 = _player.call("get_current_move_direction")
		return d.normalized() if d.length_squared() > 0.001 else Vector2.ZERO
	if _player is CharacterBody2D:
		var body: CharacterBody2D = _player as CharacterBody2D
		return body.velocity.normalized() if body.velocity.length_squared() > 1.0 else Vector2.ZERO
	return Vector2.ZERO

func _get_orc_surround_velocity(distance: float, to_player: Vector2, melee_range: float) -> Vector2:
	var dir_to_player: Vector2 = to_player.normalized() if to_player.length_squared() > 0.001 else Vector2.RIGHT
	var speed_mult: float = status_effects.get_speed_multiplier()
	var preferred_angle: float = float(get_instance_id() % 628) / 100.0
	var ring_radius: float = clampf(melee_range * 0.92, 42.0, 72.0)
	var desired_point: Vector2 = _player.global_position + Vector2(cos(preferred_angle), sin(preferred_angle)) * ring_radius
	var to_slot: Vector2 = desired_point - global_position
	var slot_velocity: Vector2 = to_slot.normalized() * movement_speed_px if to_slot.length() > 6.0 else Vector2.ZERO
	var separation: Vector2 = _get_orc_separation_force(distance)
	var combined: Vector2 = slot_velocity + separation * movement_speed_px
	if distance > melee_range * 1.25:
		combined += dir_to_player * movement_speed_px * 0.65
	if combined.length_squared() <= 0.001:
		return Vector2.ZERO
	return combined.normalized() * movement_speed_px * speed_mult

func _get_orc_separation_force(distance_to_player: float) -> Vector2:
	var force: Vector2 = Vector2.ZERO
	var preferred_sep: float = lerpf(ORC_MIN_SEPARATION_PX, ORC_MAX_SEPARATION_PX, clampf(distance_to_player / ORC_MAX_SEPARATION_DISTANCE_PX, 0.0, 1.0))
	for node in get_tree().get_nodes_in_group("enemies"):
		var other: Node2D = node as Node2D
		if other == null or other == self or not is_instance_valid(other):
			continue
		if not other.has_method("get_enemy_family") or str(other.call("get_enemy_family")) != "orc":
			continue
		var away: Vector2 = global_position - other.global_position
		var d: float = away.length()
		if d > 0.01 and d < preferred_sep:
			force += away.normalized() * ((preferred_sep - d) / preferred_sep)
	return force

func get_enemy_family() -> String:
	if _is_orc_enemy():
		return "orc"
	if _is_slime_enemy():
		return "slime"
	if _is_spirit_enemy():
		return "spirit"
	return "other"

func _get_player() -> Node2D:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D

func _damage_from_profile(profile: String) -> float:
	if profile.contains("высок"):
		return 16.0
	if profile.contains("средний"):
		return 10.0
	return 7.0
