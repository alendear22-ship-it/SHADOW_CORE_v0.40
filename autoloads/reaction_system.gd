extends Node

signal reaction_triggered(reaction_id: String, target: Node, payload: DamagePayload, tags: Array)
signal reaction_blocked(reason: String, target: Node, payload: DamagePayload)

const TARGET_REACTION_COOLDOWN_SECONDS: float = 0.35
const VISUAL_BURST_WINDOW_SECONDS: float = 0.5
const MAX_VISUAL_BURSTS_PER_WINDOW: int = 2
const MAX_TRACKED_SOURCE_EVENTS: int = 128

var debug_reactions_enabled: bool = false

var _target_reaction_cooldowns: Dictionary = {}
var _visual_burst_times: Array[float] = []
var _consumed_source_events: Dictionary = {}
var _consumed_source_event_order: Array[String] = []

func _ready() -> void:
	_connect_combat_system_once()

func reset_run() -> void:
	_target_reaction_cooldowns.clear()
	_visual_burst_times.clear()
	_consumed_source_events.clear()
	_consumed_source_event_order.clear()

func handle_damage_event(payload: DamagePayload) -> bool:
	if payload == null:
		return false
	var target: Node = payload.target
	if target == null or not is_instance_valid(target):
		return false
	payload.normalize_source_type()
	if payload.chain_depth > 0:
		_emit_blocked("chain_depth_blocked", target, payload)
		return false
	if not _can_source_type_trigger_reaction(payload):
		_emit_blocked("source_type_blocked:" + str(payload.source_type), target, payload)
		return false
	if payload.reaction_consumed:
		_emit_blocked("source_event_reaction_already_consumed", target, payload)
		return false
	if _is_source_event_consumed(payload.source_event_id):
		_emit_blocked("source_event_id_already_consumed", target, payload)
		return false
	var tags: Array[String] = _collect_reaction_tags(target, payload)
	if tags.is_empty():
		return false
	var reaction_id: String = _select_reaction_id(tags)
	if reaction_id.is_empty():
		return false
	if not _try_consume_target_reaction_cooldown(target, reaction_id):
		_emit_blocked("target_reaction_cooldown", target, payload)
		return false
	payload.reaction_consumed = true
	_mark_source_event_consumed(payload.source_event_id)
	var visual_allowed: bool = _try_consume_visual_burst_slot()
	_emit_reaction_triggered(reaction_id, target, payload, tags, visual_allowed)
	return true

func can_source_type_trigger_reaction(source_type: String) -> bool:
	var payload: DamagePayload = DamagePayload.new()
	payload.source_type = source_type
	payload.normalize_source_type()
	return _can_source_type_trigger_reaction(payload)

func simulate_direct_active_hit_with_tags(tags: Array = []) -> bool:
	# DEV/DEBUG test hook only. Does not apply damage.
	var payload: DamagePayload = _build_test_payload(DamagePayload.SOURCE_DIRECT_ACTIVE_HIT, tags)
	payload.target = self
	return handle_damage_event(payload)

func simulate_dot_tick() -> bool:
	# DEV/DEBUG test hook only. Expected result: false.
	var payload: DamagePayload = _build_test_payload(DamagePayload.SOURCE_DOT_TICK, ["reaction_burst"])
	payload.target = self
	return handle_damage_event(payload)

func simulate_reaction_damage() -> bool:
	# DEV/DEBUG test hook only. Expected result: false.
	var payload: DamagePayload = _build_test_payload(DamagePayload.SOURCE_REACTION_DAMAGE, ["reaction_burst"])
	payload.target = self
	return handle_damage_event(payload)

func _connect_combat_system_once() -> void:
	var combat_system: Node = get_node_or_null("/root/CombatSystem")
	if combat_system == null:
		push_warning("ReactionSystem: CombatSystem autoload is missing; reactions will not receive damage_applied events.")
		return
	_safe_connect_signal(combat_system, &"damage_applied", Callable(self, "handle_damage_event"))

