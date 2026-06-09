extends Node

const PIXELS_PER_METER: float = 48.0
const RANGE_INDICATOR_SCRIPT: String = "res://scripts/effects/ability_range_indicator.gd"
const DRAW_EFFECT_SCRIPT: String = "res://scripts/effects/simple_draw_effect.gd"
const DAGGER_PROJECTILE_SCRIPT: String = "res://scripts/effects/dagger_projectile_vfx.gd"
const DAGGER_PROJECTILE_SPEED_PX: float = 416.0 # Patch S: previous visual speed reduced by 20%.
const QUICK_TARGET_SEARCH_MULTIPLIER: float = 1.35

var _player: Node2D = null
var _cooldowns: Dictionary = {}
var _durations: Dictionary = {}
var _target_indicator: Node2D = null
var _targeting_slot: String = ""
var _targeting_direction: Vector2 = Vector2.RIGHT
var _targeting_canceled: bool = false


func _get_event_bus() -> Node:
	return get_node_or_null("/root/EventBus")

func _safe_connect_signal(source: Object, signal_name: StringName, target: Callable) -> void:
	if source == null:
		return
	if not source.has_signal(signal_name):
		return
	if source.is_connected(signal_name, target):
		return
	source.connect(signal_name, target)

func _emit_event_bus(signal_name: StringName, args: Array = []) -> void:
	var bus: Node = _get_event_bus()
	if bus == null:
		return
	if not bus.has_signal(signal_name):
		return
	var call_args: Array = [signal_name]
	call_args.append_array(args)
	bus.callv("emit_signal", call_args)

func _ready() -> void:
	var bus: Node = _get_event_bus()
	_safe_connect_signal(bus, &"ability_button_pressed", Callable(self, "request_cast"))
	_safe_connect_signal(bus, &"ability_targeting_started", Callable(self, "_on_ability_targeting_started"))
	_safe_connect_signal(bus, &"ability_targeting_changed", Callable(self, "_on_ability_targeting_changed"))
	_safe_connect_signal(bus, &"ability_targeting_finished", Callable(self, "_on_ability_targeting_finished"))

func reset_run() -> void:
	_cooldowns.clear()
	_durations.clear()
	_hide_target_indicator()
	_emit_known_cooldowns_reset()

func reset_cooldowns_for_new_encounter() -> void:
	for slot in _cooldowns.keys():
		_cooldowns[slot] = 0.0
	_hide_target_indicator()
	_emit_known_cooldowns_reset()

func register_player(player: Node2D) -> void:
	_player = player
	reset_run()

func _process(delta: float) -> void:
	if _is_developer_zero_cooldown():
		for slot in ["active_1", "active_2", "ultimate"]:
			_cooldowns[slot] = 0.0
			_emit_event_bus(&"ability_cooldown_changed", [slot, 0.0, float(_durations.get(slot, 0.0))])
		return
	for slot in _cooldowns.keys():
		_cooldowns[slot] = max(0.0, float(_cooldowns[slot]) - delta)
		_emit_event_bus(&"ability_cooldown_changed", [slot, float(_cooldowns[slot]), float(_durations.get(slot, 0.0))])

func request_cast(slot: String, direction_override: Vector2 = Vector2.ZERO) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var dev_zero_cooldown: bool = _is_developer_zero_cooldown()
	if not dev_zero_cooldown and float(_cooldowns.get(slot, 0.0)) > 0.0:
		return
	var ability: Dictionary = DataRegistry.get_hero_ability(RunManager.current_hero_id, slot)
	if ability.is_empty():
		return
	var cooldown: float = 0.0 if dev_zero_cooldown else float(ability.get("cooldown_seconds", 0.0))
	_cooldowns[slot] = cooldown
	_durations[slot] = float(ability.get("cooldown_seconds", 0.0))
	_emit_event_bus(&"ability_cooldown_changed", [slot, cooldown, float(_durations.get(slot, cooldown))])
	var cast_direction: Vector2 = direction_override
	if cast_direction.length_squared() <= 0.001:
		cast_direction = _get_auto_target_direction(slot, ability)
	else:
		cast_direction = cast_direction.normalized()
	var context: EffectTriggerContext = EffectTriggerContext.new()
	context.caster = _player
	context.ability_id = ability.get("id", "")
	context.hit_position = _player.global_position
	context.damage_payload = null
	# BossAbilitySystem v0.13 applies only on active hits. Cast-side secondary effect hooks are disabled.
	match slot:
		"active_1":
			_cast_kael_shadow_dagger(ability, cast_direction)
		"active_2":
			_cast_kael_shadow_scythe(ability, cast_direction)
		"ultimate":
			_cast_kael_shadow_rupture(ability, cast_direction)
		_:
			pass

