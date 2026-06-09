extends Node

# CORE Progression Rework v0.23
# Route layout is data-driven from data/run_config.json via DataRegistry.
# No silent fallback to the old 3-floor or code-hardcoded 7-floor scheme is allowed.

var current_floor: int = 1
var current_room_on_floor: int = 1
var rooms_by_floor: Dictionary = {}
var total_floors: int = 0
var route_state: Dictionary = {}
var config_valid: bool = false
var config_error: String = ""

func _ready() -> void:
	reload_config()
	if route_state.is_empty():
		_reset_route_state()

func reload_config() -> void:
	config_valid = false
	config_error = ""
	rooms_by_floor.clear()
	total_floors = 0

	var config: Dictionary = _get_run_config()
	if config.is_empty():
		_set_config_error("RunRouteManager: missing data/run_config.json or DataRegistry run_config entry.")
		return

	total_floors = int(config.get("floors_total", 0))
	rooms_by_floor = _parse_rooms_by_floor(config.get("rooms_by_floor", {}))
	var validation_error: String = _validate_route_config(config)
	if not validation_error.is_empty():
		_set_config_error(validation_error)
		return

	config_valid = true
	config_error = ""

func reset_run() -> void:
	reset_route()

func reset_route() -> void:
	reload_config()
	current_floor = 1
	current_room_on_floor = 1
	_reset_route_state()

func get_rooms_for_floor(floor_index: int) -> int:
	if not config_valid:
		push_error(config_error)
		return 0
	if rooms_by_floor.has(floor_index):
		return int(rooms_by_floor[floor_index])
	push_error("RunRouteManager: run_config.rooms_by_floor has no entry for floor " + str(floor_index))
	return 0

func is_floor_complete() -> bool:
	var rooms_on_floor: int = get_rooms_for_floor(current_floor)
	if rooms_on_floor <= 0:
		return false
	return current_room_on_floor > rooms_on_floor

func is_run_ready_for_final_preparation() -> bool:
	return config_valid and current_floor >= total_floors and is_floor_complete()

func advance_room() -> void:
	current_room_on_floor += 1
	route_state["phase"] = "boss_choice" if is_floor_complete() else "route_choice"
	route_state["last_advanced"] = "room"
	route_state["context"] = get_next_route_context()

func advance_floor() -> void:
	current_floor += 1
	current_room_on_floor = 1
	route_state["phase"] = "final_preparation" if config_valid and current_floor > total_floors else "route_choice"
	route_state["last_advanced"] = "floor"
	route_state["context"] = get_next_route_context()

func get_next_route_context() -> Dictionary:
	var rooms_on_floor: int = get_rooms_for_floor(current_floor)
	return {
		"current_floor": current_floor,
		"floor_index": current_floor,
		"current_room_on_floor": current_room_on_floor,
		"room_index_on_floor": current_room_on_floor,
		"rooms_on_floor": rooms_on_floor,
		"rooms_by_floor": _rooms_by_floor_string_keys(),
		"total_floors": total_floors,
		"is_floor_complete": is_floor_complete(),
		"ready_for_final_preparation": is_run_ready_for_final_preparation(),
		"route_config_valid": config_valid,
		"route_config_error": config_error,
		"route_state": route_state.duplicate(true)
	}

func get_state() -> Dictionary:
	return {
		"floor_index": current_floor,
		"room_index_on_floor": current_room_on_floor,
		"rooms_by_floor": _rooms_by_floor_string_keys(),
		"total_floors": total_floors,
		"route_config_valid": config_valid,
		"route_config_error": config_error,
		"route_state": route_state.duplicate(true)
	}

func set_state(state: Variant) -> void:
	reload_config()
	if not (state is Dictionary):
		reset_route()
		return
	var state_dict: Dictionary = state
	current_floor = clampi(int(state_dict.get("floor_index", state_dict.get("current_floor", 1))), 1, max(total_floors + 1, 1))
	current_room_on_floor = max(1, int(state_dict.get("room_index_on_floor", state_dict.get("current_room_on_floor", state_dict.get("room_index", 1)))))
	# Do not restore rooms_by_floor from saved run-state. Route layout is sourced only from data/run_config.json.
	var incoming_route_state: Variant = state_dict.get("route_state", {})
	route_state = incoming_route_state.duplicate(true) if incoming_route_state is Dictionary else {}
	if route_state.is_empty():
		_reset_route_state()
	route_state["context"] = get_next_route_context()

func set_route_state(new_route_state: Variant) -> void:
	if new_route_state is Dictionary:
		route_state = new_route_state.duplicate(true)
	else:
		_reset_route_state()
	route_state["context"] = get_next_route_context()

func _reset_route_state() -> void:
	route_state = {
		"version": 3,
		"phase": "room",
		"last_choice": {},
		"context": {
			"floor_index": current_floor,
			"room_index_on_floor": current_room_on_floor,
			"route_config_valid": config_valid
		}
	}

func _get_run_config() -> Dictionary:
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null:
		if registry.has_method("get_run_config"):
			var config_value: Variant = registry.call("get_run_config")
			if config_value is Dictionary:
				return config_value
		elif registry.has_method("get_raw"):
			var raw: Variant = registry.call("get_raw", "run_config")
			if raw is Dictionary:
				return raw
	return _load_run_config_directly()

func _load_run_config_directly() -> Dictionary:
	var path: String = "res://data/run_config.json"
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func _parse_rooms_by_floor(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	if raw is Dictionary:
		for key in raw.keys():
			var floor_index: int = int(str(key))
			if floor_index <= 0:
				continue
			var room_count: int = int(raw[key])
			if room_count <= 0:
				continue
			result[floor_index] = room_count
	return result

func _rooms_by_floor_string_keys() -> Dictionary:
	var result: Dictionary = {}
	for key in rooms_by_floor.keys():
		result[str(key)] = int(rooms_by_floor[key])
	return result

func _validate_route_config(config: Dictionary) -> String:
	if total_floors != 7:
		return "RunRouteManager: run_config.floors_total must be 7 for CORE Progression Rework."
	if rooms_by_floor.size() != total_floors:
		return "RunRouteManager: run_config.rooms_by_floor must define every floor."
	for floor_index in range(1, total_floors + 1):
		if not rooms_by_floor.has(floor_index):
			return "RunRouteManager: missing rooms_by_floor for floor " + str(floor_index)
		if int(rooms_by_floor[floor_index]) <= 0:
			return "RunRouteManager: invalid room count for floor " + str(floor_index)
	var final_preparation: Variant = config.get("final_preparation", {})
	if not (final_preparation is Dictionary) or not bool(final_preparation.get("enabled", false)):
		return "RunRouteManager: final_preparation.enabled must be true."
	if int(final_preparation.get("elite_waves", 0)) != 1:
		return "RunRouteManager: final_preparation.elite_waves must be 1."
	var final_boss: Variant = config.get("final_boss", {})
	if not (final_boss is Dictionary) or str(final_boss.get("boss_id", "")).is_empty():
		return "RunRouteManager: final_boss.boss_id is required."
	return ""

func _set_config_error(message: String) -> void:
	config_valid = false
	config_error = message
	push_error(message)
