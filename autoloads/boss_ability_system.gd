extends Node

signal boss_ability_unlocked(boss_ability_id: String, level: int)
signal boss_ability_upgraded(boss_ability_id: String, level: int)
signal boss_ability_effect_applied(boss_ability_id: String, level: int, tags: Array, context: Dictionary)

const MAX_LEVEL: int = 3
const ACTIVE_ABILITY_SLOTS: Array[String] = ["active_1", "active_2", "third_ability"]
const LEGACY_ACTIVE_ABILITY_SLOTS: Array[String] = ["ultimate"] # adapter only; UI/state still uses existing Kael ids.
const METERS_TO_PIXELS: float = 48.0

var _levels: Dictionary = {}
var _unlocked: Dictionary = {}
var _cooldowns: Dictionary = {}
var _last_error: String = ""

func reset_run() -> void:
	_levels.clear()
	_unlocked.clear()
	_cooldowns.clear()
	_last_error = ""
	_emit_resource_changed()

func get_ability_data(boss_ability_id: String) -> Dictionary:
	if boss_ability_id.is_empty():
		return {}
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry == null or not registry.has_method("get_boss_ability"):
		return {}
	var data: Variant = registry.call("get_boss_ability", boss_ability_id)
	if data is Dictionary:
		return data
	return {}

func get_boss_abilities(boss_id: String) -> Array:
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_boss_abilities_for_boss"):
		var abilities: Variant = registry.call("get_boss_abilities_for_boss", boss_id)
		if abilities is Array:
			return abilities
	return []

func get_boss_ability_by_index(boss_id: String, ability_index: int) -> Dictionary:
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_boss_ability_by_index"):
		var ability: Variant = registry.call("get_boss_ability_by_index", boss_id, ability_index)
		if ability is Dictionary:
			return ability
	for ability_value in get_boss_abilities(boss_id):
		if ability_value is Dictionary and int(ability_value.get("ability_index", 0)) == ability_index:
			return ability_value
	return {}

func get_boss_abilities_by_creature_type(creature_type_id: String) -> Array:
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_boss_abilities_for_creature_type"):
		var abilities: Variant = registry.call("get_boss_abilities_for_creature_type", creature_type_id)
		if abilities is Array:
			return abilities
	return []

# Backward-compatible alias for older call sites.
func get_boss_abilities_for_creature_type(creature_type_id: String) -> Array:
	return get_boss_abilities_by_creature_type(creature_type_id)

func get_player_version(boss_ability_id: String, level: int) -> Dictionary:
	return get_version_data(boss_ability_id, "player_version", level)

func get_boss_version(boss_ability_id: String, level: int) -> Dictionary:
	return get_version_data(boss_ability_id, "boss_version", level)

func get_weak_mob_version(boss_ability_id: String, level: int) -> Dictionary:
	return get_version_data(boss_ability_id, "weak_mob_version", level)

func get_version_data(boss_ability_id: String, version_name: String, level: int) -> Dictionary:
	if not ["player_version", "boss_version", "weak_mob_version"].has(version_name):
		_last_error = "Invalid boss ability version: " + version_name
		push_warning("BossAbilitySystem.get_version_data(): " + _last_error)
		return {}
	var ability_data: Dictionary = get_ability_data(boss_ability_id)
	return _get_version_level_data(ability_data, version_name, level)

func apply_player_version(boss_ability_id: String, level: int, context) -> bool:
	var ability_data: Dictionary = get_ability_data(boss_ability_id)
	if ability_data.is_empty():
		return false
	var level_data: Dictionary = get_player_version(boss_ability_id, level)
	if level_data.is_empty():
		return false
	return _apply_level_effect(boss_ability_id, ability_data, level_data, context)

func get_current_level(boss_ability_id: String) -> int:
	return get_level(boss_ability_id)

func get_level(boss_ability_id: String) -> int:
	if boss_ability_id.is_empty():
		return 0
	return clampi(int(_levels.get(boss_ability_id, 0)), 0, MAX_LEVEL)

