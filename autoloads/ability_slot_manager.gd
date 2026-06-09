extends Node

# SHADOW CORE v0.34
# Single source of truth for run-scoped player_version boss ability installation.
# Boss abilities are not inventory items: they only work while installed into active_1 / active_2 / third_ability slots.

signal ability_slots_changed(state: Dictionary)
signal boss_ability_installed(active_ability_id: String, slot_index: int, boss_ability_id: String)
signal boss_ability_replaced(active_ability_id: String, slot_index: int, old_boss_ability_id: String, new_boss_ability_id: String)

const SLOTS_PER_ACTIVE_ABILITY: int = 3
const ACTIVE_SLOT_IDS: Array[String] = ["active_1", "active_2", "third_ability"]
const FORBIDDEN_SLOT_IDS: Array[String] = ["auto_attack", "passive", "weapon", "stat", "mob", "boss"]

var _slots_by_active_ability: Dictionary = {}

func _ready() -> void:
	_ensure_initialized()

func reset_run() -> void:
	_slots_by_active_ability.clear()
	for active_ability_id in ACTIVE_SLOT_IDS:
		_slots_by_active_ability[active_ability_id] = _new_empty_slots(active_ability_id)
	_emit_changed()

func get_state() -> Dictionary:
	_ensure_initialized()
	return {
		"schema_version": 2,
		"slot_count_per_active_ability": SLOTS_PER_ACTIVE_ABILITY,
		"active_ability_ids": ACTIVE_SLOT_IDS.duplicate(true),
		"installed_boss_abilities": _duplicate_slots(),
		"slots": _duplicate_slots(),
		"source_of_truth": "AbilitySlotManager",
		"version": "player_version"
	}

func set_state(state: Variant = {}) -> void:
	_slots_by_active_ability.clear()
	for active_ability_id in ACTIVE_SLOT_IDS:
		_slots_by_active_ability[active_ability_id] = _new_empty_slots(active_ability_id)
	if not (state is Dictionary):
		_emit_changed()
		return
	var state_dict: Dictionary = state
	var slots_source: Variant = state_dict.get("installed_boss_abilities", state_dict.get("slots", {}))
	if slots_source is Dictionary:
		for key_value in slots_source.keys():
			var active_id: String = _normalize_active_slot_id(str(key_value))
			if not _is_allowed_active_slot(active_id):
				continue
			var restored_slots: Array = _new_empty_slots(active_id)
			var raw_slots: Variant = slots_source[key_value]
			if raw_slots is Array:
				for i in range(min(SLOTS_PER_ACTIVE_ABILITY, raw_slots.size())):
					var restored_entry: Dictionary = _normalize_slot_entry(raw_slots[i], active_id, i)
					if not restored_entry.is_empty():
						restored_slots[i] = restored_entry
			_slots_by_active_ability[active_id] = restored_slots
	_sync_levels_to_boss_ability_system()
	_emit_changed()

func get_slots(active_ability_id: String) -> Array:
	_ensure_initialized()
	var active_id: String = _normalize_active_slot_id(active_ability_id)
	if not _is_allowed_active_slot(active_id):
		return []
	var slots_value: Variant = _slots_by_active_ability.get(active_id, _new_empty_slots(active_id))
	if slots_value is Array:
		return _duplicate_slot_array(slots_value)
	return _new_empty_slots(active_id)

func get_all_slots() -> Dictionary:
	_ensure_initialized()
	return _duplicate_slots()

func get_installed_effects(active_ability_id: String) -> Array:
	var effects: Array = []
	var active_id: String = _normalize_active_slot_id(active_ability_id)
	if not _is_allowed_active_slot(active_id):
		return effects
	var boss_ability_system: Node = get_node_or_null("/root/BossAbilitySystem")
	for slot_entry_value in get_slots(active_id):
		if not (slot_entry_value is Dictionary):
			continue
		var slot_entry: Dictionary = slot_entry_value
		var boss_ability_id: String = str(slot_entry.get("boss_ability_id", ""))
		if boss_ability_id.is_empty():
			continue
		var level: int = max(1, int(slot_entry.get("level", 1)))
		var effect: Dictionary = slot_entry.duplicate(true)
		effect["active_ability_id"] = active_id
		effect["version"] = "player_version"
		if boss_ability_system != null and boss_ability_system.has_method("get_player_version"):
			var player_version: Variant = boss_ability_system.call("get_player_version", boss_ability_id, level)
			if player_version is Dictionary:
				effect["player_version"] = player_version.duplicate(true)
		effects.append(effect)
	return effects

