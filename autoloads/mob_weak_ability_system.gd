extends Node

signal weak_ability_progress_changed(creature_type_id: String, defeat_count: int)
signal weak_abilities_applied(enemy: Node, creature_type_id: String, ability_count: int)

const BASE_STAGE_POWER_SCALE: float = 0.40
const ESCALATED_STAGE_POWER_SCALE: float = 0.50
const DEBUG_META_KEY: String = "shadow_core_mob_weak_debug"

var _boss_defeat_count_by_creature_type: Dictionary = {}
var _boss_defeat_history: Array[String] = []
var _last_applied_enemy_ids: Dictionary = {}
var _debug_enabled: bool = false
var _debug_events: Array[Dictionary] = []

func _ready() -> void:
	_debug_enabled = _is_debug_allowed() and bool(ProjectSettings.get_setting("shadow_core/debug/mob_weak_abilities", false))

func reset_run() -> void:
	_boss_defeat_count_by_creature_type.clear()
	_boss_defeat_history.clear()
	_last_applied_enemy_ids.clear()
	_debug_events.clear()

func get_state() -> Dictionary:
	return {
		"boss_defeat_count_by_creature_type": _boss_defeat_count_by_creature_type.duplicate(true),
		"boss_defeat_history": _boss_defeat_history.duplicate(),
		"debug_enabled": _debug_enabled if _is_debug_allowed() else false
	}

func set_state(state: Variant = {}) -> void:
	reset_run()
	if not (state is Dictionary):
		return
	var state_dict: Dictionary = state
	var counts_raw: Variant = state_dict.get("boss_defeat_count_by_creature_type", {})
	if counts_raw is Dictionary:
		for key_value in counts_raw.keys():
			var creature_type_id: String = str(key_value).strip_edges()
			if not creature_type_id.is_empty():
				_boss_defeat_count_by_creature_type[creature_type_id] = max(0, int(counts_raw[key_value]))
	var history_raw: Variant = state_dict.get("boss_defeat_history", [])
	if history_raw is Array:
		for boss_id_value in history_raw:
			var boss_id: String = str(boss_id_value).strip_edges()
			if not boss_id.is_empty():
				_boss_defeat_history.append(boss_id)
	if _is_debug_allowed():
		_debug_enabled = bool(state_dict.get("debug_enabled", _debug_enabled))

func on_boss_defeated(creature_type_id: String) -> int:
	var clean_id: String = str(creature_type_id).strip_edges()
	if clean_id.is_empty():
		return 0
	var next_count: int = get_defeat_count(clean_id) + 1
	_boss_defeat_count_by_creature_type[clean_id] = next_count
	weak_ability_progress_changed.emit(clean_id, next_count)
	_debug_log("boss_defeated", clean_id, [], {"count": next_count, "stage": get_weak_stage(clean_id), "power_scale": get_weak_power_scale(clean_id)})
	return next_count

func on_boss_defeated_by_boss_id(boss_id: String) -> int:
	var clean_boss_id: String = str(boss_id).strip_edges()
	if clean_boss_id.is_empty():
		return 0
	var boss: Dictionary = _get_boss_data(clean_boss_id)
	if boss.is_empty():
		return 0
	if _is_morgath_or_final_boss(clean_boss_id, boss):
		_debug_log("final_boss_ignored", str(boss.get("creature_type_id", "")), [], {"boss_id": clean_boss_id})
		return 0
	var creature_type_id: String = str(boss.get("creature_type_id", "")).strip_edges()
	if creature_type_id.is_empty():
		push_warning("MobWeakAbilitySystem: boss has no creature_type_id: " + clean_boss_id)
		return 0
	_boss_defeat_history.append(clean_boss_id)
	return on_boss_defeated(creature_type_id)

# Backward-compatible aliases used by older RunManager/BossController code.
func update_on_boss_defeated(creature_type_id: String) -> int:
	return on_boss_defeated(creature_type_id)

func update_on_boss_defeated_by_boss_id(boss_id: String) -> int:
	return on_boss_defeated_by_boss_id(boss_id)

func get_defeat_count(creature_type_id: String) -> int:
	var clean_id: String = str(creature_type_id).strip_edges()
	if clean_id.is_empty():
		return 0
	return max(0, int(_boss_defeat_count_by_creature_type.get(clean_id, 0)))

func get_weak_stage(creature_type_id: String) -> int:
	var count: int = get_defeat_count(creature_type_id)
	if count <= 0:
		return 0
	if count == 1:
		return 1
	if count == 2:
		return 2
	return 3

func get_weak_power_scale(creature_type_id: String) -> float:
	return ESCALATED_STAGE_POWER_SCALE if get_defeat_count(creature_type_id) >= 3 else BASE_STAGE_POWER_SCALE

func get_available_weak_abilities(creature_type_id: String) -> Array:
	return build_weak_ability_payloads(creature_type_id)