func set_level(boss_ability_id: String, level: int) -> void:
	if boss_ability_id.is_empty():
		return
	var ability_data: Dictionary = get_ability_data(boss_ability_id)
	if ability_data.is_empty():
		_last_error = "Unknown boss ability: " + boss_ability_id
		push_warning("BossAbilitySystem.set_level(): " + _last_error)
		return
	var safe_level: int = clampi(level, 0, MAX_LEVEL)
	if safe_level <= 0:
		_levels.erase(boss_ability_id)
		_unlocked.erase(boss_ability_id)
	else:
		_levels[boss_ability_id] = safe_level
		_unlocked[boss_ability_id] = true
	_emit_resource_changed()

func unlock_ability(boss_ability_id: String) -> bool:
	if boss_ability_id.is_empty():
		_last_error = "Empty boss ability id."
		return false
	if get_ability_data(boss_ability_id).is_empty():
		_last_error = "Unknown boss ability: " + boss_ability_id
		push_warning("BossAbilitySystem.unlock_ability(): " + _last_error)
		return false
	var current_level: int = get_level(boss_ability_id)
	if current_level <= 0:
		_levels[boss_ability_id] = 1
	else:
		_levels[boss_ability_id] = current_level
	_unlocked[boss_ability_id] = true
	boss_ability_unlocked.emit(boss_ability_id, get_level(boss_ability_id))
	_emit_resource_changed()
	return true

func upgrade_ability(boss_ability_id: String) -> bool:
	if boss_ability_id.is_empty():
		_last_error = "Empty boss ability id."
		return false
	if get_ability_data(boss_ability_id).is_empty():
		_last_error = "Unknown boss ability: " + boss_ability_id
		push_warning("BossAbilitySystem.upgrade_ability(): " + _last_error)
		return false
	var current_level: int = get_level(boss_ability_id)
	if current_level >= MAX_LEVEL:
		_last_error = "Boss ability already at max level: " + boss_ability_id
		return false
	var next_level: int = max(1, current_level + 1)
	_levels[boss_ability_id] = next_level
	_unlocked[boss_ability_id] = true
	if current_level <= 0:
		boss_ability_unlocked.emit(boss_ability_id, next_level)
	else:
		boss_ability_upgraded.emit(boss_ability_id, next_level)
	_emit_resource_changed()
	return true

func is_unlocked(boss_ability_id: String) -> bool:
	return bool(_unlocked.get(boss_ability_id, false)) and get_level(boss_ability_id) > 0

func is_max_level(boss_ability_id: String) -> bool:
	return get_level(boss_ability_id) >= MAX_LEVEL

func remove_ability(boss_ability_id: String) -> void:
	if boss_ability_id.is_empty():
		return
	_levels.erase(boss_ability_id)
	_unlocked.erase(boss_ability_id)
	_emit_resource_changed()

func get_current_level_data(boss_ability_id: String) -> Dictionary:
	return _get_level_data(boss_ability_id, get_level(boss_ability_id))

func get_next_level_data(boss_ability_id: String) -> Dictionary:
	var next_level: int = clampi(get_level(boss_ability_id) + 1, 1, MAX_LEVEL)
	if is_max_level(boss_ability_id):
		return {}
	return _get_level_data(boss_ability_id, next_level)

func get_current_description(boss_ability_id: String) -> String:
	var level_data: Dictionary = get_current_level_data(boss_ability_id)
	return str(level_data.get("description_ru", ""))

func get_next_description(boss_ability_id: String) -> String:
	if is_max_level(boss_ability_id):
		return "Максимальный уровень уже достигнут."
	var level_data: Dictionary = get_next_level_data(boss_ability_id)
	return str(level_data.get("description_ru", ""))

