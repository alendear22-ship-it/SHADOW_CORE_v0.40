extends Node

signal scaling_changed(bonus_state: Dictionary, reason: String)

const FACTION_KRUSHERS: String = "FACTION_KRUSHERS"
const FACTION_NATURE: String = "FACTION_NATURE"
const FACTION_ETHERS: String = "FACTION_ETHERS"
const DIMINISHING_START: float = 300.0
const DIMINISHING_RATE_AFTER_CAP: float = 0.35

var _last_bonus_state: Dictionary = {}
var _revision: int = 0

func _ready() -> void:
	recalculate("ready")

func reset_run() -> void:
	_last_bonus_state.clear()
	_revision += 1
	recalculate("reset_run")

func recalculate(reason: String = "essence_changed") -> Dictionary:
	_last_bonus_state = get_bonus_state()
	_revision += 1
	scaling_changed.emit(_last_bonus_state.duplicate(true), reason)
	_apply_to_active_player()
	return _last_bonus_state.duplicate(true)

func get_revision() -> int:
	return _revision

func get_bonus_state() -> Dictionary:
	var crushers: float = _effective_essence_for_faction(FACTION_KRUSHERS)
	var nature: float = _effective_essence_for_faction(FACTION_NATURE)
	var ethers: float = _effective_essence_for_faction(FACTION_ETHERS)
	return _build_bonus_state_from_effective(crushers, nature, ethers, _raw_faction_amounts())

func get_damage_multiplier() -> float:
	return float(get_bonus_state().get("damage_multiplier", 1.0))

func get_move_speed_multiplier() -> float:
	return float(get_bonus_state().get("move_speed_multiplier", 1.0))

func get_hp_multiplier() -> float:
	return float(get_bonus_state().get("hp_multiplier", 1.0))

func get_dot_duration_multiplier() -> float:
	return float(get_bonus_state().get("dot_duration_multiplier", 1.0))

func get_ability_damage_multiplier() -> float:
	return float(get_bonus_state().get("ability_damage_multiplier", 1.0))

func get_ability_range_multiplier() -> float:
	return float(get_bonus_state().get("ability_range_multiplier", 1.0))

func get_state() -> Dictionary:
	return {
		"revision": _revision,
		"bonus_state": get_bonus_state(),
		"source": "EssenceBank live totals",
		"diminishing_start": DIMINISHING_START,
		"diminishing_rate_after_cap": DIMINISHING_RATE_AFTER_CAP
	}

func preview_after_sacrifice(faction_or_mix, amount: int) -> Dictionary:
	var before_raw: Dictionary = _raw_faction_amounts()
	var after_raw: Dictionary = _simulate_faction_spend(before_raw, str(faction_or_mix), max(0, amount))
	var before_state: Dictionary = _build_bonus_state_from_raw(before_raw)
	var after_state: Dictionary = _build_bonus_state_from_raw(after_raw)
	return {
		"before": before_state,
		"after": after_state,
		"loss": _calculate_loss(before_state, after_state),
		"amount": max(0, amount),
		"source": str(faction_or_mix)
	}

func _effective_essence_for_faction(faction_id: String) -> float:
	var amount: float = float(_raw_faction_amounts().get(faction_id, 0))
	return _effective_amount(amount)

func _effective_amount(amount: float) -> float:
	var safe_amount: float = max(0.0, amount)
	if safe_amount <= DIMINISHING_START:
		return safe_amount
	return DIMINISHING_START + ((safe_amount - DIMINISHING_START) * DIMINISHING_RATE_AFTER_CAP)

func _raw_faction_amounts() -> Dictionary:
	var essence_bank: Node = get_node_or_null("/root/EssenceBank")
	if essence_bank != null and essence_bank.has_method("get_amounts_by_faction"):
		var raw = essence_bank.call("get_amounts_by_faction")
		if raw is Dictionary:
			return raw.duplicate(true)
	return {}

func _build_bonus_state_from_raw(raw: Dictionary) -> Dictionary:
	var crushers: float = _effective_amount(float(raw.get(FACTION_KRUSHERS, 0)))
	var nature: float = _effective_amount(float(raw.get(FACTION_NATURE, 0)))
	var ethers: float = _effective_amount(float(raw.get(FACTION_ETHERS, 0)))
	return _build_bonus_state_from_effective(crushers, nature, ethers, raw)

func _build_bonus_state_from_effective(crushers_effective: float, nature_effective: float, ethers_effective: float, raw: Dictionary) -> Dictionary:
	return {
		"raw_essence_by_faction": raw.duplicate(true),
		"effective_essence_by_faction": {
			FACTION_KRUSHERS: crushers_effective,
			FACTION_NATURE: nature_effective,
			FACTION_ETHERS: ethers_effective
		},
		"damage_multiplier": 1.0 + crushers_effective * 0.002,
		"move_speed_multiplier": 1.0 + crushers_effective * 0.001,
		"hp_multiplier": 1.0 + nature_effective * 0.003,
		"dot_duration_multiplier": 1.0 + nature_effective * 0.002,
		"ability_damage_multiplier": 1.0 + ethers_effective * 0.002,
		"ability_range_multiplier": 1.0 + ethers_effective * 0.0015,
		"diminishing_start": DIMINISHING_START,
		"diminishing_rate_after_cap": DIMINISHING_RATE_AFTER_CAP
	}

func _simulate_faction_spend(raw: Dictionary, source: String, amount: int) -> Dictionary:
	var result: Dictionary = raw.duplicate(true)
	var remaining: int = max(0, amount)
	if remaining <= 0:
		return result
	if result.has(source):
		var take: int = min(int(result.get(source, 0)), remaining)
		result[source] = max(0, int(result.get(source, 0)) - take)
		return result
	var keys: Array = result.keys()
	keys.sort_custom(func(a, b) -> bool:
		return int(result.get(a, 0)) > int(result.get(b, 0))
	)
	for key_value in keys:
		if remaining <= 0:
			break
		var key: String = str(key_value)
		var current: int = int(result.get(key, 0))
		var take_amount: int = min(current, remaining)
		if take_amount <= 0:
			continue
		result[key] = current - take_amount
		remaining -= take_amount
	return result

func _calculate_loss(before_state: Dictionary, after_state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["damage_multiplier", "move_speed_multiplier", "hp_multiplier", "dot_duration_multiplier", "ability_damage_multiplier", "ability_range_multiplier"]:
		var before_value: float = float(before_state.get(key, 1.0))
		var after_value: float = float(after_state.get(key, 1.0))
		result[key] = max(0.0, before_value - after_value)
	return result

func _apply_to_active_player() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for player in tree.get_nodes_in_group("player"):
		if player != null and is_instance_valid(player) and player.has_method("apply_stat_upgrade_runtime"):
			player.call_deferred("apply_stat_upgrade_runtime")

func set_state(state: Variant = {}) -> void:
	# Derived from EssenceBank. Recalculate instead of restoring stale multipliers.
	recalculate("set_state_derived")
