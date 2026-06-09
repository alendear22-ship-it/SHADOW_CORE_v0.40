extends Node

# CORE Progression Rework v0.15
# Source of truth for post-boss reward cards. It is the only post-boss reward card source
# after mandatory bosses, optional bosses and echo encounters.

const MAX_LEVEL: int = 3
const DECLINE_SOUL_ASH: int = 5

var _last_reward_payload: Dictionary = {}

func reset_run() -> void:
	_last_reward_payload.clear()

func get_state() -> Dictionary:
	return {
		"last_reward_payload": _last_reward_payload.duplicate(true)
	}

func set_state(state: Variant) -> void:
	_last_reward_payload.clear()
	if not (state is Dictionary):
		return
	var payload: Variant = state.get("last_reward_payload", {})
	if payload is Dictionary:
		_last_reward_payload = payload.duplicate(true)

func build_reward_payload(boss_id: String, context: Dictionary = {}) -> Dictionary:
	var is_optional: bool = bool(context.get("is_optional", false))
	var is_echo: bool = bool(context.get("is_echo", false))
	var boss: Dictionary = _get_boss_data(boss_id)
	var options: Array = build_reward_cards(boss_id, context)
	_mark_reward_abilities_seen(options)
	var title: String = "Награда Отголоска босса" if is_echo else ("Награда дополнительного босса" if is_optional else "Награда босса")
	var marker: String = "Отголосок босса побеждён" if is_echo else ("Дополнительный босс побеждён" if is_optional else "Обязательный босс побеждён")
	var payload: Dictionary = {
		"reward_kind": "boss_ability_reward",
		"boss_id": boss_id,
		"boss_name": str(boss.get("name_ru", boss.get("name", boss_id))),
		"boss_faction_id": str(boss.get("faction_id", "")),
		"boss_creature_type_id": str(boss.get("creature_type_id", "")),
		"is_optional": is_optional,
		"is_echo": is_echo,
		"title": title,
		"marker": marker,
		"description": "Выберите одну из 3 способностей босса. Новая способность открывается через слот активной способности; уже открытая способность улучшается до уровня 3. Отказ: +5 Пепла Душ.",
		"decline_reward_soul_ash": DECLINE_SOUL_ASH,
		"can_decline_for_soul_ash": true,
		"reward_options": options,
		"source_of_truth": "data/boss_abilities.json"
	}
	_last_reward_payload = payload.duplicate(true)
	return payload

func build_reward_cards(boss_id: String, context: Dictionary = {}) -> Array:
	var result: Array = []
	var boss: Dictionary = _get_boss_data(boss_id)
	var ability_ids: Array = _get_boss_ability_ids(boss_id, boss)
	for ability_id_value in ability_ids:
		var ability_id: String = str(ability_id_value)
		if ability_id.is_empty():
			continue
		var card: Dictionary = build_reward_card(ability_id, boss_id, context)
		if not card.is_empty():
			result.append(card)
		if result.size() >= 3:
			break
	return result