func get_next_level_preview(boss_ability_id: String) -> Dictionary:
	var ability: Dictionary = get_ability_data(boss_ability_id)
	if ability.is_empty():
		return {}
	var current_level: int = get_level(boss_ability_id)
	var next_level: int = 0 if current_level >= MAX_LEVEL else max(1, current_level + 1)
	return {
		"boss_ability_id": boss_ability_id,
		"name_ru": str(ability.get("name_ru", boss_ability_id)),
		"current_level": current_level,
		"next_level": next_level,
		"current": get_player_version(boss_ability_id, current_level) if current_level > 0 else {},
		"next": get_player_version(boss_ability_id, next_level) if next_level > 0 else {},
		"icon_path": str(ability.get("icon_path", ""))
	}

func get_tooltip_data(boss_ability_id: String) -> Dictionary:
	var preview: Dictionary = get_next_level_preview(boss_ability_id)
	if preview.is_empty():
		return {}
	var current_data: Dictionary = preview.get("current", {}) if preview.get("current", {}) is Dictionary else {}
	var next_data: Dictionary = preview.get("next", {}) if preview.get("next", {}) is Dictionary else {}
	return {
		"boss_ability_id": boss_ability_id,
		"name_ru": str(preview.get("name_ru", boss_ability_id)),
		"icon_path": str(preview.get("icon_path", "")),
		"current_level": int(preview.get("current_level", 0)),
		"next_level": int(preview.get("next_level", 0)),
		"current_description_ru": str(current_data.get("description_ru", "Не открыта.")),
		"next_description_ru": str(next_data.get("description_ru", "Максимальный уровень уже достигнут.")),
		"effect_tags": _array_duplicate(next_data.get("effect_tags", [])),
		"reaction_tags": _array_duplicate(next_data.get("reaction_tags", []))
	}

func get_upgrade_candidate_ids() -> Array:
	var candidates: Array = []
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry == null or not registry.has_method("get_items"):
		return candidates
	var items: Array = registry.call("get_items", "boss_abilities")
	for item in items:
		if not (item is Dictionary):
			continue
		var ability_id: String = str(item.get("boss_ability_id", item.get("id", "")))
		if ability_id.is_empty():
			continue
		if not is_max_level(ability_id):
			candidates.append(ability_id)
	return candidates

func get_total_level() -> int:
	var total: int = 0
	for key_value in _levels.keys():
		total += get_level(str(key_value))
	return total

func get_active_power_level(_hero_ability_id: String = "") -> int:
	return clampi(1 + int(floor(float(get_total_level()) / 3.0)), 1, 3)

func apply_effect_on_active_hit(context) -> void:
	if context == null:
		return
	if not _is_context_valid_for_boss_ability(context):
		return
	var active_ability_id: String = _resolve_context_active_slot(context)
	if active_ability_id.is_empty():
		return
	var installed_effects: Array = _get_installed_boss_ability_effects_for_active(active_ability_id)
	if installed_effects.is_empty():
		return
	for effect_value in installed_effects:
		if not (effect_value is Dictionary):
			continue
		var effect: Dictionary = effect_value
		var ability_id: String = str(effect.get("boss_ability_id", ""))
		var level: int = int(effect.get("level", get_level(ability_id)))
		if ability_id.is_empty() or level <= 0:
			continue
		apply_player_version(ability_id, level, context)

func get_state() -> Dictionary:
	return {
		"levels": _levels.duplicate(true),
		"unlocked": _unlocked.duplicate(true)
	}

func set_state(state) -> void:
	_levels.clear()
	_unlocked.clear()
	_cooldowns.clear()
	if not (state is Dictionary):
		_emit_resource_changed()
		return
	var level_source: Variant = state.get("levels", state.get("boss_ability_levels", state.get("boss_abilities", {})))
	if level_source is Dictionary:
		for key_value in level_source.keys():
			var ability_id: String = str(key_value)
			var level: int = clampi(int(level_source[key_value]), 0, MAX_LEVEL)
			if not ability_id.is_empty() and level > 0 and not get_ability_data(ability_id).is_empty():
				_levels[ability_id] = level
				_unlocked[ability_id] = true
	var unlocked_source: Variant = state.get("unlocked", {})
	if unlocked_source is Dictionary:
		for key_value in unlocked_source.keys():
			var ability_id: String = str(key_value)
			if bool(unlocked_source[key_value]) and not ability_id.is_empty() and not get_ability_data(ability_id).is_empty():
				_unlocked[ability_id] = true
				if get_level(ability_id) <= 0:
					_levels[ability_id] = 1
	_emit_resource_changed()