func build_weak_ability_payloads(creature_type_id: String) -> Array:
	var clean_id: String = str(creature_type_id).strip_edges()
	var result: Array = []
	if clean_id.is_empty():
		return result
	var allowed_indexes: Array[int] = _get_available_ability_indexes(clean_id)
	var scale: float = get_weak_power_scale(clean_id)
	for ability_data in _get_boss_abilities_by_creature_type(clean_id):
		if not (ability_data is Dictionary):
			continue
		var ability_index: int = int(ability_data.get("ability_index", 0))
		if not allowed_indexes.has(ability_index):
			continue
		var payload: Dictionary = _build_weak_ability_payload(ability_data, ability_index, scale)
		if not payload.is_empty():
			result.append(payload)
	result.sort_custom(Callable(self, "_sort_weak_payload_by_index"))
	return result

func apply_weak_ability_to_enemy(enemy: Node, creature_type_id: String) -> Array:
	var clean_id: String = str(creature_type_id).strip_edges()
	var weak_payloads: Array = build_weak_ability_payloads(clean_id)
	if enemy == null or not is_instance_valid(enemy):
		return weak_payloads
	var ability_ids: Array[String] = []
	for payload_value in weak_payloads:
		if payload_value is Dictionary:
			ability_ids.append(str(payload_value.get("boss_ability_id", "")))
	_last_applied_enemy_ids[str(enemy.get_instance_id())] = {
		"creature_type_id": clean_id,
		"defeat_count": get_defeat_count(clean_id),
		"weak_stage": get_weak_stage(clean_id),
		"power_scale": get_weak_power_scale(clean_id),
		"ability_count": weak_payloads.size(),
		"ability_ids": ability_ids
	}
	if enemy.has_method("set_weak_abilities"):
		enemy.call("set_weak_abilities", weak_payloads)
	elif enemy.has_method("apply_weak_boss_abilities"):
		enemy.call("apply_weak_boss_abilities", weak_payloads)
	else:
		enemy.set_meta("weak_boss_abilities", weak_payloads)
	weak_abilities_applied.emit(enemy, clean_id, weak_payloads.size())
	_debug_log("apply_to_enemy", clean_id, ability_ids, {"enemy_instance_id": enemy.get_instance_id(), "count": get_defeat_count(clean_id), "stage": get_weak_stage(clean_id), "power_scale": get_weak_power_scale(clean_id)})
	return weak_payloads

func debug_force_defeat_count(creature_type_id: String, count: int) -> void:
	if not _is_debug_allowed():
		return
	var clean_id: String = str(creature_type_id).strip_edges()
	if clean_id.is_empty():
		return
	_boss_defeat_count_by_creature_type[clean_id] = max(0, count)
	weak_ability_progress_changed.emit(clean_id, get_defeat_count(clean_id))
	debug_print_weak_stage(clean_id)

func debug_print_weak_stage(creature_type_id: String) -> void:
	if not _is_debug_allowed():
		return
	var clean_id: String = str(creature_type_id).strip_edges()
	print("[MobWeakAbilitySystem] creature=", clean_id, " count=", get_defeat_count(clean_id), " stage=", get_weak_stage(clean_id), " power_scale=", get_weak_power_scale(clean_id), " ability_indexes=", _get_available_ability_indexes(clean_id))

# v0.28 debug alias kept for dev scripts. Not used by player-facing UI.
func force_boss_defeat_count(creature_type_id: String, count: int) -> bool:
	if not _is_debug_allowed():
		push_warning("MobWeakAbilitySystem.force_boss_defeat_count is DEV/DEBUG only.")
		return false
	debug_force_defeat_count(creature_type_id, count)
	return true

func set_debug_enabled(enabled: bool) -> void:
	if not _is_debug_allowed():
		_debug_enabled = false
		return
	_debug_enabled = enabled

func is_debug_enabled() -> bool:
	return _debug_enabled and _is_debug_allowed()

func get_debug_events() -> Array:
	return _debug_events.duplicate(true)

func get_last_applied_enemy_debug() -> Dictionary:
	return _last_applied_enemy_ids.duplicate(true)

func _get_available_ability_indexes(creature_type_id: String) -> Array[int]:
	match get_defeat_count(creature_type_id):
		0:
			return [1]
		1:
			return [1, 2]
		2:
			return [1, 2, 3]
		_:
			return [1, 2, 3]

