extends Node

# CORE Progression Rework prep v0.09
# Generates floor boss choice cards. This replaces the old direct floor-boss roll in the main flow.
# It does not grant abilities or change combat balance yet.

const NEW_MARKER: String = "Новый"
const ECHO_MARKER: String = "Отголосок"

var unique_bosses_seen_this_run: Array[String] = []
var unique_bosses_defeated_this_run: Array[String] = []
var _last_generated_choices: Array = []
var _last_route_context: Dictionary = {}


func reset_run() -> void:
	unique_bosses_seen_this_run.clear()
	unique_bosses_defeated_this_run.clear()
	_last_generated_choices.clear()
	_last_route_context.clear()


func get_state() -> Dictionary:
	return {
		"unique_bosses_seen_this_run": unique_bosses_seen_this_run.duplicate(),
		"unique_bosses_defeated_this_run": unique_bosses_defeated_this_run.duplicate(),
		"last_generated_choices": _last_generated_choices.duplicate(true),
		"last_route_context": _last_route_context.duplicate(true)
	}


func set_state(state: Variant) -> void:
	reset_run()
	if not (state is Dictionary):
		return
	var state_dict: Dictionary = state
	for boss_id_value in state_dict.get("unique_bosses_seen_this_run", []):
		_mark_seen(str(boss_id_value))
	for boss_id_value in state_dict.get("unique_bosses_defeated_this_run", []):
		_mark_defeated(str(boss_id_value))
	var choices: Variant = state_dict.get("last_generated_choices", [])
	if choices is Array:
		_last_generated_choices = choices.duplicate(true)
	var route_context: Variant = state_dict.get("last_route_context", {})
	if route_context is Dictionary:
		_last_route_context = route_context.duplicate(true)


func generate_boss_choices(route_context: Dictionary = {}) -> Array:
	_last_route_context = route_context.duplicate(true)
	var seen_count_before_roll: int = unique_bosses_seen_this_run.size()
	var excluded_ids: Array[String] = []
	var choices: Array = []
	for slot_index in range(2):
		var preferred_mode: String = _roll_mode_for_slot(slot_index, seen_count_before_roll)
		var resolved_mode: String = preferred_mode
		var boss: Dictionary = _select_boss_for_mode(resolved_mode, excluded_ids)
		if boss.is_empty():
			resolved_mode = "echo" if preferred_mode == "new" else "new"
			boss = _select_boss_for_mode(resolved_mode, excluded_ids)
		if boss.is_empty():
			# Both requested mode and legal fallback failed. Keep the flow valid by offering a known boss as a normal card, never as invalid Echo.
			resolved_mode = "new"
			boss = _select_any_known_boss(excluded_ids)
		if boss.is_empty():
			continue
		var is_echo: bool = resolved_mode == "echo"
		var boss_id: String = _get_boss_id(boss)
		excluded_ids.append(boss_id)
		var card: Dictionary = _make_boss_choice_card(boss, is_echo, slot_index + 1, route_context)
		choices.append(card)
		_mark_seen(boss_id)
	_last_generated_choices = choices.duplicate(true)
	return choices


func mark_boss_selected(card: Dictionary) -> void:
	if not (card is Dictionary):
		return
	_mark_seen(str(card.get("boss_id", "")))


func mark_boss_defeated(boss_id: String) -> void:
	_mark_defeated(boss_id)
	_mark_seen(boss_id)


func get_last_generated_choices() -> Array:
	return _last_generated_choices.duplicate(true)


func _roll_mode_for_slot(slot_index: int, seen_count: int) -> String:
	if _get_new_candidates([]).is_empty():
		return "echo"
	var new_probability: float = _get_new_probability(slot_index, seen_count)
	return "new" if randf() <= new_probability else "echo"


func _get_new_probability(slot_index: int, seen_count: int) -> float:
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_boss_choice_new_probability"):
		return clampf(float(registry.call("get_boss_choice_new_probability", slot_index, seen_count)), 0.0, 1.0)
	push_error("BossChoiceManager: DataRegistry.get_boss_choice_new_probability() is required; refusing silent hardcoded fallback.")
	return 0.0


func _select_boss_for_mode(mode: String, excluded_ids: Array[String]) -> Dictionary:
	var candidates: Array = _get_echo_candidates(excluded_ids) if mode == "echo" else _get_new_candidates(excluded_ids)
	if candidates.is_empty():
		return {}
	return candidates.pick_random().duplicate(true)


func _get_new_candidates(excluded_ids: Array[String]) -> Array:
	var result: Array = []
	for boss in _get_all_bosses():
		var boss_id: String = _get_boss_id(boss)
		if boss_id.is_empty():
			continue
		if excluded_ids.has(boss_id):
			continue
		if unique_bosses_seen_this_run.has(boss_id):
			continue
		result.append(boss)
	return result