func has_free_slot(active_ability_id: String) -> bool:
	return get_first_free_slot(active_ability_id) >= 0

func get_first_free_slot(active_ability_id: String) -> int:
	var active_id: String = _normalize_active_slot_id(active_ability_id)
	if not _is_allowed_active_slot(active_id):
		return -1
	var slots: Array = get_slots(active_id)
	for i in range(slots.size()):
		if not (slots[i] is Dictionary) or str(slots[i].get("boss_ability_id", "")).is_empty():
			return i
	return -1

func can_install(active_ability_id: String, boss_ability_id: String) -> Dictionary:
	var active_id: String = _normalize_active_slot_id(active_ability_id)
	if boss_ability_id.is_empty():
		return {"ok": false, "reason": "Boss ability id is empty.", "needs_replace": false}
	if _is_forbidden_slot_id(active_id) or not _is_allowed_active_slot(active_id):
		return {"ok": false, "reason": "Boss abilities can only be installed into active ability slots.", "needs_replace": false}
	if is_boss_ability_installed(boss_ability_id):
		return {"ok": false, "reason": "Эта способность уже установлена в этом забеге.", "needs_replace": false}
	if not _is_slot_allowed_by_player_version(active_id, boss_ability_id):
		return {"ok": false, "reason": "Boss abilities can only be installed into active ability slots.", "needs_replace": false}
	return {"ok": true, "reason": "", "needs_replace": not has_free_slot(active_id)}

func install_boss_ability(active_ability_id: String, boss_ability_id: String, level: int = 1) -> bool:
	var active_id: String = _normalize_active_slot_id(active_ability_id)
	var can_result: Dictionary = can_install(active_id, boss_ability_id)
	if not bool(can_result.get("ok", false)) or bool(can_result.get("needs_replace", false)):
		push_warning("AbilitySlotManager.install_boss_ability(): " + str(can_result.get("reason", "install failed")))
		return false
	var slot_index: int = get_first_free_slot(active_id)
	if slot_index < 0:
		return false
	var slots: Array = _slots_by_active_ability[active_id]
	slots[slot_index] = _make_slot_entry(active_id, slot_index, boss_ability_id, level)
	_slots_by_active_ability[active_id] = slots
	boss_ability_installed.emit(active_id, slot_index, boss_ability_id)
	_emit_changed()
	return true

func replace_boss_ability(active_ability_id: String, slot_index: int, boss_ability_id: String, level: int = 1) -> bool:
	var active_id: String = _normalize_active_slot_id(active_ability_id)
	if boss_ability_id.is_empty():
		return false
	if slot_index < 0 or slot_index >= SLOTS_PER_ACTIVE_ABILITY:
		return false
	if _is_forbidden_slot_id(active_id) or not _is_allowed_active_slot(active_id):
		push_warning("AbilitySlotManager.replace_boss_ability(): Boss abilities can only be installed into active ability slots.")
		return false
	if not _is_slot_allowed_by_player_version(active_id, boss_ability_id):
		return false
	var existing_location: Dictionary = get_installed_location(boss_ability_id)
	if not existing_location.is_empty():
		var same_slot: bool = str(existing_location.get("active_ability_id", "")) == active_id and int(existing_location.get("slot_index", -1)) == slot_index
		if not same_slot:
			push_warning("AbilitySlotManager.replace_boss_ability(): ability already installed in another slot: " + boss_ability_id)
			return false
	var slots: Array = _slots_by_active_ability.get(active_id, _new_empty_slots(active_id))
	var old_entry: Dictionary = {}
	if slots[slot_index] is Dictionary:
		old_entry = slots[slot_index]
	var old_id: String = str(old_entry.get("boss_ability_id", ""))
	slots[slot_index] = _make_slot_entry(active_id, slot_index, boss_ability_id, level)
	_slots_by_active_ability[active_id] = slots
	boss_ability_replaced.emit(active_id, slot_index, old_id, boss_ability_id)
	_emit_changed()
	return true