func get_last_error() -> String:
	return _last_error

func _get_installed_boss_ability_effects_for_active(active_ability_id: String) -> Array:
	var slot_manager: Node = get_node_or_null("/root/AbilitySlotManager")
	if slot_manager == null or not slot_manager.has_method("get_installed_effects"):
		return []
	var effects: Variant = slot_manager.call("get_installed_effects", active_ability_id)
	if effects is Array:
		return effects
	return []

func _get_installed_boss_ability_ids_for_active(active_ability_id: String) -> Array:
	var result: Array = []
	for effect_value in _get_installed_boss_ability_effects_for_active(active_ability_id):
		if effect_value is Dictionary:
			var ability_id: String = str(effect_value.get("boss_ability_id", ""))
			if not ability_id.is_empty():
				result.append(ability_id)
	return result

func _get_level_data(boss_ability_id: String, level: int) -> Dictionary:
	return get_player_version(boss_ability_id, level)

func _get_version_level_data(ability_data: Dictionary, version_key: String, level: int) -> Dictionary:
	if ability_data.is_empty() or level <= 0:
		return {}
	var version_raw: Variant = ability_data.get(version_key, {})
	if not (version_raw is Dictionary):
		return {}
	var version: Dictionary = version_raw
	var levels_raw: Variant = version.get("levels", {})
	if levels_raw is Dictionary:
		var level_data_raw: Variant = levels_raw.get(str(level), {})
		if level_data_raw is Dictionary:
			var level_data: Dictionary = level_data_raw.duplicate(true)
			level_data["level"] = level
			level_data["version"] = version_key
			level_data["boss_ability_id"] = str(ability_data.get("boss_ability_id", ability_data.get("id", "")))
			level_data["allowed_slots"] = _array_duplicate(version.get("allowed_slots", []))
			level_data["forbidden_slots"] = _array_duplicate(version.get("forbidden_slots", []))
			return level_data
	return {}

func _is_context_valid_for_boss_ability(context) -> bool:
	if context.damage_payload == null:
		return false
	context.damage_payload.normalize_source_type()
	if not _is_source_type_allowed_for_player_version(str(context.damage_payload.source_type)):
		return false
	if not bool(context.damage_payload.can_trigger_boss_abilities):
		return false
	if not bool(context.damage_payload.can_trigger_secondary_effects):
		return false
	if bool(context.damage_payload.is_auto_attack):
		return false
	var ability_id: String = str(context.ability_id)
	if ability_id.is_empty() or _is_auto_attack_ability_id(ability_id):
		return false
	var active_slot: String = _resolve_context_active_slot(context)
	return ACTIVE_ABILITY_SLOTS.has(active_slot)


func _is_source_type_allowed_for_player_version(source_type: String) -> bool:
	match source_type:
		DamagePayload.SOURCE_DIRECT_ACTIVE_HIT:
			return true
		DamagePayload.SOURCE_ZONE_INITIAL_HIT:
			return false
		_:
			return false

func _is_auto_attack_ability_id(ability_id: String) -> bool:
	if ability_id.to_lower().contains("auto"):
		return true
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_ability"):
		var ability: Variant = registry.call("get_ability", ability_id)
		if ability is Dictionary and str(ability.get("slot", "")) == "auto_attack":
			return true
	return false

func _is_active_ability_id(ability_id: String) -> bool:
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry == null or not registry.has_method("get_ability"):
		return true
	var ability: Variant = registry.call("get_ability", ability_id)
	if not (ability is Dictionary):
		return true
	var slot: String = str(ability.get("slot", ""))
	return ACTIVE_ABILITY_SLOTS.has(slot) or LEGACY_ACTIVE_ABILITY_SLOTS.has(slot)

