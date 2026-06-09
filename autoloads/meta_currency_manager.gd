extends Node

const CURRENCY_ID: String = "ESSENCE_CORE"
const CURRENCY_NAME_RU: String = "Ядро эссенции"
const MORGATH_BASE_REWARD: int = 1

var _core_essence: int = 0
var _earned_this_run: int = 0
var _last_award: Dictionary = {}

func _ready() -> void:
	_load_from_meta_progression()

func reset_run() -> void:
	_earned_this_run = 0
	_last_award.clear()

func get_amount() -> int:
	_load_from_meta_progression()
	return _core_essence

func get_earned_this_run() -> int:
	return _earned_this_run

func add(amount: int, reason: String = "") -> int:
	var safe_amount: int = max(0, amount)
	if safe_amount <= 0:
		return 0
	_core_essence += safe_amount
	_earned_this_run += safe_amount
	_last_award = {
		"currency_id": CURRENCY_ID,
		"currency_name_ru": CURRENCY_NAME_RU,
		"storage_key": "core_essence",
		"amount": safe_amount,
		"reason": reason,
		"total": _core_essence
	}
	_save_to_meta_progression()
	return safe_amount

func award_morgath_victory(run_context: Dictionary = {}) -> Dictionary:
	var amount: int = int(run_context.get("core_essence_reward", MORGATH_BASE_REWARD))
	amount = max(1, amount)
	var granted: int = add(amount, "morgath_defeated")
	return {
		"currency_id": CURRENCY_ID,
		"currency_name_ru": CURRENCY_NAME_RU,
		"storage_key": "core_essence",
		"amount": granted,
		"total": _core_essence,
		"reason": "morgath_defeated",
		"direct_stat_growth": false
	}

func can_afford(amount: int) -> bool:
	return get_amount() >= max(0, amount)

func spend(amount: int, reason: String = "") -> bool:
	var safe_amount: int = max(0, amount)
	if safe_amount <= 0:
		return true
	_load_from_meta_progression()
	if _core_essence < safe_amount:
		return false
	_core_essence -= safe_amount
	_last_award = {
		"currency_id": CURRENCY_ID,
		"currency_name_ru": CURRENCY_NAME_RU,
		"storage_key": "core_essence",
		"amount": -safe_amount,
		"reason": reason,
		"total": _core_essence
	}
	_save_to_meta_progression()
	return true

func get_state() -> Dictionary:
	_load_from_meta_progression()
	return {
		"currency_id": CURRENCY_ID,
		"currency_name_ru": CURRENCY_NAME_RU,
		"storage_key": "core_essence",
		"amount": _core_essence,
		"earned_this_run": _earned_this_run,
		"last_award": _last_award.duplicate(true),
		"direct_stat_growth": false
	}

func set_state(state: Variant) -> void:
	if not (state is Dictionary):
		return
	var data: Dictionary = state
	_core_essence = max(0, int(data.get("amount", _core_essence)))
	_earned_this_run = max(0, int(data.get("earned_this_run", _earned_this_run)))
	_last_award = data.get("last_award", {}) if data.get("last_award", {}) is Dictionary else {}
	_save_to_meta_progression()

func get_possible_unlocks() -> Array:
	var result: Array = []
	if not DataRegistry.has_method("get_items"):
		return result
	for item in DataRegistry.get_items("meta_unlocks"):
		if not (item is Dictionary):
			continue
		var unlock: Dictionary = item
		result.append({
			"id": str(unlock.get("id", "")),
			"unlock_type": str(unlock.get("unlock_type", "")),
			"name_ru": str(unlock.get("name_ru", unlock.get("id", ""))),
			"cost": int(unlock.get("core_essence_cost", 0)),
			"enabled": bool(unlock.get("enabled", false)),
			"affordable": can_afford(int(unlock.get("core_essence_cost", 0)))
		})
	return result

func _load_from_meta_progression() -> void:
	var meta: Node = get_node_or_null("/root/MetaProgression")
	if meta != null and meta.has_method("get_essence_core"):
		_core_essence = max(0, int(meta.call("get_essence_core")))
	elif meta != null:
		var value: Variant = meta.get("essence_core")
		if value != null:
			_core_essence = max(0, int(value))

func _save_to_meta_progression() -> void:
	var meta: Node = get_node_or_null("/root/MetaProgression")
	if meta == null:
		return
	if meta.has_method("set_essence_core"):
		meta.call("set_essence_core", _core_essence)
	else:
		meta.set("essence_core", _core_essence)
		if meta.has_method("save_meta"):
			meta.call("save_meta")