func _safe_connect_signal(source: Object, signal_name: StringName, target: Callable) -> void:
	if source == null:
		return
	if not source.has_signal(signal_name):
		push_warning("ReactionSystem: source has no signal %s" % str(signal_name))
		return
	if not target.is_valid():
		return
	if source.is_connected(signal_name, target):
		return
	source.connect(signal_name, target)

func _can_source_type_trigger_reaction(payload: DamagePayload) -> bool:
	if not bool(payload.can_trigger_reactions):
		return false
	match payload.source_type:
		DamagePayload.SOURCE_DIRECT_ACTIVE_HIT:
			return true
		DamagePayload.SOURCE_ZONE_INITIAL_HIT:
			return true
		DamagePayload.SOURCE_ZONE_TICK:
			return false
		DamagePayload.SOURCE_DOT_TICK:
			return false
		DamagePayload.SOURCE_BOSS_ABILITY_DAMAGE, DamagePayload.SOURCE_WEAK_MOB_ABILITY_DAMAGE, DamagePayload.SOURCE_BOSS_AI_ABILITY_DAMAGE, DamagePayload.SOURCE_ALTAR_CARD_DAMAGE:
			return false
		DamagePayload.SOURCE_REACTION_DAMAGE:
			return false
		DamagePayload.SOURCE_FRIENDLY_FIRE:
			return false
		DamagePayload.SOURCE_AUTO_ATTACK_PRIMARY, DamagePayload.SOURCE_AUTO_ATTACK_EXTRA_SHURIKEN, DamagePayload.SOURCE_AUTO_ATTACK_BOUNCE, DamagePayload.SOURCE_AUTO_ATTACK_PROC_BONUS:
			return false
		_:
			return false

func _collect_reaction_tags(target: Node, payload: DamagePayload) -> Array[String]:
	var result: Array[String] = []
	for tag in payload.get_all_reaction_tags():
		_add_unique_tag(result, str(tag))
	# Reactions are status/tag-driven. No direct reward IDs are read here.
	if target.has_method("get_reaction_tags"):
		var target_tags: Variant = target.call("get_reaction_tags")
		if target_tags is Array:
			for tag in target_tags:
				_add_unique_tag(result, str(tag))
	return result

func _select_reaction_id(tags: Array[String]) -> String:
	if tags.has("reaction_burst"):
		return "reaction_burst"
	if tags.has("direct_active_hit"):
		return "direct_active_hit"
	if tags.size() > 0:
		return "tag:" + str(tags[0])
	return ""

func _try_consume_target_reaction_cooldown(target: Node, reaction_id: String) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	var key: String = str(target.get_instance_id()) + ":" + reaction_id
	if float(_target_reaction_cooldowns.get(key, -1000.0)) > now:
		return false
	_target_reaction_cooldowns[key] = now + TARGET_REACTION_COOLDOWN_SECONDS
	return true

func _try_consume_visual_burst_slot() -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	var kept: Array[float] = []
	for value in _visual_burst_times:
		if now - float(value) <= VISUAL_BURST_WINDOW_SECONDS:
			kept.append(float(value))
	_visual_burst_times = kept
	if _visual_burst_times.size() >= MAX_VISUAL_BURSTS_PER_WINDOW:
		return false
	_visual_burst_times.append(now)
	return true

func _is_source_event_consumed(source_event_id: String) -> bool:
	return not source_event_id.is_empty() and bool(_consumed_source_events.get(source_event_id, false))

func _mark_source_event_consumed(source_event_id: String) -> void:
	if source_event_id.is_empty():
		return
	if _consumed_source_events.has(source_event_id):
		return
	_consumed_source_events[source_event_id] = true
	_consumed_source_event_order.append(source_event_id)
	while _consumed_source_event_order.size() > MAX_TRACKED_SOURCE_EVENTS:
		var old_id: String = str(_consumed_source_event_order.pop_front())
		_consumed_source_events.erase(old_id)

