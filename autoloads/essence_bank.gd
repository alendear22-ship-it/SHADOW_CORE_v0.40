extends Node

var essence_by_creature_type: Dictionary = {}

func reset_run() -> void:
	essence_by_creature_type.clear()
	_notify_auto_scaling_changed("reset_run")
	EventBus.run_resource_changed.emit()

func add_essence(creature_type_id: String, faction_id: String, amount: int) -> void:
	if creature_type_id.is_empty() or amount <= 0:
		return
	essence_by_creature_type[creature_type_id] = int(essence_by_creature_type.get(creature_type_id, 0)) + amount
	MetaProgression.add_faction_counter(faction_id, amount)
	EventBus.essence_collected.emit(creature_type_id, faction_id, amount)
	_notify_auto_scaling_changed("essence_collected")
	EventBus.run_resource_changed.emit()

func get_amount(creature_type_id: String) -> int:
	return int(essence_by_creature_type.get(creature_type_id, 0))

func get_total_amount() -> int:
	var total: int = 0
	for key in essence_by_creature_type.keys():
		total += int(essence_by_creature_type.get(key, 0))
	return total

func get_amounts_by_creature_type() -> Dictionary:
	return essence_by_creature_type.duplicate(true)

func get_total_for_faction(faction_id: String) -> int:
	var total: int = 0
	for creature_type_id in DataRegistry.get_creature_type_ids_for_faction(faction_id):
		total += get_amount(creature_type_id)
	return total

func get_amounts_by_faction() -> Dictionary:
	var result: Dictionary = {}
	for creature_type_id in essence_by_creature_type.keys():
		var creature: Dictionary = DataRegistry.get_creature_type(str(creature_type_id))
		var faction_id: String = str(creature.get("faction_id", "unknown"))
		result[faction_id] = int(result.get(faction_id, 0)) + int(essence_by_creature_type.get(creature_type_id, 0))
	return result

func can_sacrifice(faction_or_mix, amount: int) -> bool:
	var requested: int = max(0, amount)
	if requested <= 0:
		return true
	var source: String = str(faction_or_mix)
	if source.is_empty() or source == "mix" or source == "all":
		return get_total_amount() >= requested
	if _is_known_faction(source):
		return get_total_for_faction(source) >= requested
	return get_amount(source) >= requested

func sacrifice_essence(faction_or_mix, amount: int) -> int:
	var requested: int = max(0, amount)
	if requested <= 0:
		return 0
	if not can_sacrifice(faction_or_mix, requested):
		return 0
	var source: String = str(faction_or_mix)
	var spent: int = 0
	if source.is_empty() or source == "mix" or source == "all":
		spent = _spend_from_all_sources(requested)
	elif _is_known_faction(source):
		spent = _spend_from_faction(source, requested)
	else:
		spent = _spend_from_creature_type(source, requested)
	if spent > 0:
		_notify_auto_scaling_changed("altar_sacrifice")
		EventBus.run_resource_changed.emit()
	return spent

func _spend_from_all_sources(amount: int) -> int:
	var remaining: int = amount
	var keys: Array = essence_by_creature_type.keys()
	keys.sort_custom(func(a, b) -> bool:
		return int(essence_by_creature_type.get(a, 0)) > int(essence_by_creature_type.get(b, 0))
	)
	var spent: int = 0
	for key in keys:
		if remaining <= 0:
			break
		var creature_type_id: String = str(key)
		var current: int = get_amount(creature_type_id)
		var take: int = min(current, remaining)
		if take <= 0:
			continue
		essence_by_creature_type[creature_type_id] = current - take
		remaining -= take
		spent += take
	return spent

func _spend_from_faction(faction_id: String, amount: int) -> int:
	var remaining: int = amount
	var creature_ids: Array = DataRegistry.get_creature_type_ids_for_faction(faction_id)
	creature_ids.sort_custom(func(a, b) -> bool:
		return get_amount(str(a)) > get_amount(str(b))
	)
	var spent: int = 0
	for creature_type_id_value in creature_ids:
		if remaining <= 0:
			break
		var creature_type_id: String = str(creature_type_id_value)
		var current: int = get_amount(creature_type_id)
		var take: int = min(current, remaining)
		if take <= 0:
			continue
		essence_by_creature_type[creature_type_id] = current - take
		remaining -= take
		spent += take
	return spent

