extends Node

signal visual_spawned(profile_id: String, node: Node)
signal visual_missing(profile_id: String, fallback_id: String)

const PROFILES_COLLECTION: String = "effect_visual_profiles"
const FALLBACK_VISUAL_ID: String = "VISUAL_GENERIC_HIT"
const REACTION_VISUAL_ID: String = "VISUAL_GENERIC_REACTION_BURST"
const DEFAULT_ICON_VISUAL_ID: String = "VISUAL_GENERIC_CAST"

const ImpactEffectScript = preload("res://scripts/effects/procedural_impact_effect.gd")
const ConeEffectScript = preload("res://scripts/effects/procedural_cone_effect.gd")
const ZoneEffectScript = preload("res://scripts/effects/procedural_zone_effect.gd")
const ProjectileTrailScript = preload("res://scripts/effects/procedural_projectile_trail.gd")
const StatusAuraScript = preload("res://scripts/effects/procedural_status_aura.gd")
const TelegraphEffectScript = preload("res://scripts/effects/procedural_telegraph_effect.gd")

var reaction_visual_hook_enabled: bool = true
var boss_ability_visual_hook_enabled: bool = true
var max_active_effects: int = 60
var _profiles_by_id: Dictionary = {}
var _fallback_rules: Array = []
var _spawned_this_frame: Dictionary = {}

func _ready() -> void:
	_load_profiles()
	_connect_visual_events()

func reset_run() -> void:
	_spawned_this_frame.clear()

func get_state() -> Dictionary:
	return {
		"profiles_loaded": _profiles_by_id.size(),
		"reaction_visual_hook_enabled": reaction_visual_hook_enabled,
		"boss_ability_visual_hook_enabled": boss_ability_visual_hook_enabled,
		"max_active_effects": max_active_effects,
		"active_effect_count": get_tree().get_nodes_in_group("combat_effects").size()
	}

func set_state(state: Variant = {}) -> void:
	if state is Dictionary:
		reaction_visual_hook_enabled = bool(state.get("reaction_visual_hook_enabled", reaction_visual_hook_enabled))
		boss_ability_visual_hook_enabled = bool(state.get("boss_ability_visual_hook_enabled", boss_ability_visual_hook_enabled))
		max_active_effects = max(1, int(state.get("max_active_effects", max_active_effects)))

func can_spawn_minor_effect() -> bool:
	return get_tree().get_nodes_in_group("combat_effects").size() < max_active_effects

func spawn_visual(profile_id: String, context: Dictionary = {}) -> Node:
	var profile: Dictionary = get_visual_profile(profile_id)
	if profile.is_empty():
		visual_missing.emit(profile_id, FALLBACK_VISUAL_ID)
		push_warning("EffectVisualSystem: missing visual profile: " + profile_id + ", using " + FALLBACK_VISUAL_ID)
		profile = get_visual_profile(FALLBACK_VISUAL_ID)
	return spawn_visual_from_profile(profile, context)

func spawn_visual_from_profile(profile: Dictionary, context: Dictionary = {}) -> Node:
	if profile.is_empty():
		return null
	var is_minor: bool = bool(profile.get("minor_effect", true)) and not bool(profile.get("critical_telegraph_or_impact", false))
	if is_minor and not can_spawn_minor_effect():
		return null
	var event_key: String = str(context.get("visual_event_id", context.get("source_event_id", "")))
	if not event_key.is_empty() and _spawned_this_frame.has(event_key):
		return _spawned_this_frame[event_key]
	var effect: Node2D = _create_effect_node(profile)
	if effect == null:
		return null
	var parent: Node = _resolve_parent(context)
	parent.add_child(effect)
	if effect.has_method("setup"):
		effect.call("setup", profile, context)
	if not event_key.is_empty():
		_spawned_this_frame[event_key] = effect
		call_deferred("_clear_spawn_key", event_key)
	visual_spawned.emit(str(profile.get("id", "")), effect)
	return effect

func spawn_icon_preview(profile_id: String, size: Vector2 = Vector2(64, 64)) -> Texture2D:
	var profile: Dictionary = get_visual_profile(profile_id)
	if profile.is_empty():
		profile = get_visual_profile(DEFAULT_ICON_VISUAL_ID)
	var factory: Node = get_node_or_null("/root/ProceduralIconFactory")
	if factory != null and factory.has_method("get_icon_texture"):
		return factory.call("get_icon_texture", profile, int(max(size.x, size.y)))
	return null