func _emit_reaction_triggered(reaction_id: String, target: Node, payload: DamagePayload, tags: Array[String], visual_allowed: bool) -> void:
	reaction_triggered.emit(reaction_id, target, payload, tags)
	var reaction_payload: DamagePayload = build_reaction_damage_payload(payload, reaction_id, 0.0)
	var data: Dictionary = _build_reaction_event_data(reaction_id, target, payload, tags, visual_allowed)
	data["reaction_payload_source_type"] = reaction_payload.source_type
	data["reaction_payload_chain_depth"] = reaction_payload.chain_depth
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(&"reaction_triggered_event"):
		bus.emit_signal(&"reaction_triggered_event", data)
	if visual_allowed and bus != null and bus.has_signal(&"reaction_visual_requested"):
		bus.emit_signal(&"reaction_visual_requested", data)
	if debug_reactions_enabled:
		print("ReactionSystem: triggered ", reaction_id, " source=", payload.source_type, " tags=", tags)

func _emit_blocked(reason: String, target: Node, payload: DamagePayload) -> void:
	reaction_blocked.emit(reason, target, payload)
	var source_type_value: String = ""
	var source_event_value: String = ""
	if payload != null:
		source_type_value = str(payload.source_type)
		source_event_value = str(payload.source_event_id)
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(&"reaction_blocked_event"):
		bus.emit_signal(&"reaction_blocked_event", {
			"reason": reason,
			"source_type": source_type_value,
			"source_event_id": source_event_value
		})
	if debug_reactions_enabled:
		print("ReactionSystem: blocked ", reason)

func _build_reaction_event_data(reaction_id: String, target: Node, payload: DamagePayload, tags: Array[String], visual_allowed: bool) -> Dictionary:
	var position: Vector2 = Vector2.ZERO
	var target_instance_id: int = 0
	if target != null:
		target_instance_id = target.get_instance_id()
	if target is Node2D:
		position = (target as Node2D).global_position
	return {
		"reaction_id": reaction_id,
		"target_instance_id": target_instance_id,
		"position": position,
		"source_type": str(payload.source_type),
		"source_event_id": str(payload.source_event_id),
		"ability_id": str(payload.ability_id),
		"tags": tags.duplicate(),
		"visual_allowed": visual_allowed
	}

func _build_test_payload(source_type: String, tags: Array) -> DamagePayload:
	var payload: DamagePayload = DamagePayload.new()
	payload.amount = 1.0
	payload.damage_type = "test"
	payload.source_id = "reaction_test"
	payload.ability_id = "reaction_test"
	payload.source_type = source_type
	payload.can_trigger_reactions = true
	payload.can_trigger_boss_abilities = false
	payload.can_trigger_secondary_effects = false
	payload.can_apply_reaction_prerequisites = source_type == DamagePayload.SOURCE_DIRECT_ACTIVE_HIT
	for tag in tags:
		payload.add_reaction_tag(str(tag))
	if tags.is_empty() and source_type == DamagePayload.SOURCE_DIRECT_ACTIVE_HIT:
		payload.add_reaction_tag("reaction_burst")
	payload.normalize_source_type()
	return payload

func _add_unique_tag(target: Array[String], tag: String) -> void:
	if tag.is_empty() or target.has(tag):
		return
	target.append(tag)

func get_state() -> Dictionary:
	return {"transient": true, "cooldowns_persisted": false}

func set_state(state: Variant = {}) -> void:
	# Reaction cooldowns are transient and intentionally not restored across suspend/load.
	reset_run()

func build_reaction_damage_payload(source_payload: DamagePayload, reaction_id: String, amount: float = 0.0) -> DamagePayload:
	var payload: DamagePayload = source_payload.duplicate_payload() if source_payload != null else DamagePayload.new()
	payload.amount = amount
	payload.source_id = reaction_id
	payload.ability_id = reaction_id
	payload.source_type = DamagePayload.SOURCE_REACTION_DAMAGE
	payload.chain_depth = 1
	payload.can_trigger_boss_abilities = false
	payload.can_trigger_reactions = false
	payload.can_trigger_weapon_upgrades = false
	payload.can_trigger_secondary_effects = false
	payload.can_apply_reaction_prerequisites = false
	payload.normalize_source_type()
	return payload