func _spend_from_creature_type(creature_type_id: String, amount: int) -> int:
	var current: int = get_amount(creature_type_id)
	var take: int = min(current, amount)
	if take <= 0:
		return 0
	essence_by_creature_type[creature_type_id] = current - take
	return take

func _is_known_faction(faction_id: String) -> bool:
	if faction_id.is_empty():
		return false
	if get_node_or_null("/root/DataRegistry") == null:
		return false
	return not DataRegistry.get_by_id("factions", faction_id).is_empty()

func spend_specific(creature_type_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if get_amount(creature_type_id) < amount:
		return false
	essence_by_creature_type[creature_type_id] = get_amount(creature_type_id) - amount
	_notify_auto_scaling_changed("spend_specific")
	EventBus.run_resource_changed.emit()
	return true

func can_spend_within_faction(source_creature_type_id: String, faction_id: String, amount: int) -> bool:
	return _available_within_faction(source_creature_type_id, faction_id) >= amount

func spend_within_faction(source_creature_type_id: String, faction_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if not can_spend_within_faction(source_creature_type_id, faction_id, amount):
		return false
	var remaining: int = amount
	var source_amount: int = min(get_amount(source_creature_type_id), remaining)
	if source_amount > 0:
		essence_by_creature_type[source_creature_type_id] = get_amount(source_creature_type_id) - source_amount
		remaining -= source_amount
	if remaining > 0:
		var alternatives: Array = DataRegistry.get_creature_type_ids_for_faction(faction_id)
		alternatives.erase(source_creature_type_id)
		alternatives.sort_custom(func(a: String, b: String) -> bool:
			return get_amount(a) < get_amount(b)
		)
		for creature_type_id in alternatives:
			if remaining <= 0:
				break
			var spend: int = min(get_amount(creature_type_id), remaining)
			if spend <= 0:
				continue
			essence_by_creature_type[creature_type_id] = get_amount(creature_type_id) - spend
			remaining -= spend
	_notify_auto_scaling_changed("spend_within_faction")
	EventBus.run_resource_changed.emit()
	return remaining <= 0

func apply_fraction_penalty(fraction: float) -> int:
	var safe_fraction: float = clampf(fraction, 0.0, 1.0)
	if safe_fraction <= 0.0:
		return 0
	var removed_total: int = 0
	for creature_type_id in essence_by_creature_type.keys():
		var current: int = int(essence_by_creature_type.get(creature_type_id, 0))
		var remove_amount: int = int(floor(float(current) * safe_fraction))
		if remove_amount <= 0 and current > 0 and safe_fraction >= 0.5:
			remove_amount = 1
		essence_by_creature_type[creature_type_id] = max(0, current - remove_amount)
		removed_total += remove_amount
	_notify_auto_scaling_changed("fraction_penalty")
	EventBus.run_resource_changed.emit()
	return removed_total

func _available_within_faction(_source_creature_type_id: String, faction_id: String) -> int:
	var total: int = 0
	for creature_type_id in DataRegistry.get_creature_type_ids_for_faction(faction_id):
		total += get_amount(creature_type_id)
	return total

func get_state() -> Dictionary:
	return essence_by_creature_type.duplicate(true)

func set_state(data: Dictionary) -> void:
	essence_by_creature_type = data.duplicate(true)
	_notify_auto_scaling_changed("set_state")
	EventBus.run_resource_changed.emit()

func debug_add_mvp_upgrade_stipend() -> void:
	var stipend: Dictionary = DataRegistry.get_rewards().get("mvp_upgrade_stipend", {})
	if not bool(stipend.get("enabled", false)):
		return
	var values: Dictionary = stipend.get("essence_by_creature_type", {})
	for creature_type_id in values.keys():
		var creature: Dictionary = DataRegistry.get_creature_type(creature_type_id)
		add_essence(creature_type_id, creature.get("faction_id", ""), int(values[creature_type_id]))


func _notify_auto_scaling_changed(reason: String = "essence_changed") -> void:
	var scaling: Node = get_node_or_null("/root/EssenceAutoScaling")
	if scaling != null and scaling.has_method("recalculate"):
		scaling.call("recalculate", reason)
