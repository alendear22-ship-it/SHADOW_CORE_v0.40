extends Node

# CORE Progression Rework prep v0.10
# Дополнительные боссы заменяют комнату маршрута, а не добавляются отдельной волной.
# Main rules:
# - one optional boss kill per pair: 2-3, 4-5, 6-7;
# - first refusal creates one second chance on the last room-choice of the next floor;
# - second refusal closes the pair;
# - victory closes the pair;
# - optional boss does not count as mandatory floor boss progression.

const PAIR_2_3: String = "pair_2_3"
const PAIR_4_5: String = "pair_4_5"
const PAIR_6_7: String = "pair_6_7"


var pair_2_3: Dictionary = {}
var pair_4_5: Dictionary = {}
var pair_6_7: Dictionary = {}
var _last_optional_card: Dictionary = {}


func _ready() -> void:
	reset_run()


func reset_run() -> void:
	pair_2_3 = _make_pair_state(PAIR_2_3)
	pair_4_5 = _make_pair_state(PAIR_4_5)
	pair_6_7 = _make_pair_state(PAIR_6_7)
	_last_optional_card.clear()


func _make_pair_state(pair_id: String) -> Dictionary:
	return {
		"pair_id": pair_id,
		"offered_count": 0,
		"refused_count": 0,
		"defeated": false,
		"closed": false,
		"pending_second_chance": false,
		"selected_boss_id": "",
		"defeated_boss_id": ""
	}


func get_state() -> Dictionary:
	return {
		PAIR_2_3: pair_2_3.duplicate(true),
		PAIR_4_5: pair_4_5.duplicate(true),
		PAIR_6_7: pair_6_7.duplicate(true),
		"last_optional_card": _last_optional_card.duplicate(true)
	}


func set_state(state: Variant) -> void:
	reset_run()
	if not (state is Dictionary):
		return
	var state_dict: Dictionary = state
	pair_2_3 = _merge_pair_state(PAIR_2_3, state_dict.get(PAIR_2_3, {}))
	pair_4_5 = _merge_pair_state(PAIR_4_5, state_dict.get(PAIR_4_5, {}))
	pair_6_7 = _merge_pair_state(PAIR_6_7, state_dict.get(PAIR_6_7, {}))
	var last_card: Variant = state_dict.get("last_optional_card", {})
	if last_card is Dictionary:
		_last_optional_card = last_card.duplicate(true)


func _merge_pair_state(pair_id: String, raw_state: Variant) -> Dictionary:
	var merged: Dictionary = _make_pair_state(pair_id)
	if not (raw_state is Dictionary):
		return merged
	var source: Dictionary = raw_state
	merged["offered_count"] = max(0, int(source.get("offered_count", 0)))
	merged["refused_count"] = max(0, int(source.get("refused_count", 0)))
	merged["defeated"] = bool(source.get("defeated", false))
	merged["closed"] = bool(source.get("closed", false))
	merged["pending_second_chance"] = bool(source.get("pending_second_chance", false))
	merged["selected_boss_id"] = str(source.get("selected_boss_id", ""))
	merged["defeated_boss_id"] = str(source.get("defeated_boss_id", ""))
	if merged["defeated"]:
		merged["closed"] = true
	if int(merged["refused_count"]) >= 2:
		merged["closed"] = true
		merged["pending_second_chance"] = false
	return merged


func get_pair_id_for_floor(floor_index: int) -> String:
	for cfg in _get_pair_configs():
		var floors: Array = _pair_floors(cfg)
		if floors.has(floor_index):
			return str(cfg.get("pair_id", ""))
	return ""