func _resolve_context_active_slot(context) -> String:
	var explicit_slot: String = ""
	if context != null:
		explicit_slot = str(context.get("active_ability_id"))
	if not explicit_slot.is_empty():
		return _normalize_active_slot_id(explicit_slot)
	return _normalize_active_slot_id(str(context.ability_id))

func _normalize_active_slot_id(active_ability_id: String) -> String:
	var raw_id: String = str(active_ability_id).strip_edges()
	if raw_id == "ultimate":
		return "third_ability"
	if ACTIVE_ABILITY_SLOTS.has(raw_id):
		return raw_id
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_ability"):
		var ability: Variant = registry.call("get_ability", raw_id)
		if ability is Dictionary:
			var slot: String = str(ability.get("slot", ""))
			if slot == "ultimate":
				return "third_ability"
			return slot
	return raw_id

func _apply_level_effect(ability_id: String, ability_data: Dictionary, level_data: Dictionary, context) -> bool:
	var target: Node = context.target
	if target == null or not is_instance_valid(target):
		return false
	var effect_data: Dictionary = level_data.get("effect_data", {}) if level_data.get("effect_data", {}) is Dictionary else {}
	if effect_data.is_empty():
		return false
	var tags: Array = _collect_tags(ability_data, level_data)
	var did_apply: bool = false
	if _apply_damage_effects(ability_id, effect_data, context):
		did_apply = true
	if _apply_status_effects(ability_id, effect_data, tags, context):
		did_apply = true
	if did_apply:
		var hit_position: Vector2 = context.hit_position
		if hit_position == Vector2.ZERO and target is Node2D:
			hit_position = (target as Node2D).global_position
		var caster_position: Vector2 = Vector2.ZERO
		if context.caster is Node2D:
			caster_position = (context.caster as Node2D).global_position
		var direction: Vector2 = Vector2.RIGHT
		if hit_position != Vector2.ZERO and caster_position != Vector2.ZERO:
			direction = (hit_position - caster_position).normalized()
		var source_event_id: String = ""
		if context.damage_payload != null:
			source_event_id = str(context.damage_payload.source_event_id)
		boss_ability_effect_applied.emit(ability_id, int(level_data.get("level", 1)), tags, {
			"position": hit_position,
			"caster": context.caster,
			"target": target,
			"direction": direction,
			"hero_ability_id": str(context.ability_id),
			"active_ability_id": _resolve_context_active_slot(context),
			"boss_ability_id": ability_id,
			"level": int(level_data.get("level", 1)),
			"target_id": str(target.get_instance_id()),
			"source_event_id": source_event_id,
			"creature_type_id": str(ability_data.get("creature_type_id", "")),
			"faction_id": str(ability_data.get("faction_id", "")),
			"effect_tags": tags.duplicate(),
			"power_scale": 1.0,
			"visual_spawned": false,
			"version": "player_version"
		})
	return did_apply

func _apply_damage_effects(ability_id: String, effect_data: Dictionary, context) -> bool:
	if context.damage_payload == null or context.target == null or not is_instance_valid(context.target):
		return false
	var base_damage: float = float(context.damage_payload.amount)
	if base_damage <= 0.0:
		return false
	var damage_percent: float = _extract_damage_percent(effect_data)
	if damage_percent <= 0.0:
		return false
	var cooldown_key: String = ability_id + "_damage_" + str(context.target.get_instance_id())
	if not _try_consume_cooldown(cooldown_key, 0.18):
		return false
	var payload: DamagePayload = context.damage_payload.duplicate_payload()
	payload.amount = base_damage * damage_percent / 100.0
	payload.source_id = ability_id
	payload.source_type = DamagePayload.SOURCE_BOSS_ABILITY_DAMAGE
	payload.source_event_id = ""
	payload.event_id = ""
	payload.chain_depth = int(context.damage_payload.chain_depth) + 1
	payload.can_trigger_secondary_effects = false
	payload.can_trigger_boss_abilities = false
	payload.can_trigger_reactions = false
	payload.can_apply_reaction_prerequisites = false
	payload.is_periodic = false
	payload.add_effect_tag("boss_ability_damage")
	payload.normalize_source_type()
	if str(effect_data.keys()).to_lower().contains("fire") or str(effect_data.keys()).to_lower().contains("burn"):
		payload.damage_type = "magical"
	elif str(effect_data.keys()).to_lower().contains("lightning") or str(effect_data.keys()).to_lower().contains("rift"):
		payload.damage_type = "magical"
	CombatSystem.apply_damage(context.target, payload)
	return true

