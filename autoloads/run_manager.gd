extends Node

const STARTING_SOUL_ASH: int = 0

var current_hero_id: String = "HERO_KAEL"
var current_room_index: int = 1
var current_floor_index: int = 1
var current_boss_number: int = 0
var rooms_completed_in_floor: int = 0
var soul_ash: int = STARTING_SOUL_ASH
var seed: int = 0
var selected_room_card: Dictionary = {}
var selected_boss_card: Dictionary = {}
var run_active: bool = false
var continue_used: bool = false
var final_preparation_active: bool = false
var final_boss_unlocked: bool = false
var final_preparation_choice: String = ""
var final_preparation_buff: Dictionary = {}
var essence_core_earned: int = 0
var morgath_defeated: bool = false

var run_started_msec: int = 0
var enemies_killed: int = 0
var essence_earned_total: int = 0
var bosses_defeated: Array[String] = []
var optional_bosses_defeated: Array[String] = []
var rooms_completed: int = 0
var route_state: Dictionary = {}



func _get_soul_ash_manager() -> Node:
	return get_node_or_null("/root/SoulAshManager")

func _sync_soul_ash_from_manager() -> void:
	var manager: Node = _get_soul_ash_manager()
	if manager != null and manager.has_method("get_amount"):
		soul_ash = int(manager.call("get_amount"))
	else:
		soul_ash = max(0, soul_ash)

func get_soul_ash() -> int:
	_sync_soul_ash_from_manager()
	return soul_ash

func add_soul_ash(amount: int, reason: String = "") -> void:
	var manager: Node = _get_soul_ash_manager()
	if manager != null and manager.has_method("add"):
		manager.call("add", amount, reason)
	else:
		soul_ash += max(0, amount)
	_sync_soul_ash_from_manager()
	EventBus.run_resource_changed.emit()

func spend_soul_ash(amount: int, reason: String = "") -> bool:
	var manager: Node = _get_soul_ash_manager()
	var ok: bool = false
	if manager != null and manager.has_method("spend"):
		ok = bool(manager.call("spend", amount, reason))
	else:
		if amount <= 0:
			ok = true
		elif soul_ash >= amount:
			soul_ash -= amount
			ok = true
	_sync_soul_ash_from_manager()
	EventBus.run_resource_changed.emit()
	return ok

func can_afford_soul_ash(amount: int) -> bool:
	var manager: Node = _get_soul_ash_manager()
	if manager != null and manager.has_method("can_afford"):
		return bool(manager.call("can_afford", amount))
	return soul_ash >= max(0, amount)

func _get_soul_ash_state() -> Dictionary:
	var manager: Node = _get_soul_ash_manager()
	if manager != null and manager.has_method("get_state"):
		var state: Variant = manager.call("get_state")
		if state is Dictionary:
			var state_dict: Dictionary = state
			return state_dict.duplicate(true)
	return {"amount": soul_ash, "history": []}

func _set_soul_ash_state(state: Variant) -> void:
	var manager: Node = _get_soul_ash_manager()
	if manager != null and manager.has_method("set_state"):
		manager.call("set_state", state if state is Dictionary else {"amount": int(state) if state is int else STARTING_SOUL_ASH})
	_sync_soul_ash_from_manager()


func _get_meta_currency_manager() -> Node:
	return get_node_or_null("/root/MetaCurrencyManager")

func add_essence_core_earned(amount: int) -> void:
	essence_core_earned += max(0, amount)
	EventBus.run_resource_changed.emit()

func get_essence_core_total() -> int:
	var manager: Node = _get_meta_currency_manager()
	if manager != null and manager.has_method("get_amount"):
		return int(manager.call("get_amount"))
	if get_node_or_null("/root/MetaProgression") != null and MetaProgression.has_method("get_essence_core"):
		return int(MetaProgression.call("get_essence_core"))
	return 0

func _get_route_manager() -> Node:
	return get_node_or_null("/root/RunRouteManager")

func _reset_route_for_new_run() -> void:
	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("reset_route"):
		route_manager.call("reset_route")
	_sync_from_route_manager()

func _sync_from_route_manager() -> void:
	var route_manager: Node = _get_route_manager()
	if route_manager == null:
		route_state = {
			"phase": "route_manager_missing_guard",
			"floor_index": current_floor_index,
			"room_index_on_floor": current_room_index
		}
		return
	if route_manager.has_method("get_state"):
		var state: Variant = route_manager.call("get_state")
		if state is Dictionary:
			var state_dict: Dictionary = state
			current_floor_index = int(state_dict.get("floor_index", current_floor_index))
			current_room_index = int(state_dict.get("room_index_on_floor", current_room_index))
			route_state = state_dict.get("route_state", {}) if state_dict.get("route_state", {}) is Dictionary else {}