func should_offer_optional_boss(route_context: Dictionary) -> bool:
	var floor_index: int = int(route_context.get("floor_index", route_context.get("current_floor", 1)))
	var room_index: int = int(route_context.get("room_index_on_floor", route_context.get("current_room_on_floor", 1)))
	var rooms_on_floor: int = int(route_context.get("rooms_on_floor", 1))
	var pair_id: String = get_pair_id_for_floor(floor_index)
	if pair_id.is_empty():
		return false
	var pair_state: Dictionary = _get_pair_state(pair_id)
	if bool(pair_state.get("closed", false)) or bool(pair_state.get("defeated", false)):
		return false
	if room_index > rooms_on_floor:
		return false
	var pair_cfg: Dictionary = _get_pair_config(pair_id)
	var floors: Array = _pair_floors(pair_cfg)
	var first_floor: int = int(floors[0]) if floors.size() >= 1 else -1
	var second_floor: int = int(floors[1]) if floors.size() >= 2 else -1

	# First offer: between rooms on the first floor of the pair.
	# This keeps optional boss as a replacement for a normal room, never as an added wave.
	if floor_index == first_floor and int(pair_state.get("offered_count", 0)) <= 0:
		return room_index > 1

	# Second chance: last route choice of the next floor before mandatory boss.
	if floor_index == second_floor and bool(pair_state.get("pending_second_chance", false)):
		return room_index == rooms_on_floor

	return false


func build_optional_boss_route_card(route_context: Dictionary) -> Dictionary:
	var floor_index: int = int(route_context.get("floor_index", route_context.get("current_floor", 1)))
	var pair_id: String = get_pair_id_for_floor(floor_index)
	if pair_id.is_empty():
		return {}
	var boss: Dictionary = _select_optional_boss(pair_id)
	if boss.is_empty():
		return {}
	var boss_id: String = _get_boss_id(boss)
	var ability_ids: Array = _normalize_ability_ids(boss.get("ability_ids", []))
	var card: Dictionary = {
		"choice_type": "optional_boss",
		"route_option_type": "optional_boss",
		"route_label": "Дополнительный босс",
		"room_type_name": "Дополнительный босс",
		"name": str(boss.get("name_ru", boss.get("name", boss_id))),
		"name_ru": str(boss.get("name_ru", boss.get("name", boss_id))),
		"boss_id": boss_id,
		"id": boss_id,
		"boss_scene_path": str(boss.get("boss_scene_path", boss.get("scene_path", "res://scenes/bosses/test_floor_boss.tscn"))),
		"scene_path": str(boss.get("boss_scene_path", boss.get("scene_path", "res://scenes/bosses/test_floor_boss.tscn"))),
		"portrait_path": str(boss.get("portrait_path", "")),
		"faction_id": str(boss.get("faction_id", "")),
		"creature_type_id": str(boss.get("creature_type_id", "")),
		"difficulty": str(boss.get("difficulty", boss.get("difficulty_band", "Дополнительный"))),
		"difficulty_band": str(boss.get("difficulty_band", "optional")),
		"ability_ids": ability_ids,
		"is_optional_boss": true,
		"is_echo": false,
		"optional_boss_pair_id": pair_id,
		"optional_boss_replaces_room": true,
		"boss_choice_marker": "Дополнительный босс",
		"boss_health_scale": _get_optional_health_scale(floor_index),
		"reward_preview": "Заменяет комнату. Победа: награда босса. Отказ: окно пары обновится."
	}
	_last_optional_card = card.duplicate(true)
	return card


func mark_optional_boss_offered(pair_id: String) -> void:
	if pair_id.is_empty():
		return
	var state: Dictionary = _get_pair_state(pair_id)
	if state.is_empty() or bool(state.get("closed", false)) or bool(state.get("defeated", false)):
		return
	state["offered_count"] = int(state.get("offered_count", 0)) + 1
	_set_pair_state(pair_id, state)


func mark_optional_boss_refused(pair_id: String) -> void:
	if pair_id.is_empty():
		return
	var state: Dictionary = _get_pair_state(pair_id)
	if state.is_empty() or bool(state.get("closed", false)) or bool(state.get("defeated", false)):
		return
	state["refused_count"] = int(state.get("refused_count", 0)) + 1
	if int(state.get("refused_count", 0)) >= 2:
		state["closed"] = true
		state["pending_second_chance"] = false
	else:
		state["pending_second_chance"] = true
	_set_pair_state(pair_id, state)