func _apply_status_effects(ability_id: String, effect_data: Dictionary, tags: Array, context) -> bool:
	var target: Node = context.target
	if target == null or not is_instance_valid(target):
		return false
	var applied: bool = false
	var duration: float = _extract_duration(effect_data, 2.5)
	var base_damage: float = float(context.damage_payload.amount) if context.damage_payload != null else 0.0
	var bleed_percent: float = _extract_periodic_percent(effect_data, "bleed")
	if bleed_percent > 0.0 and target.has_method("apply_periodic_status") and context.damage_payload != null:
		var payload: DamagePayload = context.damage_payload.duplicate_payload()
		payload.amount = base_damage * bleed_percent / 100.0
		payload.can_trigger_secondary_effects = false
		payload.can_trigger_boss_abilities = false
		payload.can_trigger_reactions = false
		payload.can_apply_reaction_prerequisites = false
		payload.is_periodic = true
		payload.source_type = DamagePayload.SOURCE_DOT_TICK
		payload.source_event_id = ""
		payload.event_id = ""
		payload.chain_depth = int(context.damage_payload.chain_depth) + 1
		payload.source_id = ability_id + "_bleed"
		payload.normalize_source_type()
		target.call("apply_periodic_status", "boss_bleed", payload.amount, duration, payload)
		applied = true
	var burn_percent: float = _extract_periodic_percent(effect_data, "burn")
	if burn_percent > 0.0 and target.has_method("apply_periodic_status") and context.damage_payload != null:
		var burn_payload: DamagePayload = context.damage_payload.duplicate_payload()
		burn_payload.amount = base_damage * burn_percent / 100.0
		burn_payload.can_trigger_secondary_effects = false
		burn_payload.can_trigger_boss_abilities = false
		burn_payload.can_trigger_reactions = false
		burn_payload.can_apply_reaction_prerequisites = false
		burn_payload.is_periodic = true
		burn_payload.source_type = DamagePayload.SOURCE_DOT_TICK
		burn_payload.source_event_id = ""
		burn_payload.event_id = ""
		burn_payload.chain_depth = int(context.damage_payload.chain_depth) + 1
		burn_payload.source_id = ability_id + "_burn"
		burn_payload.normalize_source_type()
		target.call("apply_periodic_status", "boss_burn", burn_payload.amount, duration, burn_payload)
		applied = true
	var poison_percent: float = _extract_periodic_percent(effect_data, "poison")
	if poison_percent > 0.0 and target.has_method("apply_periodic_status") and context.damage_payload != null:
		var poison_payload: DamagePayload = context.damage_payload.duplicate_payload()
		poison_payload.amount = base_damage * poison_percent / 100.0
		poison_payload.can_trigger_secondary_effects = false
		poison_payload.can_trigger_boss_abilities = false
		poison_payload.can_trigger_reactions = false
		poison_payload.can_apply_reaction_prerequisites = false
		poison_payload.is_periodic = true
		poison_payload.source_type = DamagePayload.SOURCE_DOT_TICK
		poison_payload.source_event_id = ""
		poison_payload.event_id = ""
		poison_payload.chain_depth = int(context.damage_payload.chain_depth) + 1
		poison_payload.source_id = ability_id + "_poison"
		poison_payload.normalize_source_type()
		target.call("apply_periodic_status", "boss_poison", poison_payload.amount, duration, poison_payload)
		applied = true
	var slow_percent: float = _extract_slow_percent(effect_data)
	if slow_percent > 0.0 and target.has_method("apply_slow_status"):
		target.call("apply_slow_status", "boss_slow", slow_percent, duration)
		applied = true
	var armor_reduction: float = float(effect_data.get("armor_reduction_percent_per_stack", 0.0))
	if armor_reduction > 0.0 and target.has_method("apply_armor_reduction_status"):
		target.call("apply_armor_reduction_status", "boss_armor_reduction", armor_reduction, duration)
		applied = true
	var vulnerability: float = float(effect_data.get("additional_physical_damage_taken_percent", effect_data.get("periodic_damage_taken_increase_percent", 0.0)))
	if vulnerability > 0.0 and target.has_method("apply_vulnerability_status"):
		target.call("apply_vulnerability_status", "boss_vulnerability", vulnerability, duration, tags)
		applied = true
	var microstun: float = float(effect_data.get("microstun_seconds_vs_bleeding_target", 0.0))
	if microstun > 0.0 and target.has_method("apply_stun_status"):
		target.call("apply_stun_status", "boss_microstun", microstun)
		applied = true
	return applied