func get_route_state() -> Dictionary:
	_sync_from_route_manager()
	return {
		"floor_index": current_floor_index,
		"room_index_on_floor": current_room_index,
		"route_state": route_state.duplicate(true)
	}

func _ready() -> void:
	if not EventBus.enemy_died.is_connected(_on_enemy_died):
		EventBus.enemy_died.connect(_on_enemy_died)
	if not EventBus.essence_collected.is_connected(_on_essence_collected):
		EventBus.essence_collected.connect(_on_essence_collected)

func start_new_run(hero_id: String = "HERO_KAEL") -> void:
	current_hero_id = hero_id
	current_room_index = 1
	current_floor_index = 1
	current_boss_number = 0
	rooms_completed_in_floor = 0
	soul_ash = STARTING_SOUL_ASH
	seed = randi()
	selected_room_card = DataRegistry.get_room("ROOM_SURVIVAL_WAVES_MVP").get("default_card", {}).duplicate(true)
	selected_boss_card = {}
	_reset_route_for_new_run()
	run_active = true
	continue_used = false
	final_preparation_active = false
	final_boss_unlocked = false
	final_preparation_choice = ""
	final_preparation_buff.clear()
	essence_core_earned = 0
	morgath_defeated = false
	run_started_msec = Time.get_ticks_msec()
	enemies_killed = 0
	essence_earned_total = 0
	bosses_defeated.clear()
	optional_bosses_defeated.clear()
	rooms_completed = 0
	EssenceBank.reset_run()
	var soul_ash_manager: Node = _get_soul_ash_manager()
	if soul_ash_manager != null and soul_ash_manager.has_method("reset_run"):
		soul_ash_manager.call("reset_run")
	_sync_soul_ash_from_manager()
	var meta_currency_manager: Node = _get_meta_currency_manager()
	if meta_currency_manager != null and meta_currency_manager.has_method("reset_run"):
		meta_currency_manager.call("reset_run")
	var boss_ability_system: Node = get_node_or_null("/root/BossAbilitySystem")
	if boss_ability_system != null and boss_ability_system.has_method("reset_run"):
		boss_ability_system.call("reset_run")
	var mob_weak_system: Node = get_node_or_null("/root/MobWeakAbilitySystem")
	if mob_weak_system != null and mob_weak_system.has_method("reset_run"):
		mob_weak_system.call("reset_run")
	var reaction_system: Node = get_node_or_null("/root/ReactionSystem")
	if reaction_system != null and reaction_system.has_method("reset_run"):
		reaction_system.call("reset_run")
	var run_flow: Node = get_node_or_null("/root/RunFlow")
	if run_flow != null and run_flow.has_method("reset_run"):
		run_flow.call("reset_run")
	if get_node_or_null("/root/StatUpgradeSystem") != null:
		StatUpgradeSystem.reset_run()
	AbilityManager.reset_run()
	var boss_choice_manager: Node = get_node_or_null("/root/BossChoiceManager")
	if boss_choice_manager != null and boss_choice_manager.has_method("reset_run"):
		boss_choice_manager.call("reset_run")
	var optional_boss_manager: Node = get_node_or_null("/root/OptionalBossManager")
	if optional_boss_manager != null and optional_boss_manager.has_method("reset_run"):
		optional_boss_manager.call("reset_run")
	var altar_manager: Node = get_node_or_null("/root/AltarManager")
	if altar_manager != null and altar_manager.has_method("reset_run"):
		altar_manager.call("reset_run")
	var slot_manager: Node = get_node_or_null("/root/AbilitySlotManager")
	if slot_manager != null and slot_manager.has_method("reset_run"):
		slot_manager.call("reset_run")
	if SaveManager.has_method("clear_run_state"):
		SaveManager.call("clear_run_state")
	else:
		SaveManager.clear_suspend()
	EventBus.run_resource_changed.emit()


