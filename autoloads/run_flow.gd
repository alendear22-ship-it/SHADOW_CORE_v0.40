extends Node

signal boss_choice_cards_ready(cards: Array, route_context: Dictionary)
signal boss_reward_ready(reward_data: Dictionary)
signal ability_slot_install_requested(boss_ability_id: String, reward_data: Dictionary)
signal altar_sacrifice_requested(floor_index: int, route_context: Dictionary)
signal altar_reward_cards_ready(cards: Array, sacrifice_result: Dictionary)
signal route_choices_ready(cards: Array, route_context: Dictionary)
signal boss_choice_requested(route_context: Dictionary)
signal continue_choice_requested()
signal final_preparation_choices_ready(choices: Array)
signal run_summary_ready(summary: Dictionary)
signal run_result_ready(result: Dictionary)

const ROOM_CLEAR_PICKUP_RADIUS_MULTIPLIER: float = 10.0
const ROOM_CLEAR_PICKUP_TIMEOUT_SECONDS: float = 6.0

enum FlowState {
	IDLE,
	ROOM_RUNNING,
	ROOM_PICKUP_CLEANUP,
	ROOM_REWARD,
	ROOM_CARD_SELECT,
	ALTAR_SACRIFICE,
	ALTAR_REWARD_SELECT,
	BOSS_CHOICE_SELECT,
	BOSS_RUNNING,
	FINAL_PREPARATION_COMBAT,
	FINAL_PREPARATION_CHOICE,
	MORGATH_COMBAT,
	RUN_RESULT,
	RUN_ENDED,
	CONTINUE_CHOICE,
}

var _state: int = FlowState.IDLE
var _run_scene: Node = null
var _enemy_parent: Node = null
var _player: Node2D = null
var _pickups: Node = null
var _room_cards: Array = []
var _boss_cards: Array = []
var _pending_player: Node = null
var _pending_meta_summary: Dictionary = {}
var _debug_emit_accum: float = 0.0
var _current_boss_id: String = ""
var _current_boss_is_final: bool = false
var _current_boss_is_optional: bool = false
var _current_boss_is_echo: bool = false
var _current_optional_boss_pair_id: String = ""
var _pending_room_result: Dictionary = {}
var _pickup_cleanup_elapsed: float = 0.0
var _pending_after_boss_reward: String = ""
var _pending_altar_sacrifice: Dictionary = {}
var _pending_altar_cards: Array = []
var _pending_boss_reward_data: Dictionary = {}
var _pending_boss_reward_ability_id: String = ""
var _pending_final_preparation_choices: Array = []


func _get_event_bus() -> Node:
	return get_node_or_null("/root/EventBus")

func _safe_connect_signal(source: Object, signal_name: StringName, target: Callable) -> void:
	if source == null:
		return
	if not source.has_signal(signal_name):
		return
	if not target.is_valid():
		return
	if source.is_connected(signal_name, target):
		return
	source.connect(signal_name, target)

func _emit_event_bus(signal_name: StringName, args: Array = []) -> void:
	var bus: Node = _get_event_bus()
	if bus == null:
		return
	if not bus.has_signal(signal_name):
		return
	var call_args: Array = [signal_name]
	call_args.append_array(args)
	bus.callv("emit_signal", call_args)


func _clear_reward_selection_state() -> void:
	# Hotfix v0.23.1: central cleanup helper restored after removed reward-flow cleanup.
	# This only clears transient selection payloads. It does not reopen any removed reward UI.
	_pending_boss_reward_ability_id = ""
	_pending_boss_reward_data.clear()
	_pending_altar_sacrifice.clear()
	_pending_altar_cards.clear()
	_pending_final_preparation_choices.clear()


func reset_run() -> void:
	_state = FlowState.IDLE
	_room_cards.clear()
	_boss_cards.clear()
	_pending_player = null
	_pending_meta_summary.clear()
	_current_boss_id = ""
	_current_boss_is_final = false
	_current_boss_is_optional = false
	_current_boss_is_echo = false
	_current_optional_boss_pair_id = ""
	_pending_room_result.clear()
	_pickup_cleanup_elapsed = 0.0
	_pending_after_boss_reward = ""
	_clear_reward_selection_state()


func get_state() -> Dictionary:
	return {
		"state_id": int(_state),
		"state_name": _state_to_string(_state),
		"current_boss_id": _current_boss_id,
		"current_boss_is_final": _current_boss_is_final,
		"current_boss_is_optional": _current_boss_is_optional,
		"current_boss_is_echo": _current_boss_is_echo,
		"current_optional_boss_pair_id": _current_optional_boss_pair_id,
		"pending_after_boss_reward": _pending_after_boss_reward,
		"pending_room_result": _pending_room_result.duplicate(true),
		"pending_boss_reward_data": _pending_boss_reward_data.duplicate(true),
		"pending_boss_reward_ability_id": _pending_boss_reward_ability_id,
		"pending_altar_sacrifice": _pending_altar_sacrifice.duplicate(true),
		"pending_altar_cards": _pending_altar_cards.duplicate(true),
		"pending_final_preparation_choices": _pending_final_preparation_choices.duplicate(true),
		"pending_meta_summary": _pending_meta_summary.duplicate(true),
		"suspend_allowed": can_suspend_current_state(),
		"suspend_block_reason": get_suspend_block_reason()
	}


func set_state(state: Variant) -> void:
	if not (state is Dictionary):
		reset_run()
		return
	var data: Dictionary = state
	var restored_state_name: String = str(data.get("state_name", ""))
	var restored_state_id: int = int(data.get("state_id", FlowState.IDLE))
	if not restored_state_name.is_empty():
		restored_state_id = _state_from_string(restored_state_name)
	_state = restored_state_id
	_current_boss_id = str(data.get("current_boss_id", ""))
	_current_boss_is_final = bool(data.get("current_boss_is_final", false))
	_current_boss_is_optional = bool(data.get("current_boss_is_optional", false))
	_current_boss_is_echo = bool(data.get("current_boss_is_echo", false))
	_current_optional_boss_pair_id = str(data.get("current_optional_boss_pair_id", ""))
	_pending_after_boss_reward = str(data.get("pending_after_boss_reward", ""))
	_pending_room_result = data.get("pending_room_result", {}) if data.get("pending_room_result", {}) is Dictionary else {}
	_pending_boss_reward_data = data.get("pending_boss_reward_data", {}) if data.get("pending_boss_reward_data", {}) is Dictionary else {}
	_pending_boss_reward_ability_id = str(data.get("pending_boss_reward_ability_id", ""))
	_pending_altar_sacrifice = data.get("pending_altar_sacrifice", {}) if data.get("pending_altar_sacrifice", {}) is Dictionary else {}
	_pending_altar_cards = data.get("pending_altar_cards", []) if data.get("pending_altar_cards", []) is Array else []
	_pending_final_preparation_choices = data.get("pending_final_preparation_choices", []) if data.get("pending_final_preparation_choices", []) is Array else []
	_pending_meta_summary = data.get("pending_meta_summary", {}) if data.get("pending_meta_summary", {}) is Dictionary else {}


func can_suspend_current_state() -> bool:
	return not _is_mid_ui_state(_state)


func get_suspend_block_reason() -> String:
	if can_suspend_current_state():
		return ""
	return "Сохранение во время открытого progression UI отключено: завершите текущий выбор."


