extends Node

signal altar_used(floor_index: int, sacrifice_result: Dictionary)
signal altar_card_applied(card_data: Dictionary, result: Dictionary)

const SOUL_ASH_DIVISOR: int = 5
const MINIMUM_SACRIFICE: int = 20

var used_floors: Dictionary = {}
var last_sacrifice: Dictionary = {}
var applied_cards: Array[Dictionary] = []
var weapon_upgrade_level: int = 0 # legacy mirror: sum of weapon_upgrade_levels
var weapon_upgrade_levels: Dictionary = {}
var boss_ability_levels: Dictionary = {}
var service_state: Dictionary = {"heal_cards_used": 0} # Reroll/service cards are disabled from active card pool until full implementation.

func reset_run() -> void:
	used_floors.clear()
	last_sacrifice.clear()
	applied_cards.clear()
	weapon_upgrade_level = 0
	weapon_upgrade_levels.clear()
	boss_ability_levels.clear()
	service_state = {"heal_cards_used": 0}
	_emit_run_resource_changed()

func can_use_altar(floor: int) -> bool:
	if floor <= 0:
		return false
	if bool(used_floors.get(str(floor), false)):
		return false
	var essence_bank: Node = get_node_or_null("/root/EssenceBank")
	if essence_bank != null and essence_bank.has_method("get_total_amount"):
		return int(essence_bank.call("get_total_amount")) >= MINIMUM_SACRIFICE
	return false

func mark_altar_used(floor: int) -> void:
	if floor <= 0:
		return
	used_floors[str(floor)] = true
	_emit_run_resource_changed()

func calculate_soul_ash(amount: int) -> int:
	return int(floor(float(max(0, amount)) / float(SOUL_ASH_DIVISOR)))

func sacrifice_essence(faction_or_mix, amount: int) -> Dictionary:
	var floor_index: int = _get_current_floor()
	var requested_amount: int = max(0, amount)
	var scaling_preview: Dictionary = _get_scaling_preview(faction_or_mix, requested_amount)
	var result: Dictionary = {
		"ok": false,
		"floor_index": floor_index,
		"source": faction_or_mix,
		"requested_amount": requested_amount,
		"spent_amount": 0,
		"soul_ash_gain": 0,
		"chances": get_chances_for_amount(requested_amount),
		"scaling_preview": scaling_preview,
		"scaling_loss": scaling_preview.get("loss", {}) if scaling_preview is Dictionary else {},
		"error": ""
	}
	if not can_use_altar(floor_index):
		result["error"] = "Алтарь на этом этаже уже использован или не хватает эссенции."
		return result
	if requested_amount < MINIMUM_SACRIFICE:
		result["error"] = "Минимальная жертва: %d essence." % MINIMUM_SACRIFICE
		return result
	var essence_bank: Node = get_node_or_null("/root/EssenceBank")
	if essence_bank == null or not essence_bank.has_method("sacrifice_essence"):
		result["error"] = "EssenceBank не поддерживает sacrifice_essence()."
		return result
	var spent: int = int(essence_bank.call("sacrifice_essence", faction_or_mix, requested_amount))
	if spent <= 0:
		result["error"] = "Не удалось списать essence."
		return result
	var soul_ash_gain: int = calculate_soul_ash(spent)
	var run_manager: Node = get_node_or_null("/root/RunManager")
	if run_manager != null and run_manager.has_method("add_soul_ash"):
		run_manager.call("add_soul_ash", soul_ash_gain, "altar_sacrifice")
	else:
		var soul_ash_manager: Node = get_node_or_null("/root/SoulAshManager")
		if soul_ash_manager != null and soul_ash_manager.has_method("add"):
			soul_ash_manager.call("add", soul_ash_gain, "altar_sacrifice")
	mark_altar_used(floor_index)
	result["ok"] = true
	result["spent_amount"] = spent
	result["soul_ash_gain"] = soul_ash_gain
	result["chances"] = get_chances_for_amount(spent)
	result["scaling_preview"] = _get_scaling_preview(faction_or_mix, spent)
	result["scaling_loss"] = result["scaling_preview"].get("loss", {}) if result["scaling_preview"] is Dictionary else {}
	last_sacrifice = result.duplicate(true)
	altar_used.emit(floor_index, result.duplicate(true))
	_emit_run_resource_changed()
	return result

func get_chances_for_amount(amount: int) -> Dictionary:
	var safe_amount: int = max(0, amount)
	if safe_amount >= 150:
		return {"weak": 20, "medium": 58, "strong": 22}
	if safe_amount >= 80:
		return {"weak": 32, "medium": 55, "strong": 13}
	if safe_amount >= 40:
		return {"weak": 50, "medium": 43, "strong": 7}
	if safe_amount >= 20:
		return {"weak": 70, "medium": 28, "strong": 2}
	return {"weak": 0, "medium": 0, "strong": 0, "disabled": true, "min_amount": MINIMUM_SACRIFICE}