func _cast_kael_shadow_dagger(ability: Dictionary, direction: Vector2) -> void:
	_play_player_cast_animation(0.20)
	if direction.length_squared() <= 0.001:
		direction = _get_auto_target_direction("active_1", ability)
	direction = direction.normalized()
	var origin: Vector2 = _player.global_position
	var range_px: float = _get_ability_range(ability, 288.0)
	var bounce_range: float = float(ability.get("bounce_range_px", 168.0)) * _get_ability_range_multiplier()
	var power_level: int = _get_ability_power_level(str(ability.get("id", "")))
	var damage_table: Array = [34.0, 45.0, 58.0]
	var second_damage_table: Array = [22.0, 30.0, 40.0]
	var first_slow_table: Array = [40.0, 45.0, 50.0]
	var second_slow_table: Array = [15.0, 20.0, 25.0]
	var index: int = clampi(power_level - 1, 0, 2)
	var first: Node2D = _find_first_enemy_in_line(origin, direction, range_px, 28.0)
	var end_pos: Vector2 = first.global_position if first != null and is_instance_valid(first) else origin + direction * range_px
	var flight_time: float = _spawn_dagger_projectile_vfx(origin, end_pos, direction)
	if flight_time > 0.0:
		await get_tree().create_timer(flight_time).timeout
	if first == null or not is_instance_valid(first):
		return
	_hit_enemy(first, ability, _scale_damage(float(damage_table[index])), false)
	if first.has_method("apply_slow_status"):
		first.apply_slow_status("kael_dagger_first_slow", float(first_slow_table[index]), 3.0)
	var second: Node2D = _find_nearest_enemy(first.global_position, bounce_range, first)
	if second != null:
		var bounce_time: float = _spawn_dagger_projectile_vfx(first.global_position, second.global_position, (second.global_position - first.global_position).normalized())
		if bounce_time > 0.0:
			await get_tree().create_timer(bounce_time).timeout
		if second != null and is_instance_valid(second):
			_hit_enemy(second, ability, _scale_damage(float(second_damage_table[index])), false)
			if second.has_method("apply_slow_status"):
				second.apply_slow_status("kael_dagger_second_slow", float(second_slow_table[index]), 3.0)

func _cast_kael_shadow_scythe(ability: Dictionary, direction: Vector2) -> void:
	_play_player_cast_animation(0.28)
	var origin: Vector2 = _player.global_position
	if direction.length_squared() <= 0.001:
		direction = _get_player_direction()
	var range_px: float = _get_ability_range(ability, 216.0)
	var damage: float = _get_ability_damage(ability, 30.0)
	_spawn_scythe_vfx(origin, direction, range_px)
	var targets: Array = _get_enemies_in_cone(origin, direction.normalized(), range_px, deg_to_rad(float(ability.get("angle_degrees", 100.0))))
	for enemy in targets:
		_hit_enemy(enemy, ability, damage, false)
		if enemy.has_method("apply_slow_status"):
			enemy.apply_slow_status("kael_scythe_slow", 15.0, 1.5)

func _cast_kael_shadow_rupture(ability: Dictionary, direction: Vector2) -> void:
	_play_player_cast_animation(0.30)
	if direction.length_squared() <= 0.001:
		direction = _get_player_direction()
	direction = direction.normalized()
	var cast_range: float = _get_ability_range(ability, float(ability.get("range_px", 72.0)))
	var cast_position: Vector2 = _player.global_position + direction * cast_range
	var damage: float = _get_ability_damage(ability, 38.0)
	var radius: float = _get_ability_radius(ability, 115.0)
	var delay: float = float(ability.get("delay_seconds", 0.6))
	_spawn_shadow_rupture_telegraph(cast_position, radius, delay)
	await get_tree().create_timer(delay).timeout
	if _player == null or not is_instance_valid(_player):
		return
	var targets: Array = _get_enemies_in_radius(cast_position, radius)
	_spawn_impact_vfx(cast_position, radius * 0.50, Color(0.72, 0.38, 1.0, 0.95), 0.30)
	for enemy in targets:
		_hit_enemy(enemy, ability, damage, false)