func advance_room() -> void:
	rooms_completed += 1
	rooms_completed_in_floor += 1
	if final_preparation_active:
		current_room_index += 1
		route_state = {"phase": "final_boss", "floor_index": current_floor_index, "room_index_on_floor": current_room_index}
		EventBus.run_resource_changed.emit()
		return
	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("advance_room"):
		route_manager.call("advance_room")
		_sync_from_route_manager()
	else:
		current_room_index += 1
		route_state = {"phase": "route_manager_missing_guard", "floor_index": current_floor_index, "room_index_on_floor": current_room_index}
	EventBus.run_resource_changed.emit()

func advance_to_next_floor() -> void:
	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("advance_floor"):
		route_manager.call("advance_floor")
		_sync_from_route_manager()
	else:
		current_floor_index += 1
		current_room_index = 1
		route_state = {"phase": "route_manager_missing_guard", "floor_index": current_floor_index, "room_index_on_floor": current_room_index}
	rooms_completed_in_floor = 0
	selected_room_card = {}
	selected_boss_card = {}
	final_preparation_active = false
	final_boss_unlocked = false
	EventBus.run_resource_changed.emit()

func begin_final_preparation() -> void:
	# v0.19: short final preparation starts after floor 7 boss. It is not a new route floor and must not return to normal rooms.
	current_room_index = 1
	rooms_completed_in_floor = 0
	selected_room_card = {}
	selected_boss_card = {}
	route_state = {"phase": "final_preparation_elite_wave", "floor_index": current_floor_index, "room_index_on_floor": current_room_index}
	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("set_state"):
		route_manager.call("set_state", {"floor_index": current_floor_index, "room_index_on_floor": current_room_index, "route_state": route_state})
	final_preparation_active = true
	final_boss_unlocked = false
	final_preparation_choice = ""
	final_preparation_buff.clear()
	EventBus.run_resource_changed.emit()

func unlock_final_boss() -> void:
	final_preparation_active = false
	final_boss_unlocked = true
	selected_room_card = {}
	selected_boss_card = {}
	route_state = {"phase": "final_boss", "floor_index": current_floor_index, "room_index_on_floor": current_room_index}
	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("set_state"):
		route_manager.call("set_state", {"floor_index": current_floor_index, "room_index_on_floor": current_room_index, "route_state": route_state})
	EventBus.run_resource_changed.emit()


func mark_final_preparation_choice(choice_id: String, payload: Dictionary = {}) -> void:
	final_preparation_choice = choice_id
	final_preparation_buff = payload.duplicate(true)
	route_state = {"phase": "MORGATH_COMBAT", "floor_index": current_floor_index, "room_index_on_floor": current_room_index, "final_preparation_choice": choice_id}
	EventBus.run_resource_changed.emit()

func mark_morgath_defeated(final_boss_id: String = "") -> void:
	morgath_defeated = true
	_mark_meta_boss_defeated(final_boss_id)
	final_boss_unlocked = false
	final_preparation_active = false
	route_state = {"phase": "RUN_RESULT", "floor_index": current_floor_index, "room_index_on_floor": current_room_index, "morgath_defeated": true}
	EventBus.run_resource_changed.emit()

func mark_boss_defeated(boss_id: String) -> void:
	var is_optional_boss: bool = bool(selected_boss_card.get("is_optional_boss", false))
	var boss_choice_manager: Node = get_node_or_null("/root/BossChoiceManager")
	_update_mob_weak_ability_progress_for_boss(boss_id)
	_mark_meta_boss_defeated(boss_id)
	if is_optional_boss:
		if not optional_bosses_defeated.has(boss_id):
			optional_bosses_defeated.append(boss_id)
		# Optional route bosses are valid echo sources, but they must not advance mandatory boss counters.
		if boss_choice_manager != null and boss_choice_manager.has_method("mark_boss_defeated"):
			boss_choice_manager.call("mark_boss_defeated", boss_id)
		EventBus.run_resource_changed.emit()
		return
	if not bosses_defeated.has(boss_id):
		bosses_defeated.append(boss_id)
	if boss_choice_manager != null and boss_choice_manager.has_method("mark_boss_defeated"):
		boss_choice_manager.call("mark_boss_defeated", boss_id)
	current_boss_number = max(current_boss_number, bosses_defeated.size())
	EventBus.run_resource_changed.emit()


func _mark_meta_boss_defeated(boss_id: String) -> void:
	var clean_id: String = str(boss_id).strip_edges()
	if clean_id.is_empty():
		return
	var meta: Node = get_node_or_null("/root/MetaProgression")
	if meta != null and meta.has_method("mark_boss_defeated_ever"):
		meta.call("mark_boss_defeated_ever", clean_id)