func build_reward_card(boss_ability_id: String, boss_id: String = "", context: Dictionary = {}) -> Dictionary:
	if boss_ability_id.is_empty():
		return {}
	var ability: Dictionary = _get_ability_data(boss_ability_id)
	if ability.is_empty():
		return {}
	var current_level: int = _get_level(boss_ability_id)
	var unlocked: bool = _is_unlocked(boss_ability_id)
	var maxed: bool = current_level >= MAX_LEVEL
	var meta_locked: bool = _is_meta_locked(boss_ability_id)
	var locked: bool = bool(context.get("locked", false)) or meta_locked
	var action: String = "install"
	var state: String = "AVAILABLE"
	if maxed:
		action = "max"
		state = "MAX"
	elif unlocked or current_level > 0:
		action = "upgrade"
		state = "AVAILABLE"
	if locked:
		state = "LOCKED"
	var next_level: int = 0 if maxed else clampi(max(1, current_level + 1), 1, MAX_LEVEL)
	var current_level_data: Dictionary = _get_level_data(ability, current_level) if current_level > 0 else {}
	var next_level_data: Dictionary = _get_level_data(ability, next_level) if next_level > 0 else {}
	return {
		"boss_ability_id": boss_ability_id,
		"id": boss_ability_id,
		"boss_id": str(ability.get("boss_id", boss_id)),
		"creature_type_id": str(ability.get("creature_type_id", "")),
		"faction_id": str(ability.get("faction_id", "")),
		"name_ru": str(ability.get("name_ru", boss_ability_id)),
		"icon_path": str(ability.get("icon_path", "")),
		"icon_profile": ability.get("icon_profile", {}) if ability.get("icon_profile", {}) is Dictionary else {},
		"visual_summary_ru": _build_visual_summary_ru(ability),
		"current_level": current_level,
		"next_level": next_level,
		"max_level": MAX_LEVEL,
		"is_unlocked": unlocked,
		"is_max_level": maxed,
		"locked": locked,
		"meta_locked": meta_locked,
		"state": state,
		"action": action,
		"reward_action": action,
		"version": "player_version",
		"button_label": _button_label_for_action(action, state),
		"description_ru": str(ability.get("description_ru", "")),
		"current_description_ru": str(current_level_data.get("description_ru", "Не открыта.")),
		"next_description_ru": str(next_level_data.get("description_ru", "Максимальный уровень уже достигнут." if maxed else "")),
		"current_tags": _safe_array(current_level_data.get("effect_tags", current_level_data.get("tags", []))),
		"next_tags": _safe_array(next_level_data.get("effect_tags", next_level_data.get("tags", []))),
		"current_player_version": current_level_data.duplicate(true),
		"next_player_version": next_level_data.duplicate(true),
		"current_player_effect_data": current_level_data.get("effect_data", {}) if current_level_data.get("effect_data", {}) is Dictionary else {},
		"next_player_effect_data": next_level_data.get("effect_data", {}) if next_level_data.get("effect_data", {}) is Dictionary else {},
		"reaction_tags": _safe_array(current_level_data.get("reaction_tags", [])),
		"disabled": state == "MAX" or state == "LOCKED"
	}

func get_last_reward_payload() -> Dictionary:
	return _last_reward_payload.duplicate(true)

func get_reward_option(boss_ability_id: String, payload: Dictionary = {}) -> Dictionary:
	var source: Dictionary = payload if not payload.is_empty() else _last_reward_payload
	var options: Variant = source.get("reward_options", [])
	if options is Array:
		for option_value in options:
			if option_value is Dictionary:
				var option: Dictionary = option_value
				if str(option.get("boss_ability_id", option.get("id", ""))) == boss_ability_id:
					return option.duplicate(true)
	return build_reward_card(boss_ability_id)

func get_action_for_ability(boss_ability_id: String) -> String:
	var card: Dictionary = build_reward_card(boss_ability_id)
	return str(card.get("action", "unlock"))

func can_select_reward_option(option: Dictionary) -> bool:
	if option.is_empty():
		return false
	if bool(option.get("disabled", false)):
		return false
	var state: String = str(option.get("state", "AVAILABLE"))
	return state != "MAX" and state != "LOCKED"


func _mark_reward_abilities_seen(options: Array) -> void:
	var meta: Node = get_node_or_null("/root/MetaProgression")
	if meta == null or not meta.has_method("mark_boss_ability_seen"):
		return
	for option_value in options:
		if not (option_value is Dictionary):
			continue
		var option: Dictionary = option_value
		var ability_id: String = str(option.get("boss_ability_id", option.get("id", ""))).strip_edges()
		if not ability_id.is_empty():
			meta.call("mark_boss_ability_seen", ability_id, false)
	if meta.has_method("save_meta"):
		meta.call("save_meta")

func _get_boss_data(boss_id: String) -> Dictionary:
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_by_id"):
		var boss: Variant = registry.call("get_by_id", "bosses", boss_id)
		if boss is Dictionary:
			return boss
	return {}

func _get_ability_data(boss_ability_id: String) -> Dictionary:
	var system: Node = get_node_or_null("/root/BossAbilitySystem")
	if system != null and system.has_method("get_ability_data"):
		var system_data: Variant = system.call("get_ability_data", boss_ability_id)
		if system_data is Dictionary:
			return system_data
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_boss_ability"):
		var data: Variant = registry.call("get_boss_ability", boss_ability_id)
		if data is Dictionary:
			return data
	return {}

