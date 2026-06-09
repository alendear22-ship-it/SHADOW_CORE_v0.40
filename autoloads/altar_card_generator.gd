extends Node

const MINIMUM_SACRIFICE: int = 20
const ACTIVE_CARD_TYPES: Array[String] = ["weapon_upgrade", "stat_upgrade", "boss_ability_upgrade", "heal"]
const DISABLED_CARD_TYPES: Array[String] = ["reroll", "service"] # Disabled until full UI/apply/save implementation.

func generate_cards(sacrifice_result: Dictionary, count: int = 3) -> Array:
	var amount: int = int(sacrifice_result.get("spent_amount", sacrifice_result.get("amount", 0)))
	if amount < MINIMUM_SACRIFICE:
		push_warning("AltarCardGenerator: sacrifice amount below minimum; no reward cards generated.")
		return []
	var available_types: Array[String] = _get_enabled_card_types()
	if available_types.is_empty():
		push_error("AltarCardGenerator: no active altar card types with valid handlers.")
		return []
	var result: Array = []
	var used_types: Dictionary = {}
	for i in range(max(1, count)):
		var card_type: String = _pick_card_type(available_types, used_types)
		if card_type.is_empty():
			continue
		used_types[card_type] = true
		var card: Dictionary = _build_card(card_type, amount, i)
		if _is_generated_card_valid(card):
			result.append(card)
	return result

func get_chances(amount: int) -> Dictionary:
	var altar_manager: Node = get_node_or_null("/root/AltarManager")
	if altar_manager != null and altar_manager.has_method("get_chances_for_amount"):
		var chances = altar_manager.call("get_chances_for_amount", amount)
		if chances is Dictionary:
			return chances
	if amount >= 150:
		return {"weak": 20, "medium": 58, "strong": 22}
	if amount >= 80:
		return {"weak": 32, "medium": 55, "strong": 13}
	if amount >= 40:
		return {"weak": 50, "medium": 43, "strong": 7}
	if amount >= 20:
		return {"weak": 70, "medium": 28, "strong": 2}
	return {"weak": 0, "medium": 0, "strong": 0, "disabled": true, "min_amount": MINIMUM_SACRIFICE}

func _get_enabled_card_types() -> Array[String]:
	var result: Array[String] = []
	if get_node_or_null("/root/DataRegistry") == null:
		return ACTIVE_CARD_TYPES.duplicate()
	for item in DataRegistry.get_items("altar_cards"):
		if not (item is Dictionary):
			continue
		if not bool(item.get("enabled", true)):
			continue
		if not bool(item.get("main_flow", true)):
			continue
		var card_type: String = str(item.get("card_type", ""))
		if not _is_supported_active_type(card_type):
			continue
		if not _has_valid_handler(card_type):
			continue
		if not _type_available_now(card_type):
			continue
		if not result.has(card_type):
			result.append(card_type)
	return result

func _is_supported_active_type(card_type: String) -> bool:
	return ACTIVE_CARD_TYPES.has(card_type) and not DISABLED_CARD_TYPES.has(card_type)

func _has_valid_handler(card_type: String) -> bool:
	match card_type:
		"weapon_upgrade", "stat_upgrade", "boss_ability_upgrade", "heal":
			return true
		_:
			return false

func _type_available_now(card_type: String) -> bool:
	match card_type:
		"stat_upgrade":
			var stat_upgrades: Node = get_node_or_null("/root/StatUpgradeSystem")
			return stat_upgrades != null and stat_upgrades.has_method("grant_free_upgrade")
		"boss_ability_upgrade":
			return not _pick_boss_ability_id().is_empty()
		_:
			return true

func _pick_card_type(available_types: Array[String], used_types: Dictionary) -> String:
	var candidates: Array[String] = []
	for card_type in available_types:
		if not used_types.has(card_type):
			candidates.append(card_type)
	if candidates.is_empty():
		candidates = available_types.duplicate()
	if candidates.is_empty():
		return ""
	return candidates[randi() % candidates.size()]

func _build_card(card_type: String, amount: int, index: int) -> Dictionary:
	var template: Dictionary = _get_template(card_type)
	var strength: String = _roll_strength_for_card(card_type, amount)
	var card: Dictionary = template.duplicate(true)
	card["id"] = "%s_RUN_%d_%d" % [str(template.get("id", card_type)).to_upper(), Time.get_ticks_msec(), index]
	card["template_id"] = str(template.get("id", ""))
	card["card_type"] = card_type
	card["card_type_ru"] = _type_ru(card_type)
	card["strength"] = strength
	card["strength_ru"] = _strength_ru(strength)
	card["rarity"] = strength
	card["rarity_ru"] = _strength_ru(strength)
	card["sacrifice_amount"] = amount
	card["generated_by"] = "AltarCardGenerator"
	card["enabled"] = true
	card["main_flow"] = true
	if str(card.get("title_ru", "")).is_empty():
		card["title_ru"] = str(card.get("name_ru", _type_ru(card_type)))
	if str(card.get("name_ru", "")).is_empty():
		card["name_ru"] = str(card.get("title_ru", _type_ru(card_type)))
	if str(card.get("description_ru", "")).is_empty():
		card["description_ru"] = _default_description_ru(card_type)
	_apply_type_specific_payload(card)
	return card

func _get_template(card_type: String) -> Dictionary:
	if get_node_or_null("/root/DataRegistry") != null:
		for item in DataRegistry.get_items("altar_cards"):
			if item is Dictionary and str(item.get("card_type", "")) == card_type:
				return item.duplicate(true)
	return {
		"id": "ALTAR_CARD_" + card_type.to_upper(),
		"card_type": card_type,
		"title_ru": _type_ru(card_type),
		"name_ru": _type_ru(card_type),
		"description_ru": _default_description_ru(card_type),
		"effect_data": {},
		"effect_payload": {"handler": _handler_name_for_type(card_type)}
	}