func get_elapsed_seconds() -> int:
	if run_started_msec <= 0:
		return 0
	return int((Time.get_ticks_msec() - run_started_msec) / 1000)

func build_result(victory: bool, reason: String = "") -> Dictionary:
	return {
		"victory": victory,
		"reason": reason,
		"time_seconds": get_elapsed_seconds(),
		"enemies_killed": enemies_killed,
		"essence_total": essence_earned_total,
		"bosses_defeated": bosses_defeated.duplicate(),
		"bosses_defeated_count": bosses_defeated.size(),
		"optional_bosses_defeated": optional_bosses_defeated.duplicate(),
		"soul_ash": get_soul_ash(),
		"soul_ash_state": _get_soul_ash_state(),
		"rooms_completed": rooms_completed,
		"rooms_completed_in_floor": rooms_completed_in_floor,
		"floor_reached": current_floor_index,
		"floor_index": current_floor_index,
		"room_index_on_floor": current_room_index,
		"route_state": get_route_state(),
		"altar_state": _get_altar_state(),
		"boss_abilities": _get_boss_ability_state(),
		"boss_ability_levels": _get_boss_ability_levels(),
		"installed_boss_abilities": _get_ability_slot_state(),
		"hero_id": current_hero_id,
		"boss_ability_source_of_truth": "BossAbilitySystem",
		"mob_weak_ability_state": _get_mob_weak_ability_state(),
		"final_preparation_choice": final_preparation_choice,
		"final_preparation_buff": final_preparation_buff.duplicate(true),
		"morgath_defeated": morgath_defeated,
		"essence_core_earned": essence_core_earned,
		"core_essence_earned": essence_core_earned,
		"essence_core_total": get_essence_core_total(),
		"core_essence_total": get_essence_core_total(),
		"meta_currency_name_ru": "Ядро эссенции",
		"direct_stat_growth_from_meta_currency": false,
		"run_phase": "RUN_RESULT" if morgath_defeated or not run_active else str(route_state.get("phase", ""))
	}

func finish_run(victory: bool, reason: String = "") -> Dictionary:
	var result: Dictionary = build_result(victory, reason)
	run_active = false
	final_preparation_active = false
	final_boss_unlocked = false
	route_state = {"phase": "RUN_RESULT", "victory": victory, "reason": reason, "morgath_defeated": morgath_defeated}
	SaveManager.clear_suspend()
	return result

func create_suspend_after_second_boss() -> void:
	# Backwards-compatible checkpoint hook. Full run-state save is no longer limited to this function,
	# but BossController can still call it after the second boss.
	if current_boss_number != 2:
		return
	save_current_run_state("after_second_boss")

func reset_run() -> void:
	# Clear run-only state without touching persistent meta-state.
	current_room_index = 1
	current_floor_index = 1
	current_boss_number = 0
	rooms_completed_in_floor = 0
	soul_ash = STARTING_SOUL_ASH
	selected_room_card.clear()
	selected_boss_card.clear()
	run_active = false
	continue_used = false
	final_preparation_active = false
	final_boss_unlocked = false
	final_preparation_choice = ""
	final_preparation_buff.clear()
	essence_core_earned = 0
	morgath_defeated = false
	enemies_killed = 0
	essence_earned_total = 0
	bosses_defeated.clear()
	optional_bosses_defeated.clear()
	rooms_completed = 0
	route_state.clear()
	EssenceBank.reset_run()
	_reset_runtime_manager("/root/SoulAshManager")
	_reset_runtime_manager("/root/RunRouteManager")
	_reset_runtime_manager("/root/OptionalBossManager")
	_reset_runtime_manager("/root/BossChoiceManager")
	_reset_runtime_manager("/root/AltarManager")
	_reset_runtime_manager("/root/BossAbilitySystem")
	_reset_runtime_manager("/root/AbilitySlotManager")
	_reset_runtime_manager("/root/MobWeakAbilitySystem")
	_reset_runtime_manager("/root/ReactionSystem")
	_reset_runtime_manager("/root/RunFlow")
	if get_node_or_null("/root/StatUpgradeSystem") != null and StatUpgradeSystem.has_method("reset_run"):
		StatUpgradeSystem.reset_run()
	if get_node_or_null("/root/AbilityManager") != null and AbilityManager.has_method("reset_run"):
		AbilityManager.reset_run()
	EventBus.run_resource_changed.emit()


func _reset_runtime_manager(path: String) -> void:
	var manager: Node = get_node_or_null(path)
	if manager != null and manager.has_method("reset_run"):
		manager.call("reset_run")