func get_visual_profile(profile_id: String) -> Dictionary:
	if _profiles_by_id.is_empty():
		_load_profiles()
	return _profiles_by_id.get(profile_id, {}).duplicate(true) if _profiles_by_id.has(profile_id) else {}

func has_visual_profile(profile_id: String) -> bool:
	if _profiles_by_id.is_empty():
		_load_profiles()
	return _profiles_by_id.has(profile_id)

func resolve_profile_id_for_data(data: Dictionary, preferred_key: String = "impact") -> String:
	var visual_profile: Variant = data.get("visual_profile", {})
	if visual_profile is Dictionary:
		var profile_dict: Dictionary = visual_profile
		var player_version_raw: Variant = profile_dict.get("player_version", {})
		if player_version_raw is Dictionary:
			var player_version: Dictionary = player_version_raw
			var nested_id: String = str(player_version.get(preferred_key + "_visual_id", player_version.get(preferred_key, "")))
			if not nested_id.is_empty() and has_visual_profile(nested_id):
				return nested_id
		var preferred_id: String = str(profile_dict.get(preferred_key + "_visual_id", profile_dict.get(preferred_key, "")))
		if not preferred_id.is_empty() and has_visual_profile(preferred_id):
			return preferred_id
		for key in ["player_impact_visual_id", "player_cast_visual_id", "boss_impact_visual_id", "weak_mob_visual_id", "icon_profile_id"]:
			var value: String = str(profile_dict.get(key, ""))
			if not value.is_empty() and has_visual_profile(value):
				return value
	var tags: Array = _collect_tags(data)
	for rule_value in _fallback_rules:
		if not (rule_value is Dictionary):
			continue
		var rule: Dictionary = rule_value
		var match_tags: Array = rule.get("match_any_tag", []) if rule.get("match_any_tag", []) is Array else []
		for tag_value in match_tags:
			if tags.has(str(tag_value).to_lower()):
				var visual_id: String = str(rule.get("visual_id", ""))
				if has_visual_profile(visual_id):
					return visual_id
	return FALLBACK_VISUAL_ID

func _connect_visual_events() -> void:
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		_safe_connect_signal(bus, &"reaction_visual_requested", Callable(self, "_on_reaction_visual_requested"))
	var boss_system: Node = get_node_or_null("/root/BossAbilitySystem")
	if boss_system != null:
		_safe_connect_signal(boss_system, &"boss_ability_effect_applied", Callable(self, "_on_boss_ability_effect_applied"))

func _safe_connect_signal(source: Object, signal_name: StringName, target: Callable) -> void:
	if source == null or not source.has_signal(signal_name) or not target.is_valid():
		return
	if source.is_connected(signal_name, target):
		return
	source.connect(signal_name, target)

func _on_reaction_visual_requested(reaction_data: Dictionary) -> void:
	if not reaction_visual_hook_enabled:
		return
	var profile_id: String = str(reaction_data.get("visual_profile_id", REACTION_VISUAL_ID))
	var context: Dictionary = reaction_data.duplicate(true)
	context["visual_event_id"] = "reaction:" + str(reaction_data.get("source_event_id", Time.get_ticks_msec()))
	spawn_visual(profile_id, context)

func _on_boss_ability_effect_applied(boss_ability_id: String, level: int, tags: Array, context: Dictionary) -> void:
	if not boss_ability_visual_hook_enabled:
		return
	var data: Dictionary = {}
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_boss_ability"):
		var raw: Variant = registry.call("get_boss_ability", boss_ability_id)
		if raw is Dictionary:
			data = raw
	if data.is_empty():
		return
	var visual_profile_raw: Variant = data.get("visual_profile", {})
	if not (visual_profile_raw is Dictionary):
		return
	var visual_profile: Dictionary = visual_profile_raw
	var player_version_raw: Variant = visual_profile.get("player_version", {})
	if not (player_version_raw is Dictionary):
		return
	var player_version: Dictionary = player_version_raw
	var base_context: Dictionary = context.duplicate(true)
	base_context["effect_tags"] = tags.duplicate()
	base_context["level"] = level
	base_context["boss_ability_id"] = boss_ability_id
	base_context["version"] = "player_version"
	base_context["power_scale"] = float(base_context.get("power_scale", 1.0))
	var spawn_order: Array = [
		["cast", "cast_visual_id"],
		["delayed", "delayed_visual_id"],
		["travel", "travel_visual_id"],
		["impact", "impact_visual_id"],
		["zone", "zone_visual_id"],
		["status", "status_visual_id"]
	]
	for pair in spawn_order:
		var slot_name: String = str(pair[0])
		var key: String = str(pair[1])
		var visual_id: String = str(player_version.get(key, ""))
		if visual_id.is_empty():
			continue
		var visual_context: Dictionary = base_context.duplicate(true)
		visual_context["visual_slot"] = slot_name
		visual_context["visual_spawned"] = true
		visual_context["visual_event_id"] = _build_visual_event_id(boss_ability_id, level, slot_name, base_context)
		spawn_visual(visual_id, visual_context)