func _get_echo_candidates(excluded_ids: Array[String]) -> Array:
	var allowed_ids: Array[String] = []
	for boss_id in unique_bosses_defeated_this_run:
		if not boss_id.is_empty() and not allowed_ids.has(boss_id):
			allowed_ids.append(boss_id)
	for boss_id in _get_meta_defeated_boss_ids():
		if not boss_id.is_empty() and not allowed_ids.has(boss_id):
			allowed_ids.append(boss_id)

	var result: Array = []
	for boss in _get_all_bosses():
		var boss_id: String = _get_boss_id(boss)
		if boss_id.is_empty() or excluded_ids.has(boss_id):
			continue
		if not bool(boss.get("can_be_echo", true)):
			continue
		if allowed_ids.has(boss_id):
			result.append(boss)
	return result


func _get_any_echo_capable_bosses(excluded_ids: Array[String]) -> Array:
	var result: Array = []
	for boss in _get_all_bosses():
		var boss_id: String = _get_boss_id(boss)
		if boss_id.is_empty() or excluded_ids.has(boss_id):
			continue
		if bool(boss.get("can_be_echo", true)):
			result.append(boss)
	return result


func _select_any_known_boss(excluded_ids: Array[String]) -> Dictionary:
	var candidates: Array = _get_all_bosses()
	var filtered: Array = []
	for boss in candidates:
		var boss_id: String = _get_boss_id(boss)
		if boss_id.is_empty() or excluded_ids.has(boss_id):
			continue
		filtered.append(boss)
	if filtered.is_empty():
		filtered = candidates
	return filtered.pick_random().duplicate(true) if not filtered.is_empty() else {}


func _make_boss_choice_card(boss: Dictionary, is_echo: bool, slot_number: int, route_context: Dictionary) -> Dictionary:
	var boss_id: String = _get_boss_id(boss)
	var ability_ids: Array = _normalize_ability_ids(boss.get("ability_ids", []))
	var ability_previews: Array = []
	for ability_id in ability_ids:
		ability_previews.append(_make_ability_preview(ability_id))
	var floor_index: int = int(route_context.get("floor_index", route_context.get("current_floor", RunManager.current_floor_index if has_node("/root/RunManager") else 1)))
	return {
		"choice_type": "boss_choice",
		"boss_id": boss_id,
		"id": boss_id,
		"name": str(boss.get("name_ru", boss.get("name", boss_id))),
		"name_ru": str(boss.get("name_ru", boss.get("name", boss_id))),
		"portrait_path": str(boss.get("portrait_path", "")),
		"boss_scene_path": str(boss.get("boss_scene_path", boss.get("scene_path", "res://scenes/bosses/test_floor_boss.tscn"))),
		"scene_path": str(boss.get("boss_scene_path", boss.get("scene_path", "res://scenes/bosses/test_floor_boss.tscn"))),
		"faction_id": str(boss.get("faction_id", "")),
		"faction_name": str(boss.get("faction_name", boss.get("faction", ""))),
		"creature_type_id": str(boss.get("creature_type_id", "")),
		"difficulty": str(boss.get("difficulty", boss.get("difficulty_band", "Средняя"))),
		"difficulty_band": str(boss.get("difficulty_band", "")),
		"ability_ids": ability_ids,
		"ability_previews": ability_previews,
		"is_echo": is_echo,
		"boss_choice_marker": ECHO_MARKER if is_echo else NEW_MARKER,
		"echo_source": _resolve_echo_source(boss_id) if is_echo else "new_roll",
		"floor": floor_index,
		"slot_number": slot_number,
		"boss_health_scale": _get_health_scale(floor_index, is_echo),
		"reward_preview": "Способность босса / путь эссенции"
	}


func _make_ability_preview(ability_id: String) -> Dictionary:
	var ability: Dictionary = DataRegistry.get_boss_ability(ability_id) if has_node("/root/DataRegistry") else {}
	var current_level: int = _get_current_boss_ability_level(ability_id)
	var next_level: int = min(3, current_level + 1)
	var tooltip: Dictionary = {}
	var system: Node = get_node_or_null("/root/BossAbilitySystem")
	if system != null and system.has_method("get_tooltip_data"):
		var tooltip_value: Variant = system.call("get_tooltip_data", ability_id)
		if tooltip_value is Dictionary:
			tooltip = tooltip_value
	var next_description: String = str(tooltip.get("next_description_ru", ""))
	if next_description.is_empty():
		next_description = _player_level_description(ability, next_level)
	return {
		"ability_id": ability_id,
		"name_ru": str(ability.get("name_ru", ability_id)),
		"description_ru": str(ability.get("description_ru", next_description)),
		"current_level": current_level,
		"next_level": next_level if current_level < 3 else 0,
		"next_description_ru": next_description if current_level < 3 else "Максимальный уровень уже достигнут.",
		"tags": _player_level_tags(ability, next_level),
		"icon_path": str(ability.get("icon_path", "")),
		"icon_profile": ability.get("icon_profile", {}) if ability.get("icon_profile", {}) is Dictionary else {},
		"faction_id": str(ability.get("faction_id", ""))
	}