func _is_mid_ui_state(state: int) -> bool:
	return state == FlowState.ROOM_REWARD \
		or state == FlowState.ROOM_CARD_SELECT \
		or state == FlowState.ALTAR_SACRIFICE \
		or state == FlowState.ALTAR_REWARD_SELECT \
		or state == FlowState.BOSS_CHOICE_SELECT \
		or state == FlowState.FINAL_PREPARATION_CHOICE \
		or state == FlowState.CONTINUE_CHOICE


func _state_from_string(state_name: String) -> int:
	match state_name:
		"IDLE":
			return FlowState.IDLE
		"ROOM_RUNNING":
			return FlowState.ROOM_RUNNING
		"ROOM_PICKUP_CLEANUP":
			return FlowState.ROOM_PICKUP_CLEANUP
		"ROOM_REWARD":
			return FlowState.ROOM_REWARD
		"ROOM_CARD_SELECT":
			return FlowState.ROOM_CARD_SELECT
		"ALTAR_SACRIFICE":
			return FlowState.ALTAR_SACRIFICE
		"ALTAR_REWARD_SELECT":
			return FlowState.ALTAR_REWARD_SELECT
		"BOSS_CHOICE_SELECT":
			return FlowState.BOSS_CHOICE_SELECT
		"BOSS_RUNNING":
			return FlowState.BOSS_RUNNING
		"FINAL_PREPARATION_COMBAT":
			return FlowState.FINAL_PREPARATION_COMBAT
		"FINAL_PREPARATION_CHOICE":
			return FlowState.FINAL_PREPARATION_CHOICE
		"MORGATH_COMBAT":
			return FlowState.MORGATH_COMBAT
		"RUN_RESULT":
			return FlowState.RUN_RESULT
		"RUN_ENDED":
			return FlowState.RUN_ENDED
		"CONTINUE_CHOICE":
			return FlowState.CONTINUE_CHOICE
		"RESULT":
			# Backward-compatible mapping for old save data.
			return FlowState.RUN_RESULT
		_:
			return clampi(int(state_name) if state_name.is_valid_int() else FlowState.IDLE, FlowState.IDLE, FlowState.CONTINUE_CHOICE)


func _ready() -> void:
	var bus: Node = _get_event_bus()
	_safe_connect_signal(bus, &"room_completed", Callable(self, "_on_room_completed"))
	_safe_connect_signal(bus, &"boss_defeated", Callable(self, "_on_boss_defeated"))
	_safe_connect_signal(bus, &"run_finished", Callable(self, "_on_run_finished_event"))

func _process(delta: float) -> void:
	if _state == FlowState.ROOM_PICKUP_CLEANUP:
		_update_room_pickup_cleanup(delta)
	_debug_emit_accum += delta
	if _debug_emit_accum >= 0.25:
		_debug_emit_accum = 0.0
		_emit_event_bus(&"run_debug_changed", [get_debug_state()])

func bind_runtime(run_scene: Node, enemy_parent: Node, player: Node2D, pickups: Node) -> void:
	_run_scene = run_scene
	_enemy_parent = enemy_parent
	_player = player
	_pickups = pickups


func _get_route_manager() -> Node:
	return get_node_or_null("/root/RunRouteManager")

func _get_optional_boss_manager() -> Node:
	return get_node_or_null("/root/OptionalBossManager")

func _get_altar_manager() -> Node:
	return get_node_or_null("/root/AltarManager")

func _get_altar_card_generator() -> Node:
	return get_node_or_null("/root/AltarCardGenerator")

func _get_boss_ability_system() -> Node:
	return get_node_or_null("/root/BossAbilitySystem")

func _get_boss_reward_manager() -> Node:
	return get_node_or_null("/root/BossRewardManager")

func _get_ability_slot_manager() -> Node:
	return get_node_or_null("/root/AbilitySlotManager")

func _get_meta_currency_manager() -> Node:
	return get_node_or_null("/root/MetaCurrencyManager")

func _get_final_boss_id() -> String:
	var registry: Node = get_node_or_null("/root/DataRegistry")
	if registry != null and registry.has_method("get_final_boss_id"):
		return str(registry.call("get_final_boss_id"))
	push_error("RunFlow: DataRegistry.get_final_boss_id() is required; cannot start final boss from hardcoded id.")
	return ""

func _is_final_boss_id(boss_id: String) -> bool:
	if boss_id.is_empty():
		return false
	return boss_id == _get_final_boss_id() or not DataRegistry.get_by_id("final_bosses", boss_id).is_empty()

func _get_route_context() -> Dictionary:
	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("get_next_route_context"):
		var context: Variant = route_manager.call("get_next_route_context")
		if context is Dictionary:
			return context
	var total_floors: int = DataRegistry.get_total_floors() if DataRegistry.has_method("get_total_floors") else 0
	var rooms_on_floor: int = _fallback_rooms_for_floor(RunManager.current_floor_index)
	return {
		"floor_index": RunManager.current_floor_index,
		"room_index_on_floor": RunManager.current_room_index,
		"rooms_on_floor": rooms_on_floor,
		"total_floors": total_floors,
		"is_floor_complete": rooms_on_floor > 0 and RunManager.current_room_index > rooms_on_floor,
		"ready_for_final_preparation": total_floors > 0 and RunManager.current_floor_index >= total_floors and rooms_on_floor > 0 and RunManager.current_room_index > rooms_on_floor,
		"route_state": RunManager.route_state if RunManager.get("route_state") is Dictionary else {},
		"route_config_valid": total_floors > 0 and rooms_on_floor > 0
	}

func _fallback_rooms_for_floor(floor_index: int) -> int:
	var rooms: Dictionary = DataRegistry.get_rooms_by_floor() if DataRegistry.has_method("get_rooms_by_floor") else {}
	if rooms.has(str(floor_index)):
		return int(rooms[str(floor_index)])
	if rooms.has(floor_index):
		return int(rooms[floor_index])
	push_error("RunFlow: run_config.rooms_by_floor has no configured value for floor " + str(floor_index))
	return 0

func _is_current_floor_complete() -> bool:
	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("is_floor_complete"):
		return bool(route_manager.call("is_floor_complete"))
	return RunManager.current_room_index > _fallback_rooms_for_floor(RunManager.current_floor_index)

func _is_current_route_final_floor() -> bool:
	var context: Dictionary = _get_route_context()
	var total_floors: int = int(context.get("total_floors", DataRegistry.get_total_floors() if DataRegistry.has_method("get_total_floors") else 0))
	return total_floors > 0 and int(context.get("floor_index", RunManager.current_floor_index)) >= total_floors

func _show_next_route_or_boss_choice() -> void:
	_clear_reward_selection_state()
	if _is_current_floor_complete():
		_show_boss_choice_for_current_floor()
		return
	_show_route_choices_for_next_room()