func get_state() -> Dictionary:
	return build_run_state()


func set_state(state: Variant) -> void:
	if state is Dictionary:
		restore_suspend(state)


func build_run_state() -> Dictionary:
	_sync_soul_ash_from_manager()
	var flow_state: Dictionary = _get_run_flow_state()
	var boss_choice_state: Dictionary = _get_boss_choice_state()
	var optional_state: Dictionary = _get_optional_boss_state()
	var altar_state: Dictionary = _get_altar_state()
	var mob_state: Dictionary = _get_mob_weak_ability_state()
	var boss_ability_state: Dictionary = _get_boss_ability_state()
	var slot_state: Dictionary = _get_ability_slot_state()
	var route_context: Dictionary = {}
	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("get_next_route_context"):
		var context_value: Variant = route_manager.call("get_next_route_context")
		if context_value is Dictionary:
			route_context = context_value.duplicate(true)
	var flow_state_name: String = str(flow_state.get("state_name", str(route_state.get("phase", ""))))
	var full_route_state: Dictionary = get_route_state()
	return {
		"schema_version": 2,
		"hero_id": current_hero_id,
		"floor_index": current_floor_index,
		"room_index": current_room_index,
		"room_index_on_floor": current_room_index,
		"current_flow_state": flow_state_name,
		"run_flow_state": flow_state,
		"current_route_context": route_context,
		"route_state": full_route_state,
		"boss_number": current_boss_number,
		"rooms_completed_in_floor": rooms_completed_in_floor,
		"seed": seed,
		"run_active": run_active,
		"continue_used": continue_used,
		"essence_by_faction": _get_essence_by_faction_snapshot(),
		"essence": EssenceBank.get_state(),
		"soul_ash": get_soul_ash(),
		"soul_ash_state": _get_soul_ash_state(),
		"altar_used_by_floor": altar_state.get("used_floors", {}) if altar_state.get("used_floors", {}) is Dictionary else {},
		"altar_state": altar_state,
		"optional_boss_state_by_pair": optional_state,
		"optional_boss_state": optional_state,
		"unique_bosses_seen_this_run": boss_choice_state.get("unique_bosses_seen_this_run", []) if boss_choice_state.get("unique_bosses_seen_this_run", []) is Array else [],
		"unique_bosses_defeated_this_run": boss_choice_state.get("unique_bosses_defeated_this_run", []) if boss_choice_state.get("unique_bosses_defeated_this_run", []) is Array else [],
		"boss_choice_state": boss_choice_state,
		"boss_defeat_count_by_creature_type": mob_state.get("boss_defeat_count_by_creature_type", {}) if mob_state.get("boss_defeat_count_by_creature_type", {}) is Dictionary else {},
		"mob_weak_ability_state": mob_state,
		"boss_ability_levels": _get_boss_ability_levels(),
		"boss_abilities": boss_ability_state,
		"installed_boss_abilities": slot_state,
		"ability_slots": slot_state,
		"final_preparation_started": final_preparation_active or flow_state_name == "FINAL_PREPARATION_COMBAT" or flow_state_name == "FINAL_PREPARATION_CHOICE" or final_boss_unlocked or morgath_defeated,
		"final_preparation_completed": final_boss_unlocked or flow_state_name == "MORGATH_COMBAT" or morgath_defeated,
		"final_preparation_active": final_preparation_active,
		"final_boss_unlocked": final_boss_unlocked,
		"final_preparation_choice": final_preparation_choice,
		"final_preparation_buff": final_preparation_buff.duplicate(true),
		"morgath_started": flow_state_name == "MORGATH_COMBAT" or morgath_defeated,
		"morgath_defeated": morgath_defeated,
		"current_pending_reward": flow_state.get("pending_boss_reward_data", {}) if flow_state.get("pending_boss_reward_data", {}) is Dictionary else {},
		"current_pending_install": {
			"boss_ability_id": str(flow_state.get("pending_boss_reward_ability_id", "")),
			"reward_data": flow_state.get("pending_boss_reward_data", {}) if flow_state.get("pending_boss_reward_data", {}) is Dictionary else {}
		},
		"stat_upgrades": StatUpgradeSystem.get_state() if get_node_or_null("/root/StatUpgradeSystem") != null else {},
		"optional_bosses_defeated": optional_bosses_defeated.duplicate(),
		"bosses_defeated": bosses_defeated.duplicate(),
		"enemies_killed": enemies_killed,
		"essence_earned_total": essence_earned_total,
		"rooms_completed": rooms_completed,
		"essence_core_earned": essence_core_earned,
		"core_essence_earned": essence_core_earned,
		"suspend_allowed": can_save_current_run_state(),
		"suspend_block_reason": get_suspend_block_reason()
	}