func get_installed_ability_ids(active_ability_id: String) -> Array:
	var result: Array = []
	for effect in get_installed_effects(active_ability_id):
		if effect is Dictionary:
			var boss_ability_id: String = str(effect.get("boss_ability_id", ""))
			if not boss_ability_id.is_empty():
				result.append(boss_ability_id)
	return result

func is_boss_ability_installed(boss_ability_id: String) -> bool:
	if boss_ability_id.is_empty():
		return false
	return not get_installed_location(boss_ability_id).is_empty()

func get_installed_location(boss_ability_id: String) -> Dictionary:
	_ensure_initialized()
	if boss_ability_id.is_empty():
		return {}
	for active_id in ACTIVE_SLOT_IDS:
		var slots: Array = _slots_by_active_ability.get(active_id, [])
		for i in range(slots.size()):
			if slots[i] is Dictionary and str(slots[i].get("boss_ability_id", "")) == boss_ability_id:
				return {
					"active_ability_id": active_id,
					"slot_index": i,
					"level": int(slots[i].get("level", 1)),
					"version": "player_version"
				}
	return {}

func upgrade_installed_boss_ability(boss_ability_id: String, new_level: int) -> bool:
	var location: Dictionary = get_installed_location(boss_ability_id)
	if location.is_empty():
		return false
	var active_id: String = str(location.get("active_ability_id", ""))
	var slot_index: int = int(location.get("slot_index", -1))
	if not _is_allowed_active_slot(active_id) or slot_index < 0:
		return false
	var slots: Array = _slots_by_active_ability[active_id]
	if not (slots[slot_index] is Dictionary):
		return false
	var entry: Dictionary = slots[slot_index]
	entry["level"] = clampi(new_level, 1, 3)
	entry["version"] = "player_version"
	slots[slot_index] = entry
	_slots_by_active_ability[active_id] = slots
	_emit_changed()
	return true

func get_active_ability_ids() -> Array:
	return ACTIVE_SLOT_IDS.duplicate(true)

func get_active_ability_label(active_ability_id: String) -> String:
	var active_id: String = _normalize_active_slot_id(active_ability_id)
	match active_id:
		"active_1":
			return "Active 1"
		"active_2":
			return "Active 2"
		"third_ability":
			return "Third Ability"
		_:
			return active_ability_id

func clear_state() -> void:
	reset_run()

func normalize_active_ability_id(active_ability_id: String) -> String:
	return _normalize_active_slot_id(active_ability_id)

func _ensure_initialized() -> void:
	for active_ability_id in ACTIVE_SLOT_IDS:
		if not _slots_by_active_ability.has(active_ability_id):
			_slots_by_active_ability[active_ability_id] = _new_empty_slots(active_ability_id)

func _new_empty_slots(active_ability_id: String = "") -> Array:
	var result: Array = []
	for i in range(SLOTS_PER_ACTIVE_ABILITY):
		result.append({
			"slot_index": i,
			"active_ability_id": active_ability_id,
			"boss_ability_id": "",
			"level": 0,
			"version": "player_version"
		})
	return result

func _make_slot_entry(active_ability_id: String, slot_index: int, boss_ability_id: String, level: int) -> Dictionary:
	return {
		"slot_index": slot_index,
		"active_ability_id": active_ability_id,
		"boss_ability_id": boss_ability_id,
		"level": clampi(level, 1, 3),
		"version": "player_version"
	}

func _normalize_slot_entry(raw_entry: Variant, active_ability_id: String, slot_index: int) -> Dictionary:
	if raw_entry is Dictionary:
		var entry: Dictionary = raw_entry
		var boss_ability_id: String = str(entry.get("boss_ability_id", entry.get("id", "")))
		if boss_ability_id.is_empty():
			return _new_empty_slots(active_ability_id)[slot_index]
		return _make_slot_entry(active_ability_id, slot_index, boss_ability_id, int(entry.get("level", 1)))
	var legacy_id: String = str(raw_entry)
	if legacy_id.is_empty():
		return _new_empty_slots(active_ability_id)[slot_index]
	return _make_slot_entry(active_ability_id, slot_index, legacy_id, _get_boss_ability_level(legacy_id))