func _show_route_choices_for_next_room() -> void:
	_state = FlowState.ROOM_CARD_SELECT
	var context: Dictionary = _get_route_context()
	var floor_index: int = int(context.get("floor_index", RunManager.current_floor_index))
	var room_index: int = int(context.get("room_index_on_floor", RunManager.current_room_index))
	var result: Array = []

	var optional_manager: Node = _get_optional_boss_manager()
	if optional_manager != null and optional_manager.has_method("should_offer_optional_boss") and bool(optional_manager.call("should_offer_optional_boss", context)):
		var pair_id: String = str(optional_manager.call("get_pair_id_for_floor", floor_index)) if optional_manager.has_method("get_pair_id_for_floor") else ""
		var normal_cards: Array = SpawnDirector.build_room_cards(floor_index, room_index, 1)
		var normal_card: Dictionary = normal_cards[0].duplicate(true) if not normal_cards.is_empty() else {}
		normal_card["route_label"] = "Обычная комната"
		normal_card["route_option_type"] = "room"
		normal_card["optional_boss_offer_active"] = true
		normal_card["optional_boss_pair_id"] = pair_id
		normal_card["disabled"] = false
		var optional_card_value: Variant = optional_manager.call("build_optional_boss_route_card", context) if optional_manager.has_method("build_optional_boss_route_card") else {}
		if optional_card_value is Dictionary:
			var optional_card: Dictionary = optional_card_value
			if not optional_card.is_empty():
				result.append(normal_card)
				result.append(optional_card.duplicate(true))
				if optional_manager.has_method("mark_optional_boss_offered"):
					optional_manager.call("mark_optional_boss_offered", pair_id)
		if result.is_empty():
			push_warning("RunFlow: OptionalBossManager was eligible but produced no card; falling back to normal room choices.")

	if result.is_empty():
		var cards: Array = SpawnDirector.build_room_cards(floor_index, room_index, 2)
		for i in range(min(2, cards.size())):
			var card: Dictionary = cards[i].duplicate(true)
			card["route_label"] = "Комната A" if i == 0 else "Комната B"
			card["route_option_type"] = "room"
			card["disabled"] = false
			result.append(card)
		if _can_offer_altar_now(floor_index):
			result.append(_build_altar_route_card(floor_index))

	_room_cards = result
	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("set_route_state"):
		route_manager.call("set_route_state", {
			"version": 2,
			"phase": "route_choice",
			"floor_index": floor_index,
			"room_index_on_floor": room_index,
			"altar_enabled": _route_cards_include_altar(_room_cards),
			"optional_boss_offer": _route_cards_include_optional_boss(_room_cards)
		})
	EventBus.route_choice_requested.emit(context)
	route_choices_ready.emit(_room_cards, context)
	_emit_event_bus(&"run_resource_changed")

func _route_cards_include_optional_boss(cards: Array) -> bool:
	for card_value in cards:
		if not (card_value is Dictionary):
			continue
		var card: Dictionary = card_value
		if str(card.get("route_option_type", "")) == "optional_boss":
			return true
		if bool(card.get("optional_boss_offer_active", false)):
			return true
	return false

func _route_cards_include_altar(cards: Array) -> bool:
	for card_value in cards:
		if not (card_value is Dictionary):
			continue
		var card: Dictionary = card_value
		if str(card.get("route_option_type", "")) == "altar":
			return true
	return false

func _show_boss_choice_for_current_floor() -> void:
	_state = FlowState.BOSS_CHOICE_SELECT
	var context: Dictionary = _get_route_context()
	var floor_index: int = int(context.get("floor_index", RunManager.current_floor_index))
	var boss_choice_manager: Node = get_node_or_null("/root/BossChoiceManager")
	if boss_choice_manager != null and boss_choice_manager.has_method("generate_boss_choices"):
		var generated: Variant = boss_choice_manager.call("generate_boss_choices", context)
		_boss_cards = generated if generated is Array else []
	else:
		push_error("RunFlow: BossChoiceManager missing; boss choice cannot be generated.")
		_boss_cards = []
	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("set_route_state"):
		route_manager.call("set_route_state", {
			"version": 1,
			"phase": "boss_choice",
			"floor_index": floor_index,
			"room_index_on_floor": int(context.get("room_index_on_floor", RunManager.current_room_index)),
			"choice_count": _boss_cards.size()
		})
	EventBus.boss_choice_requested.emit(context)
	boss_choice_cards_ready.emit(_boss_cards, context)
	_emit_event_bus(&"run_resource_changed")

func start_or_resume_current_run() -> void:
	if not RunManager.run_active:
		RunManager.start_new_run("HERO_KAEL")
	_clear_runtime_nodes()
	_start_room(RunManager.selected_room_card)

func start_new_run_in_current_scene(hero_id: String = "HERO_KAEL") -> void:
	RunManager.start_new_run(hero_id)
	_current_boss_id = ""
	_current_boss_is_final = false
	_current_boss_is_optional = false
	_current_boss_is_echo = false
	_current_optional_boss_pair_id = ""
	_pending_room_result.clear()
	_clear_reward_selection_state()
	_reset_player_for_new_run(hero_id)
	_clear_runtime_nodes()
	_start_room(RunManager.selected_room_card)

func continue_after_boss_reward() -> void:
	if _state != FlowState.ROOM_REWARD:
		return
	var after_boss_action: String = _pending_after_boss_reward
	_clear_reward_selection_state()
	_pending_after_boss_reward = ""
	if after_boss_action == "next_floor":
		_begin_next_floor_after_boss()
		return
	if after_boss_action == "final_preparation":
		_begin_final_preparation_room()
		return
	if after_boss_action == "morgath":
		_start_morgath()
		return
	_show_next_route_or_boss_choice()

func decline_boss_reward_for_soul_ash() -> void:
	if _state != FlowState.ROOM_REWARD:
		return
	RunManager.add_soul_ash(5, "boss_reward_declined")
	_pending_boss_reward_ability_id = ""
	_pending_boss_reward_data.clear()
	_emit_event_bus(&"run_resource_changed")
	continue_after_boss_reward()

func choose_boss_reward_ability(boss_ability_id: String) -> void:
	if _state != FlowState.ROOM_REWARD:
		return
	if boss_ability_id.is_empty():
		return
	var boss_reward_manager: Node = _get_boss_reward_manager()
	var option: Dictionary = {}
	if boss_reward_manager != null and boss_reward_manager.has_method("get_reward_option"):
		var option_value: Variant = boss_reward_manager.call("get_reward_option", boss_ability_id, _pending_boss_reward_data)
		if option_value is Dictionary:
			option = option_value
	if option.is_empty():
		option = _find_pending_boss_reward_option(boss_ability_id)
	if not option.is_empty():
		var option_state: String = str(option.get("state", "AVAILABLE"))
		if bool(option.get("disabled", false)) or option_state == "MAX" or option_state == "LOCKED":
			return
	_pending_boss_reward_ability_id = boss_ability_id
	var boss_ability_system: Node = _get_boss_ability_system()
	var current_level: int = int(boss_ability_system.call("get_level", boss_ability_id)) if boss_ability_system != null and boss_ability_system.has_method("get_level") else int(option.get("current_level", 0))
	var is_unlocked: bool = current_level > 0
	if boss_ability_system != null and boss_ability_system.has_method("is_unlocked"):
		is_unlocked = bool(boss_ability_system.call("is_unlocked", boss_ability_id))
	var action: String = str(option.get("action", option.get("reward_action", "upgrade" if is_unlocked else "unlock")))
	if action == "upgrade" or is_unlocked:
		if current_level >= 3:
			return
		var upgraded: bool = false
		if boss_ability_system != null and boss_ability_system.has_method("upgrade_ability"):
			upgraded = bool(boss_ability_system.call("upgrade_ability", boss_ability_id))
		if upgraded:
			var slot_manager_upgrade: Node = _get_ability_slot_manager()
			if slot_manager_upgrade != null and slot_manager_upgrade.has_method("upgrade_installed_boss_ability") and boss_ability_system.has_method("get_level"):
				slot_manager_upgrade.call("upgrade_installed_boss_ability", boss_ability_id, int(boss_ability_system.call("get_level", boss_ability_id)))
		_continue_after_boss_reward_resolution()
		return
	ability_slot_install_requested.emit(boss_ability_id, _pending_boss_reward_data.duplicate(true))