func can_save_current_run_state() -> bool:
	var flow: Node = get_node_or_null("/root/RunFlow")
	if flow != null and flow.has_method("can_suspend_current_state"):
		return bool(flow.call("can_suspend_current_state"))
	return true


func get_suspend_block_reason() -> String:
	var flow: Node = get_node_or_null("/root/RunFlow")
	if flow != null and flow.has_method("get_suspend_block_reason"):
		return str(flow.call("get_suspend_block_reason"))
	return ""


func save_current_run_state(reason: String = "manual") -> bool:
	if not can_save_current_run_state():
		push_warning("RunManager: suspend blocked: " + get_suspend_block_reason())
		return false
	var state: Dictionary = build_run_state()
	state["save_reason"] = reason
	state["saved_msec"] = Time.get_ticks_msec()
	return bool(SaveManager.call("save_run_state", state)) if SaveManager.has_method("save_run_state") else false


func _get_run_flow_state() -> Dictionary:
	var flow: Node = get_node_or_null("/root/RunFlow")
	if flow != null and flow.has_method("get_state"):
		var state: Variant = flow.call("get_state")
		if state is Dictionary:
			return state.duplicate(true)
	return {"state_name": str(route_state.get("phase", ""))}


func _set_run_flow_state(state: Variant) -> void:
	var flow: Node = get_node_or_null("/root/RunFlow")
	if flow != null and flow.has_method("set_state"):
		flow.call("set_state", state if state is Dictionary else {})


func _get_essence_by_faction_snapshot() -> Dictionary:
	var result: Dictionary = {}
	var essence_state: Dictionary = EssenceBank.get_state()
	for creature_type_id_value in essence_state.keys():
		var creature_type_id: String = str(creature_type_id_value)
		var creature: Dictionary = DataRegistry.get_creature_type(creature_type_id) if DataRegistry.has_method("get_creature_type") else {}
		var faction_id: String = str(creature.get("faction_id", "unknown"))
		result[faction_id] = int(result.get(faction_id, 0)) + int(essence_state[creature_type_id_value])
	return result


func restore_suspend(data: Dictionary) -> void:
	if data.is_empty():
		return
	current_hero_id = data.get("hero_id", "HERO_KAEL")
	current_room_index = int(data.get("room_index_on_floor", data.get("room_index", 1)))
	current_floor_index = int(data.get("floor_index", 1))
	current_boss_number = int(data.get("boss_number", 0))
	rooms_completed_in_floor = int(data.get("rooms_completed_in_floor", 0))
	soul_ash = int(data.get("soul_ash", STARTING_SOUL_ASH))
	seed = int(data.get("seed", randi()))
	continue_used = bool(data.get("continue_used", false))
	final_preparation_active = bool(data.get("final_preparation_active", data.get("final_preparation_started", false)))
	final_boss_unlocked = bool(data.get("final_boss_unlocked", data.get("final_preparation_completed", false)))
	final_preparation_choice = str(data.get("final_preparation_choice", ""))
	final_preparation_buff = data.get("final_preparation_buff", {}) if data.get("final_preparation_buff", {}) is Dictionary else {}
	essence_core_earned = int(data.get("essence_core_earned", data.get("core_essence_earned", 0)))
	morgath_defeated = bool(data.get("morgath_defeated", false))
	enemies_killed = int(data.get("enemies_killed", 0))
	essence_earned_total = int(data.get("essence_earned_total", 0))
	bosses_defeated = []
	for boss_id in data.get("bosses_defeated", []):
		bosses_defeated.append(str(boss_id))
	optional_bosses_defeated = []
	for boss_id in data.get("optional_bosses_defeated", []):
		optional_bosses_defeated.append(str(boss_id))
	rooms_completed = int(data.get("rooms_completed", 0))
	EssenceBank.set_state(data.get("essence", {}))
	_set_soul_ash_state(data.get("soul_ash_state", {"amount": int(data.get("soul_ash", STARTING_SOUL_ASH))}))
	_set_boss_ability_state(data.get("boss_abilities", data.get("boss_ability_state", {})))
	if get_node_or_null("/root/StatUpgradeSystem") != null:
		StatUpgradeSystem.set_state(data.get("stat_upgrades", {}))
	_set_ability_slot_state(data.get("installed_boss_abilities", data.get("ability_slots", {})))
	_set_run_flow_state(data.get("run_flow_state", {"state_name": str(data.get("current_flow_state", ""))}))
	_set_boss_choice_state(data.get("boss_choice_state", {}))
	_set_optional_boss_state(data.get("optional_boss_state", data.get("optional_boss_state_by_pair", {})))
	_set_altar_state(data.get("altar_state", {}))
	_set_mob_weak_ability_state(data.get("mob_weak_ability_state", {}))
	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("set_state"):
		var restored_route_state: Dictionary = data.get("route_state", {}) if data.get("route_state", {}) is Dictionary else {}
		if restored_route_state.has("floor_index"):
			route_manager.call("set_state", restored_route_state)
		else:
			route_manager.call("set_state", {
				"floor_index": current_floor_index,
				"room_index_on_floor": current_room_index,
				"route_state": restored_route_state
			})
		_sync_from_route_manager()
	run_started_msec = Time.get_ticks_msec()
	run_active = true
	EventBus.run_resource_changed.emit()