func _create_effect_node(profile: Dictionary) -> Node2D:
	var visual_type: String = str(profile.get("visual_type", "impact"))
	if visual_type.contains("telegraph") or visual_type.contains("delayed"):
		return TelegraphEffectScript.new()
	if visual_type.contains("zone") or visual_type.contains("puddle") or visual_type.contains("patch") or visual_type.contains("cloud") or visual_type.contains("vortex") or visual_type.contains("rift"):
		return ZoneEffectScript.new()
	if visual_type.contains("projectile") or visual_type.contains("trail") or visual_type.contains("wave") or visual_type.contains("orb") or visual_type.contains("chain"):
		return ProjectileTrailScript.new()
	if visual_type.contains("status") or visual_type.contains("mark") or visual_type.contains("aura"):
		return StatusAuraScript.new()
	if visual_type.contains("cone"):
		return ConeEffectScript.new()
	return ImpactEffectScript.new()

func _resolve_parent(context: Dictionary) -> Node:
	var parent_value: Variant = context.get("parent", null)
	if parent_value is Node and is_instance_valid(parent_value):
		return parent_value
	var scene: Node = get_tree().current_scene
	if scene != null:
		return scene
	return get_tree().root

func _load_profiles() -> void:
	_profiles_by_id.clear()
	_fallback_rules.clear()
	var raw: Variant = null
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_raw"):
		raw = registry.call("get_raw", PROFILES_COLLECTION)
	if not (raw is Dictionary):
		raw = _load_profiles_from_json()
	if not (raw is Dictionary):
		return
	var items: Array = raw.get("items", []) if raw.get("items", []) is Array else []
	for item_value in items:
		if item_value is Dictionary:
			var item: Dictionary = item_value
			var profile_id: String = str(item.get("id", ""))
			if not profile_id.is_empty():
				_profiles_by_id[profile_id] = item
	_fallback_rules = raw.get("fallback_rules", []) if raw.get("fallback_rules", []) is Array else []

func _load_profiles_from_json() -> Variant:
	var path: String = "res://data/effect_visual_profiles.json"
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	return JSON.parse_string(file.get_as_text())

func _collect_tags(data: Dictionary) -> Array:
	var result: Array = []
	for key in ["effect_tags", "reaction_tags", "tags"]:
		var raw: Variant = data.get(key, [])
		if raw is Array:
			for value in raw:
				var tag: String = str(value).to_lower()
				if not tag.is_empty() and not result.has(tag):
					result.append(tag)
	var version_keys: Array = ["player_version", "boss_version", "weak_mob_version"]
	for version_key in version_keys:
		var version: Variant = data.get(version_key, {})
		if version is Dictionary:
			var levels: Variant = version.get("levels", {})
			if levels is Dictionary:
				for level_key in levels.keys():
					var level: Variant = levels[level_key]
					if level is Dictionary:
						var effect_tags_raw: Variant = level.get("effect_tags", [])
						if effect_tags_raw is Array:
							for tag in effect_tags_raw:
								var lower_tag: String = str(tag).to_lower()
								if not lower_tag.is_empty() and not result.has(lower_tag):
									result.append(lower_tag)
	return result

func _build_visual_event_id(boss_ability_id: String, level: int, visual_slot: String, context: Dictionary) -> String:
	var source_event_id: String = str(context.get("source_event_id", ""))
	var target_id: String = str(context.get("target_id", ""))
	if source_event_id.is_empty():
		source_event_id = str(context.get("active_ability_id", "active")) + ":" + target_id
	return "player_boss_vfx:" + boss_ability_id + ":L" + str(level) + ":" + visual_slot + ":" + source_event_id

func _clear_spawn_key(event_key: String) -> void:
	_spawned_this_frame.erase(event_key)