func _hit_enemy(enemy: Node2D, ability: Dictionary, damage: float, _is_ultimate: bool) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var payload: DamagePayload = CombatSystem.build_payload(
		damage,
		_normalize_damage_type(str(ability.get("damage_type", "physical"))),
		str(ability.get("id", "")),
		"",
		str(ability.get("id", "")),
		DamagePayload.SOURCE_DIRECT_ACTIVE_HIT
	)
	payload.can_trigger_secondary_effects = true
	payload.can_trigger_boss_abilities = true
	payload.can_trigger_reactions = true
	payload.can_apply_reaction_prerequisites = true
	payload.is_ultimate = false
	payload.add_effect_tag("direct_active_hit")
	payload.add_effect_tag(str(ability.get("slot", "active_ability")))
	CombatSystem.apply_damage(enemy, payload)
	var context: EffectTriggerContext = EffectTriggerContext.new()
	context.caster = _player
	context.target = enemy
	context.ability_id = str(ability.get("id", ""))
	context.active_ability_id = _normalize_active_slot_id(ability)
	context.hit_position = enemy.global_position
	context.damage_payload = payload
	var boss_ability_system: Node = get_node_or_null("/root/BossAbilitySystem")
	if boss_ability_system != null and boss_ability_system.has_method("apply_effect_on_active_hit"):
		boss_ability_system.call("apply_effect_on_active_hit", context)
	_spawn_impact_vfx(enemy.global_position, 20.0, Color(0.7, 0.45, 1.0, 0.85), 0.18)

func _normalize_active_slot_id(ability: Dictionary) -> String:
	var slot: String = str(ability.get("slot", ""))
	if slot == "ultimate":
		return "third_ability"
	return slot