func _find_pending_boss_reward_option(boss_ability_id: String) -> Dictionary:
	var options: Variant = _pending_boss_reward_data.get("reward_options", [])
	if options is Array:
		for option_value in options:
			if option_value is Dictionary:
				var option: Dictionary = option_value
				if str(option.get("boss_ability_id", option.get("id", ""))) == boss_ability_id:
					return option
	return {}

func confirm_boss_ability_install(active_ability_id: String, slot_index: int, boss_ability_id: String) -> void:
	if _state != FlowState.ROOM_REWARD:
		return
	if boss_ability_id.is_empty():
		boss_ability_id = _pending_boss_reward_ability_id
	if active_ability_id.is_empty() or boss_ability_id.is_empty():
		return
	var slot_manager: Node = _get_ability_slot_manager()
	var boss_ability_system: Node = _get_boss_ability_system()
	if slot_manager == null:
		push_warning("RunFlow.confirm_boss_ability_install(): AbilitySlotManager is missing.")
		return
	var option: Dictionary = _find_pending_boss_reward_option(boss_ability_id)
	var next_level: int = int(option.get("next_level", 1))
	if next_level <= 0:
		next_level = 1
	var old_id: String = ""
	var installed: bool = false
	if slot_index >= 0:
		var old_slots: Array = []
		if slot_manager.has_method("get_slots"):
			var old_slots_value: Variant = slot_manager.call("get_slots", active_ability_id)
			if old_slots_value is Array:
				old_slots = old_slots_value
		if slot_index < old_slots.size() and old_slots[slot_index] is Dictionary:
			var old_entry: Dictionary = old_slots[slot_index]
			old_id = str(old_entry.get("boss_ability_id", ""))
		if slot_manager.has_method("replace_boss_ability"):
			installed = bool(slot_manager.call("replace_boss_ability", active_ability_id, slot_index, boss_ability_id, next_level))
	else:
		if slot_manager.has_method("install_boss_ability"):
			installed = bool(slot_manager.call("install_boss_ability", active_ability_id, boss_ability_id, next_level))
	if not installed:
		push_warning("RunFlow.confirm_boss_ability_install(): install/replace failed for " + boss_ability_id)
		ability_slot_install_requested.emit(boss_ability_id, _pending_boss_reward_data.duplicate(true))
		return
	if boss_ability_system != null:
		if not old_id.is_empty() and old_id != boss_ability_id and boss_ability_system.has_method("remove_ability"):
			boss_ability_system.call("remove_ability", old_id)
		if boss_ability_system.has_method("set_level"):
			boss_ability_system.call("set_level", boss_ability_id, next_level)
		elif boss_ability_system.has_method("unlock_ability"):
			boss_ability_system.call("unlock_ability", boss_ability_id)
	_emit_event_bus(&"run_resource_changed")
	_continue_after_boss_reward_resolution()

func refuse_boss_ability_install(_boss_ability_id: String = "") -> void:
	decline_boss_reward_for_soul_ash()

func _continue_after_boss_reward_resolution() -> void:
	_pending_boss_reward_ability_id = ""
	_pending_boss_reward_data.clear()
	continue_after_boss_reward()

func choose_room_card(card_index: int) -> void:
	if _state != FlowState.ROOM_CARD_SELECT:
		return
	if card_index < 0 or card_index >= _room_cards.size():
		return
	var selected_card: Dictionary = _room_cards[card_index].duplicate(true)
	if bool(selected_card.get("disabled", false)):
		push_warning("RunFlow: disabled route option selected and ignored: " + str(selected_card.get("route_label", card_index)))
		return
	var option_type: String = str(selected_card.get("route_option_type", "room"))
	var optional_manager: Node = _get_optional_boss_manager()
	var pair_id: String = str(selected_card.get("optional_boss_pair_id", ""))

	if option_type == "altar":
		_show_altar_sacrifice()
		return

	if option_type == "optional_boss":
		if optional_manager != null and optional_manager.has_method("mark_optional_boss_selected"):
			optional_manager.call("mark_optional_boss_selected", pair_id, str(selected_card.get("boss_id", "")))
		RunManager.selected_boss_card = selected_card.duplicate(true)
		_start_boss(RunManager.selected_boss_card)
		return

	if bool(selected_card.get("optional_boss_offer_active", false)) and optional_manager != null and optional_manager.has_method("mark_optional_boss_refused"):
		optional_manager.call("mark_optional_boss_refused", pair_id)

	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("set_route_state"):
		route_manager.call("set_route_state", {
			"version": 2,
			"phase": "room",
			"floor_index": RunManager.current_floor_index,
			"room_index_on_floor": RunManager.current_room_index,
			"last_choice": selected_card.duplicate(true),
			"optional_boss_refused": bool(selected_card.get("optional_boss_offer_active", false))
		})
	RunManager.selected_room_card = selected_card
	_clear_runtime_nodes()
	_start_room(RunManager.selected_room_card)

func choose_boss_card(card_index: int) -> void:
	if _state != FlowState.BOSS_CHOICE_SELECT:
		return
	if card_index < 0 or card_index >= _boss_cards.size():
		return
	RunManager.selected_boss_card = _boss_cards[card_index].duplicate(true)
	var boss_choice_manager: Node = get_node_or_null("/root/BossChoiceManager")
	if boss_choice_manager != null and boss_choice_manager.has_method("mark_boss_selected"):
		boss_choice_manager.call("mark_boss_selected", RunManager.selected_boss_card)
	_start_boss(RunManager.selected_boss_card)


func _can_offer_altar_now(floor_index: int) -> bool:
	if _is_current_floor_complete():
		return false
	var altar_manager: Node = _get_altar_manager()
	if altar_manager == null or not altar_manager.has_method("can_use_altar"):
		return false
	return bool(altar_manager.call("can_use_altar", floor_index))

func _build_altar_route_card(floor_index: int) -> Dictionary:
	var total_essence: int = EssenceBank.get_total_amount() if get_node_or_null("/root/EssenceBank") != null else 0
	return {
		"route_label": "Алтарь",
		"route_option_type": "altar",
		"room_type_name": "Алтарь жертвы",
		"description": "Post-room сервис. Не считается комнатой. Жертва доступна один раз за этаж.",
		"reward_preview": "Эссенция: %d → Пепел Душ + карточки" % total_essence,
		"floor_index": floor_index,
		"disabled": false
	}

func _show_altar_sacrifice() -> void:
	_state = FlowState.ALTAR_SACRIFICE
	var context: Dictionary = _get_route_context()
	var floor_index: int = int(context.get("floor_index", RunManager.current_floor_index))
	var route_manager: Node = _get_route_manager()
	if route_manager != null and route_manager.has_method("set_route_state"):
		route_manager.call("set_route_state", {
			"version": 3,
			"phase": "altar_sacrifice",
			"floor_index": floor_index,
			"room_index_on_floor": int(context.get("room_index_on_floor", RunManager.current_room_index)),
			"altar_enabled": true
		})
	altar_sacrifice_requested.emit(floor_index, context)
	_emit_event_bus(&"run_resource_changed")