func _get_boss_ability_ids(boss_id: String, boss: Dictionary) -> Array:
	var result: Array = []
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_boss_abilities_for_boss"):
		var abilities: Variant = registry.call("get_boss_abilities_for_boss", boss_id)
		if abilities is Array:
			for ability_value in abilities:
				if ability_value is Dictionary:
					var ability: Dictionary = ability_value
					var ability_id: String = str(ability.get("boss_ability_id", ability.get("id", "")))
					if not ability_id.is_empty() and not result.has(ability_id):
						result.append(ability_id)
				if result.size() >= 3:
					break
	if result.size() >= 3:
		return result
	var raw_ids: Variant = boss.get("ability_ids", [])
	if raw_ids is Array:
		for value in raw_ids:
			var ability_id: String = str(value)
			if not ability_id.is_empty() and not result.has(ability_id):
				result.append(ability_id)
	return result

func _get_level(boss_ability_id: String) -> int:
	var system: Node = get_node_or_null("/root/BossAbilitySystem")
	if system != null and system.has_method("get_level"):
		return clampi(int(system.call("get_level", boss_ability_id)), 0, MAX_LEVEL)
	return 0

func _is_unlocked(boss_ability_id: String) -> bool:
	var system: Node = get_node_or_null("/root/BossAbilitySystem")
	if system != null and system.has_method("is_unlocked"):
		return bool(system.call("is_unlocked", boss_ability_id))
	return _get_level(boss_ability_id) > 0

func _is_meta_locked(boss_ability_id: String) -> bool:
	# meta_unlocks.json currently contains disabled templates only. Keep the hook safe and explicit.
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry == null or not registry.has_method("get_items"):
		return false
	var unlocks: Variant = registry.call("get_items", "meta_unlocks")
	if not (unlocks is Array):
		return false
	for unlock_value in unlocks:
		if not (unlock_value is Dictionary):
			continue
		var unlock: Dictionary = unlock_value
		if str(unlock.get("unlock_type", "")) != "boss_ability_unlock":
			continue
		if not bool(unlock.get("enabled", false)):
			continue
		var payload: Variant = unlock.get("payload", {})
		if payload is Dictionary and str(payload.get("unlock_id", "")) == boss_ability_id:
			return true
	return false

func _get_level_data(ability: Dictionary, level: int) -> Dictionary:
	if level <= 0:
		return {}
	var system: Node = get_node_or_null("/root/BossAbilitySystem")
	var ability_id: String = str(ability.get("boss_ability_id", ability.get("id", "")))
	if system != null and system.has_method("get_player_version") and not ability_id.is_empty():
		var player_data: Variant = system.call("get_player_version", ability_id, level)
		if player_data is Dictionary:
			return player_data
	var player_version_raw: Variant = ability.get("player_version", {})
	if player_version_raw is Dictionary:
		var levels_raw: Variant = player_version_raw.get("levels", {})
		if levels_raw is Dictionary:
			var level_raw: Variant = levels_raw.get(str(level), {})
			if level_raw is Dictionary:
				return level_raw
	return {}


func _build_visual_summary_ru(ability: Dictionary) -> String:
	var visual_profile_raw: Variant = ability.get("visual_profile", {})
	if not (visual_profile_raw is Dictionary):
		return "Визуал: базовый эффект"
	var visual_profile: Dictionary = visual_profile_raw
	var player_raw: Variant = visual_profile.get("player_version", {})
	if not (player_raw is Dictionary):
		return "Визуал: базовый эффект"
	var player_profile: Dictionary = player_raw
	var parts: Array[String] = []
	if not str(player_profile.get("zone_visual_id", "")).is_empty():
		parts.append("зона")
	if not str(player_profile.get("delayed_visual_id", "")).is_empty():
		parts.append("задержка")
	if not str(player_profile.get("travel_visual_id", "")).is_empty():
		parts.append("след/волна")
	if not str(player_profile.get("status_visual_id", "")).is_empty():
		parts.append("статус/метка")
	if not str(player_profile.get("impact_visual_id", "")).is_empty():
		parts.append("попадание")
	if parts.is_empty():
		return "Визуал: применение"
	return "Визуал: " + ", ".join(parts)

func _safe_array(value: Variant) -> Array:
	if value is Array:
		return value.duplicate(true)
	return []

func _button_label_for_action(action: String, state: String) -> String:
	if state == "MAX":
		return "МАКС."
	if state == "LOCKED":
		return "Закрыто"
	if action == "upgrade":
		return "Улучшить"
	return "Открыть"