func _get_auto_target_direction(slot: String, ability: Dictionary) -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return Vector2.RIGHT
	var origin: Vector2 = _player.global_position
	var search_radius: float = _get_ability_range(ability, float(ability.get("range_px", 180.0))) * QUICK_TARGET_SEARCH_MULTIPLIER
	if slot == "ultimate":
		# Patch U: quick tap on the third ability aims toward the nearest enemy even
		# when the enemy is outside cast range; the actual cast is clamped to range.
		search_radius = 999999.0
	var best: Node2D = null
	var best_dist_sq: float = search_radius * search_radius
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Node2D = node as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var dist_sq: float = origin.distance_squared_to(enemy.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = enemy
	if best != null and is_instance_valid(best):
		var dir: Vector2 = best.global_position - origin
		if dir.length_squared() > 0.001:
			return dir.normalized()
	return _get_player_direction()

func _get_player_direction() -> Vector2:
	if _player != null and _player.has_method("get_aim_direction"):
		return _player.get_aim_direction()
	return Vector2.RIGHT

func _get_enemies_in_radius(origin: Vector2, radius: float) -> Array:
	var result: Array = []
	var radius_sq: float = radius * radius
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Node2D = node as Node2D
		if enemy != null and is_instance_valid(enemy) and origin.distance_squared_to(enemy.global_position) <= radius_sq:
			result.append(enemy)
	return result

func _get_enemies_in_cone(origin: Vector2, direction: Vector2, range_px: float, angle_rad: float) -> Array:
	var result: Array = []
	var half_angle: float = angle_rad * 0.5
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Node2D = node as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var to_enemy: Vector2 = enemy.global_position - origin
		if to_enemy.length() > range_px or to_enemy.length_squared() <= 0.001:
			continue
		var angle: float = abs(direction.angle_to(to_enemy.normalized()))
		if angle <= half_angle:
			result.append(enemy)
	return result

func _find_first_enemy_in_line(origin: Vector2, direction: Vector2, range_px: float, width_px: float) -> Node2D:
	var best: Node2D = null
	var best_forward: float = range_px
	var dir: Vector2 = direction.normalized()
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Node2D = node as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var rel: Vector2 = enemy.global_position - origin
		var forward: float = rel.dot(dir)
		if forward < 0.0 or forward > range_px:
			continue
		var lateral: float = abs(rel.cross(dir))
		if lateral > width_px:
			continue
		if forward < best_forward:
			best_forward = forward
			best = enemy
	return best

func _find_nearest_enemy(origin: Vector2, radius: float, excluded: Node = null) -> Node2D:
	var best: Node2D = null
	var best_dist_sq: float = radius * radius
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy: Node2D = node as Node2D
		if enemy == null or enemy == excluded or not is_instance_valid(enemy):
			continue
		var dist_sq: float = origin.distance_squared_to(enemy.global_position)
		if dist_sq < best_dist_sq:
			best = enemy
			best_dist_sq = dist_sq
	return best

func _on_ability_targeting_started(slot: String, direction: Vector2, _cancel_radius_px: float) -> void:
	if not _slot_uses_hold_targeting(slot):
		return
	if _player == null or not is_instance_valid(_player):
		return
	if float(_cooldowns.get(slot, 0.0)) > 0.0:
		return
	_targeting_slot = slot
	_targeting_direction = direction.normalized() if direction.length_squared() > 0.001 else _get_player_direction()
	_targeting_canceled = false
	_show_target_indicator(slot, _targeting_direction, false)

func _on_ability_targeting_changed(slot: String, direction: Vector2, canceled: bool) -> void:
	if slot != _targeting_slot:
		return
	if direction.length_squared() > 0.001:
		_targeting_direction = direction.normalized()
	_targeting_canceled = canceled
	_update_target_indicator(_targeting_direction, canceled)

func _on_ability_targeting_finished(slot: String, direction: Vector2, canceled: bool) -> void:
	if slot != _targeting_slot:
		return
	if direction.length_squared() > 0.001:
		_targeting_direction = direction.normalized()
	var should_cancel: bool = canceled or _targeting_canceled
	_hide_target_indicator()
	var cast_slot: String = _targeting_slot
	var cast_direction: Vector2 = _targeting_direction
	_targeting_slot = ""
	_targeting_canceled = false
	if should_cancel:
		return
	request_cast(cast_slot, cast_direction)

func _slot_uses_hold_targeting(slot: String) -> bool:
	return slot == "active_1" or slot == "active_2" or slot == "ultimate"

func _is_developer_zero_cooldown() -> bool:
	var dev: Node = get_node_or_null("/root/DeveloperTools")
	return dev != null and bool(dev.get("enabled"))

func _show_target_indicator(slot: String, direction: Vector2, canceled: bool) -> void:
	_hide_target_indicator()
	var ability: Dictionary = DataRegistry.get_hero_ability(RunManager.current_hero_id, slot)
	var script: Script = load(RANGE_INDICATOR_SCRIPT) as Script
	if script == null:
		return
	_target_indicator = script.new() as Node2D
	if _target_indicator == null:
		return
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return
	current_scene.add_child(_target_indicator)
	var mode: String = "cone"
	var range_px: float = _get_ability_range(ability, 200.0)
	var extra_radius: float = 0.0
	match slot:
		"active_1":
			mode = "line"
		"active_2":
			mode = "cone"
		"ultimate":
			mode = "target_area"
			extra_radius = _get_ability_radius(ability, 115.0)
		_:
			mode = "circle"
	if _target_indicator.has_method("setup"):
		_target_indicator.call("setup", _player, mode, range_px, direction, canceled, extra_radius)

func _update_target_indicator(direction: Vector2, canceled: bool) -> void:
	if _target_indicator != null and is_instance_valid(_target_indicator) and _target_indicator.has_method("update_indicator"):
		_target_indicator.call("update_indicator", direction, canceled)

func _hide_target_indicator() -> void:
	if _target_indicator != null and is_instance_valid(_target_indicator):
		_target_indicator.queue_free()
	_target_indicator = null

func _play_player_cast_animation(lock_seconds: float) -> void:
	if _player != null and is_instance_valid(_player) and _player.has_method("play_visual_action"):
		_player.call("play_visual_action", "attack", lock_seconds)

func _spawn_sequence_effect(effect_id: String, origin: Vector2, duration: float, scale_value: float, rotation_value: float = 0.0, tint: Color = Color.WHITE, offset: Vector2 = Vector2.ZERO) -> void:
	var script: Script = load("res://scripts/visuals/sequence_sprite_effect.gd") as Script
	if script == null:
		return
	var effect: Node2D = script.new() as Node2D
	if effect == null:
		return
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		effect.queue_free()
		return
	current_scene.add_child(effect)
	effect.global_position = origin
	if effect.has_method("setup_from_paths"):
		var ok: bool = bool(effect.call("setup_from_paths", ShadowCoreAssetPaths.effect_sequence(effect_id), duration, scale_value, rotation_value, tint, offset, 60))
		if not ok:
			effect.queue_free()

func _spawn_dagger_projectile_vfx(origin: Vector2, end_pos: Vector2, direction: Vector2) -> float:
	var distance: float = max(1.0, origin.distance_to(end_pos))
	var duration: float = clampf(distance / DAGGER_PROJECTILE_SPEED_PX, 0.10, 0.72)
	var script: Script = load(DAGGER_PROJECTILE_SCRIPT) as Script
	if script != null:
		var projectile: Node2D = script.new() as Node2D
		var current_scene: Node = get_tree().current_scene
		if projectile != null and current_scene != null:
			current_scene.add_child(projectile)
			if projectile.has_method("setup"):
				projectile.call("setup", origin, end_pos, duration, 0.55, Color(0.86, 0.70, 1.0, 0.95))
			return duration
	# Fallback: a short tracer if the projectile script is unavailable.
	_spawn_draw_effect("line", origin, 8.0, direction.normalized(), distance, Color(0.82, 0.50, 1.0, 0.65), duration, 0.0)
	return duration

func _spawn_dagger_vfx(origin: Vector2, direction: Vector2, range_px: float, first_target: Node2D) -> void:
	var end_pos: Vector2 = first_target.global_position if first_target != null and is_instance_valid(first_target) else origin + direction.normalized() * range_px
	_spawn_dagger_projectile_vfx(origin, end_pos, direction)

func _spawn_dagger_bounce_vfx(from_position: Vector2, to_position: Vector2) -> void:
	var dir: Vector2 = (to_position - from_position).normalized()
	_spawn_dagger_projectile_vfx(from_position, to_position, dir)

func _spawn_scythe_vfx(origin: Vector2, direction: Vector2, range_px: float) -> void:
	_spawn_draw_effect("slash", origin, range_px * 0.18, direction, range_px, Color(0.62, 0.34, 1.0, 0.92), 0.26, deg_to_rad(105.0))
	_spawn_sequence_effect("scythe_slash", origin + direction.normalized() * (range_px * 0.45), 0.28, max(0.55, range_px / 230.0), direction.angle(), Color(0.86, 0.70, 1.0, 0.95))
	_spawn_draw_effect("cone", origin, range_px * 0.18, direction, range_px, Color(0.38, 0.22, 0.88, 0.30), 0.20, deg_to_rad(100.0))

func _spawn_shadow_rupture_telegraph(origin: Vector2, radius: float, delay: float) -> void:
	_spawn_draw_effect("telegraph_circle", origin, radius, Vector2.RIGHT, radius, Color(0.56, 0.20, 0.88, 0.76), delay, TAU)
	_spawn_sequence_effect("night_core", origin, delay + 0.25, max(0.48, radius / 220.0), 0.0, Color(0.82, 0.56, 1.0, 0.55))

func _spawn_impact_vfx(origin: Vector2, radius: float, effect_color: Color, duration: float) -> void:
	_spawn_draw_effect("impact", origin, radius, Vector2.RIGHT, radius, effect_color, duration, TAU)
	if radius >= 28.0:
		_spawn_sequence_effect("impact_purple", origin, max(duration, 0.22), max(0.45, radius / 72.0), 0.0, effect_color)

func _spawn_draw_effect(mode: String, origin: Vector2, radius: float, direction: Vector2, range_px: float, effect_color: Color, duration: float, angle_rad: float) -> void:
	var script: Script = load(DRAW_EFFECT_SCRIPT) as Script
	if script == null:
		return
	var effect: Node2D = script.new() as Node2D
	if effect == null:
		return
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return
	current_scene.add_child(effect)
	effect.global_position = origin
	if effect.has_method("setup"):
		effect.call("setup", mode, radius, direction, range_px, effect_color, duration, angle_rad)

func _emit_known_cooldowns_reset() -> void:
	for slot in ["active_1", "active_2", "ultimate"]:
		_emit_event_bus(&"ability_cooldown_changed", [slot, 0.0, float(_durations.get(slot, 0.0))])

func _get_ability_damage(ability: Dictionary, fallback: float) -> float:
	return _scale_damage(float(ability.get("base_damage", fallback)))

func _scale_damage(base: float) -> float:
	var stat_upgrades: Node = get_node_or_null("/root/StatUpgradeSystem")
	if stat_upgrades != null and stat_upgrades.has_method("get_attack_multiplier"):
		base *= float(stat_upgrades.call("get_attack_multiplier"))
	var essence_scaling: Node = get_node_or_null("/root/EssenceAutoScaling")
	if essence_scaling != null and essence_scaling.has_method("get_ability_damage_multiplier"):
		base *= float(essence_scaling.call("get_ability_damage_multiplier"))
	return base

func _get_ability_range(ability: Dictionary, fallback: float) -> float:
	var base: float = float(ability.get("range_px", fallback))
	base *= _get_ability_range_multiplier()
	return base

func _get_ability_radius(ability: Dictionary, fallback: float) -> float:
	var base: float = float(ability.get("radius_px", ability.get("range_px", fallback)))
	base *= _get_ability_range_multiplier()
	return base

func _get_ability_range_multiplier() -> float:
	var multiplier: float = 1.0
	var stat_upgrades: Node = get_node_or_null("/root/StatUpgradeSystem")
	if stat_upgrades != null and stat_upgrades.has_method("get_ability_range_multiplier"):
		multiplier *= float(stat_upgrades.call("get_ability_range_multiplier"))
	elif stat_upgrades != null and stat_upgrades.has_method("get_range_multiplier"):
		multiplier *= float(stat_upgrades.call("get_range_multiplier"))
	var essence_scaling: Node = get_node_or_null("/root/EssenceAutoScaling")
	if essence_scaling != null and essence_scaling.has_method("get_ability_range_multiplier"):
		multiplier *= float(essence_scaling.call("get_ability_range_multiplier"))
	return multiplier

func _get_ability_power_level(ability_id: String) -> int:
	var boss_ability_system: Node = get_node_or_null("/root/BossAbilitySystem")
	if boss_ability_system != null and boss_ability_system.has_method("get_active_power_level"):
		return int(boss_ability_system.call("get_active_power_level", ability_id))
	return 1

func _normalize_damage_type(raw: String) -> String:
	var lower: String = raw.to_lower()
	if lower.contains("маг") or lower.contains("magic"):
		return "magical"
	return "physical"

func get_state() -> Dictionary:
	return {
		"cooldowns": _cooldowns.duplicate(true),
		"durations": _durations.duplicate(true),
		"targeting_slot": _targeting_slot,
		"targeting_canceled": _targeting_canceled
	}

func set_state(state: Variant = {}) -> void:
	_cooldowns.clear()
	_durations.clear()
	if not (state is Dictionary):
		_emit_known_cooldowns_reset()
		return
	var state_dict: Dictionary = state
	var cooldowns_raw: Variant = state_dict.get("cooldowns", {})
	if cooldowns_raw is Dictionary:
		for key in cooldowns_raw.keys():
			_cooldowns[str(key)] = max(0.0, float(cooldowns_raw[key]))
	var durations_raw: Variant = state_dict.get("durations", {})
	if durations_raw is Dictionary:
		for key in durations_raw.keys():
			_durations[str(key)] = max(0.0, float(durations_raw[key]))
	_targeting_slot = str(state_dict.get("targeting_slot", ""))
	_targeting_canceled = bool(state_dict.get("targeting_canceled", false))
	_emit_known_cooldowns_reset()