func cancel_altar() -> void:
	if _state != FlowState.ALTAR_SACRIFICE and _state != FlowState.ALTAR_REWARD_SELECT:
		return
	_pending_altar_sacrifice.clear()
	_pending_altar_cards.clear()
	_show_route_choices_for_next_room()

func confirm_altar_sacrifice(faction_or_mix, amount: int) -> void:
	if _state != FlowState.ALTAR_SACRIFICE:
		return
	var altar_manager: Node = _get_altar_manager()
	if altar_manager == null or not altar_manager.has_method("sacrifice_essence"):
		push_error("RunFlow: AltarManager.sacrifice_essence() is missing.")
		_show_route_choices_for_next_room()
		return
	var sacrifice_result = altar_manager.call("sacrifice_essence", faction_or_mix, amount)
	if not (sacrifice_result is Dictionary):
		push_error("RunFlow: invalid altar sacrifice result.")
		_show_route_choices_for_next_room()
		return
	_pending_altar_sacrifice = sacrifice_result.duplicate(true)
	if not bool(_pending_altar_sacrifice.get("ok", false)):
		push_warning("RunFlow: altar sacrifice rejected: " + str(_pending_altar_sacrifice.get("error", "unknown")))
		_show_route_choices_for_next_room()
		return
	var generator: Node = _get_altar_card_generator()
	if generator != null and generator.has_method("generate_cards"):
		var cards = generator.call("generate_cards", _pending_altar_sacrifice, 3)
		_pending_altar_cards = cards if cards is Array else []
	else:
		_pending_altar_cards = []
	if _pending_altar_cards.is_empty():
		push_warning("RunFlow: altar sacrifice produced no valid reward cards; returning to route flow.")
		_pending_altar_sacrifice.clear()
		_show_next_route_or_boss_choice()
		return
	_state = FlowState.ALTAR_REWARD_SELECT
	altar_reward_cards_ready.emit(_pending_altar_cards, _pending_altar_sacrifice)
	_emit_event_bus(&"run_resource_changed")

func choose_altar_reward_card(card_index: int) -> void:
	if _state != FlowState.ALTAR_REWARD_SELECT:
		return
	if card_index < 0 or card_index >= _pending_altar_cards.size():
		return
	var card: Dictionary = _pending_altar_cards[card_index].duplicate(true)
	var altar_manager: Node = _get_altar_manager()
	var result: Dictionary = {}
	if altar_manager != null and altar_manager.has_method("apply_card_effect"):
		var applied = altar_manager.call("apply_card_effect", card, _player)
		if applied is Dictionary:
			result = applied
	if bool(result.get("reroll_requested", false)):
		# Defensive branch: reroll cards are disabled from the active pool until full rules exist.
		var generator: Node = _get_altar_card_generator()
		if generator != null and generator.has_method("generate_cards"):
			var cards = generator.call("generate_cards", _pending_altar_sacrifice, 3)
			_pending_altar_cards = cards if cards is Array else []
			altar_reward_cards_ready.emit(_pending_altar_cards, _pending_altar_sacrifice)
			return
	_pending_altar_cards.clear()
	_pending_altar_sacrifice.clear()
	_show_next_route_or_boss_choice()

func handle_player_death(player: Node) -> bool:
	if RunManager.continue_used:
		_finish_run(false, "player_dead")
		return true
	_pending_player = player
	RunManager.continue_used = true
	_state = FlowState.CONTINUE_CHOICE
	continue_choice_requested.emit()
	return true

func accept_continue_option(health_ratio: float, essence_penalty_fraction: float) -> void:
	if _state != FlowState.CONTINUE_CHOICE:
		return
	EssenceBank.apply_fraction_penalty(essence_penalty_fraction)
	if _pending_player != null and is_instance_valid(_pending_player) and _pending_player.has_method("revive_with_health_ratio"):
		_pending_player.revive_with_health_ratio(health_ratio)
	_pending_player = null
	_state = FlowState.MORGATH_COMBAT if _current_boss_is_final else (FlowState.BOSS_RUNNING if not _current_boss_id.is_empty() else FlowState.ROOM_RUNNING)
	get_tree().paused = false
	_emit_event_bus(&"run_resource_changed")

func notify_final_boss_defeated(final_boss_id: String) -> void:
	# Финальный выход из забега: Морграт выдаёт только мета-валюту. BossRewardUI текущего забега не открывается.
	if final_boss_id.is_empty():
		final_boss_id = _get_final_boss_id()
	if _state == FlowState.RUN_RESULT or _state == FlowState.RUN_ENDED:
		return
	if RunManager != null and bool(RunManager.get("morgath_defeated")):
		return
	var meta_award: Dictionary = {}
	var meta_manager: Node = _get_meta_currency_manager()
	if meta_manager != null and meta_manager.has_method("award_morgath_victory"):
		var award_context: Dictionary = {
			"final_boss_id": final_boss_id,
			"bosses_defeated": RunManager.bosses_defeated.duplicate(),
			"final_preparation_choice": RunManager.final_preparation_choice,
			"final_preparation_buff": RunManager.final_preparation_buff.duplicate(true)
		}
		var award_value: Variant = meta_manager.call("award_morgath_victory", award_context)
		if award_value is Dictionary:
			meta_award = award_value
	if RunManager != null:
		if RunManager.has_method("mark_morgath_defeated"):
			RunManager.mark_morgath_defeated(final_boss_id)
		if RunManager.has_method("add_essence_core_earned"):
			RunManager.add_essence_core_earned(int(meta_award.get("amount", 0)))
	_current_boss_id = ""
	_current_boss_is_final = false
	_current_boss_is_optional = false
	_current_boss_is_echo = false
	_finish_run(true, "morgath_defeated")

func has_pending_meta_summary() -> bool:
	return not _pending_meta_summary.is_empty()

func consume_pending_meta_summary() -> Dictionary:
	var result: Dictionary = _pending_meta_summary.duplicate(true)
	_pending_meta_summary.clear()
	return result

func mark_run_result_closed() -> void:
	if _state == FlowState.RUN_RESULT:
		_state = FlowState.RUN_ENDED
		_emit_event_bus(&"run_resource_changed")

func get_debug_state() -> Dictionary:
	var active_enemies: int = 0
	if _enemy_parent != null:
		active_enemies = _enemy_parent.get_child_count()
	var dev_node: Node = get_node_or_null("/root/DeveloperTools")
	var dev_enabled: bool = dev_node != null and bool(dev_node.get("enabled"))
	return {
		"state": int(_state),
		"state_name": _state_to_string(_state),
		"current_boss": _current_boss_id,
		"continue_used": RunManager.continue_used,
		"active_enemies": active_enemies,
		"nearby_pickups_waiting": _count_nearby_pickups_for_cleanup(),
		"difficulty": float(RunManager.selected_room_card.get("difficulty", 1.0)),
		"essence_total": EssenceBank.get_total_amount(),
		"room_type": RunManager.selected_room_card.get("room_type", "survival_waves"),
		"rooms_completed": RunManager.rooms_completed,
		"rooms_completed_in_floor": RunManager.rooms_completed_in_floor,
		"floor": RunManager.current_floor_index,
		"boss_number": RunManager.current_boss_number,
		"is_final_boss": _current_boss_is_final,
		"final_preparation_active": RunManager.final_preparation_active,
		"route_context": _get_route_context(),
		"dev_mode": dev_enabled
	}