func mark_optional_boss_selected(pair_id: String, boss_id: String = "") -> void:
	if pair_id.is_empty():
		return
	var state: Dictionary = _get_pair_state(pair_id)
	if state.is_empty() or bool(state.get("closed", false)) or bool(state.get("defeated", false)):
		return
	state["selected_boss_id"] = boss_id
	state["pending_second_chance"] = false
	_set_pair_state(pair_id, state)


func mark_optional_boss_defeated(pair_id: String, boss_id: String) -> void:
	if pair_id.is_empty():
		return
	var state: Dictionary = _get_pair_state(pair_id)
	if state.is_empty():
		return
	state["defeated"] = true
	state["closed"] = true
	state["pending_second_chance"] = false
	state["defeated_boss_id"] = boss_id
	if str(state.get("selected_boss_id", "")).is_empty():
		state["selected_boss_id"] = boss_id
	_set_pair_state(pair_id, state)


func get_pair_state(pair_id: String) -> Dictionary:
	return _get_pair_state(pair_id).duplicate(true)


func get_last_optional_card() -> Dictionary:
	return _last_optional_card.duplicate(true)


func _get_pair_state(pair_id: String) -> Dictionary:
	match pair_id:
		PAIR_2_3:
			return pair_2_3
		PAIR_4_5:
			return pair_4_5
		PAIR_6_7:
			return pair_6_7
		_:
			return {}


func _set_pair_state(pair_id: String, state: Dictionary) -> void:
	match pair_id:
		PAIR_2_3:
			pair_2_3 = state
		PAIR_4_5:
			pair_4_5 = state
		PAIR_6_7:
			pair_6_7 = state
		_:
			pass



func _get_pair_configs() -> Array:
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_optional_boss_pairs"):
		var pairs_value: Variant = registry.call("get_optional_boss_pairs")
		if pairs_value is Array:
			var pairs: Array = pairs_value
			return pairs
	push_error("OptionalBossManager: data/run_config.json optional_boss_pairs are required; optional boss route disabled.")
	return []

func _get_pair_config(pair_id: String) -> Dictionary:
	for cfg in _get_pair_configs():
		if cfg is Dictionary and str(cfg.get("pair_id", "")) == pair_id:
			return cfg
	return {}

func _pair_floors(pair_cfg: Dictionary) -> Array:
	var raw: Variant = pair_cfg.get("floors", [])
	if raw is Array:
		var result: Array = []
		for floor_value in raw:
			result.append(int(floor_value))
		return result
	return []

func _select_optional_boss(pair_id: String) -> Dictionary:
	var candidates: Array = []
	for boss in DataRegistry.get_items("bosses"):
		if not (boss is Dictionary):
			continue
		var boss_dict: Dictionary = boss
		var boss_id: String = _get_boss_id(boss_dict)
		if boss_id.is_empty():
			continue
		if _is_boss_already_optional_defeated(boss_id):
			continue
		candidates.append(boss_dict)
	if candidates.is_empty():
		for boss in DataRegistry.get_items("bosses"):
			if boss is Dictionary:
				candidates.append(boss)
	if candidates.is_empty():
		return {}
	# Use the pair id as a soft deterministic bias without making the route predictable.
	candidates.shuffle()
	return candidates[0].duplicate(true)


func _is_boss_already_optional_defeated(boss_id: String) -> bool:
	for cfg in _get_pair_configs():
		var pair_id: String = str(cfg.get("pair_id", ""))
		var state: Dictionary = _get_pair_state(pair_id)
		if str(state.get("defeated_boss_id", "")) == boss_id:
			return true
	return false


func _get_boss_id(boss: Dictionary) -> String:
	var boss_id: String = str(boss.get("boss_id", boss.get("id", "")))
	return boss_id


func _normalize_ability_ids(raw_value: Variant) -> Array:
	var result: Array = []
	if raw_value is Array:
		for value in raw_value:
			var ability_id: String = str(value)
			if not ability_id.is_empty():
				result.append(ability_id)
	while result.size() < 3:
		result.append("")
	if result.size() > 3:
		result.resize(3)
	return result


func _get_optional_health_scale(floor_index: int) -> float:
	return 0.90 + float(max(0, floor_index - 1)) * 0.08