func _extract_damage_percent(effect_data: Dictionary) -> float:
	var best: float = 0.0
	for key_value in effect_data.keys():
		var key: String = str(key_value)
		var lower: String = key.to_lower()
		if lower.contains("damage_percent") or lower.contains("damage_per_second_percent") or lower.contains("lightning_damage_percent") or lower.contains("phantom_damage_percent") or lower.contains("rift_damage_percent") or lower == "damage":
			if lower.contains("taken"):
				continue
			best = max(best, float(effect_data[key_value]))
	return best

func _extract_periodic_percent(effect_data: Dictionary, periodic_type: String) -> float:
	var best: float = 0.0
	for key_value in effect_data.keys():
		var key: String = str(key_value).to_lower()
		if key.contains(periodic_type) and (key.contains("total_damage_percent") or key.contains("damage_per_second_percent")):
			best = max(best, float(effect_data[key_value]))
	return best

func _extract_slow_percent(effect_data: Dictionary) -> float:
	var best: float = 0.0
	for key_value in effect_data.keys():
		var key: String = str(key_value).to_lower()
		if key.contains("slow_percent"):
			best = max(best, float(effect_data[key_value]))
	return best

func _extract_duration(effect_data: Dictionary, fallback: float) -> float:
	var duration: float = fallback
	for key_value in effect_data.keys():
		var key: String = str(key_value).to_lower()
		if key.contains("duration_seconds") or key.contains("duration_sec"):
			duration = max(0.1, float(effect_data[key_value]))
			break
	var essence_scaling: Node = get_node_or_null("/root/EssenceAutoScaling")
	if essence_scaling != null and essence_scaling.has_method("get_dot_duration_multiplier"):
		duration *= float(essence_scaling.call("get_dot_duration_multiplier"))
	return max(0.1, duration)

func _collect_tags(ability_data: Dictionary, level_data: Dictionary) -> Array:
	var result: Array = []
	for tag in _array_duplicate(ability_data.get("reaction_tags", [])):
		_add_unique_tag(result, str(tag))
	for tag in _array_duplicate(level_data.get("reaction_tags", [])):
		_add_unique_tag(result, str(tag))
	for tag in _array_duplicate(level_data.get("effect_tags", [])):
		_add_unique_tag(result, str(tag))
	for tag in _array_duplicate(level_data.get("tags", [])):
		_add_unique_tag(result, str(tag))
	return result

func _array_duplicate(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			result.append(item)
	return result

func _add_unique_tag(result: Array, tag: String) -> void:
	if tag.is_empty():
		return
	if not result.has(tag):
		result.append(tag)

func _try_consume_cooldown(key: String, duration: float) -> bool:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if float(_cooldowns.get(key, -1000.0)) > now:
		return false
	_cooldowns[key] = now + duration
	return true

func _emit_resource_changed() -> void:
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("run_resource_changed"):
		bus.emit_signal("run_resource_changed")