func build_run_summary(result: Dictionary = {}) -> Dictionary:
	var boss_ability_state: Dictionary = _get_boss_ability_state()
	var unlocked: Array[String] = []
	var unlocked_value: Variant = boss_ability_state.get("unlocked", [])
	if unlocked_value is Array:
		for ability_id in unlocked_value:
			unlocked.append(str(ability_id))
	elif unlocked_value is Dictionary:
		for ability_id in unlocked_value.keys():
			if bool(unlocked_value[ability_id]):
				unlocked.append(str(ability_id))
	var possible_unlocks: Array = []
	var manager: Node = _get_meta_currency_manager()
	if manager != null and manager.has_method("get_possible_unlocks"):
		var value: Variant = manager.call("get_possible_unlocks")
		if value is Array:
			possible_unlocks = value
	var summary: Dictionary = result.duplicate(true)
	summary["morgath_defeated"] = morgath_defeated
	summary["bosses_defeated"] = bosses_defeated.duplicate()
	summary["opened_boss_abilities"] = unlocked
	summary["core_essence_earned"] = essence_core_earned
	summary["core_essence_total"] = get_essence_core_total()
	summary["essence_core_earned"] = essence_core_earned
	summary["essence_core_total"] = get_essence_core_total()
	summary["possible_meta_unlocks"] = possible_unlocks
	summary["final_preparation_choice"] = final_preparation_choice
	summary["final_preparation_buff"] = final_preparation_buff.duplicate(true)
	var altar_state: Dictionary = _get_altar_state()
	summary["used_altar_rewards"] = altar_state.get("applied_cards", []) if altar_state.get("applied_cards", []) is Array else []
	summary["altar_state"] = altar_state
	summary["final_resources"] = {
		"soul_ash": get_soul_ash(),
		"essence_total": EssenceBank.get_total_amount() if get_node_or_null("/root/EssenceBank") != null and EssenceBank.has_method("get_total_amount") else 0,
		"core_essence_total": get_essence_core_total(),
		"core_essence_earned": essence_core_earned
	}
	summary["run_finished_after_morgath"] = morgath_defeated
	summary["no_current_run_power_after_morgath"] = true
	summary["direct_stat_growth_from_meta_currency"] = false
	return summary

func _get_mob_weak_ability_system() -> Node:
	return get_node_or_null("/root/MobWeakAbilitySystem")

func _update_mob_weak_ability_progress_for_boss(boss_id: String) -> void:
	if boss_id.is_empty():
		return
	var system: Node = _get_mob_weak_ability_system()
	if system == null:
		return
	if system.has_method("on_boss_defeated_by_boss_id"):
		system.call("on_boss_defeated_by_boss_id", boss_id)
		return
	if system.has_method("update_on_boss_defeated_by_boss_id"):
		system.call("update_on_boss_defeated_by_boss_id", boss_id)
		return
	var boss: Dictionary = DataRegistry.get_by_id("bosses", boss_id)
	var creature_type_id: String = str(boss.get("creature_type_id", ""))
	if creature_type_id.is_empty():
		return
	if system.has_method("on_boss_defeated"):
		system.call("on_boss_defeated", creature_type_id)
		return
	if system.has_method("update_on_boss_defeated"):
		system.call("update_on_boss_defeated", creature_type_id)