func _get_current_boss_ability_level(ability_id: String) -> int:
	var boss_ability_system: Node = get_node_or_null("/root/BossAbilitySystem")
	if boss_ability_system != null and boss_ability_system.has_method("get_level"):
		return clampi(int(boss_ability_system.call("get_level", ability_id)), 0, 3)
	return 0


func _player_level_description(ability: Dictionary, level: int) -> String:
	if level <= 0:
		return ""
	var player_version: Variant = ability.get("player_version", {})
	if player_version is Dictionary:
		var levels_raw: Variant = player_version.get("levels", {})
		if levels_raw is Dictionary:
			var level_raw: Variant = levels_raw.get(str(level), {})
			if level_raw is Dictionary:
				return str(level_raw.get("description_ru", ""))
	return ""

func _player_level_tags(ability: Dictionary, level: int) -> Array:
	if level <= 0:
		return []
	var player_version: Variant = ability.get("player_version", {})
	if player_version is Dictionary:
		var levels_raw: Variant = player_version.get("levels", {})
		if levels_raw is Dictionary:
			var level_raw: Variant = levels_raw.get(str(level), {})
			if level_raw is Dictionary:
				var effect_tags: Variant = level_raw.get("effect_tags", [])
				return effect_tags.duplicate(true) if effect_tags is Array else []
	return []

func _normalize_ability_ids(raw: Variant) -> Array:
	var result: Array = []
	if raw is Array:
		for ability_id_value in raw:
			var ability_id: String = str(ability_id_value)
			if not ability_id.is_empty():
				result.append(ability_id)
			if result.size() >= 3:
				break
	return result


func _get_health_scale(floor_index: int, is_echo: bool) -> float:
	var scale: float = 1.0 + max(0, floor_index - 1) * 0.16
	if is_echo:
		scale *= 0.92
	return scale


func _resolve_echo_source(boss_id: String) -> String:
	if unique_bosses_defeated_this_run.has(boss_id):
		return "current_run_defeated"
	if _get_meta_defeated_boss_ids().has(boss_id):
		return "meta_progression_defeated"
	return "unavailable"


func _get_meta_defeated_boss_ids() -> Array[String]:
	var result: Array[String] = []
	var meta: Node = get_node_or_null("/root/MetaProgression")
	if meta == null:
		return result
	var value: Variant = []
	if meta.has_method("get_defeated_boss_ids"):
		value = meta.call("get_defeated_boss_ids")
	elif meta.has_method("get_bosses_defeated_ever"):
		value = meta.call("get_bosses_defeated_ever")
	else:
		value = meta.get("bosses_defeated_ever")
	if value is Array:
		for boss_id_value in value:
			var boss_id: String = str(boss_id_value).strip_edges()
			if not boss_id.is_empty() and not result.has(boss_id):
				result.append(boss_id)
	return result


func _get_all_bosses() -> Array:
	var bosses: Array = DataRegistry.get_items("bosses") if has_node("/root/DataRegistry") else []
	var result: Array = []
	for boss in bosses:
		if boss is Dictionary:
			var boss_dict: Dictionary = boss
			if not _get_boss_id(boss_dict).is_empty():
				result.append(boss_dict)
	return result


func _get_boss_id(boss: Dictionary) -> String:
	return str(boss.get("boss_id", boss.get("id", "")))


func _mark_seen(boss_id: String) -> void:
	if boss_id.is_empty():
		return
	if not unique_bosses_seen_this_run.has(boss_id):
		unique_bosses_seen_this_run.append(boss_id)


func _mark_defeated(boss_id: String) -> void:
	if boss_id.is_empty():
		return
	if not unique_bosses_defeated_this_run.has(boss_id):
		unique_bosses_defeated_this_run.append(boss_id)
	var meta: Node = get_node_or_null("/root/MetaProgression")
	if meta != null and meta.has_method("mark_boss_defeated_ever"):
		meta.call("mark_boss_defeated_ever", boss_id)