func _start_room(room_card: Dictionary) -> void:
	_state = FlowState.FINAL_PREPARATION_COMBAT if bool(room_card.get("is_final_preparation", false)) else FlowState.ROOM_RUNNING
	_current_boss_id = ""
	_current_boss_is_final = false
	_current_boss_is_optional = false
	_current_boss_is_echo = false
	_current_optional_boss_pair_id = ""
	_emit_event_bus(&"boss_hud_hidden")
	_pending_room_result.clear()
	_clear_reward_selection_state()
	_refresh_ability_cooldowns_for_new_encounter()
	var selected_card: Dictionary = room_card.duplicate(true)
	if selected_card.is_empty():
		var generated: Array = SpawnDirector.build_room_cards(RunManager.current_floor_index, RunManager.current_room_index, 1)
		selected_card = generated[0] if not generated.is_empty() else DataRegistry.get_room("ROOM_SURVIVAL_WAVES_MVP").get("default_card", {}).duplicate(true)
	RunManager.selected_room_card = selected_card.duplicate(true)
	var room_data: Dictionary = DataRegistry.get_room("ROOM_SURVIVAL_WAVES_MVP")
	WaveDirector.start_survival_room(_run_scene, _enemy_parent, _player, room_data, selected_card)
	_emit_event_bus(&"run_resource_changed")

func _start_boss(boss_card: Dictionary) -> void:
	WaveDirector.stop()
	_clear_runtime_nodes()
	_refresh_ability_cooldowns_for_new_encounter()
	var boss_id: String = str(boss_card.get("boss_id", boss_card.get("final_boss_id", "BOSS_KR_B_BRUKK")))
	_current_boss_is_optional = bool(boss_card.get("is_optional_boss", false))
	_current_boss_is_echo = bool(boss_card.get("is_echo", false))
	_current_optional_boss_pair_id = str(boss_card.get("optional_boss_pair_id", ""))
	var boss_data: Dictionary = {}
	_current_boss_is_final = bool(boss_card.get("is_final_boss", false)) or _is_final_boss_id(boss_id) or not DataRegistry.get_by_id("final_bosses", boss_id).is_empty()
	_state = FlowState.MORGATH_COMBAT if _current_boss_is_final else FlowState.BOSS_RUNNING
	if _current_boss_is_final:
		boss_data = BossController.get_final_boss_data(boss_id)
		RunManager.unlock_final_boss()
	else:
		boss_data = DataRegistry.get_by_id("bosses", boss_id).duplicate(true)
		boss_data["runtime_floor_scale"] = float(boss_card.get("boss_health_scale", 1.0))
		boss_data["is_echo"] = _current_boss_is_echo
		boss_data["is_optional_boss"] = _current_boss_is_optional
		boss_data["optional_boss_pair_id"] = _current_optional_boss_pair_id
		boss_data["echo_source"] = str(boss_card.get("echo_source", ""))
		boss_data["selected_ability_ids"] = boss_card.get("ability_ids", []) if boss_card.get("ability_ids", []) is Array else []
		if str(boss_data.get("scene_path", "")).is_empty():
			boss_data["scene_path"] = str(boss_card.get("boss_scene_path", "res://scenes/bosses/test_floor_boss.tscn"))
	_current_boss_id = boss_id
	SpawnDirector.spawn_boss(_enemy_parent, _player, boss_data)
	_emit_event_bus(&"run_resource_changed")

func _on_room_completed(room_result: Dictionary) -> void:
	if _state != FlowState.ROOM_RUNNING and _state != FlowState.FINAL_PREPARATION_COMBAT:
		return
	RunManager.advance_room()
	_pending_room_result = room_result.duplicate(true)
	_state = FlowState.ROOM_PICKUP_CLEANUP
	_pickup_cleanup_elapsed = 0.0
	_boost_nearby_pickups_for_cleanup()
	_emit_event_bus(&"run_resource_changed")

func _update_room_pickup_cleanup(delta: float) -> void:
	_pickup_cleanup_elapsed += delta
	_boost_nearby_pickups_for_cleanup()
	if _count_nearby_pickups_for_cleanup() <= 0:
		_open_post_room_flow_after_pickup_cleanup()
		return
	if _pickup_cleanup_elapsed >= ROOM_CLEAR_PICKUP_TIMEOUT_SECONDS:
		_open_post_room_flow_after_pickup_cleanup()

func _boost_nearby_pickups_for_cleanup() -> void:
	if _pickups == null or _player == null or not is_instance_valid(_player):
		return
	for child in _pickups.get_children():
		if child == null or not is_instance_valid(child):
			continue
		if child.has_method("is_inside_collection_radius"):
			if not bool(child.call("is_inside_collection_radius", _player, ROOM_CLEAR_PICKUP_RADIUS_MULTIPLIER)):
				continue
		elif child is Node2D:
			var pickup_2d: Node2D = child as Node2D
			if pickup_2d.global_position.distance_to(_player.global_position) > 160.0 * ROOM_CLEAR_PICKUP_RADIUS_MULTIPLIER:
				continue
		if child.has_method("start_room_clear_magnet"):
			child.call("start_room_clear_magnet", _player, ROOM_CLEAR_PICKUP_RADIUS_MULTIPLIER)

func _count_nearby_pickups_for_cleanup() -> int:
	if _pickups == null or _player == null or not is_instance_valid(_player):
		return 0
	var count: int = 0
	for child in _pickups.get_children():
		if child == null or not is_instance_valid(child):
			continue
		if child.has_method("is_inside_collection_radius"):
			if bool(child.call("is_inside_collection_radius", _player, ROOM_CLEAR_PICKUP_RADIUS_MULTIPLIER)):
				count += 1
		elif child is Node2D:
			var pickup_2d: Node2D = child as Node2D
			if pickup_2d.global_position.distance_to(_player.global_position) <= 160.0 * ROOM_CLEAR_PICKUP_RADIUS_MULTIPLIER:
				count += 1
	return count

func _open_post_room_flow_after_pickup_cleanup() -> void:
	if _state != FlowState.ROOM_PICKUP_CLEANUP:
		return
	_pending_room_result.clear()
	_clear_reward_selection_state()
	if RunManager.final_preparation_active:
		_show_final_preparation_choices()
		_emit_event_bus(&"run_resource_changed")
		return
	_show_next_route_or_boss_choice()
	_emit_event_bus(&"run_resource_changed")

func _get_faction_name(faction_id: String) -> String:
	var faction: Dictionary = DataRegistry.get_by_id("factions", faction_id)
	return str(faction.get("name", faction_id))