func get_sacrifice_preview(amount: int) -> Dictionary:
	var safe_amount: int = max(0, amount)
	var scaling_preview: Dictionary = _get_scaling_preview("mix", safe_amount)
	return {
		"amount": safe_amount,
		"soul_ash_gain": calculate_soul_ash(safe_amount),
		"chances": get_chances_for_amount(safe_amount),
		"scaling_preview": scaling_preview,
		"scaling_loss": scaling_preview.get("loss", {}) if scaling_preview is Dictionary else {},
		"warning_ru": "Жертва уменьшает текущую эссенцию и снижает авто-усиления текущего забега."
	}

func _get_scaling_preview(faction_or_mix, amount: int) -> Dictionary:
	var scaling: Node = get_node_or_null("/root/EssenceAutoScaling")
	if scaling != null and scaling.has_method("preview_after_sacrifice"):
		var preview = scaling.call("preview_after_sacrifice", faction_or_mix, amount)
		if preview is Dictionary:
			return preview
	return {}

func apply_card_effect(card_data: Dictionary, player: Node = null) -> Dictionary:
	var card: Dictionary = card_data.duplicate(true)
	var card_type: String = str(card.get("card_type", card.get("type", "")))
	var strength: String = str(card.get("strength", "weak"))
	var result: Dictionary = {"ok": true, "card_type": card_type, "strength": strength, "message": "", "reroll_requested": false}
	match card_type:
		"weapon_upgrade":
			result = _apply_weapon_card(card, result)
		"stat_upgrade":
			result = _apply_stat_card(card, result)
		"boss_ability_upgrade":
			result = _apply_boss_ability_card(card, result)
		"heal":
			result = _apply_heal_card(card, player, result)
		"reroll", "service":
			# These card types are removed from active generation until full UI/apply/save rules exist.
			result["ok"] = false
			result["message"] = "Этот тип карточки Алтаря временно отключён из основного пути."
		_:
			result["ok"] = false
			result["message"] = "Неизвестный тип карточки Алтаря: " + card_type
	if bool(result.get("ok", false)):
		applied_cards.append({"card": card, "result": result.duplicate(true)})
		altar_card_applied.emit(card, result.duplicate(true))
	_emit_run_resource_changed()
	return result

func _apply_weapon_card(card: Dictionary, result: Dictionary) -> Dictionary:
	var branch_id: String = str(card.get("weapon_branch_id", card.get("branch_id", "shadow_blade")))
	if branch_id.is_empty():
		branch_id = "shadow_blade"
	var current: int = int(weapon_upgrade_levels.get(branch_id, 0))
	var next_level: int = current + 1
	weapon_upgrade_levels[branch_id] = next_level
	weapon_upgrade_level = 0
	for key in weapon_upgrade_levels.keys():
		weapon_upgrade_level += int(weapon_upgrade_levels.get(key, 0))
	result["ok"] = true
	result["weapon_branch_id"] = branch_id
	result["weapon_branch_level"] = next_level
	result["weapon_upgrade_levels"] = weapon_upgrade_levels.duplicate(true)
	result["message"] = "Ветка оружия усилена через Алтарь: %s +1." % branch_id
	return result

func get_weapon_upgrade_levels() -> Dictionary:
	return weapon_upgrade_levels.duplicate(true)

func get_weapon_branch_level(branch_id: String) -> int:
	return int(weapon_upgrade_levels.get(branch_id, 0))

func _apply_stat_card(card: Dictionary, result: Dictionary) -> Dictionary:
	var stat_upgrades: Node = get_node_or_null("/root/StatUpgradeSystem")
	if stat_upgrades == null:
		result["ok"] = false
		result["message"] = "Система усиления характеристик недоступна."
		return result
	var upgrade_id: String = str(card.get("upgrade_id", card.get("stat_upgrade_id", "")))
	if upgrade_id.is_empty() and stat_upgrades.has_method("get_upgrade_ids"):
		var ids: Array = stat_upgrades.call("get_upgrade_ids")
		upgrade_id = _pick_lowest_level_stat(ids, stat_upgrades)
	var ok: bool = false
	if stat_upgrades.has_method("grant_free_upgrade"):
		ok = bool(stat_upgrades.call("grant_free_upgrade", upgrade_id, "altar_card"))
	result["ok"] = ok
	result["upgrade_id"] = upgrade_id
	result["message"] = "Характеристика усилена через Алтарь." if ok else "Не удалось применить карточку усиления характеристики."
	return result