func _duplicate_slot_array(slots: Array) -> Array:
	var result: Array = []
	for value in slots:
		if value is Dictionary:
			result.append(value.duplicate(true))
		else:
			result.append(value)
	return result

func _duplicate_slots() -> Dictionary:
	_ensure_initialized()
	var result: Dictionary = {}
	for active_id in ACTIVE_SLOT_IDS:
		var slots_value: Variant = _slots_by_active_ability.get(active_id, _new_empty_slots(active_id))
		result[active_id] = _duplicate_slot_array(slots_value if slots_value is Array else _new_empty_slots(active_id))
	return result

func _normalize_active_slot_id(active_ability_id: String) -> String:
	var raw_id: String = str(active_ability_id).strip_edges()
	if raw_id == "ultimate":
		return "third_ability"
	if ACTIVE_SLOT_IDS.has(raw_id) or FORBIDDEN_SLOT_IDS.has(raw_id):
		return raw_id
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_ability"):
		var ability: Variant = registry.call("get_ability", raw_id)
		if ability is Dictionary:
			var slot: String = str(ability.get("slot", ""))
			if slot == "ultimate":
				return "third_ability"
			if not slot.is_empty():
				return slot
	return raw_id

func _is_allowed_active_slot(active_ability_id: String) -> bool:
	return ACTIVE_SLOT_IDS.has(active_ability_id)

func _is_forbidden_slot_id(slot_id: String) -> bool:
	return FORBIDDEN_SLOT_IDS.has(slot_id) or slot_id == "ultimate"

func _is_slot_allowed_by_player_version(active_ability_id: String, boss_ability_id: String) -> bool:
	var ability_data: Dictionary = _get_boss_ability_data(boss_ability_id)
	var player_version: Dictionary = ability_data.get("player_version", {}) if ability_data.get("player_version", {}) is Dictionary else {}
	var allowed_slots: Array = player_version.get("allowed_slots", ACTIVE_SLOT_IDS) if player_version.get("allowed_slots", ACTIVE_SLOT_IDS) is Array else ACTIVE_SLOT_IDS
	var forbidden_slots: Array = player_version.get("forbidden_slots", FORBIDDEN_SLOT_IDS) if player_version.get("forbidden_slots", FORBIDDEN_SLOT_IDS) is Array else FORBIDDEN_SLOT_IDS
	if forbidden_slots.has(active_ability_id):
		return false
	return allowed_slots.has(active_ability_id)

func _get_boss_ability_data(boss_ability_id: String) -> Dictionary:
	var system: Node = get_node_or_null("/root/BossAbilitySystem")
	if system != null and system.has_method("get_ability_data"):
		var system_data: Variant = system.call("get_ability_data", boss_ability_id)
		if system_data is Dictionary:
			return system_data
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_boss_ability"):
		var registry_data: Variant = registry.call("get_boss_ability", boss_ability_id)
		if registry_data is Dictionary:
			return registry_data
	return {}

func _get_boss_ability_level(boss_ability_id: String) -> int:
	var system: Node = get_node_or_null("/root/BossAbilitySystem")
	if system != null and system.has_method("get_level"):
		return max(1, int(system.call("get_level", boss_ability_id)))
	return 1

func _sync_levels_to_boss_ability_system() -> void:
	var system: Node = get_node_or_null("/root/BossAbilitySystem")
	if system == null or not system.has_method("set_level"):
		return
	for active_id in ACTIVE_SLOT_IDS:
		for entry_value in get_slots(active_id):
			if not (entry_value is Dictionary):
				continue
			var entry: Dictionary = entry_value
			var boss_ability_id: String = str(entry.get("boss_ability_id", ""))
			if not boss_ability_id.is_empty():
				system.call("set_level", boss_ability_id, int(entry.get("level", 1)))

func _emit_changed() -> void:
	ability_slots_changed.emit(get_state())
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(&"run_resource_changed"):
		bus.emit_signal(&"run_resource_changed")