func _on_boss_defeated(boss_id: String) -> void:
	if _state != FlowState.BOSS_RUNNING and _state != FlowState.MORGATH_COMBAT:
		return
	var was_final_boss: bool = _current_boss_is_final or _is_final_boss_id(boss_id) or not DataRegistry.get_by_id("final_bosses", boss_id).is_empty()
	if was_final_boss:
		notify_final_boss_defeated(boss_id)
		return
	_current_boss_id = boss_id
	_current_boss_is_final = false
	if RunManager != null and RunManager.has_method("mark_boss_defeated"):
		RunManager.mark_boss_defeated(boss_id)
	_clear_runtime_nodes()

	if _current_boss_is_optional:
		var optional_manager: Node = _get_optional_boss_manager()
		if optional_manager != null and optional_manager.has_method("mark_optional_boss_defeated"):
			optional_manager.call("mark_optional_boss_defeated", _current_optional_boss_pair_id, boss_id)
		# Дополнительный босс заменяет обычную комнату и продвигает маршрут только после победы.
		RunManager.advance_room()
		_state = FlowState.ROOM_REWARD
		_pending_after_boss_reward = ""
		var optional_reward: Dictionary = _build_boss_reward_payload(boss_id, true, _current_boss_is_echo)
		_pending_boss_reward_data = optional_reward.duplicate(true)
		boss_reward_ready.emit(optional_reward)
		_current_boss_id = ""
		_current_boss_is_optional = false
		_current_boss_is_echo = false
		_current_optional_boss_pair_id = ""
		_emit_event_bus(&"run_resource_changed")
		return

	# Route patch v0.14: mandatory floor bosses now resolve through BossRewardUI before route advancement.
	_state = FlowState.ROOM_REWARD
	if _is_current_route_final_floor():
		_pending_after_boss_reward = "final_preparation"
	else:
		_pending_after_boss_reward = "next_floor"
	var reward: Dictionary = _build_boss_reward_payload(boss_id, false, _current_boss_is_echo)
	_pending_boss_reward_data = reward.duplicate(true)
	boss_reward_ready.emit(reward)
	_emit_event_bus(&"run_resource_changed")

func _begin_next_floor_after_boss() -> void:
	RunManager.advance_to_next_floor()
	_show_route_choices_for_next_room()
	_emit_event_bus(&"run_resource_changed")

func _begin_final_preparation_room() -> void:
	_state = FlowState.FINAL_PREPARATION_COMBAT
	RunManager.begin_final_preparation()
	var prep_card: Dictionary = SpawnDirector.build_final_preparation_card()
	# v0.19: short Final Preparation = exactly one elite wave before the preparation choice UI.
	prep_card["room_type"] = "final_preparation_elite_wave"
	prep_card["room_type_name"] = "Короткая финальная подготовка"
	prep_card["is_final_preparation"] = true
	prep_card["spawn_budget_per_wave"] = [18]
	prep_card["difficulty"] = max(1.85, float(prep_card.get("difficulty", 1.0)))
	prep_card["difficulty_label"] = "Elite wave"
	RunManager.selected_room_card = prep_card.duplicate(true)
	_start_room(prep_card)


func _show_final_preparation_choices() -> void:
	_state = FlowState.FINAL_PREPARATION_CHOICE
	_pending_final_preparation_choices = _build_final_preparation_choices()
	final_preparation_choices_ready.emit(_pending_final_preparation_choices)
	_emit_event_bus(&"run_resource_changed")

func choose_final_preparation(choice_id: String) -> void:
	if _state != FlowState.FINAL_PREPARATION_CHOICE:
		return
	if choice_id.is_empty():
		return
	var choice: Dictionary = _find_final_preparation_choice(choice_id)
	if choice.is_empty():
		return
	var payload: Dictionary = _apply_final_preparation_choice(choice)
	if RunManager != null and RunManager.has_method("mark_final_preparation_choice"):
		RunManager.mark_final_preparation_choice(choice_id, payload)
	_pending_final_preparation_choices.clear()
	_start_morgath()

func _build_final_preparation_choices() -> Array:
	return [
		{
			"id": "heal",
			"name_ru": "Восстановление",
			"description_ru": "Полностью восстановить здоровье перед Моргратом.",
			"effect_type": "heal"
		},
		{
			"id": "boss_ability_tuning",
			"name_ru": "Настройка способности",
			"description_ru": "Бесплатно улучшить одну открытую способность босса, если есть доступный уровень. Иначе: +3 Пепла Душ.",
			"effect_type": "boss_ability_tuning"
		},
		{
			"id": "temporary_final_boss_buff",
			"name_ru": "Короткий боевой фокус",
			"description_ru": "Временное усиление только для боя с Моргратом. Не сохраняется после забега и не является мета-прогрессом.",
			"effect_type": "temporary_final_boss_buff"
		}
	]

func _find_final_preparation_choice(choice_id: String) -> Dictionary:
	for choice_value in _pending_final_preparation_choices:
		if choice_value is Dictionary:
			var choice: Dictionary = choice_value
			if str(choice.get("id", "")) == choice_id:
				return choice
	return {}

func _apply_final_preparation_choice(choice: Dictionary) -> Dictionary:
	var effect_type: String = str(choice.get("effect_type", choice.get("id", "")))
	var payload: Dictionary = {"id": str(choice.get("id", "")), "effect_type": effect_type, "applied": false}
	match effect_type:
		"heal":
			if _player != null and is_instance_valid(_player) and _player.has_method("heal_from_essence"):
				_player.call("heal_from_essence", 99999.0)
				payload["applied"] = true
		"boss_ability_tuning":
			payload = _apply_final_preparation_boss_ability_tuning(payload)
		"temporary_final_boss_buff":
			payload["applied"] = true
			payload["morgath_only"] = true
			payload["damage_multiplier_bonus"] = 0.08
		_:
			push_warning("RunFlow: unknown final preparation choice: " + effect_type)
	_emit_event_bus(&"run_resource_changed")
	return payload

func _apply_final_preparation_boss_ability_tuning(payload: Dictionary) -> Dictionary:
	var boss_ability_system: Node = _get_boss_ability_system()
	if boss_ability_system == null or not boss_ability_system.has_method("get_state"):
		RunManager.add_soul_ash(3, "final_preparation_tuning_fallback")
		payload["fallback_soul_ash"] = 3
		return payload
	var state_value: Variant = boss_ability_system.call("get_state")
	if not (state_value is Dictionary):
		RunManager.add_soul_ash(3, "final_preparation_tuning_fallback")
		payload["fallback_soul_ash"] = 3
		return payload
	var state: Dictionary = state_value
	var levels: Dictionary = state.get("levels", {}) if state.get("levels", {}) is Dictionary else {}
	for ability_id_value in levels.keys():
		var ability_id: String = str(ability_id_value)
		var level: int = int(levels.get(ability_id_value, 0))
		if level > 0 and level < 3 and boss_ability_system.has_method("upgrade_ability"):
			boss_ability_system.call("upgrade_ability", ability_id)
			payload["applied"] = true
			payload["upgraded_boss_ability_id"] = ability_id
			return payload
	RunManager.add_soul_ash(3, "final_preparation_tuning_fallback")
	payload["fallback_soul_ash"] = 3
	return payload

func _start_morgath() -> void:
	var final_boss_id: String = _get_final_boss_id()
	if final_boss_id.is_empty():
		push_error("RunFlow: невозможно запустить Морграта — отсутствует run_config.final_boss.boss_id.")
		return
	RunManager.unlock_final_boss()
	var card: Dictionary = _build_morgath_card()
	card["is_final_boss"] = true
	card["boss_id"] = final_boss_id
	card["final_boss_id"] = final_boss_id
	card["route_source"] = "final_preparation"
	RunManager.selected_boss_card = card.duplicate(true)
	_start_boss(card)