func _apply_boss_ability_card(card: Dictionary, result: Dictionary) -> Dictionary:
	var ability_id: String = str(card.get("boss_ability_id", card.get("ability_id", "")))
	var boss_ability_system: Node = get_node_or_null("/root/BossAbilitySystem")
	if ability_id.is_empty() and boss_ability_system != null and boss_ability_system.has_method("get_upgrade_candidate_ids"):
		var ids: Array = boss_ability_system.call("get_upgrade_candidate_ids")
		if not ids.is_empty():
			ability_id = str(ids[0])
	if ability_id.is_empty():
		var abilities: Array = DataRegistry.get_items("boss_abilities") if DataRegistry.has_method("get_items") else []
		if not abilities.is_empty() and abilities[0] is Dictionary:
			ability_id = str(abilities[0].get("id", ""))
	if ability_id.is_empty():
		result["ok"] = false
		result["message"] = "Нет доступной способности босса для улучшения."
		return result
	if boss_ability_system == null or not boss_ability_system.has_method("upgrade_ability"):
		result["ok"] = false
		result["message"] = "Система способностей боссов недоступна."
		return result
	var ok: bool = bool(boss_ability_system.call("upgrade_ability", ability_id))
	var next_level: int = int(boss_ability_system.call("get_level", ability_id)) if boss_ability_system.has_method("get_level") else 0
	if ok:
		boss_ability_levels[ability_id] = next_level # legacy mirror for old save/debug panels only
	result["ok"] = ok
	result["boss_ability_id"] = ability_id
	result["level"] = next_level
	result["message"] = "Способность босса усилена до уровня %d." % next_level if ok else "Способность босса уже на максимальном уровне или недоступна."
	return result

func _apply_heal_card(card: Dictionary, player: Node, result: Dictionary) -> Dictionary:
	var heal_percent: float = float(card.get("heal_percent", card.get("effect_data", {}).get("heal_percent", 25)))
	var amount: float = 25.0
	if player != null and is_instance_valid(player):
		if player.get("health_component") != null:
			var health_component = player.get("health_component")
			amount = float(health_component.get("max_health")) * heal_percent / 100.0
		if player.has_method("heal_from_essence"):
			player.call("heal_from_essence", amount)
			service_state["heal_cards_used"] = int(service_state.get("heal_cards_used", 0)) + 1
			result["amount"] = amount
			result["message"] = "Герой исцелён через Алтарь."
			return result
	result["ok"] = false
	result["message"] = "Игрок недоступен для карточки исцеления."
	return result

func _strength_to_level_delta(strength: String) -> int:
	match strength:
		"strong":
			return 2
		_:
			return 1

func _pick_lowest_level_stat(ids: Array, stat_upgrades: Node) -> String:
	var best_id: String = ""
	var best_level: int = 999
	for id_value in ids:
		var upgrade_id: String = str(id_value)
		var level: int = int(stat_upgrades.call("get_level", upgrade_id)) if stat_upgrades.has_method("get_level") else 0
		if level < best_level:
			best_id = upgrade_id
			best_level = level
	return best_id

func get_state() -> Dictionary:
	return {
		"used_floors": used_floors.duplicate(true),
		"last_sacrifice": last_sacrifice.duplicate(true),
		"applied_cards": applied_cards.duplicate(true),
		"weapon_upgrade_level": weapon_upgrade_level,
		"weapon_upgrade_levels": weapon_upgrade_levels.duplicate(true),
		"boss_ability_levels": boss_ability_levels.duplicate(true),
		"service_state": service_state.duplicate(true)
	}

func set_state(state) -> void:
	if not (state is Dictionary):
		reset_run()
		return
	used_floors = state.get("used_floors", {}).duplicate(true) if state.get("used_floors", {}) is Dictionary else {}
	last_sacrifice = state.get("last_sacrifice", {}).duplicate(true) if state.get("last_sacrifice", {}) is Dictionary else {}
	applied_cards.clear()
	var applied_raw = state.get("applied_cards", [])
	if applied_raw is Array:
		for entry in applied_raw:
			if entry is Dictionary:
				applied_cards.append(entry.duplicate(true))
	weapon_upgrade_level = max(0, int(state.get("weapon_upgrade_level", 0)))
	weapon_upgrade_levels = state.get("weapon_upgrade_levels", {}).duplicate(true) if state.get("weapon_upgrade_levels", {}) is Dictionary else {}
	if weapon_upgrade_levels.is_empty() and weapon_upgrade_level > 0:
		weapon_upgrade_levels["legacy_total"] = weapon_upgrade_level
	boss_ability_levels = state.get("boss_ability_levels", {}).duplicate(true) if state.get("boss_ability_levels", {}) is Dictionary else {}
	service_state = state.get("service_state", {}).duplicate(true) if state.get("service_state", {}) is Dictionary else {"heal_cards_used": 0}
	_emit_run_resource_changed()

func _get_current_floor() -> int:
	var route_manager: Node = get_node_or_null("/root/RunRouteManager")
	if route_manager != null and route_manager.has_method("get_state"):
		var route_state = route_manager.call("get_state")
		if route_state is Dictionary:
			return int(route_state.get("floor_index", 1))
	var run_manager: Node = get_node_or_null("/root/RunManager")
	if run_manager != null:
		return int(run_manager.get("current_floor_index"))
	return 1

func _emit_run_resource_changed() -> void:
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("run_resource_changed"):
		bus.emit_signal("run_resource_changed")