func _get_mob_weak_ability_state() -> Dictionary:
	var system: Node = _get_mob_weak_ability_system()
	if system != null and system.has_method("get_state"):
		var state: Variant = system.call("get_state")
		if state is Dictionary:
			var state_dict: Dictionary = state
			return state_dict.duplicate(true)
	return {}

func _set_mob_weak_ability_state(state: Variant) -> void:
	var system: Node = _get_mob_weak_ability_system()
	if system != null and system.has_method("set_state"):
		system.call("set_state", state if state is Dictionary else {})

func _get_boss_choice_state() -> Dictionary:
	var boss_choice_manager: Node = get_node_or_null("/root/BossChoiceManager")
	if boss_choice_manager != null and boss_choice_manager.has_method("get_state"):
		var state: Variant = boss_choice_manager.call("get_state")
		if state is Dictionary:
			var state_dict: Dictionary = state
			return state_dict.duplicate(true)
	return {}

func _set_boss_choice_state(state: Variant) -> void:
	var boss_choice_manager: Node = get_node_or_null("/root/BossChoiceManager")
	if boss_choice_manager != null and boss_choice_manager.has_method("set_state"):
		boss_choice_manager.call("set_state", state if state is Dictionary else {})

func _get_optional_boss_state() -> Dictionary:
	var optional_boss_manager: Node = get_node_or_null("/root/OptionalBossManager")
	if optional_boss_manager != null and optional_boss_manager.has_method("get_state"):
		var state: Variant = optional_boss_manager.call("get_state")
		if state is Dictionary:
			var state_dict: Dictionary = state
			return state_dict.duplicate(true)
	return {}

func _set_optional_boss_state(state: Variant) -> void:
	var optional_boss_manager: Node = get_node_or_null("/root/OptionalBossManager")
	if optional_boss_manager != null and optional_boss_manager.has_method("set_state"):
		optional_boss_manager.call("set_state", state if state is Dictionary else {})



func _get_boss_ability_system() -> Node:
	return get_node_or_null("/root/BossAbilitySystem")

func _get_boss_ability_state() -> Dictionary:
	var system: Node = _get_boss_ability_system()
	if system != null and system.has_method("get_state"):
		var state: Variant = system.call("get_state")
		if state is Dictionary:
			return state
	return {}

func _set_boss_ability_state(state) -> void:
	var system: Node = _get_boss_ability_system()
	if system != null and system.has_method("set_state"):
		system.call("set_state", state)

func _get_boss_ability_levels() -> Dictionary:
	var state: Dictionary = _get_boss_ability_state()
	var levels: Variant = state.get("levels", {})
	if levels is Dictionary:
		return levels.duplicate(true)
	return {}

func _get_altar_state() -> Dictionary:
	var altar_manager: Node = get_node_or_null("/root/AltarManager")
	if altar_manager != null and altar_manager.has_method("get_state"):
		var state = altar_manager.call("get_state")
		if state is Dictionary:
			return state.duplicate(true)
	return {}

func _set_altar_state(state) -> void:
	var altar_manager: Node = get_node_or_null("/root/AltarManager")
	if altar_manager != null and altar_manager.has_method("set_state"):
		altar_manager.call("set_state", state if state is Dictionary else {})

func _get_ability_slot_state() -> Dictionary:
	var slot_manager: Node = get_node_or_null("/root/AbilitySlotManager")
	if slot_manager != null and slot_manager.has_method("get_state"):
		var state: Variant = slot_manager.call("get_state")
		if state is Dictionary:
			var state_dict: Dictionary = state
			return state_dict.duplicate(true)
	return {}

func _set_ability_slot_state(state: Variant) -> void:
	var slot_manager: Node = get_node_or_null("/root/AbilitySlotManager")
	if slot_manager != null and slot_manager.has_method("set_state"):
		slot_manager.call("set_state", state if state is Dictionary else {})

func _on_enemy_died(_enemy_id: String, _faction_id: String, _creature_type_id: String, _essence_amount: int) -> void:
	enemies_killed += 1

func _on_essence_collected(_creature_type_id: String, _faction_id: String, amount: int) -> void:
	essence_earned_total += max(0, amount)


func _get_essence_scaling_state() -> Dictionary:
	var scaling: Node = get_node_or_null("/root/EssenceAutoScaling")
	if scaling != null and scaling.has_method("get_state"):
		var state = scaling.call("get_state")
		if state is Dictionary:
			return state.duplicate(true)
	return {}