func _roll_strength(amount: int) -> String:
	var chances: Dictionary = get_chances(amount)
	if bool(chances.get("disabled", false)):
		return "weak"
	var roll: int = randi() % 100
	var weak: int = int(chances.get("weak", 100))
	var medium: int = int(chances.get("medium", 0))
	if roll < weak:
		return "weak"
	if roll < weak + medium:
		return "medium"
	return "strong"

func _roll_strength_for_card(card_type: String, amount: int) -> String:
	var strength: String = _roll_strength(amount)
	if card_type == "stat_upgrade" and strength == "strong":
		return "medium"
	return strength

func _strength_ru(strength: String) -> String:
	match strength:
		"strong":
			return "Мощная"
		"medium":
			return "Средняя"
		_:
			return "Слабая"

func _type_ru(card_type: String) -> String:
	match card_type:
		"weapon_upgrade":
			return "Усиление оружия"
		"stat_upgrade":
			return "Усиление характеристик"
		"boss_ability_upgrade":
			return "Усиление способности босса"
		"heal":
			return "Исцеление"
		_:
			return "Карточка Алтаря"

func _default_description_ru(card_type: String) -> String:
	match card_type:
		"weapon_upgrade":
			return "Повышает одну ветку оружия на +1 уровень."
		"stat_upgrade":
			return "Даёт слабое или среднее усиление характеристики."
		"boss_ability_upgrade":
			return "Повышает уровень доступной способности босса."
		"heal":
			return "Восстанавливает часть здоровья героя."
		_:
			return "Эта карточка временно недоступна в основном flow."

func _handler_name_for_type(card_type: String) -> String:
	match card_type:
		"weapon_upgrade":
			return "AltarManager._apply_weapon_card"
		"stat_upgrade":
			return "AltarManager._apply_stat_card"
		"boss_ability_upgrade":
			return "AltarManager._apply_boss_ability_card"
		"heal":
			return "AltarManager._apply_heal_card"
		_:
			return ""

func _apply_type_specific_payload(card: Dictionary) -> void:
	var card_type: String = str(card.get("card_type", ""))
	match card_type:
		"stat_upgrade":
			card["upgrade_id"] = _pick_stat_upgrade_id()
			card["effect_payload"] = {"handler": _handler_name_for_type(card_type), "upgrade_id": card["upgrade_id"], "strength": card.get("strength", "weak")}
		"boss_ability_upgrade":
			card["boss_ability_id"] = _pick_boss_ability_id()
			card["effect_payload"] = {"handler": _handler_name_for_type(card_type), "boss_ability_id": card["boss_ability_id"], "level_delta": 1}
		"heal":
			card["heal_percent"] = _strength_to_heal_percent(str(card.get("strength", "weak")))
			card["effect_payload"] = {"handler": _handler_name_for_type(card_type), "heal_percent": card["heal_percent"]}
		"weapon_upgrade":
			card["weapon_upgrade_delta"] = 1
			card["weapon_branch_id"] = _pick_weapon_branch_id()
			card["effect_payload"] = {"handler": _handler_name_for_type(card_type), "weapon_branch_id": card["weapon_branch_id"], "amount": 1}
		_:
			pass

func _is_generated_card_valid(card: Dictionary) -> bool:
	var card_type: String = str(card.get("card_type", ""))
	if not _is_supported_active_type(card_type):
		return false
	if str(card.get("id", "")).is_empty():
		return false
	if str(card.get("title_ru", card.get("name_ru", ""))).is_empty():
		return false
	if str(card.get("description_ru", "")).is_empty():
		return false
	var payload = card.get("effect_payload", {})
	if not (payload is Dictionary):
		return false
	return not str(payload.get("handler", "")).is_empty()

func _pick_weapon_branch_id() -> String:
	var branches: Array = []
	var template: Dictionary = _get_template("weapon_upgrade")
	var effect_data: Dictionary = template.get("effect_data", {}) if template.get("effect_data", {}) is Dictionary else {}
	var raw = effect_data.get("weapon_branches", [])
	if raw is Array:
		branches = raw
	if branches.is_empty():
		return "shadow_blade"
	var picked = branches[randi() % branches.size()]
	if picked is Dictionary:
		return str(picked.get("branch_id", picked.get("id", "shadow_blade")))
	return str(picked)

func _pick_stat_upgrade_id() -> String:
	var stat_upgrades: Node = get_node_or_null("/root/StatUpgradeSystem")
	if stat_upgrades == null or not stat_upgrades.has_method("get_upgrade_ids"):
		return "attack"
	var ids: Array = stat_upgrades.call("get_upgrade_ids")
	if ids.is_empty():
		return "attack"
	ids.shuffle()
	return str(ids[0])

func _pick_boss_ability_id() -> String:
	var boss_ability_system: Node = get_node_or_null("/root/BossAbilitySystem")
	if boss_ability_system != null and boss_ability_system.has_method("get_upgrade_candidate_ids"):
		var candidate_ids: Array = boss_ability_system.call("get_upgrade_candidate_ids")
		if not candidate_ids.is_empty():
			candidate_ids.shuffle()
			return str(candidate_ids[0])
	return ""

func _strength_to_heal_percent(strength: String) -> int:
	match strength:
		"strong":
			return 60
		"medium":
			return 40
		_:
			return 25

func reset_run() -> void:
	# Stateless generator. Kept for RunManager state API compatibility.
	pass

func get_state() -> Dictionary:
	return {"stateless": true, "source_of_truth": "data/altar_cards.json"}

func set_state(state: Variant = {}) -> void:
	# Stateless generator. Incoming state intentionally ignored.
	pass