func _build_morgath_card() -> Dictionary:
	var final_boss_id: String = _get_final_boss_id()
	var cards: Array = BossController.get_final_boss_cards()
	for card_value in cards:
		if card_value is Dictionary:
			var card: Dictionary = card_value
			if str(card.get("final_boss_id", card.get("boss_id", ""))) == final_boss_id:
				card["is_final_boss"] = true
				card["boss_id"] = final_boss_id
				card["final_boss_id"] = final_boss_id
				card["route_source"] = "final_preparation"
				return card
	var final_config: Dictionary = DataRegistry.get_final_boss_config() if DataRegistry.has_method("get_final_boss_config") else {}
	return {
		"boss_id": final_boss_id,
		"final_boss_id": final_boss_id,
		"is_final_boss": true,
		"name": str(final_config.get("name_ru", "Морграт Разломанный")),
		"faction_name": "Крушители / Эфиры",
		"difficulty": "Высокая",
		"route_source": "final_preparation"
	}

func _on_run_finished_event(result: Dictionary) -> void:
	if _state == FlowState.RUN_RESULT or _state == FlowState.RUN_ENDED:
		return
	if result.get("result", "") == "defeat":
		_finish_run(false, str(result.get("reason", "legacy_defeat")))
	elif result.get("result", "") == "victory":
		_finish_run(true, str(result.get("reason", "legacy_victory")))

func _finish_run(victory: bool, reason: String) -> void:
	WaveDirector.stop()
	_clear_runtime_nodes()
	_state = FlowState.RUN_RESULT
	_current_boss_is_final = false
	var result: Dictionary = RunManager.finish_run(victory, reason)
	var summary: Dictionary = RunManager.build_run_summary(result) if RunManager.has_method("build_run_summary") else result.duplicate(true)
	summary["victory"] = victory
	summary["reason"] = reason
	summary["run_state"] = "RUN_RESULT"
	_pending_meta_summary = {
		"result": {"result": "victory" if victory else "defeat", "reason": reason},
		"cores": MetaProgression.cores_by_faction.duplicate(true),
		"shards": MetaProgression.shards_by_faction.duplicate(true),
		"soul_ash": RunManager.get_soul_ash() if RunManager.has_method("get_soul_ash") else 0,
		"meta_progress": MetaProgression.counters_by_faction.duplicate(true),
		"hero_experience": MetaProgression.hero_levels.duplicate(true),
		"unlocked_upgrades": [],
		"meta_currency": MetaProgression.meta_currency, # legacy generic currency
		"essence_core": int(summary.get("core_essence_total", 0)),
		"core_essence_earned": int(summary.get("core_essence_earned", 0))
	}
	if victory and reason == "morgath_defeated":
		run_summary_ready.emit(summary)
	else:
		run_result_ready.emit(result) # legacy result panel remains available as debug/fallback.
	_emit_event_bus(&"run_resource_changed")


func _build_optional_boss_reward_payload(boss_id: String) -> Dictionary:
	return _build_boss_reward_payload(boss_id, true)

func _build_boss_reward_payload(boss_id: String, is_optional: bool = false, is_echo: bool = false) -> Dictionary:
	var context: Dictionary = {
		"is_optional": is_optional,
		"is_echo": is_echo,
		"decline_reward_soul_ash": 5,
		"after_boss_action": _pending_after_boss_reward
	}
	var boss_reward_manager: Node = _get_boss_reward_manager()
	if boss_reward_manager != null and boss_reward_manager.has_method("build_reward_payload"):
		var payload_value: Variant = boss_reward_manager.call("build_reward_payload", boss_id, context)
		if payload_value is Dictionary:
			return payload_value
	var boss: Dictionary = {}
	if DataRegistry.has_method("get_by_id"):
		boss = DataRegistry.get_by_id("bosses", boss_id)
	return {
		"reward_kind": "boss_ability_reward",
		"boss_id": boss_id,
		"boss_name": str(boss.get("name_ru", boss.get("name", boss_id))),
		"title": "Награда Отголоска босса" if is_echo else ("Награда дополнительного босса" if is_optional else "Награда босса"),
		"marker": "Отголосок босса побеждён" if is_echo else ("Дополнительный босс побеждён" if is_optional else "Обязательный босс побеждён"),
		"description": "Выберите способность босса или откажитесь от награды.",
		"decline_reward_soul_ash": 5,
		"can_decline_for_soul_ash": true,
		"reward_options": []
	}

func _reset_player_for_new_run(hero_id: String) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("reset_for_new_run"):
		_player.call("reset_for_new_run", hero_id)
	elif _player.has_method("revive_with_health_ratio"):
		_player.call("revive_with_health_ratio", 1.0)

func _refresh_ability_cooldowns_for_new_encounter() -> void:
	var ability_manager: Node = get_node_or_null("/root/AbilityManager")
	if ability_manager != null and ability_manager.has_method("reset_cooldowns_for_new_encounter"):
		ability_manager.call("reset_cooldowns_for_new_encounter")

func _clear_runtime_nodes() -> void:
	SpawnDirector.clear_combatants(_enemy_parent)
	if _pickups != null:
		for child in _pickups.get_children():
			child.queue_free()
	_clear_room_effects()
	_emit_event_bus(&"boss_hud_hidden")

func _clear_room_effects() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var groups: Array[String] = ["room_effects", "combat_effects", "status_effects"]
	var cleaned: Dictionary = {}
	for group_name in groups:
		for node in tree.get_nodes_in_group(group_name):
			if node == null or not is_instance_valid(node):
				continue
			var id: int = node.get_instance_id()
			if cleaned.has(id):
				continue
			cleaned[id] = true
			node.queue_free()

func _state_to_string(state: int) -> String:
	match state:
		FlowState.IDLE:
			return "IDLE"
		FlowState.ROOM_RUNNING:
			return "ROOM_RUNNING"
		FlowState.ROOM_PICKUP_CLEANUP:
			return "ROOM_PICKUP_CLEANUP"
		FlowState.ROOM_REWARD:
			return "ROOM_REWARD"
		FlowState.ROOM_CARD_SELECT:
			return "ROOM_CARD_SELECT"
		FlowState.ALTAR_SACRIFICE:
			return "ALTAR_SACRIFICE"
		FlowState.ALTAR_REWARD_SELECT:
			return "ALTAR_REWARD_SELECT"
		FlowState.BOSS_CHOICE_SELECT:
			return "BOSS_CHOICE_SELECT"
		FlowState.BOSS_RUNNING:
			return "BOSS_RUNNING"
		FlowState.FINAL_PREPARATION_COMBAT:
			return "FINAL_PREPARATION_COMBAT"
		FlowState.FINAL_PREPARATION_CHOICE:
			return "FINAL_PREPARATION_CHOICE"
		FlowState.MORGATH_COMBAT:
			return "MORGATH_COMBAT"
		FlowState.RUN_RESULT:
			return "RUN_RESULT"
		FlowState.RUN_ENDED:
			return "RUN_ENDED"
		FlowState.CONTINUE_CHOICE:
			return "CONTINUE_CHOICE"
		_:
			return "UNKNOWN"