func _build_weak_ability_payload(ability_data: Dictionary, ability_index: int, power_scale: float) -> Dictionary:
	var ability_id: String = str(ability_data.get("boss_ability_id", ability_data.get("id", "")))
	if ability_id.is_empty():
		return {}
	var weak_version: Dictionary = _get_weak_mob_version(ability_id, ability_index)
	if weak_version.is_empty():
		return {}
	var effect_data: Dictionary = {}
	if weak_version.get("effect_data", {}) is Dictionary:
		effect_data = weak_version.get("effect_data", {}).duplicate(true)
	effect_data["power_scale"] = power_scale
	effect_data["power_multiplier"] = power_scale
	effect_data["is_weak_mob_version"] = true
	effect_data["is_full_boss_ability"] = false
	effect_data["cannot_trigger_boss_full_effect"] = true
	effect_data["cannot_trigger_player_reactions"] = true
	effect_data["cannot_trigger_boss_ability_chain"] = true
	effect_data["cannot_use_player_version"] = true
	return {
		"id": ability_id + "_WEAK_MOB_STAGE_" + str(get_weak_stage(str(ability_data.get("creature_type_id", "")))),
		"boss_ability_id": ability_id,
		"ability_index": ability_index,
		"weak_level": ability_index,
		"creature_type_id": str(ability_data.get("creature_type_id", "")),
		"faction_id": str(ability_data.get("faction_id", "")),
		"boss_id": str(ability_data.get("boss_id", "")),
		"name_ru": str(ability_data.get("name_ru", ability_id)),
		"description_ru": str(weak_version.get("description_ru", "Ослабленная версия способности босса.")),
		"power_scale": power_scale,
		"power_multiplier": power_scale,
		"source_type": DamagePayload.SOURCE_WEAK_MOB_ABILITY_DAMAGE,
		"effect_tags": _array_duplicate(weak_version.get("effect_tags", weak_version.get("tags", []))),
		"tags": _array_duplicate(weak_version.get("effect_tags", weak_version.get("tags", []))),
		"reaction_tags": _array_duplicate(weak_version.get("reaction_tags", [])),
		"effect_data": effect_data,
		"cooldown_seconds": max(0.25, float(weak_version.get("cooldown_seconds", 4.0))),
		"trigger_limits": weak_version.get("trigger_limits", {}) if weak_version.get("trigger_limits", {}) is Dictionary else {},
		"is_weak_mob_version": true,
		"is_full_boss_ability": false,
		"uses_player_version": false,
		"run_only": true
	}

func _get_boss_abilities_by_creature_type(creature_type_id: String) -> Array:
	var system: Node = get_node_or_null("/root/BossAbilitySystem")
	if system != null and system.has_method("get_boss_abilities_by_creature_type"):
		var abilities_value: Variant = system.call("get_boss_abilities_by_creature_type", creature_type_id)
		if abilities_value is Array:
			return abilities_value
	if system != null and system.has_method("get_boss_abilities_for_creature_type"):
		var fallback_value: Variant = system.call("get_boss_abilities_for_creature_type", creature_type_id)
		if fallback_value is Array:
			return fallback_value
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_boss_abilities_for_creature_type"):
		var registry_value: Variant = registry.call("get_boss_abilities_for_creature_type", creature_type_id)
		if registry_value is Array:
			return registry_value
	return []

func _get_weak_mob_version(boss_ability_id: String, ability_index: int) -> Dictionary:
	var system: Node = get_node_or_null("/root/BossAbilitySystem")
	if system != null and system.has_method("get_weak_mob_version"):
		var version_value: Variant = system.call("get_weak_mob_version", boss_ability_id, ability_index)
		if version_value is Dictionary and not version_value.is_empty():
			return version_value.duplicate(true)
	return {}

func _get_boss_data(boss_id: String) -> Dictionary:
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_by_id"):
		var boss_value: Variant = registry.call("get_by_id", "bosses", boss_id)
		if boss_value is Dictionary:
			return boss_value
	return {}

func _is_morgath_or_final_boss(boss_id: String, boss_data: Dictionary) -> bool:
	if boss_id == "BOSS_MORGATH" or bool(boss_data.get("is_final_boss", false)):
		return true
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_by_id"):
		var final_data: Variant = registry.call("get_by_id", "final_bosses", boss_id)
		return final_data is Dictionary and not final_data.is_empty()
	return false

func _sort_weak_payload_by_index(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("ability_index", 0)) < int(b.get("ability_index", 0))

func _array_duplicate(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			result.append(item)
	return result

func _debug_log(event_type: String, creature_type_id: String, ability_ids: Array, extra: Dictionary = {}) -> void:
	if not is_debug_enabled():
		return
	var event: Dictionary = {
		"event": event_type,
		"creature_type_id": creature_type_id,
		"ability_ids": ability_ids.duplicate(),
		"extra": extra.duplicate(true),
		"ticks_msec": Time.get_ticks_msec()
	}
	_debug_events.append(event)
	while _debug_events.size() > 48:
		_debug_events.pop_front()
	print("[MobWeakAbilitySystem] " + event_type + " creature=" + creature_type_id + " abilities=" + str(ability_ids) + " extra=" + str(extra))

func _is_debug_allowed() -> bool:
	return OS.is_debug_build() or Engine.is_editor_hint()
